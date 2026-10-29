class_name EnemyManager
extends Node
## All enemies live here as plain data objects (E) driven by ONE loop - no per-enemy scripts.
## Sprites are pooled Sprite2D nodes parented to the y-sorted Actors node. Neighbour queries use a
## spatial hash rebuilt every frame. This is the piece that has to hold 60 FPS at 200+ enemies.

const CELL := 48.0
const MAX_POOL := 460
const MAX_ALIVE := 300
const PLAYER_RADIUS := 8.0
# Burn status (Archive "Brimstone Breath" mod) and the unique boss (EnemyDef.boss_time).
const BURN_FX_EVERY := 24            # a burning enemy sheds an ember every N frames (keeps particles cheap)
const BURN_TINT := Color(1.0, 0.62, 0.38)
const BOSS_SPAWN_DIST := 420.0
const BOSS_FIRE_RANGE := 480.0       # the boss only fires its ring when the player is this close
const BOSS_RING := 14                # radial bullet ring size
const BOSS_RING_ENRAGED := 22
const BOSS_ENRAGE_HP := 0.4          # below this fraction of max hp the boss enrages
const BOSS_ENRAGE_SPEED := 1.35
const BOSS_ENRAGE_FIRE := 0.7        # enraged ring cooldown multiplier
const BOSS_TELEGRAPH_T := 0.45       # cosmetic pre-warning window (shoot-timer seconds); never delays a volley
const BLINK_WAIT_MIN := 2.0         # blink (reserved hunt-blink): stalk seconds before blink
const BLINK_WAIT_MAX := 3.5
const BLINK_VANISH_T := 0.12        # invisible + invulnerable window (matches white-out frame)
const BLINK_RING_MIN := 90.0        # reappear ring around player
const BLINK_RING_MAX := 160.0
const GLITCH_JITTER := 3.0          # glitch goblin: stalk micro-jitter px (RGB-split feel)
const LAG_SKIP_MIN := 1.2           # glitch goblin: stalk seconds before a lag spike
const LAG_SKIP_MAX := 2.4
const LAG_HANG_T := 0.5             # frozen hang (dropped-frames read, damage-immune, no telegraph)
const LAG_HOPS := 4                 # stutter jerks toward the player after the hang
const LAG_HOP_T := 0.06             # seconds between jerks
const LAG_HOP_D := 18.0             # px per jerk along live dir-to-player

class E:
	var uid := 0
	var def
	var sprite: Sprite2D
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var sep := Vector2.ZERO
	var hp := 0.0
	var max_hp := 0.0
	var radius := 9.0
	var speed := 50.0
	var dmg := 0.0
	var alive := false
	var is_elite := false
	var slot := -1
	var stun := 0.0
	var fear := 0.0
	var fear_from := Vector2.ZERO
	var slow := 1.0
	var cc_immune_t := 0.0
	var marks := {}
	var hit_gate := {}
	var atk_slow := 1.0
	var slow_t := 0.0
	var contact_mult := 1.0         # smoke veil: contact-damage multiplier while inside
	var contact_mult_t := 0.0
	var poison_dps := 0.0
	var poison_t := 0.0
	var burn_dps := 0.0
	var burn_t := 0.0
	var infect_t := 0.0
	var flash := 0.0
	var anim_t := 0.0
	var phase := 0.0
	var knock := Vector2.ZERO
	var state := 0
	var state_t := 0.0
	var dash_dir := Vector2.ZERO
	var shoot_t := 0.0
	var contact_cd := 0.0
	var web = null
	var volley := 0               # boss: volleys fired (spiral replaces every Nth)
	var spiral_t := 0.0           # boss: spiral cast in progress
	var spiral_ang := 0.0
	var spiral_sign := 1.0
	var spiral_fired := 0
	var enraged_seen := false     # boss: enrage callout already fired
	var summoned := false         # boss adds (Creditors): no Fragment drop, still drops gems
	var atk := ""                 # boss_broker: current attack kind
	var atk_phase := 0            # boss_broker: 0 telegraph, 1 execute, 2 recover
	var atk_t := 0.0
	var deck_bag: Array = []   # boss_broker: shuffled remaining deck
	var last_atk := ""            # boss_broker: never the same kind twice in a row
	var add_t := 0.0              # boss_broker: seconds until the next Creditors summon
	var burst_left := 0           # boss_broker: fan bursts still to fire
	var burst_t := 0.0
	var aim := Vector2.ZERO       # boss_broker: locked telegraph aim

static var _flash_material: ShaderMaterial

var world
var player
var actors: Node2D
var active: Array[E] = []
var elites: Array[E] = []
var _free: Array[E] = []
var _grid: Dictionary = {}
var _bucket_free: Array = []
var _bucket_used: Array = []
var _uid := 0
var _frame := 0
var _spawn_acc := 0.0
var _spawnable: Array = []
var _elite_defs: Array = []
var _elite_next: Dictionary = {}
var _boss_defs: Array = []              # defs with boss_time > 0 (one timed spawn per run)
var _boss_spawned: Dictionary = {}
var _event_next := 50.0
var _dead: Array[E] = []
var _act_tint := Color.WHITE     # act enemy_tint, refreshed on act_changed
var _last_elite_time := -1000.0  # run second of the last elite spawn (act cooldown gate)
var _breather_t := 0.0           # zero-director-spawns window (act transitions)
# --- Dev / sandbox overrides (set via apply_dev_config) ----------------------
var allowed_ids: Array = []       # whitelist of enemy ids; empty = no filter
var elite_only := false
var spawn_mult := 1.0             # director rate multiplier (lag test)
var director_paused := false


## Apply sandbox spawn rules. Safe to call with empty dict (resets to normal).
## Paused = zero director spawns (regular, elite timer, boss one-shots, bat
## ring); manual spawn_around_id() still works for enemy isolation. Timers are
## seeded from the jump-in clock so skipping to boss time yields the boss
## without a stale bat catch-up burst on top.
func apply_dev_config(cfg: Dictionary) -> void:
	allowed_ids = (cfg.get("allowed_enemies", []) as Array).duplicate()
	elite_only = bool(cfg.get("elite_only", false))
	spawn_mult = maxf(0.0, float(cfg.get("spawn_mult", 1.0)))
	director_paused = bool(cfg.get("director_paused", false))
	_spawn_acc = 0.0
	_rebuild_spawn_lists()
	var start_t := maxf(0.0, float(cfg.get("start_time", 0.0)))
	_event_next = maxf(50.0, start_t + 60.0)
	for id in _elite_next.keys():
		_elite_next[id] = maxf(float(_elite_next[id]), start_t)
	_boss_spawned.clear()
	_last_elite_time = -1000.0
	_breather_t = 0.0


func _rebuild_spawn_lists() -> void:
	_spawnable.clear()
	_elite_defs.clear()
	_elite_next.clear()
	_boss_defs.clear()
	for def in DB.enemies.values():
		if not allowed_ids.is_empty() and not allowed_ids.has(def.id):
			continue
		if elite_only and not def.is_elite:
			continue
		if def.boss_time > 0.0:
			_boss_defs.append(def)
		if def.spawn_weight > 0.0 or not allowed_ids.is_empty():
			# Whitelisted ids are spawnable even when spawn_weight == 0 (e.g. goblin_brute).
			if allowed_ids.is_empty() and def.spawn_weight <= 0.0:
				continue
			_spawnable.append(def)
		if def.elite_every > 0.0:
			if allowed_ids.is_empty() or allowed_ids.has(def.id):
				_elite_defs.append(def)
				_elite_next[def.id] = def.spawn_start


