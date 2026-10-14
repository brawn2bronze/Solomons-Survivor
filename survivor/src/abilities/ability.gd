class_name Ability
extends RefCounted
## Runtime instance of a WeaponDef / PassiveDef. Effective numbers live in `p` (base + level scaling +
## chosen branch), recomputed whenever the level or branch changes. Subclasses override the hooks below.

const BRANCH_LEVEL := 4         # branch pair (A/B) owed when a kit ability reaches 4
const EVO1_LEVEL := 8           # first evolution (branch-specific) owed at 8
const EVO2_LEVEL := 16          # final evolution (same line) owed at 16
const POST_MAX := 16            # kit ceiling; leveling never gates on picks
const MILESTONE_LEVELS := [10, 13]  # small pacing bumps between the evolutions

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
            _apply_milestones(b)
            if evo1 >= 0:
                _apply_evo_opt(evo_option(1, evo1))
            if evo2 >= 0:
                _apply_evo_opt(evo_option(2, evo2))
    for ops in mod_ops:
        _apply(ops as Dictionary)


## One evolution option for this ability's picked branch. Hand-authored data
## (branch "evo1"/"evo2" tables) wins; otherwise a generated fallback derived
## from the branch's own ops, so the pair is never empty and always
## branch-flavored. Shape: {name, desc, ops, ops2?, ops3?, flags}.
func evo_option(tier: int, idx: int) -> Dictionary:
    if branch >= 0 and (tier == 1 or tier == 2) and (idx == 0 or idx == 1):
        var br: Dictionary = def.branches[branch]
        var table = br.get("evo1" if tier == 1 else "evo2", [])
        if table is Array and idx < (table as Array).size() and (table as Array)[idx] is Dictionary:
            var opt: Dictionary = ((table as Array)[idx] as Dictionary).duplicate(true)
            opt["fallback"] = false
            return opt
    return _fallback_evo(tier, idx)


func _fallback_evo(tier: int, idx: int) -> Dictionary:
    var br: Dictionary = def.branches[branch] if branch >= 0 else {}
    var per: Dictionary = (br.get("per_level", {}) as Dictionary).duplicate(true)
    var pick: Dictionary = (br.get("on_pick", {}) as Dictionary).duplicate(true)
    var bname := branch_name()
    if tier == 2:
        if idx == 0:
            return {"name": bname + " Ascension", "desc": "Final evolution of " + bname + ": its gift and its growth, both unleashed.", "ops": pick, "ops2": per, "ops3": per, "flags": {}, "fallback": true}
        return {"name": bname + " Transcendence", "desc": "Final evolution of " + bname + ": growth beyond growth, threefold.", "ops": per, "ops2": per, "ops3": per, "flags": {}, "fallback": true}
    if idx == 0:
        return {"name": bname + " Surge", "desc": "Evolve " + bname + ": its per-level growth strikes twice as hard.", "ops": per, "ops2": per, "flags": {}, "fallback": true}
    return {"name": bname + " Focus", "desc": "Evolve " + bname + ": feel its gift a second time.", "ops": pick, "flags": {}, "fallback": true}


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
func _apply_milestones(b: Dictionary) -> void:
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
        if entry.is_empty():
            _apply(b["per_level"])
        else:
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
## power only — leveling never waits for it.
func needs_evo(tier: int) -> bool:
    if not evolvable():
        return false
    if tier == 1:
        return branch >= 0 and evo1 < 0 and level >= EVO1_LEVEL
    if tier == 2:
        return evo1 >= 0 and evo2 < 0 and level >= EVO2_LEVEL
    return false


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
    pass


func on_armor_break() -> void:
    pass


func draw_overlay(_canvas: Node2D) -> void:
    pass


func hud_line() -> String:
    return ""
