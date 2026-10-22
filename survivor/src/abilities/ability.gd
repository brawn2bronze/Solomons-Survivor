class_name Ability
extends RefCounted
## Runtime instance of a WeaponDef / PassiveDef. Effective numbers live in `p` (base + level scaling +
## chosen branch), recomputed whenever the level or branch changes. Subclasses override the hooks below.

const BRANCH_LEVEL := 4         # branch pair (A/B) owed when a kit ability reaches 4
const EVO1_LEVEL := 8           # first evolution (branch-specific) owed at 8
const EVO2_LEVEL := 16          # final evolution (same line) owed at 16
const POST_MAX := 16            # kit ceiling; leveling never gates on picks
const MILESTONE_LEVELS := [10, 13]  # small pacing bumps between the evolutions
## Snapshot state (Descent checkpoint, Phase 3). Single source for to_dict/from_dict
## so the two never drift (check_project verifies the round-trip statically).
const STATE_KEYS := ["level", "branch", "branch_level", "evo1", "evo2"]
## Evolution option ids whose behavior code is live. A tier is only offered
## when BOTH of its options are in this set, so each slice ships on its own
## (extend when a slice's behaviors + data land; workbench §9).
const READY_EVOS := [
	# six_shooter (Revolver)
	"running_reload", "fan_the_hammer", "quickdraw", "showdown",
	"ricochet_rounds", "long_barrel", "dead_eye", "dead_mans_hand",
	# katana (MeleeSwipe)
	"wayfinder", "momentum_edge", "moonfall_whirl", "afterimage",
	"weaving_blades", "unbroken_combo", "thousand_cuts", "reprisal",
	# flailing_whip (Whip)
	"twirling_lasso", "dragging_chain", "roundup", "barbed_fence",
	"sweet_spot", "snap_parry", "fast_hands", "wanted_poster",
	# flash_bombs (StunPulse)
	"smoke_veil", "trailing_mines", "vanish", "cascade_flash",
	"killing_light", "panic_powder", "kawarimi", "five_point_palm",
	# hand_cannon (Cannon)
	"chain_shot", "broadside", "phantom_broadside", "bombard",
	"rebound", "kickback", "burning_pitch", "primed_powder",
	# pirate_crew (SummonAllies)
	"gun_crew", "boarding_party", "jolly_roger", "x_marks_the_spot",
	"grog_rations", "human_shield", "man_overboard", "release_the_kraken",
	# greatsword (MeleeSwipe)
	"crusaders_march", "mirror_wave", "dawnbreaker", "pilgrims_road",
	"fervor", "retribution", "holy_leap", "bulwark_stance",
	# prayer (Whip)
	"consecration", "seraph_ring", "sanctuary", "lay_on_hands",
	"tolling_bell", "verdict_mark", "final_judgement", "twin_suns",
]

var def
var player: Player
var level := 1
var branch := -1              # -1 none, 0 = branch A, 1 = branch B
var branch_level := 0
var evo1 := -1                # tier-1 evolution pick (8), -1 = not taken
var evo2 := -1                # tier-2 evolution pick (16), -1 = not taken
var p: Dictionary = {}
var flags: Dictionary = {}
var t := 0.0                  # generic countdown for subclasses
var mod_ops: Array = []        # owned Black Market mods: stat ops (same format as branches)
var mod_flags: Dictionary = {} # owned Black Market mods: behavior switches/params read via has_mod() / mod_f()
var evo_ids: Array = []         # chosen evolution ids (from authored evo1/evo2)
var evo_mods: Array = []        # live EvoModule instances for evo_ids
var prim_meters: Dictionary = {} # primitive 1: movement/charge meters, key -> value
var prim_nth: Dictionary = {}    # primitive 2: every-nth counters, key -> count
var _afters: Array = []          # primitive 10: scheduled {t, cb} delayed callables


static func make(res, pl: Player) -> Ability:
	var a: Ability = null
	if res is WeaponDef:
		a = WeaponBehaviors.make(res.behavior)
	elif res is PassiveDef:
		a = PassiveBehaviors.make(res.behavior)
	if a == null:
		push_error("Ability: no behavior '%s' for %s" % [res.behavior, res.id])
		return null
	a.def = res
	a.player = pl
	a.recompute()
	a.on_ready()
	return a