## One-shot helpers used by DevMenu / DevOverlay.
func spawn_around(def, count: int, min_r: float = 120.0, max_r: float = 320.0) -> int:
	var n := 0
	for i in count:
		var ang := randf() * TAU
		var p: Vector2 = player.global_position + Vector2.from_angle(ang) * randf_range(min_r, max_r)
		if spawn(def, p) != null:
			n += 1
	return n


func spawn_around_id(enemy_id: String, count: int) -> int:
	var def = DB.enemies.get(enemy_id)
	if def == null:
		return 0
	return spawn_around(def, count)


## Act transition: refresh the cached enemy tint and re-apply it to live sprites.
func _on_act_changed(_i: int) -> void:
	var act = world.acts.current()
	if act == null:
		return
	_act_tint = act.enemy_tint
	for e in active:
		if e.stun <= 0.0 and e.slow >= 1.0 and e.fear <= 0.0 and e.burn_t <= 0.0:
			e.sprite.modulate = _resting_tint(e)


func kill_all() -> void:
	for e in active:
		_dead.append(e)


func clear_to(n: int) -> void:
	# Trim extras (used after stress tests). _kill swap-pops from active, so the loop shrinks.
	while active.size() > n and not active.is_empty():
		_kill(active.back(), true)


## Zero director spawns for the given seconds (act transitions; dev pause is separate).
func breather(seconds: float) -> void:
	_breather_t = maxf(_breather_t, seconds)


## Any active unique boss (boss_time > 0). Drives boss music + act hold checks.
func boss_alive() -> bool:
	for e in active:
		if float(e.def.boss_time) > 0.0:
			return true
	return false


## Quiet field wipe for act transitions: no drops, no on_kill, and at most
## ~12 death bursts total (a 150-enemy burst storm would spike the frame).
func wipe_quiet() -> void:
	var snapshot: Array[E] = active.duplicate()
	var burst_budget := 12
	for e in snapshot:
		if not e.alive:
			continue
		var silent: bool = burst_budget <= 0
		burst_budget -= 1
		_kill(e, true, silent)
	_dead.clear()


static func flash_material() -> ShaderMaterial:
	if _flash_material == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() { vec4 c = texture(TEXTURE, UV); COLOR = vec4(vec3(1.0), c.a * COLOR.a); }"
		_flash_material = ShaderMaterial.new()
		_flash_material.shader = sh
	return _flash_material


func setup(world_ref, actors_node: Node2D) -> void:
	world = world_ref
	player = world.player
	actors = actors_node
	if world.acts != null:
		world.acts.act_changed.connect(_on_act_changed)
		var act = world.acts.current()
		if act != null:
			_act_tint = act.enemy_tint
	for i in MAX_POOL:
		var e := E.new()
		var sp := Sprite2D.new()
		sp.visible = false
		sp.offset = Vector2(0, -22)
		actors.add_child(sp)
		e.sprite = sp
		_free.append(e)
	for def in DB.enemies.values():
		if def.spawn_weight > 0.0:
			_spawnable.append(def)
		if def.elite_every > 0.0:
			_elite_defs.append(def)
			_elite_next[def.id] = def.spawn_start
		if def.boss_time > 0.0:
			_boss_defs.append(def)


# ------------------------------------------------------------------ spawning
func spawn(def, pos: Vector2, hp_mult: float = 1.0, dmg_mult: float = 1.0):
	if _free.is_empty():
		return null
	var e: E = _free.pop_back()
	_uid += 1
	e.uid = _uid
	e.def = def
	e.pos = pos
	e.vel = Vector2.ZERO
	e.sep = Vector2.ZERO
	e.max_hp = def.max_hp * hp_mult
	e.hp = e.max_hp
	e.radius = def.radius
	e.speed = def.speed * randf_range(0.92, 1.08)
	if float(def.boss_time) <= 0.0 and world.acts != null:
		e.speed *= world.acts.current().speed_mult
	e.dmg = def.contact_damage * dmg_mult
	e.alive = true
	e.is_elite = def.is_elite
	e.stun = 0.0
	e.fear = 0.0
	e.slow = 1.0
	e.atk_slow = 1.0
	e.slow_t = 0.0
	e.cc_immune_t = 0.0
	e.marks.clear()
	e.hit_gate.clear()
	e.poison_t = 0.0
	e.poison_dps = 0.0
	e.burn_t = 0.0
	e.burn_dps = 0.0
	e.infect_t = 0.0
	e.flash = 0.0
	e.knock = Vector2.ZERO
	e.state = 0
	e.state_t = randf_range(0.6, 2.2)
	if String(def.behavior) == "glitch":
		e.state_t = randf_range(LAG_SKIP_MIN, LAG_SKIP_MAX)
	elif String(def.behavior) == "blink":
		e.state_t = randf_range(BLINK_WAIT_MIN, BLINK_WAIT_MAX)
	e.shoot_t = randf_range(0.6, maxf(0.7, def.shoot_interval))
	e.contact_cd = 0.0
	e.volley = 0
	e.spiral_t = 0.0
	e.spiral_ang = 0.0
	e.spiral_sign = 1.0
	e.spiral_fired = 0
	e.enraged_seen = false
	e.summoned = false
	e.atk = ""
	e.atk_phase = 0
	e.atk_t = 0.0
	e.deck_bag = []
	e.last_atk = ""
	e.add_t = 6.0 if String(def.behavior) == "boss_broker" else 0.0
	e.burst_left = 0
	e.burst_t = 0.0
	e.aim = Vector2.ZERO
	e.phase = randf() * TAU
	e.web = null
	var sp := e.sprite
	sp.texture = DB.texture(def.sprite)
	sp.hframes = def.frames
	sp.frame = 0
	sp.scale = Vector2.ONE * def.sprite_scale
	sp.material = null
	sp.modulate = _resting_tint(e)
	sp.flip_h = false
	sp.position = pos
	sp.visible = true
	e.slot = active.size()
	active.append(e)
	if e.is_elite:
		elites.append(e)
	if world != null and world.fx != null:
		world.fx.summon(e.pos, def.sprite_scale)
	return e


func _spawn_ring(def, count: int, t: float) -> void:
	var act = world.acts.current() if world.acts != null else null
	var hp_mult: float = (1.0 + t / 240.0) * (float(act.hp_mult) if act != null else 1.0)
	var dmg_mult: float = (1.0 + t / 600.0) * (float(act.dmg_mult) if act != null else 1.0)
	var base := randf() * TAU
	for i in count:
		var ang := base + float(i) / float(maxi(count, 1)) * TAU * 0.35 + randf_range(-0.05, 0.05)
		var p: Vector2 = player.global_position + Vector2.from_angle(ang) * randf_range(390.0, 430.0)
		spawn(def, p, hp_mult, dmg_mult)


