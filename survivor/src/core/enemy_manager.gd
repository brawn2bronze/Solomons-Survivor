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
    var atk_slow := 1.0
    var slow_t := 0.0
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


func kill_all() -> void:
    for e in active:
        _dead.append(e)


func clear_to(n: int) -> void:
    # Trim extras (used after stress tests).
    while active.size() > n and not active.is_empty():
        _dead.append(active.back())


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
    e.dmg = def.contact_damage * dmg_mult
    e.alive = true
    e.is_elite = def.is_elite
    e.stun = 0.0
    e.fear = 0.0
    e.slow = 1.0
    e.atk_slow = 1.0
    e.slow_t = 0.0
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
    e.phase = randf() * TAU
    e.web = null
    var sp := e.sprite
    sp.texture = DB.texture(def.sprite)
    sp.hframes = def.frames
    sp.frame = 0
    sp.scale = Vector2.ONE * def.sprite_scale
    sp.material = null
    sp.modulate = Color(1.0, 0.82, 0.82) if e.is_elite else Color.WHITE
    sp.flip_h = false
    sp.position = pos
    sp.visible = true
    e.slot = active.size()
    active.append(e)
    if e.is_elite:
        elites.append(e)
    return e


func _spawn_ring(def, count: int, t: float) -> void:
    var hp_mult := 1.0 + t / 240.0
    var dmg_mult := 1.0 + t / 600.0
    var base := randf() * TAU
    for i in count:
        var ang := base + float(i) / float(maxi(count, 1)) * TAU * 0.35 + randf_range(-0.05, 0.05)
        var p: Vector2 = player.global_position + Vector2.from_angle(ang) * randf_range(390.0, 430.0)
        spawn(def, p, hp_mult, dmg_mult)


func _tick_director(delta: float) -> void:
    if director_paused:
        return
    var t: float = world.run_time
    var target := clampi(int(16.0 + t * 0.55 + pow(t / 60.0, 1.4) * 9.0), 16, MAX_ALIVE)
    var seal_mult := maxf(0.2, 1.0 + Meta.get_seal_bonus("reinforced_walls"))
    _spawn_acc += delta * (5.0 + t * 0.045) * spawn_mult * seal_mult
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
        spawn(def, p, 1.0 + t / 240.0, 1.0 + t / 600.0)
    # elites
    for def in _elite_defs:
        if t >= float(_elite_next[def.id]):
            _elite_next[def.id] = t + def.elite_every
            var ang2 := randf() * TAU
            var e = spawn(def, player.global_position + Vector2.from_angle(ang2) * 420.0, 1.0 + t / 200.0, 1.0 + t / 500.0)
            if e != null:
                Audio.sfx("elite_enemy_spawn", -2.0, 1.0, 0.0)
                world.announce("%s approaches" % def.display_name.to_upper(), def.height == 1)
                Game.shake(4.0)
    # unique boss events (EnemyDef.boss_time): once per run, never on the elite timer.
    # PRE-BATTLE HOOK: future boss intro dialogue pauses the director here before the spawn.
    for def in _boss_defs:
        if _boss_spawned.has(def.id) or t < def.boss_time:
            continue
        _boss_spawned[def.id] = true
        var boss = spawn(def, player.global_position + Vector2.from_angle(randf() * TAU) * BOSS_SPAWN_DIST)
        if boss != null:
            Audio.sfx("elite_enemy_spawn", 0.0, 0.7, 0.0)
            world.announce("%s HAS ARRIVED" % String(def.display_name).to_upper(), true)
            Game.shake(7.0)
        else:
            _boss_spawned.erase(def.id)   # pool was full: retry next frame
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
    var n := active.size()
    for i in n:
        var e: E = active[i]
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
    if e.slow_t > 0.0:
        e.slow_t -= delta
        if e.slow_t <= 0.0:
            e.slow = 1.0
            e.atk_slow = 1.0
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
    elif e.fear > 0.0:
        e.fear -= delta
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
    if e.contact_cd <= 0.0 and e.stun <= 0.0 and e.fear <= 0.0 and dist < e.radius + PLAYER_RADIUS and not (String(d.behavior) == "blink" and e.state == 1):
        e.contact_cd = 0.75
        player.take_damage(e.dmg, d.height == 1 or d.can_hit_flying, d.display_name)
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
        sp.modulate = Color(1.0, 0.82, 0.82) if e.is_elite else Color.WHITE


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


func nearest(center: Vector2, max_r: float, exclude: Array = []) -> E:
    var best: E = null
    var best_d := max_r * max_r
    for e in active:
        if exclude.has(e):
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


func damage(e: E, amount: float, knock_dir: Vector2 = Vector2.ZERO, knock_force: float = 0.0, tint: Color = Color(1.0, 0.9, 0.6)) -> void:
    if not e.alive:
        return
    if String(e.def.behavior) == "blink" and e.state == 1:
        return
    if String(e.def.behavior) == "glitch" and e.state == 1:
        return
    var is_dummy := String(e.def.behavior) == "dummy"
    var crit: bool = randf() < 0.07 + float(player.stat("luck")) * 0.25 + float(player.stat("crit_chance"))
    if crit:
        amount *= 2.0
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
    if e.hp <= 0.0 and not is_dummy:
        _kill(e)


func stun(e: E, seconds: float) -> void:
    e.stun = maxf(e.stun, seconds * (0.5 if e.is_elite else 1.0))


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
    e.slow = minf(e.slow, mult)
    e.atk_slow = minf(e.atk_slow, mult)
    e.slow_t = maxf(e.slow_t, seconds)


func _kill(e: E, quiet: bool = false) -> void:
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
        world.coins.on_enemy_killed(e)
        if e.is_elite:
            world.chests.drop(e.pos)
    world.fx.death_burst(e.pos, e.def, e.is_elite)
    world.fx.signature_kill(e.pos, e.is_elite)
    if float(e.def.boss_time) > 0.0:
        world.fx.clear_cues(e.get_instance_id())
        world.fx.boss_kill_feel(e.pos)
    elif e.is_elite and not quiet:
        world.fx.elite_kill_feel(e.pos)
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