## Kit-only gate for the 9-16 track: character-kit abilities evolve, pickup
## (chest) weapons do not — their evolution path is the Black Market mods.
func evolvable() -> bool:
	return def != null and not String(def.id).begins_with("pickup_")


## Ceiling: kit abilities always run to POST_MAX (no gates — owed pairs are
## bonus power, never blockers). Everything else stops at the data max_level.
func max_level_now() -> int:
	if evolvable():
		return POST_MAX
	return int(def.max_level)


func recompute() -> void:
	p = def.base.duplicate(true)
	flags = {}
	for i in level - 1:
		_apply(def.level_scaling)
	if branch >= 0:
		var b: Dictionary = def.branches[branch]
		_apply(b["on_pick"])
		for i in level - branch_level:
			_apply(b["per_level"])
		flags = (b["flags"] as Dictionary).duplicate()
		if evolvable():
			_apply_milestones()
			if evo1 >= 0:
				_apply_evo_opt(evo_option(1, evo1))
			if evo2 >= 0:
				_apply_evo_opt(evo_option(2, evo2))
	evo_ids.clear()
	if branch >= 0 and evolvable():
		var br: Dictionary = def.branches[branch]
		if evo1 >= 0:
			var t1 = br.get("evo1", [])
			if t1 is Array and evo1 < (t1 as Array).size():
				var o1: Dictionary = (t1 as Array)[evo1]
				if o1 is Dictionary and o1.has("id"):
					evo_ids.append(String(o1.get("id")))
		if evo2 >= 0:
			var t2 = br.get("evo2", [])
			if t2 is Array and evo2 < (t2 as Array).size():
				var o2: Dictionary = (t2 as Array)[evo2]
				if o2 is Dictionary and o2.has("id"):
					evo_ids.append(String(o2.get("id")))
	for ops in mod_ops:
		_apply(ops as Dictionary)
	_clamp_p()
	_refresh_evos()


## One evolution option for this ability's picked branch. Hand-authored data
## (branch "evo1"/"evo2" tables) only. Cowboy slice authors 2 options per tier per branch.
func evo_option(tier: int, idx: int) -> Dictionary:
	if branch >= 0 and (tier == 1 or tier == 2) and idx >= 0:
		var br: Dictionary = def.branches[branch]
		var table = br.get("evo1" if tier == 1 else "evo2", [])
		if table is Array and idx < (table as Array).size() and (table as Array)[idx] is Dictionary:
			var opt: Dictionary = ((table as Array)[idx] as Dictionary).duplicate(true)
			return opt
	return {}





func _apply_evo_opt(opt: Dictionary) -> void:
	_apply(opt.get("ops", {}))
	if not (opt.get("ops2", {}) as Dictionary).is_empty():
		_apply(opt.get("ops2", {}))
	if not (opt.get("ops3", {}) as Dictionary).is_empty():
		_apply(opt.get("ops3", {}))
	flags.merge(opt.get("flags", {}), true)


## Milestone spikes at 10/13/16. Data-driven when the def carries
## branch_milestones entries; otherwise the branch per_level fires one extra
## time per reached milestone (small damage-forward bump, keeps every kit
## ability meaningful without hand-authoring 40 milestone sets).
func _apply_milestones() -> void:
	var table: Array = []
	if def.get("branch_milestones") is Array:
		table = def.get("branch_milestones")
	for m in MILESTONE_LEVELS:
		if level < int(m):
			continue
		var entry := {}
		for e in table:
			if e is Dictionary and int((e as Dictionary).get("level", -1)) == int(m):
				entry = e
				break
		if not entry.is_empty():
			_apply((entry as Dictionary).get("ops", {}))
			flags.merge((entry as Dictionary).get("flags", {}), true)


func _apply(ops: Dictionary) -> void:
	for k in ops.keys():
		var o: Array = ops[k]
		var cur: float = float(p.get(k, 0.0))
		match String(o[0]):
			"mul":
				p[k] = cur * float(o[1])
			"add":
				p[k] = cur + float(o[1])
			"set":
				p[k] = float(o[1])


func level_up() -> void:
	if not can_level():
		return
	level += 1
	recompute()
	on_changed()


## Attach the owned Black Market mods for this weapon (MarketItemDef list). Later mods override earlier flags.
func set_mods(items: Array) -> void:
	mod_ops = []
	mod_flags = {}
	for it in items:
		mod_ops.append((it.ops as Dictionary).duplicate(true))
		mod_flags.merge((it.flags as Dictionary), true)
	recompute()
	on_changed()