func _tick_director(delta: float) -> void:
	if director_paused:
		return
	if world.acts != null and world.acts.clock_held:
		return
	if _breather_t > 0.0:
		_breather_t -= delta
		return
	var t: float = world.run_time
	var act = world.acts.current() if world.acts != null else null
	var hp_m: float = act.hp_mult if act != null else 1.0
	var dmg_m: float = act.dmg_mult if act != null else 1.0
	var rate_m: float = act.spawn_rate_mult if act != null else 1.0
	var elite_cd: float = act.elite_cooldown if act != null else 60.0
	var target := clampi(int(16.0 + t * 0.55 + pow(t / 60.0, 1.4) * 9.0), 16, MAX_ALIVE)
	var seal_mult := maxf(0.2, 1.0 + Meta.get_seal_bonus("reinforced_walls"))
	_spawn_acc += delta * (5.0 + t * 0.045) * spawn_mult * seal_mult * rate_m
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if active.size() >= target:
			_spawn_acc = 0.0
			break
		var def = _pick_def(t)
		if def == null:
			break
		var ang := randf() * TAU
		var p: Vector2 = player.global_position + Vector2.from_angle(ang) * randf_range(390.0, 430.0)
		spawn(def, p, (1.0 + t / 240.0) * hp_m, (1.0 + t / 600.0) * dmg_m)
	# elites: none before 180s; an act cooldown gates how often they may spawn.
	if t >= 180.0:
		for def in _elite_defs:
			if t >= float(_elite_next[def.id]):
				if t - _last_elite_time < elite_cd:
					continue    # leave _elite_next untouched so it fires when allowed
				_last_elite_time = t
				_elite_next[def.id] = t + def.elite_every
				var ang2 := randf() * TAU
				var e = spawn(def, player.global_position + Vector2.from_angle(ang2) * 420.0, (1.0 + t / 200.0) * hp_m, (1.0 + t / 500.0) * dmg_m)
				if e != null:
					Audio.sfx("elite_enemy_spawn", -2.0, 1.0, 0.0)
					world.announce("%s approaches" % def.display_name.to_upper(), def.height == 1)
					Game.shake(4.0)
	# the current act's unique boss only (sealed/missing defs like Lucifer are skipped).
	# On spawn the clock + director freeze via acts.hold_for_boss until the next act.
	# PRE-BATTLE HOOK: future boss intro dialogue pauses the director here before the spawn.
	if act != null and String(act.boss_id) != "":
		var bdef = DB.enemies.get(String(act.boss_id))
		if bdef != null and not _boss_spawned.has(bdef.id) and t >= float(bdef.boss_time):
			_boss_spawned[bdef.id] = true
			var boss = spawn(bdef, player.global_position + Vector2.from_angle(randf() * TAU) * BOSS_SPAWN_DIST)
			if boss != null:
				Audio.sfx("elite_enemy_spawn", 0.0, 0.7, 0.0)
				world.announce("%s HAS ARRIVED" % String(bdef.display_name).to_upper(), true)
				Game.shake(7.0)
				world.acts.hold_for_boss(bdef)
			else:
				_boss_spawned.erase(bdef.id)   # pool was full: retry next frame
	# bat swarm event (respects the sprite whitelist so isolation stays isolated)
	if t >= _event_next:
		_event_next = t + 60.0
		var bat = DB.enemies.get("bat")
		if bat != null and t >= bat.spawn_start:
			if allowed_ids.is_empty() or allowed_ids.has("bat"):
				_spawn_ring(bat, 26, t)
				world.announce("SWARM!", true)


func _pick_def(t: float):
	var total := 0.0
	for d in _spawnable:
		if t >= d.spawn_start and t <= d.spawn_end:
			# Whitelisted zero-weight elites (e.g. goblin_brute) still need a pickable weight.
			total += d.spawn_weight if d.spawn_weight > 0.0 else 1.0
	if total <= 0.0:
		return null
	var r := randf() * total
	for d in _spawnable:
		if t >= d.spawn_start and t <= d.spawn_end:
			r -= d.spawn_weight if d.spawn_weight > 0.0 else 1.0
			if r <= 0.0:
				return d
	return _spawnable[0]


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if world == null or not world.sim_running:
		return
	delta = minf(delta, 1.0 / 30.0)
	_frame += 1
	_rebuild_grid()
	_tick_director(delta)
	var pp: Vector2 = player.global_position
	# Snapshot: contact damage can call player on-hurt procs that kill enemies
	# mid-loop, and _kill() swap-pops `active`, which invalidates live indices.
	for e in active.duplicate():
		if e.alive:
			_update_enemy(e, delta, pp)
	for e in _dead:
		if e.alive:
			_kill(e)
	_dead.clear()
	for e in elites:
		_elite_aura(e)


## Ground glow + slow pulsing ring under elites and bosses (a persistent cue, so no shape-pool cost).
## Elite = amber; boss = deep red, faster and hotter once enraged.
func _elite_aura(e: E) -> void:
	if not e.alive:
		return
	var col := Color(1.0, 0.7, 0.25)
	var rate := 2.4
	var rad: float = e.radius * 2.2 + 6.0
	if float(e.def.boss_time) > 0.0:
		col = Color(1.0, 0.3, 0.2) if e.enraged_seen else Color(0.85, 0.25, 0.35)
		rate = 7.0 if e.enraged_seen else 2.0
		rad = e.radius * 2.0 + 14.0
	world.fx.cue_aura(e.get_instance_id(), 3, e.pos, rad, col, rate)


func _update_enemy(e: E, delta: float, pp: Vector2) -> void:
	var d: EnemyDef = e.def
	# Lab target prop: infinite health. DoT ticks bypass damage(), so pin HP here.
	if String(d.behavior) == "dummy":
		e.hp = e.max_hp
	e.flash = maxf(0.0, e.flash - delta)
	e.contact_cd -= delta * e.atk_slow
	e.cc_immune_t = maxf(0.0, e.cc_immune_t - delta)
	for k in e.hit_gate.keys():
		e.hit_gate[k] = float(e.hit_gate[k]) - delta
		if e.hit_gate[k] <= 0.0:
			e.hit_gate.erase(k)
	if not e.marks.is_empty():
		for mk in e.marks.keys():
			var mv = e.marks[mk]
			if mv is Dictionary and float(mv.get("t", 0.0)) > 0.0:
				var remain: float = float(mv["t"]) - delta
				if remain <= 0.0:
					e.marks.erase(mk)
				else:
					mv["t"] = remain
	if e.slow_t > 0.0:
		e.slow_t -= delta
		if e.slow_t <= 0.0:
			e.slow = 1.0
			e.atk_slow = 1.0
	if e.contact_mult_t > 0.0:
		e.contact_mult_t -= delta
		if e.contact_mult_t <= 0.0:
			e.contact_mult = 1.0
	if e.poison_t > 0.0:
		e.poison_t -= delta
		e.hp -= e.poison_dps * delta
		_maybe_execute(e)
		if e.hp <= 0.0:
			_dead.append(e)
	if e.burn_t > 0.0:
		e.burn_t -= delta
		e.hp -= e.burn_dps * delta
		_maybe_execute(e)
		if e.hp <= 0.0:
			_dead.append(e)
		elif (e.uid + _frame) % BURN_FX_EVERY == 0:
			world.fx.emit(e.pos + Vector2(randf_range(-4.0, 4.0), -e.radius), Vector2(0, -34.0), 0.35, 2.2, Color(1.0, 0.55, 0.18), 1, 1.0)
	if e.infect_t > 0.0:
		e.infect_t -= delta
	var to_p := pp - e.pos
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var move := Vector2.ZERO
	if e.stun > 0.0:
		e.stun -= delta
		if e.stun <= 0.0:
			e.stun = 0.0
			e.cc_immune_t = 1.5
	elif e.fear > 0.0:
		e.fear -= delta
		if e.fear <= 0.0:
			e.fear = 0.0
			e.cc_immune_t = 1.5
		move = (e.pos - e.fear_from).normalized() * e.speed * 1.35
	else:
		match d.behavior:
			"swarm":
				e.phase += delta * 4.0
				move = (dir + dir.orthogonal() * sin(e.phase) * 0.7).normalized() * e.speed
			"charger":
				move = _charger(e, delta, dir, dist)
			"glitch":
				move = _glitch(e, delta, dir, dist)
			"dummy":
				# Lab target prop: rooted; the FX gallery re-pins it each Attack press.
				move = Vector2.ZERO
			"blink":
				move = _blink(e, delta, dir, dist)
			"ranged":
				move = _ranged(e, delta, dir, dist)
			"boss":
				move = _boss(e, delta, dir, dist)
			"boss_broker":
				move = _boss_broker(e, delta, dir, dist)
			_:
				move = dir * e.speed
		move *= e.slow
	# separation (half the enemies per frame; result is reused)
	if (e.uid + _frame) & 1 == 0:
		e.sep = _separation(e)
	e.vel = e.vel.lerp(move + e.sep * 46.0, minf(1.0, delta * 9.0))
	e.pos += (e.vel + e.knock) * delta
	e.knock *= exp(-8.0 * delta)
	# contact damage (blink vanish cannot touch while vanished; glitch fodder always touches)
	if e.contact_cd <= 0.0 and e.stun <= 0.0 and e.fear <= 0.0 and dist < e.radius + PLAYER_RADIUS and not (String(d.behavior) == "blink" and e.state == 1) and not player.untargetable:
		e.contact_cd = 0.75
		player.take_damage(e.dmg * e.contact_mult, d.height == 1 or d.can_hit_flying, d.display_name, e.pos)
	# visuals
	var sp := e.sprite
	sp.position = e.pos + Vector2(0, -9.0 if d.height == 1 else 0.0)
	var is_blink_vanished: bool = String(d.behavior) == "blink" and e.state == 1
	if e.stun > 0.0:
		sp.frame = 0
	elif String(d.behavior) == "glitch" or String(d.behavior) == "dummy":
		# Random-skip playback preserves the authored white-out / dark strobe (4-frame 64px strip).
		# Frozen during the lag hang so the sprite visibly stalls, then snaps to a fresh frame.
		if e.state != 1:
			e.anim_t += delta * 12.0 * clampf(e.slow, 0.3, 1.0)
			if e.anim_t >= 1.0:
				e.anim_t = 0.0
				sp.frame = randi() % maxi(d.frames, 1)
	elif String(d.behavior) == "blink":
		e.anim_t += delta * 12.0 * clampf(e.slow, 0.3, 1.0)
		if e.anim_t >= 1.0:
			e.anim_t = 0.0
			sp.frame = randi() % maxi(d.frames, 1)
	else:
		e.anim_t += delta * 8.0 * clampf(e.slow, 0.3, 1.0)
		sp.frame = int(e.anim_t) % d.frames
	if absf(e.vel.x) > 4.0:
		sp.flip_h = e.vel.x > 0.0
	if e.flash > 0.0:
		sp.material = flash_material()
	elif sp.material != null:
		sp.material = null
	if e.stun > 0.0:
		sp.modulate = Color(0.75, 0.85, 1.0)
	elif is_blink_vanished:
		sp.modulate = Color(1.0, 1.0, 1.0, 0.0)
	elif e.slow < 1.0:
		sp.modulate = Color(0.85, 0.95, 0.85)
	elif e.fear > 0.0:
		sp.modulate = Color(1.0, 0.9, 0.5)
	elif e.burn_t > 0.0:
		sp.modulate = BURN_TINT
	else:
		sp.modulate = _resting_tint(e)


## Resting modulate: elite base tint x EnemyDef.tint x the act's enemy_tint.
## Status tints (stun/slow/fear/burn) still override in _update_enemy.
func _resting_tint(e: E) -> Color:
	var base := Color(1.0, 0.82, 0.82) if e.is_elite else Color.WHITE
	return base * e.def.tint * _act_tint


func _charger(e: E, delta: float, dir: Vector2, dist: float) -> Vector2:
	match e.state:
		0:
			e.state_t -= delta
			if e.state_t <= 0.0 and dist < 190.0:
				e.state = 1
				e.state_t = 0.45
				e.dash_dir = dir
			return dir * e.speed
		1:
			e.state_t -= delta
			e.dash_dir = dir
			e.flash = maxf(e.flash, 0.03) if int(e.state_t * 20.0) % 2 == 0 else e.flash
			if e.state_t <= 0.0:
				e.state = 2
				e.state_t = 0.4
			return Vector2.ZERO
		_:
			e.state_t -= delta
			if e.state_t <= 0.0:
				e.state = 0
				e.state_t = randf_range(1.6, 2.6)
			return e.dash_dir * e.speed * 3.4


## Blink (reserved hunt-blink, no def uses it yet - future elite): swarm-wobble stalk
## with micro-jitter, then a vanish into a hunt-blink reappear on a ring around the
## player. Vanish is invisible + invulnerable + non-contact.
func _blink(e: E, delta: float, dir: Vector2, _dist: float) -> Vector2:
	match e.state:
		1:
			e.state_t -= delta
			if e.state_t <= 0.0:
				var ang := randf() * TAU
				e.pos = player.global_position + Vector2.from_angle(ang) * randf_range(BLINK_RING_MIN, BLINK_RING_MAX)
				e.vel = Vector2.ZERO
				e.knock = Vector2.ZERO
				e.state = 0
				e.state_t = randf_range(BLINK_WAIT_MIN, BLINK_WAIT_MAX)
				e.flash = 0.09
				world.fx.ring(e.pos, 10.0, 60.0, 0.25, Color(0.35, 0.95, 1.0), 2.0)
			return Vector2.ZERO
		_:
			e.state_t -= delta
			if e.state_t <= 0.0:
				e.state = 1
				e.state_t = BLINK_VANISH_T
				world.fx.ring(e.pos, 10.0, 60.0, 0.25, Color(0.35, 0.95, 1.0), 2.0)
				return Vector2.ZERO
			e.phase += delta * 4.0
			var wobble := (dir + dir.orthogonal() * sin(e.phase) * 0.7).normalized() * e.speed
			wobble += Vector2(randf_range(-GLITCH_JITTER, GLITCH_JITTER), randf_range(-GLITCH_JITTER, GLITCH_JITTER)) * 12.0
			return wobble