## Snapshot this ability's persistent state (Descent checkpoint). Mods are not
## stored: they are re-derived live from Meta on restore.
func to_dict() -> Dictionary:
	var d: Dictionary = {"id": String(def.id)}
	for k in STATE_KEYS:
		d[k] = get(k)
	return d


## Restore persistent state from a snapshot in place, then recompute. Returns
## false for an empty dict so callers can treat it as absent.
func from_dict(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	for k in STATE_KEYS:
		set(k, int(d.get(k, get(k))))
	recompute()
	on_changed()
	return true


## Branch pick: locks the path but costs no level — the ability keeps whatever
## level it has and grows on this branch from here.
func pick_branch(idx: int) -> void:
	branch = idx
	branch_level = level
	recompute()
	on_changed()


## Evolution pick: one of the two tier options for the picked branch. Free,
## never gates leveling.
func apply_evo(tier: int, idx: int) -> void:
	if branch < 0 or (idx != 0 and idx != 1):
		return
	if tier == 1 and evo1 < 0:
		evo1 = idx
	elif tier == 2 and evo2 < 0:
		evo2 = idx
	else:
		return
	recompute()
	on_changed()


func has_mod(key: String) -> bool:
	return mod_flags.has(key)


## Branch-ready: kit ability at 4 with no path yet. Never forced into the
## draft — the World offers the pair as bonus cards after the next pick.
func needs_branch() -> bool:
	return branch < 0 and evolvable() and level >= BRANCH_LEVEL


## Evolution-ready: picked branch, threshold reached, tier not taken. Bonus
## power only — leveling never waits for it. The tier also requires both
## option ids in READY_EVOS (unimplemented slices never appear).
func needs_evo(tier: int) -> bool:
	if not evolvable():
		return false
	if branch < 0:
		return false
	if tier == 1:
		if not (evo1 < 0 and level >= EVO1_LEVEL):
			return false
		return _tier_ready(1)
	if tier == 2:
		if not (evo1 >= 0 and evo2 < 0 and level >= EVO2_LEVEL):
			return false
		return _tier_ready(2)
	return false


## Both options of the tier are authored in the picked branch and ready
## (behavior implemented for each id).
func _tier_ready(tier: int) -> bool:
	if branch < 0:
		return false
	var br: Dictionary = def.branches[branch]
	var t = br.get("evo1" if tier == 1 else "evo2", [])
	if not (t is Array and (t as Array).size() >= 2):
		return false
	for i in 2:
		var opt = (t as Array)[i]
		if not (opt is Dictionary):
			return false
		if not READY_EVOS.has(String((opt as Dictionary).get("id", ""))):
			return false
	return true


func mod_f(key: String, fallback: float = 0.0) -> float:
	return float(mod_flags.get(key, fallback))


func can_level() -> bool:
	return level < max_level_now()


func branch_name() -> String:
	return "" if branch < 0 else String(def.branches[branch]["name"])


# ---- helpers ------------------------------------------------------------------------------
func dmg(mult: float = 1.0) -> float:
	return float(p.get("damage", 0.0)) * player.stat("damage") * mult


func cd() -> float:
	return player.stat("cooldown")


func world():
	return player.world


# ---- hooks (override) ---------------------------------------------------------------------
func on_ready() -> void:
	pass


func on_changed() -> void:
	pass


func update(_delta: float) -> void:
	pass


func on_kill(_e) -> void:
	hook("on_kill", {"e": _e})


func has_evo(id: String) -> bool:
	for ev in evo_ids:
		if String(ev) == id:
			return true
	return false


## Namespaced evolution param: reads `flags[option_id][key]` with a fallback.
## Evolution option flags are namespaced per option id (see tools/evo_data.py), so
## branch flags stay flat keys while each picked option owns a nested dict.
func evo_param(id: String, key: String, fallback: Variant = 0.0) -> Variant:
	var d = flags.get(id)
	if d is Dictionary:
		return (d as Dictionary).get(key, fallback)
	return fallback


func _clamp_p() -> void:
	var caps: Dictionary = def.get("caps")
	if caps == null or not (caps is Dictionary):
		return
	for k in caps.keys():
		var rng = caps.get(k)
		if rng is Array and rng.size() >= 2:
			var v: float = float(p.get(k, 0.0))
			var mn: float = float(rng[0])
			var mx: float = float(rng[1])
			if mx < mn:
				var tmp = mn; mn = mx; mx = tmp
			if v < mn:
				p[k] = mn
			if v > mx:
				p[k] = mx

## Refresh the live evo_mods list to match the current evo_ids. Creates new
## modules via EvoRegistry.make(), drops ones whose id is no longer picked.
## Note: recompute() fills evo_ids first, so this must not early-return on
## "want == evo_ids" — that would leave evo_mods empty forever.
func _refresh_evos() -> void:
	var want: Array = []
	if branch >= 0:
		if evo1 >= 0:
			want.append(String(evo_option(1, evo1).get("id", "")))
		if evo2 >= 0:
			want.append(String(evo_option(2, evo2).get("id", "")))
	want.erase("")
	if want != evo_ids:
		evo_ids = want
	var keep: Array = []
	for id in evo_ids:
		var m = null
		for old in evo_mods:
			if old.id == id:
				m = old
		if m == null:
			m = EvoRegistry.make(String(id))
			if m == null:
				continue
			m.ab = self
			m.id = String(id)
			m.on_ready()
		keep.append(m)
	evo_mods = keep

## Dispatch `name` to every live evo module; ctx is mutable so modules may edit it.
func hook(name: String, ctx: Dictionary = {}) -> void:
	for m in evo_mods:
		m.call(name, ctx)

## Tick every live evo module's update() and the deferred after() timers. Called
## every frame from Player._process.
func update_evos(delta: float) -> void:
	for m in evo_mods:
		m.update(delta)
	for i in range(_afters.size() - 1, -1, -1):
		var a: Dictionary = _afters[i]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			_afters.remove_at(i)
			var cb: Callable = a["cb"]
			if cb.is_valid():
				cb.call()

## Spend (consume and return) the movement/charge meter value for `key`.
func meter_spend(key: String) -> float:
	var v: float = float(prim_meters.get(key, 0.0))
	prim_meters[key] = 0.0
	return v


# ---- Phase 1 primitives -------------------------------------------------------------------
## Primitive 1: a movement/charge meter. Grows while `moving`, decays otherwise, clamps to
## [0, cap]; returns the value after the step so callers can act on thresholds.
func meter(key: String, delta: float, moving: bool, up: float, down: float, cap: float) -> float:
	var v: float = float(prim_meters.get(key, 0.0))
	v += delta * (up if moving else -down)
	v = clampf(v, 0.0, cap)
	prim_meters[key] = v
	return v


## Primitive 2: true once every `n` calls for the given key; the counter then resets.
func nth(key: String, n: int) -> bool:
	if n <= 0:
		return false
	var c: int = int(prim_nth.get(key, 0)) + 1
	if c >= n:
		prim_nth[key] = 0
		return true
	prim_nth[key] = c
	return false


## Primitive 10: run `cb` after `delay` seconds. Ticked by Player via tick_afters
## (subclass update() overrides do not chain to super, so the Player owns the tick).
func after(delay: float, cb: Callable) -> void:
	_afters.append({"t": maxf(delay, 0.0), "cb": cb})


func tick_afters(delta: float) -> void:
	for i in range(_afters.size() - 1, -1, -1):
		var a: Dictionary = _afters[i]
		a["t"] = float(a["t"]) - delta
		if float(a["t"]) <= 0.0:
			_afters.remove_at(i)
			var cb: Callable = a["cb"]
			if cb.is_valid():
				cb.call()


func on_attack(_info) -> void:
	var ctx: Dictionary = _info if _info is Dictionary else {}
	hook("on_attack", ctx)


func on_hit(_e, _amount) -> void:
	hook("on_hit", {"e": _e, "amount": _amount})


func on_player_hurt(_amount) -> void:
	pass


## Called by Player.take_damage BEFORE hp is reduced: return true to cancel the hit
## (an ally body soaks it). The passive is asked first, then the weapon.
func absorb_hit(_amount: float) -> bool:
	return false


## Multiplier applied to incoming damage after flat defense. Source position is
## Vector2.INF when the hit has no direction (e.g. an untraceable global effect).
func incoming_damage_mult(_amount: float, _source_pos: Vector2, _source: String) -> float:
	return 1.0


func on_armor_break() -> void:
	pass


func draw_overlay(_canvas: Node2D) -> void:
	pass


func hud_line() -> String:
	return ""