## Glitch goblin (Act 2 fodder): packet-loss lag. Swarm-wobble stalk with micro-jitter,
## then a hard freeze (damage-immune, frame held, no telegraph) into a homing stutter -
## small rapid jerks toward the player's live position. Rubber-banding, not a teleport.
func _glitch(e: E, delta: float, dir: Vector2, _dist: float) -> Vector2:
	match e.state:
		1:
			e.state_t -= delta
			if e.state_t <= 0.0:
				e.state = 2
				e.state_t = float(LAG_HOPS) * LAG_HOP_T
				e.phase = float(LAG_HOPS)
			return Vector2.ZERO
		2:
			e.state_t -= delta
			while e.phase > 0.0 and e.state_t <= (e.phase - 1.0) * LAG_HOP_T:
				var hop_dir := (dir + dir.orthogonal() * randf_range(-0.3, 0.3)).normalized()
				e.pos += hop_dir * LAG_HOP_D
				e.phase -= 1.0
				e.flash = 0.09
				e.anim_t = 1.0
			if e.phase <= 0.0 or e.state_t <= 0.0:
				e.state = 0
				e.state_t = randf_range(LAG_SKIP_MIN, LAG_SKIP_MAX)
			return Vector2.ZERO
		_:
			e.state_t -= delta
			if e.state_t <= 0.0:
				e.state = 1
				e.state_t = LAG_HANG_T
				e.knock = Vector2.ZERO
				return Vector2.ZERO
			e.phase += delta * 4.0
			var wobble := (dir + dir.orthogonal() * sin(e.phase) * 0.7).normalized() * e.speed
			wobble += Vector2(randf_range(-GLITCH_JITTER, GLITCH_JITTER), randf_range(-GLITCH_JITTER, GLITCH_JITTER)) * 12.0
			return wobble


func _ranged(e: E, delta: float, dir: Vector2, dist: float) -> Vector2:
	e.shoot_t -= delta * e.atk_slow
	if e.shoot_t <= 0.0 and dist < 340.0:
		e.shoot_t = e.def.shoot_interval
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -10), dir * e.def.shoot_speed, e.def.shoot_damage, e.def.height == 1)
	if dist > 200.0:
		return dir * e.speed
	if dist < 130.0:
		return -dir * e.speed * 0.8
	return dir.orthogonal() * e.speed * 0.6


## Unique boss: the charger wind-up/dash cycle plus volleys on its shoot timer; enrages at low health.
## Volley cycle: aimed fan + radial ring, except every spiral_every-th volley which casts a rotating
## spiral burst instead. Enrage threshold/cooldown come from the def (defaults = stock 40% / 0.7x).
func _boss(e: E, delta: float, dir: Vector2, dist: float) -> Vector2:
	var d = e.def
	var enraged: bool = e.hp < e.max_hp * float(d.enrage_hp_fraction)
	if enraged and not e.enraged_seen:
		e.enraged_seen = true
		world.fx.enrage_feel(e.pos)
	_spiral_tick(e, d, delta)
	e.shoot_t -= delta * e.atk_slow
	if e.shoot_t <= 0.0 and dist < BOSS_FIRE_RANGE:
		var interval: float = d.shoot_interval * (float(d.enrage_interval_mult) if enraged else 1.0)
		e.shoot_t = interval
		e.volley += 1
		var every: int = int(d.spiral_every)
		if every > 0 and int(d.spiral_projectile_count) > 0 and e.volley % every == 0:
			_spiral_start(e, d)
		else:
			_ring_volley(e, d, dir, enraged)
	elif e.shoot_t > 0.0 and e.shoot_t < BOSS_TELEGRAPH_T and dist < BOSS_FIRE_RANGE:
		_boss_telegraph(e, d, dir, enraged)
	var move: Vector2 = _charger(e, delta, dir, dist)
	return move * (BOSS_ENRAGE_SPEED if enraged else 1.0)


## Cosmetic pre-warning for the volley about to fire. It is read straight off the shoot timer, so it
## never changes timing: orange converging ring before a spiral cast; pale ring + aim wedge before a
## ring/fan volley (red-shifted when enraged). Refreshed every frame, gone ~0.1s after the boss fires.
func _boss_telegraph(e: E, d, dir: Vector2, enraged: bool) -> void:
	var charge: float = 1.0 - clampf(e.shoot_t / BOSS_TELEGRAPH_T, 0.0, 1.0)
	var uid: int = e.get_instance_id()
	var every: int = int(d.spiral_every)
	var spiral_next: bool = every > 0 and int(d.spiral_projectile_count) > 0 and (e.volley + 1) % every == 0
	var tint := Color(1.0, 0.5, 0.15) if spiral_next else Color(0.85, 0.95, 0.75)
	if enraged:
		tint = tint.lerp(Color(1.0, 0.3, 0.25), 0.5)
	world.fx.cue_converge(uid, 0, e.pos, 150.0 if spiral_next else 130.0, 24.0, tint, charge)
	if not spiral_next and int(d.projectile_count) >= 2:
		world.fx.cue_wedge(uid, 1, e.pos + Vector2(0, -12), dir.angle(), deg_to_rad(float(d.projectile_spread_deg)), 190.0, tint, charge)


func _ring_volley(e: E, d, dir: Vector2, enraged: bool) -> void:
	var n: int = BOSS_RING_ENRAGED if enraged else BOSS_RING
	var phase: float = randf() * TAU
	for i in n:
		var v: Vector2 = Vector2.from_angle(phase + TAU * float(i) / float(n)) * d.shoot_speed
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -12), v, d.shoot_damage, d.can_hit_flying)
	_aimed_fan(e, d, dir)
	world.fx.ring(e.pos, 10.0, 110.0, 0.35, Color(0.85, 0.95, 0.75), 3.0, FxManager.PRIO_IMPORTANT)
	Audio.sfx("hand_cannon", -6.0, 0.6, 0.0)
	Game.shake(2.5)


## Aimed multi-shot fan at the player (def projectile_count/spread_deg + splash); no-op when count < 2.
func _aimed_fan(e: E, d, dir: Vector2) -> void:
	var count: int = int(d.projectile_count)
	if count < 2:
		return
	var spread: float = deg_to_rad(float(d.projectile_spread_deg))
	var base: float = dir.angle()
	var opts := {"style": String(d.projectile_style), "splash_radius": float(d.splash_radius), "splash_damage": float(d.splash_damage), "splash_falloff": bool(d.splash_falloff)}
	for i in count:
		var a: float = base + spread * (float(i) / float(count - 1) - 0.5)
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -12), Vector2.from_angle(a) * d.shoot_speed, d.shoot_damage, d.can_hit_flying, opts)
	Audio.sfx("hand_cannon", -9.0, 1.2, 0.0)


func _spiral_start(e: E, d) -> void:
	e.spiral_t = float(d.spiral_cast_time)
	e.spiral_ang = randf() * TAU
	e.spiral_fired = 0
	if bool(d.spiral_alternate_direction):
		e.spiral_sign = -e.spiral_sign
	else:
		e.spiral_sign = 1.0
	world.fx.ring(e.pos, 10.0, 130.0, 0.4, Color(1.0, 0.5, 0.15), 3.0, FxManager.PRIO_IMPORTANT)
	Audio.sfx("elite_enemy_spawn", -4.0, 0.7, 0.0)
	Game.shake(2.0)


## Emits the spiral burst over its cast time (rotating emitter, alternating direction per cast).
func _spiral_tick(e: E, d, delta: float) -> void:
	if e.spiral_t <= 0.0:
		return
	e.spiral_t -= delta
	var total: int = int(d.spiral_projectile_count)
	if total <= 0:
		e.spiral_t = 0.0
		return
	var cast: float = maxf(0.05, float(d.spiral_cast_time))
	var elapsed: float = cast - maxf(e.spiral_t, 0.0)
	var want: int = mini(total, int(float(total) * elapsed / cast) + 1)
	var speed: float = float(d.spiral_projectile_speed)
	if speed <= 0.0:
		speed = d.shoot_speed
	var opts := {"style": String(d.projectile_style), "splash_radius": float(d.spiral_splash_radius), "splash_damage": float(d.spiral_splash_damage), "splash_falloff": bool(d.splash_falloff)}
	var srange: float = float(d.spiral_projectile_range)
	if srange > 0.0:
		opts["life"] = srange / maxf(1.0, speed)
	var step: float = TAU * float(d.spiral_turns) / float(maxi(total, 1))
	while e.spiral_fired < want:
		e.spiral_fired += 1
		e.spiral_ang += step * e.spiral_sign
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -12), Vector2.from_angle(e.spiral_ang) * speed, d.shoot_damage, d.can_hit_flying, opts)
	world.fx.cue_sweep(e.get_instance_id(), 2, e.pos + Vector2(0, -12), e.spiral_ang, e.spiral_sign, 170.0, Color(1.0, 0.55, 0.2))
	if e.spiral_fired >= total:
		e.spiral_t = 0.0


## Asmodeus (behavior "boss_broker"): a shuffled attack deck, one telegraphed
## attack at a time. Stalks at 0.6x between attacks, rooted during telegraph and
## execute. Creditors (adds) inject between deck draws to keep the arena alive
## while the director is frozen. Enrage: extra fan burst, crossed ledger lines,
## a third gap ring, +2 creditors, faster recover.
func _boss_broker(e: E, delta: float, dir: Vector2, _dist: float) -> Vector2:
	var d = e.def
	var enraged: bool = e.hp < e.max_hp * float(d.enrage_hp_fraction)
	if enraged and not e.enraged_seen:
		e.enraged_seen = true
		world.fx.enrage_feel(e.pos)
	var add_def = DB.enemies.get(String(d.add_def_id)) if String(d.add_def_id) != "" else null
	if add_def != null:
		e.add_t -= delta
	if e.atk == "" and e.atk_phase == 0:
		if add_def != null and e.add_t <= 0.0 and _summoned_alive() < int(d.add_cap):
			_broker_begin(e, "summon")
		else:
			_broker_draw(e, d)
	match e.atk_phase:
		0:
			e.atk_t -= delta
			_broker_telegraph(e, d, dir, enraged)
			if e.atk_t <= 0.0:
				e.atk_phase = 1
				e.burst_t = 0.0
				_broker_execute(e, d, dir, enraged)
			return Vector2.ZERO
		1:
			if _broker_tick(e, d, delta, dir, enraged):
				e.atk_phase = 2
				e.atk_t = float(d.recover_time) * (float(d.enrage_interval_mult) if enraged else 1.0)
			return Vector2.ZERO
		_:
			e.atk_t -= delta
			if e.atk_t <= 0.0:
				e.atk = ""
				e.atk_phase = 0
			return dir * e.speed * 0.6


func _summoned_alive() -> int:
	var n := 0
	for o in active:
		if o.summoned and o.alive:
			n += 1
	return n


## Draw the next deck attack (reshuffle when empty; never the same kind twice in a row).
func _broker_draw(e: E, d) -> void:
	if e.deck_bag.is_empty():
		for k in d.deck:
			e.deck_bag.append(k)
		e.deck_bag.shuffle()
	if e.deck_bag.is_empty():
		return
	var pick := String(e.deck_bag.pop_front())
	if pick == e.last_atk and not e.deck_bag.is_empty():
		e.deck_bag.append(pick)
		pick = String(e.deck_bag.pop_front())
	_broker_begin(e, pick)


func _broker_begin(e: E, atk: String) -> void:
	e.atk = atk
	e.last_atk = atk
	e.atk_phase = 0
	e.burst_left = 0
	e.burst_t = 0.0
	match atk:
		"fan":
			e.atk_t = 0.75
		"summon":
			e.atk_t = 0.8
		_:
			e.atk_t = 0.6


## Telegraph cues, refreshed every frame, never retime the attack.
func _broker_telegraph(e: E, d, dir: Vector2, enraged: bool) -> void:
	var uid: int = e.get_instance_id()
	var tint := Color(0.93, 0.9, 0.8)
	if enraged:
		tint = tint.lerp(Color(1.0, 0.4, 0.3), 0.5)
	match e.atk:
		"fan":
			if e.atk_t > 0.15:
				e.aim = dir          # tracks the player, locks 0.15s before firing
			var charge: float = 1.0 - clampf(e.atk_t / 0.75, 0.0, 1.0)
			world.fx.cue_wedge(uid, 1, e.pos + Vector2(0, -12), e.aim.angle(), deg_to_rad(float(d.projectile_spread_deg)), 190.0, tint, charge)
		"ledger", "summon":
			var charge2: float = 1.0 - clampf(e.atk_t / (0.8 if e.atk == "summon" else 0.6), 0.0, 1.0)
			world.fx.cue_converge(uid, 0, e.pos, 130.0, 24.0, tint, charge2)
		"gap_ring":
			var charge3: float = 1.0 - clampf(e.atk_t / 0.6, 0.0, 1.0)
			world.fx.cue_converge(uid, 0, e.pos, 150.0, 24.0, tint, charge3)
		"foreclose":
			var charge4: float = 1.0 - clampf(e.atk_t / 0.6, 0.0, 1.0)
			world.fx.cue_wedge(uid, 1, e.pos + Vector2(0, -12), dir.angle(), deg_to_rad(18.0), 220.0, tint, charge4)


func _broker_execute(e: E, d, dir: Vector2, enraged: bool) -> void:
	match e.atk:
		"fan":
			e.burst_left = int(d.fan_bursts) + (1 if enraged else 0)
		"ledger":
			_broker_ledger(e, d, dir, enraged)
		"gap_ring":
			e.spiral_ang = randf() * TAU    # ring phase (spiral fields unused by the broker)
			e.burst_left = 3 if enraged else 2
		"foreclose":
			e.dash_dir = dir
			e.burst_t = 0.45
			e.spiral_t = 0.0                # zone drop timer
		"summon":
			_broker_summon(e, d, enraged)


## Execute tick; returns true when the attack is finished (-> recover).
func _broker_tick(e: E, d, delta: float, dir: Vector2, enraged: bool) -> bool:
	match e.atk:
		"fan":
			e.burst_t -= delta
			if e.burst_left > 0 and e.burst_t <= 0.0:
				_broker_fan_burst(e, d, dir)   # each burst re-aimed at the live player
				e.burst_left -= 1
				e.burst_t = float(d.fan_burst_gap)
			return e.burst_left <= 0
		"gap_ring":
			e.burst_t -= delta
			if e.burst_left > 0 and e.burst_t <= 0.0:
				var rings: int = 3 if enraged else 2
				var gap_rot: float = 0.0 if e.burst_left == rings else PI / float(maxi(1, int(d.ring_gaps)))
				_broker_ring(e, d, e.spiral_ang, gap_rot)
				e.burst_left -= 1
				e.burst_t = 0.55
			return e.burst_left <= 0
		"foreclose":
			e.burst_t -= delta
			e.spiral_t -= delta
			if e.burst_t > 0.0 and e.spiral_t <= 0.0:
				e.spiral_t = 0.1
				world.projectiles.spawn_zone(e.pos, float(d.zone_radius) * 0.7, float(d.zone_damage) * 0.7, float(d.zone_delay) * 0.8)
			return e.burst_t <= 0.0
		_:
			return true


## Loaded Dice: one fan burst of bone shards, re-aimed each burst.
func _broker_fan_burst(e: E, d, dir: Vector2) -> void:
	var count: int = maxi(1, int(d.projectile_count))
	var spread: float = deg_to_rad(float(d.projectile_spread_deg))
	var base: float = dir.angle()
	var opts := {"style": "bone"}
	var speed: float = float(d.shoot_speed) * 1.15
	var dmg: float = float(d.shoot_damage) * 0.7
	for i in count:
		var a: float = base + spread * (float(i) / float(maxi(count - 1, 1)) - 0.5)
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -12), Vector2.from_angle(a) * speed, dmg, d.can_hit_flying, opts)
	Audio.sfx("hand_cannon", -8.0, 1.1, 0.0)
	Game.shake(1.6)


## Debt Collection: a marching line of ground zones from the boss through the
## player's cast position (enrage crosses two extra lines at +/-25 deg).
func _broker_ledger(e: E, d, dir: Vector2, enraged: bool) -> void:
	var lines: Array = [dir.angle()]
	if enraged:
		lines.append(dir.angle() + deg_to_rad(25.0))
		lines.append(dir.angle() - deg_to_rad(25.0))
	var n: int = maxi(1, int(d.zone_count))
	for a in lines:
		for i in n:
			var p: Vector2 = e.pos + Vector2.from_angle(float(a)) * 38.0 * float(i + 1)
			world.projectiles.spawn_zone(p, float(d.zone_radius), float(d.zone_damage), float(d.zone_delay) + 0.1 * float(i))
	Audio.sfx("elite_enemy_spawn", -5.0, 0.8, 0.0)
	Game.shake(2.0)


## Bankruptcy: bullet rings with evenly spaced safe gaps (second ring's gaps
## rotated so the player has to weave).
func _broker_ring(e: E, d, phase: float, gap_rot: float) -> void:
	var n: int = maxi(4, int(d.ring_bullets))
	var gaps: int = maxi(1, int(d.ring_gaps))
	var gap_half := deg_to_rad(14.0)    # ~28 deg safe gaps
	var opts := {"style": "bone"}
	for i in n:
		var a: float = phase + TAU * float(i) / float(n)
		var skip := false
		for g in gaps:
			if absf(angle_difference(gap_rot + TAU * float(g) / float(gaps), a)) < gap_half:
				skip = true
				break
		if skip:
			continue
		world.projectiles.spawn_hostile(e.pos + Vector2(0, -12), Vector2.from_angle(a) * float(d.shoot_speed), d.shoot_damage, d.can_hit_flying, opts)
	world.fx.ring(e.pos, 10.0, 110.0, 0.35, Color(0.93, 0.9, 0.8), 3.0, FxManager.PRIO_IMPORTANT)
	Audio.sfx("hand_cannon", -6.0, 0.8, 0.0)
	Game.shake(2.0)


## Creditors: skeleton adds at 90-140px, weaker but keeping the arena alive
## while the director is frozen. First summon ~6s after the boss appears.
func _broker_summon(e: E, d, enraged: bool) -> void:
	var add_def = DB.enemies.get(String(d.add_def_id))
	if add_def == null:
		return
	e.add_t = float(d.add_interval)
	world.fx.ring(e.pos, 12.0, 90.0, 0.45, Color(0.85, 0.9, 0.75), 3.0, FxManager.PRIO_IMPORTANT)
	Audio.sfx("elite_enemy_spawn", -3.0, 1.3, 0.0)
	var cap: int = int(d.add_cap)
	var want: int = int(d.add_count) + (2 if enraged else 0)
	for i in want:
		if _summoned_alive() >= cap:
			break
		var p: Vector2 = e.pos + Vector2.from_angle(randf() * TAU) * randf_range(90.0, 140.0)
		var add = spawn(add_def, p, 0.6, 0.8)
		if add != null:
			add.summoned = true


func _separation(e: E) -> Vector2:
	var push := Vector2.ZERO
	var cx := floori(e.pos.x / CELL)
	var cy := floori(e.pos.y / CELL)
	var checked := 0
	for gx in range(cx - 1, cx + 2):
		for gy in range(cy - 1, cy + 2):
			var b = _grid.get(_key(gx, gy))
			if b == null:
				continue
			for o in b:
				if o == e or not o.alive:
					continue
				var off: Vector2 = e.pos - o.pos
				var r: float = (e.radius + o.radius) * 0.9
				var d2 := off.length_squared()
				if d2 < r * r and d2 > 0.01:
					var dd := sqrt(d2)
					push += off / dd * (1.0 - dd / r)
				checked += 1
				if checked > 10:
					return push
	return push


# ------------------------------------------------------------------ spatial hash
func _key(cx: int, cy: int) -> int:
	return (cx * 92837111) ^ (cy * 689287499)


func _rebuild_grid() -> void:
	for b in _bucket_used:
		b.clear()
		_bucket_free.append(b)
	_bucket_used.clear()
	_grid.clear()
	for e in active:
		var k := _key(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		var b = _grid.get(k)
		if b == null:
			b = _bucket_free.pop_back() if not _bucket_free.is_empty() else []
			_grid[k] = b
			_bucket_used.append(b)
		b.append(e)


func query_circle(center: Vector2, r: float) -> Array[E]:
	var out: Array[E] = []
	var x0 := floori((center.x - r - 24.0) / CELL)
	var x1 := floori((center.x + r + 24.0) / CELL)
	var y0 := floori((center.y - r - 24.0) / CELL)
	var y1 := floori((center.y + r + 24.0) / CELL)
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var b = _grid.get(_key(gx, gy))
			if b == null:
				continue
			for e in b:
				if not e.alive:
					continue
				var rr: float = r + e.radius
				if e.pos.distance_squared_to(center) <= rr * rr:
					out.append(e)
	return out


## Ground-only variant for drop-and-leave traps (caltrops, turds, ...).
## Skips flying enemies (def.height == 1). Spider webs are the intentional exception
## and keep using query_circle so they still catch flyers.
func query_ground_circle(center: Vector2, r: float) -> Array[E]:
	var out: Array[E] = []
	for e in query_circle(center, r):
		if e.def.height == 1:
			continue
		out.append(e)
	return out


func query_arc(center: Vector2, dir: Vector2, r: float, arc_rad: float) -> Array[E]:
	var out: Array[E] = []
	var a0 := dir.angle()
	for e in query_circle(center, r):
		var off: Vector2 = e.pos - center
		var dist := off.length()
		if dist < e.radius + 14.0 or absf(angle_difference(a0, off.angle())) <= arc_rad * 0.5 + asin(clampf(e.radius / maxf(dist, 1.0), 0.0, 1.0)):
			out.append(e)
	return out


func nearest(center: Vector2, max_r: float, exclude: Dictionary = {}) -> E:
	var best: E = null
	var best_d := max_r * max_r
	for e in active:
		if exclude.has(e.uid):
			continue
		var d := e.pos.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = e
	return best


# ------------------------------------------------------------------ damage + status
## Solomonic Decree execute: regulars + elites below threshold die via the normal
## hp == 0 path (on_kill / bestiary / coins / XP all fire). Bosses (boss_time > 0) immune.
func _maybe_execute(e: E) -> void:
	if not e.alive:
		return
	if float(e.def.boss_time) > 0.0:
		return
	var threshold := Meta.get_total_seal_bonus("execute_threshold")
	if threshold <= 0.0:
		return
	if e.hp > 0.0 and e.hp < e.max_hp * threshold:
		e.hp = 0.0


func damage(e: E, amount: float, knock_dir: Vector2 = Vector2.ZERO, knock_force: float = 0.0, tint: Color = Color(1.0, 0.9, 0.6), src: String = "") -> void:
	if not e.alive:
		return
	if String(e.def.behavior) == "blink" and e.state == 1:
		return
	if String(e.def.behavior) == "glitch" and e.state == 1:
		return
	if src != "":
		if e.hit_gate.get(src, 0.0) > 0.0:
			return
		e.hit_gate[src] = 0.10
	var is_dummy := String(e.def.behavior) == "dummy"
	var crit: bool = randf() < 0.07 + float(player.stat("luck")) * 0.25 + float(player.stat("crit_chance"))
	if crit:
		amount *= 2.0
	if not is_dummy and e.marks.has("wanted_poster"):
		var wm: Dictionary = e.marks["wanted_poster"]
		if player.global_position.distance_to(e.pos) <= float(wm.get("leash", 260.0)):
			amount *= float(wm.get("taken", 1.25))
	if not is_dummy and e.marks.has("vulnerable"):
		amount *= float((e.marks["vulnerable"] as Dictionary).get("taken", 1.25))
	if not is_dummy and src == "" and e.marks.has("killing_light"):
		amount *= float((e.marks["killing_light"] as Dictionary).get("mult", 2.0))
		e.stun = 0.0
		e.marks.erase("killing_light")
	if not is_dummy:
		e.hp -= amount
		_maybe_execute(e)
	e.flash = 0.14 if crit else 0.09
	if knock_force > 0.0 and not is_dummy:
		e.knock += knock_dir.normalized() * knock_force * (0.35 if e.is_elite else 1.0)
	world.fx.damage_number(e.pos + Vector2(randf_range(-4, 4), -e.radius * 1.5), amount, crit, e.is_elite)
	world.fx.hit_sparks(e.pos, knock_dir, tint, 4 if not crit else 8)
	if crit:
		world.fx.crit_feel(e.pos, e.is_elite)
	Audio.sfx(e.def.hit_event, -9.0)
	if world != null and not is_dummy:
		world.on_ability_hit(e, amount)
	if e.hp <= 0.0 and not is_dummy:
		_kill(e)


func stun(e: E, seconds: float) -> void:
	if e.cc_immune_t > 0.0 or float(e.def.boss_time) > 0.0:
		return
	var d: float = seconds * (0.5 if e.is_elite else 1.0)
	e.stun = maxf(e.stun, minf(d, 1.8))


func fear(e: E, seconds: float, from_pos: Vector2) -> void:
	e.fear = maxf(e.fear, seconds * (0.5 if e.is_elite else 1.0))
	e.fear_from = from_pos


func poison(e: E, dps: float, seconds: float) -> void:
	e.poison_dps = maxf(e.poison_dps, dps)
	e.poison_t = maxf(e.poison_t, seconds)


func burn(e: E, dps: float, seconds: float) -> void:
	e.burn_dps = maxf(e.burn_dps, dps)
	e.burn_t = maxf(e.burn_t, seconds)


func infect(e: E, seconds: float) -> void:
	e.infect_t = maxf(e.infect_t, seconds)


func slow(e: E, mult: float, seconds: float) -> void:
	if float(e.def.boss_time) > 0.0:
		mult = maxf(mult, 0.70)
	e.slow = minf(e.slow, mult)
	e.atk_slow = minf(e.atk_slow, mult)
	e.slow_t = maxf(e.slow_t, seconds)


func mark(e: E, key: String, seconds: float = 0.0, src: String = "", extra: Dictionary = {}) -> void:
	var m := {"t": seconds, "src": src}
	for k in extra:
		m[k] = extra[k]
	e.marks[key] = m


func has_mark(e: E, key: String) -> bool:
	return e.marks.has(key)


func clear_mark(e: E, key: String) -> void:
	e.marks.erase(key)


func pull(e: E, center: Vector2, radius: float, strength: float, _duration: float = 0.0) -> void:
	if float(e.def.boss_time) > 0.0:
		return
	var d := e.pos.distance_to(center)
	if d < 1.0 or d > radius:
		return
	var dir := (center - e.pos).normalized()
	e.knock += dir * strength


func _kill(e: E, quiet: bool = false, silent: bool = false) -> void:
	if not e.alive:
		return
	e.alive = false
	e.sprite.visible = false
	var last: E = active.back()
	active[e.slot] = last
	last.slot = e.slot
	active.pop_back()
	if e.is_elite:
		elites.erase(e)
	if not quiet:
		world.gems.drop(e.pos, e.def.xp, e.is_elite)
		if not e.summoned:      # boss adds (Creditors) drop no Fragments, still drop gems
			world.coins.on_enemy_killed(e)
		if e.is_elite:
			world.chests.drop(e.pos)
	if not silent:
		world.fx.death_burst(e.pos, e.def, e.is_elite)
		world.fx.signature_kill(e.pos, e.is_elite)
	if float(e.def.boss_time) > 0.0:
		world.fx.clear_cues(e.get_instance_id())
		if not silent:
			world.fx.boss_kill_feel(e.pos)
	elif e.is_elite and not quiet:
		world.fx.elite_kill_feel(e.pos)
	if not silent:
		Audio.sfx("enemy_death", -5.0)
	if not quiet:
		world.on_kill(e)
	_free.append(e)


## FX-lab helper: run the full death FX for a lab dummy without drops,
## bestiary entries, or on_kill procs.
func slay_quiet(e: E) -> void:
	_kill(e, true)


func alive_count() -> int:
	return active.size()
