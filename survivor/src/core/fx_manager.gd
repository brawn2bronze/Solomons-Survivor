class_name FxManager
extends Node2D
## All transient visual feedback: sparks, death bursts, slash arcs, rings, damage numbers, floating text,
## impact-feel tiers (shake + hit-stop + pulse), ambient dust.
## Everything is a pooled struct drawn from two _draw layers (additive glow + normal), so there are
## no per-particle nodes. Caps keep the worst case bounded.
## Shape kinds: ring, slash_arc, lash, bolt, star (sparkle), disc (flash / hollow marker), wedge (cone),
## beam (straight ray). Persistent cues (cue_wedge / cue_converge / cue_sweep) are refreshed every frame
## by their uid and vanish ~0.1s after it stops - used for boss telegraphs and elite/boss ground auras.
## signature_kill() adds a small per-character flourish on each kill (budgeted, shed under load).

const MAX_PARTICLES := 640
const MAX_SHAPES := 96
const MAX_NUMBERS := 60

# Shape priorities. When the shape pool is full, a new shape evicts the lowest-priority,
# soonest-to-expire shape that is not MORE important than itself; if none qualifies the new
# (less important) shape is dropped instead. Callers that pass no priority get PRIO_NORMAL.
const PRIO_AMBIENT := 0      # cosmetic spam (crit pops)
const PRIO_NORMAL := 1       # default: weapon visuals, death rings
const PRIO_IMPORTANT := 2    # boss attack cues, player-state feedback, boss death

const MAX_CUES := 32
const CUE_TTL := 0.12        # a cue disappears this long after its uid last refreshed it
const CUE_FADE := 0.06       # ...fading out over the final stretch

# Character kill signatures, matched as substrings of the CharacterDef id (index + 1 = signature number).
const SIG_KEYS := ["cowboy", "ninja", "pirate", "paladin", "wizard", "spider", "minotaur", "harpy", "necro", "goose"]
const SIG_BUDGET_MAX := 12.0   # burst allowance of non-elite signatures...
const SIG_BUDGET_RATE := 40.0  # ...refilled per second, so a 100-kills/sec swarm can't spam them

# Cosmetic load shedding: above this particle-pool fill, sparks / muzzle flashes / dust thin out
# (down to 25% of their normal count at a full pool). Telegraphs, bursts and feel tiers are never shed.
const SHED_START := 0.6

class P:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var max_life := 1.0
	var size := 2.0
	var color := Color.WHITE
	var kind := 0            # 0 square, 1 glow dot, 2 streak, 3 casing
	var drag := 3.0
	var grav := 0.0
	var add := true

class Shape:
	var kind := 0            # 0 ring, 1 slash arc, 2 lash, 3 bolt, 4 star, 5 disc, 6 wedge, 7 beam
	var pos := Vector2.ZERO
	var dir := 0.0
	var r0 := 0.0
	var r1 := 0.0
	var arc := 1.0
	var width := 3.0
	var life := 0.0
	var max_life := 0.2
	var color := Color.WHITE
	var pts := PackedVector2Array()
	var flip := 1.0
	var prio := 1            # PRIO_* - decides who gets evicted when the pool is full

class Cue:
	var uid := 0           # caller-chosen id (enemy instance id); with slot, identifies the cue
	var slot := 0
	var kind := 0            # 0 aim wedge, 1 converging ring, 2 rotating sweep, 3 ground aura
	var pos := Vector2.ZERO
	var dir := 0.0
	var spread := 0.0
	var length := 0.0        # wedge/sweep length, or converging ring start radius
	var r_to := 0.0          # converging ring end radius
	var flip := 1.0          # sweep direction (+1 / -1)
	var color := Color.WHITE
	var charge := 0.0        # 0..1: how close the warned-of attack is
	var ttl := 0.0

class Num:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var text := ""
	var size := 16
	var color := Color.WHITE
	var max_life := 0.6
	var pop := 0.0               # extra scale at spawn, eases back to 1.0 over ~0.35s
	var keep_on_screen := false  # clamp to the viewport (off-screen boss callouts)

var world
var _particles: Array = []
var _shapes: Array = []
var _numbers: Array = []
var _motes: Array = []
var _layer_add: FxLayer
var _layer_norm: FxLayer
var _layer_num: FxLayer
var _pcur := 0
var _strikes: Array = []
var _font: Font
var _crit_fx_ms := 0        # real-time gates so dense fights can't strobe or stutter
var _crit_stop_ms := 0
var _cues: Array = []
var _sig_id := ""
var _sig := 0               # signature number for the current character (0 = none)
var _sig_budget := SIG_BUDGET_MAX
var _honk_ms := 0
var _pool_fill := 0.0            # particle-pool fill 0..1, refreshed every frame (drives load shedding)
var _stat_shapes_alive := 0
var _stat_shape_steals := 0
var _stat_shape_drops := 0


func setup(world_ref) -> void:
	world = world_ref
	_font = ThemeDB.fallback_font
	for i in MAX_PARTICLES:
		var p := P.new()
		_particles.append(p)
	_layer_add = _make_layer(true)
	_layer_norm = _make_layer(false)
	var cl := CanvasLayer.new()
	cl.layer = 6
	add_child(cl)
	_layer_num = FxLayer.new()
	_layer_num.manager = self
	_layer_num.mode = 2
	cl.add_child(_layer_num)
	var lt := DB.texture("res://art/fx/lightning.png")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for i in 8:
		var sp := Sprite2D.new()
		sp.texture = lt
		sp.hframes = 12
		sp.offset = Vector2(0, -58)
		sp.material = mat
		sp.z_index = 20
		sp.visible = false
		add_child(sp)
		_strikes.append({"sp": sp, "t": 99.0})
	for i in 46:
		_motes.append({"pos": Vector2(randf_range(-330, 330), randf_range(-190, 190)), "s": randf_range(0.5, 1.5), "ph": randf() * TAU})


func _make_layer(additive: bool) -> FxLayer:
	var l := FxLayer.new()
	l.manager = self
	l.mode = 0 if additive else 1
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		l.material = m
	add_child(l)
	return l


# ------------------------------------------------------------------ spawning helpers
func _particle() -> P:
	var p: P = _particles[_pcur]
	_pcur = (_pcur + 1) % MAX_PARTICLES
	return p


func emit(pos: Vector2, vel: Vector2, life: float, size: float, color: Color, kind: int = 0, drag: float = 3.0, grav: float = 0.0, add: bool = true) -> void:
	var p := _particle()
	if p == null:
		return
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.color = color
	p.kind = kind
	p.drag = drag
	p.grav = grav
	p.add = add


## Shape-pool slot for a new shape of the given priority. Free slot first; otherwise evict the
## lowest-priority shape (ties: the one closest to expiring) that isn't more important than the
## request. Returns null when the pool is full of more important shapes - the caller drops its shape.
func _shape(prio: int = PRIO_NORMAL) -> Shape:
	if _shapes.size() < MAX_SHAPES:
		var fresh := Shape.new()
		fresh.prio = prio
		_shapes.append(fresh)
		return fresh
	var victim: Shape = null
	for s in _shapes:
		if s.life <= 0.0:
			victim = s
			break
		if s.prio > prio:
			continue
		if victim == null or s.prio < victim.prio or (s.prio == victim.prio and s.life < victim.life):
			victim = s
	if victim == null:
		_stat_shape_drops += 1
		return null
	if victim.life > 0.0:
		_stat_shape_steals += 1
	victim.prio = prio
	return victim


## 1.0 until the particle pool passes SHED_START, then ramps down to 0.25 at a full pool.
func _shed_scale() -> float:
	if _pool_fill <= SHED_START:
		return 1.0
	return lerpf(1.0, 0.25, (_pool_fill - SHED_START) / (1.0 - SHED_START))


func _shed_count(n: int) -> int:
	if _pool_fill <= SHED_START:
		return n
	return maxi(1, roundi(float(n) * _shed_scale()))


## Live pool numbers for the dev overlay / profiling: particles, shapes, load, evictions, drops.
func debug_stats() -> Dictionary:
	return {
		"particle_load": _pool_fill,
		"shapes_alive": _stat_shapes_alive,
		"shape_steals": _stat_shape_steals,
		"shape_drops": _stat_shape_drops,
	}


func hit_sparks(pos: Vector2, dir: Vector2, color: Color, count: int = 4) -> void:
	var base := dir.angle() if dir.length() > 0.1 else randf() * TAU
	for i in _shed_count(count):
		var a := base + randf_range(-0.9, 0.9)
		emit(pos, Vector2.from_angle(a) * randf_range(70.0, 190.0), randf_range(0.16, 0.3), randf_range(1.5, 2.6), color, 2, 5.0)
	emit(pos, Vector2.ZERO, 0.08, 6.0, Color(1, 1, 1, 0.9), 1, 0.0)


func death_burst(pos: Vector2, def, elite: bool) -> void:
	var c := Color(0.9, 0.35, 0.3) if def.family == "dragon" else (Color(0.85, 0.85, 0.7) if def.family == "skeleton" else Color(0.55, 0.85, 0.4))
	for i in (26 if elite else 9):
		emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(30.0, 150.0 if not elite else 260.0), randf_range(0.3, 0.6), randf_range(1.5, 3.2), c, 0, 4.0, 60.0, false)
	emit(pos, Vector2.ZERO, 0.14, 12.0 if not elite else 26.0, Color(1, 1, 1, 0.8), 1, 0.0)
	if elite:
		ring(pos, 6.0, 90.0, 0.4, Color(1.0, 0.75, 0.4), 3.0)
		ring(pos, 2.0, 55.0, 0.3, Color(1, 1, 1), 2.0)


func muzzle(pos: Vector2, dir: Vector2, color: Color) -> void:
	var a := dir.angle()
	emit(pos + dir * 6.0, Vector2.ZERO, 0.06, 8.0, Color(1, 0.95, 0.7, 0.9), 1, 0.0)
	for i in _shed_count(5):
		emit(pos + dir * 6.0, Vector2.from_angle(a + randf_range(-0.35, 0.35)) * randf_range(120.0, 260.0), randf_range(0.06, 0.12), 2.0, color, 2, 6.0)
	# ejected casing
	emit(pos, Vector2.from_angle(a + PI * 0.5 * signf(randf() - 0.5)) * randf_range(40.0, 80.0) + Vector2(0, -40), 0.55, 2.0, Color(0.95, 0.75, 0.3), 3, 2.0, 260.0, false)


func ring(pos: Vector2, r0: float, r1: float, life: float, color: Color, width: float = 2.0, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 0
	s.pos = pos
	s.r0 = r0
	s.r1 = r1
	s.life = life
	s.max_life = life
	s.color = color
	s.width = width


func slash_arc(pos: Vector2, dir: float, radius: float, arc: float, color: Color, flip: float = 1.0, life: float = 0.16, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 1
	s.pos = pos
	s.dir = dir
	s.r1 = radius
	s.arc = arc
	s.life = life
	s.max_life = life
	s.color = color
	s.flip = flip
	s.width = maxf(3.0, radius * 0.11)


func lash(pos: Vector2, dir: float, length: float, color: Color, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 2
	s.pos = pos
	s.dir = dir
	s.r1 = length
	s.life = 0.18
	s.max_life = 0.18
	s.color = color
	s.width = 3.0
	s.flip = 1.0 if randf() < 0.5 else -1.0


func bolt(points: PackedVector2Array, color: Color, life: float = 0.18, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 3
	s.pts = points
	s.life = life
	s.max_life = life
	s.color = color
	s.width = 2.5


## 4-point sparkle (crit pops, rare pickups, big kills). size = centre-to-tip px; pops then spins out.
func star(pos: Vector2, size: float, color: Color, life: float = 0.2, rot: float = 0.0, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 4
	s.pos = pos
	s.r1 = size
	s.dir = rot
	s.life = life
	s.max_life = life
	s.color = color
	s.flip = 1.0 if randf() < 0.5 else -1.0


## Disc: width 0 = filled glow that swells r0 -> r1 and fades (impact flash / bloom); width > 0 = hollow
## outline of that thickness (a clean "danger zone" marker). Convention: hollow = hostile, filled = friendly.
func disc(pos: Vector2, r0: float, r1: float, life: float, color: Color, width: float = 0.0, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 5
	s.pos = pos
	s.r0 = r0
	s.r1 = r1
	s.life = life
	s.max_life = life
	s.color = color
	s.width = width


## Cone flash: filled sector with bright edges (melee cones, breath, hit cones). arc = full width in radians.
func wedge(pos: Vector2, dir: float, arc: float, length: float, life: float, color: Color, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 6
	s.pos = pos
	s.dir = dir
	s.arc = arc
	s.r1 = length
	s.life = life
	s.max_life = life
	s.color = color


## Straight ray from pos along dir: white core + coloured glow, thinning as it fades
## (lasers, boss death rays, teleport slashes - see beam_between).
func beam(pos: Vector2, dir: float, length: float, width: float, life: float, color: Color, prio: int = PRIO_NORMAL) -> void:
	var s := _shape(prio)
	if s == null:
		return
	s.kind = 7
	s.pos = pos
	s.dir = dir
	s.r1 = length
	s.width = width
	s.life = life
	s.max_life = life
	s.color = color


func beam_between(a: Vector2, b: Vector2, width: float, life: float, color: Color, prio: int = PRIO_NORMAL) -> void:
	beam(a, (b - a).angle(), a.distance_to(b), width, life, color, prio)


# ------------------------------------------------------------------ persistent cues (telegraphs)
## A cue is re-asserted every frame by whoever owns it; if they stop (attack fired, boss died) it
## fades out within ~CUE_TTL. Costs no shape-pool slots. uid+slot identify a cue; charge is 0..1.
func _cue(uid: int, slot: int) -> Cue:
	var spare: Cue = null
	for c in _cues:
		if c.ttl > 0.0 and c.uid == uid and c.slot == slot:
			return c
		if spare == null and c.ttl <= 0.0:
			spare = c
	if spare == null:
		if _cues.size() >= MAX_CUES:
			return null
		spare = Cue.new()
		_cues.append(spare)
	spare.uid = uid
	spare.slot = slot
	return spare


## Aim wedge (cone of a fan / breath): fill and edges ramp up with charge, with a gentle (~3 Hz) pulse.
func cue_wedge(uid: int, slot: int, pos: Vector2, dir: float, spread: float, length: float, color: Color, charge: float) -> void:
	var c := _cue(uid, slot)
	if c == null:
		return
	c.kind = 0
	c.pos = pos
	c.dir = dir
	c.spread = spread
	c.length = length
	c.color = color
	c.charge = charge
	c.ttl = CUE_TTL


## Ring collapsing from r_from to r_to as the attack nears (radial volleys, spiral casts).
func cue_converge(uid: int, slot: int, pos: Vector2, r_from: float, r_to: float, color: Color, charge: float) -> void:
	var c := _cue(uid, slot)
	if c == null:
		return
	c.kind = 1
	c.pos = pos
	c.length = r_from
	c.r_to = r_to
	c.color = color
	c.charge = charge
	c.ttl = CUE_TTL


## Rotating emitter marker: a bright beam at the head with a fading trail behind it. sweep_sign is the
## rotation direction (+1 / -1), so the trail points back along the path already swept.
func cue_sweep(uid: int, slot: int, pos: Vector2, dir: float, sweep_sign: float, length: float, color: Color) -> void:
	var c := _cue(uid, slot)
	if c == null:
		return
	c.kind = 2
	c.pos = pos
	c.dir = dir
	c.flip = sweep_sign
	c.length = length
	c.color = color
	c.charge = 1.0
	c.ttl = CUE_TTL


## Ground aura under a big enemy: soft glow disc + slowly pulsing ring. rate = pulse speed in rad/s.
func cue_aura(uid: int, slot: int, pos: Vector2, radius: float, color: Color, rate: float) -> void:
	var c := _cue(uid, slot)
	if c == null:
		return
	c.kind = 3
	c.pos = pos
	c.length = radius
	c.color = color
	c.r_to = rate
	c.charge = 1.0
	c.ttl = CUE_TTL


func clear_cues(uid: int) -> void:
	for c in _cues:
		if c.uid == uid:
			c.ttl = 0.0


## Number-pool slot. A free slot always wins; when the pool is full, steal=true recycles the
## entry closest to expiring, steal=false returns null (the caller drops its number).
func _num(steal: bool = false) -> Num:
	if _numbers.size() < MAX_NUMBERS:
		var n := Num.new()
		_numbers.append(n)
		return n
	var oldest: Num = null
	for x in _numbers:
		if x.life <= 0.0:
			return x
		if steal and (oldest == null or x.life < oldest.life):
			oldest = x
	return oldest


func damage_number(pos: Vector2, amount: float, crit: bool, elite: bool) -> void:
	var n := _num(false)
	if n == null:
		return
	n.pos = pos
	n.vel = Vector2(randf_range(-14.0, 14.0), -46.0 if not crit else -62.0)
	n.life = 0.6 if not crit else 0.85
	n.max_life = n.life
	n.pop = 0.42 if crit else 0.0
	n.keep_on_screen = false
	n.text = str(int(round(amount)))
	n.size = 15 if not crit else 22
	n.color = Color(1.0, 0.92, 0.55) if crit else (Color(1.0, 0.6, 0.45) if elite else Color(1, 1, 1))
	if crit:
		n.text += "!"


## Generic floating label ("STUNNED", pickup names, boss callouts). Rises `rise` world px while fading.
## Shares the Num pool but steals the oldest slot when full, so a label is never dropped for a damage number.
## size is in screen px; pop is the spawn-time scale kick; keep_on_screen pins it inside the viewport.
func float_text(pos: Vector2, text: String, color: Color = Color.WHITE, size: int = 18, life: float = 1.1, rise: float = 18.0, pop: float = 0.3, keep_on_screen: bool = false) -> void:
	var n := _num(true)
	if n == null:
		return
	n.pos = pos
	n.vel = Vector2(0.0, -rise * 3.0)    # drag is 3/s, so total rise ~= vel / 3
	n.life = life
	n.max_life = life
	n.pop = pop
	n.keep_on_screen = keep_on_screen
	n.text = text
	n.size = size
	n.color = color


func level_up_burst(pos: Vector2) -> void:
	ring(pos, 4.0, 150.0, 0.55, Color(1.0, 0.9, 0.4), 4.0)
	ring(pos, 2.0, 96.0, 0.4, Color(1, 1, 1), 2.0)
	for i in 34:
		emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 260.0), randf_range(0.5, 0.9), randf_range(1.5, 3.0), Color.from_hsv(randf(), 0.5, 1.0), 0, 2.5, 90.0)


# ------------------------------------------------------------------ character kill signatures
func _sig_for(id: String) -> int:
	var low := id.to_lower()
	for i in SIG_KEYS.size():
		if low.contains(String(SIG_KEYS[i])):
			return i + 1
	return 0


## A small flourish on every kill, flavoured by the character being played (unknown ids get none).
## Non-elite kills spend from a refilling budget and thin out under particle load; elites always play,
## at double size. Everything is PRIO_AMBIENT / short-lived so it never competes with real cues.
func signature_kill(pos: Vector2, elite: bool) -> void:
	if world == null or world.player == null:
		return
	var id: String = String(world.player.def.id)
	if id != _sig_id:
		_sig_id = id
		_sig = _sig_for(id)
	if _sig == 0:
		return
	if not elite:
		if _sig_budget < 1.0 or randf() > _shed_scale():
			return
		_sig_budget -= 1.0
	var k: int = 2 if elite else 1
	var kf := float(k)
	match _sig:
		1:  # Cowboy: brass ping + falling casings
			star(pos, 8.0 * kf, Color(1.0, 0.85, 0.4), 0.14, 0.0, PRIO_AMBIENT)
			for i in _shed_count(2 * k):
				emit(pos, Vector2(randf_range(-50.0, 50.0), randf_range(-110.0, -60.0)), 0.5, 2.0, Color(0.95, 0.75, 0.3), 3, 2.0, 260.0, false)
		2:  # Ninja: one clean diagonal cut through the corpse
			var cut := randf_range(-0.9, 0.9) - PI * 0.25
			beam(pos - Vector2.from_angle(cut) * 18.0 * kf, cut, 36.0 * kf, 2.2, 0.16, Color(0.8, 0.95, 1.0), PRIO_AMBIENT)
		3:  # Pirate: spray arcing up and falling back, the odd gold glint
			for i in _shed_count(4 * k):
				emit(pos, Vector2.from_angle(randf_range(-2.8, -0.35)) * randf_range(60.0, 140.0), randf_range(0.35, 0.55), randf_range(1.5, 2.4), Color(0.65, 0.88, 1.0), 0, 2.5, 320.0, false)
			if randf() < 0.3:
				star(pos, 7.0 * kf, Color(1.0, 0.85, 0.35), 0.14, 0.0, PRIO_AMBIENT)
		4:  # Paladin: a short pillar of light and rising motes
			beam(pos, -PI * 0.5, 40.0 * kf, 3.0, 0.28, Color(1.0, 0.92, 0.6), PRIO_AMBIENT)
			for i in _shed_count(2 * k):
				emit(pos + Vector2(randf_range(-6.0, 6.0), 0.0), Vector2(0.0, -30.0), 0.55, 2.2, Color(1.0, 0.9, 0.55), 1, 2.0, -40.0)
		5:  # Wizard: arcane ring and a tiny zig of lightning
			ring(pos, 4.0, 22.0 * kf, 0.2, Color(0.6, 0.5, 1.0), 1.5, PRIO_AMBIENT)
			var zig := PackedVector2Array([pos, pos + Vector2(randf_range(-10.0, 10.0), randf_range(-14.0, -6.0)) * kf, pos + Vector2(randf_range(-16.0, 16.0), randf_range(-26.0, -14.0)) * kf])
			bolt(zig, Color(0.65, 0.6, 1.0), 0.12, PRIO_AMBIENT)
		6:  # Spider: three web strands and venom drops
			var web0 := randf() * TAU
			for i in 3:
				beam(pos, web0 + TAU * float(i) / 3.0, 18.0 * kf, 1.2, 0.3, Color(0.92, 0.95, 0.92), PRIO_AMBIENT)
			for i in _shed_count(2 * k):
				emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(30.0, 80.0), 0.4, 2.0, Color(0.5, 1.0, 0.35), 0, 3.0, 180.0, false)
		7:  # Minotaur: heavy ring, dust and a thump
			ring(pos, 4.0, 34.0 * kf, 0.22, Color(0.85, 0.7, 0.5), 4.0, PRIO_AMBIENT)
			dust(pos)
			dust(pos)
			Game.shake(0.8 * kf)
		8:  # Harpy: drifting feathers
			for i in _shed_count(4 * k):
				emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(30.0, 90.0), randf_range(0.6, 0.9), randf_range(2.0, 3.0), Color(0.9, 0.85, 0.75), 2, 1.5, 70.0, false)
		9:  # Necromancer: souls lifting off the corpse
			for i in _shed_count(2 * k):
				emit(pos + Vector2(randf_range(-5.0, 5.0), 0.0), Vector2(randf_range(-14.0, 14.0), -40.0), 0.9, 4.0, Color(0.45, 1.0, 0.6, 0.85), 1, 1.2, -25.0)
			ring(pos, 3.0, 16.0 * kf, 0.25, Color(0.4, 0.95, 0.55), 1.5, PRIO_AMBIENT)
		10:  # Goose: feathers, and an occasional honk
			for i in _shed_count(4 * k):
				emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(40.0, 100.0), randf_range(0.5, 0.8), randf_range(2.0, 3.0), Color(1, 1, 1), 2, 1.5, 90.0, false)
			var now := Time.get_ticks_msec()
			if now >= _honk_ms and randf() < 0.12:
				_honk_ms = now + 1500
				float_text(pos + Vector2(0, -10), "HONK!", Color(1.0, 0.95, 0.7), 16, 0.7, 14.0)


# ------------------------------------------------------------------ impact feel tiers
## Each tier is one call from gameplay code and bundles shake + hit-stop + pulse. All three
## respect the Options sliders (via Game / World), and the cheap ones are rate-limited in real
## time so a build that crits 30x/sec gets texture, not a strobe or a stutter.

## Crit on an enemy: tiny ring + pop + nudge, hit-stop at most ~3x/sec.
func crit_feel(pos: Vector2, elite: bool) -> void:
	var now := Time.get_ticks_msec()
	if now >= _crit_fx_ms:
		_crit_fx_ms = now + 90
		star(pos, 15.0 if elite else 11.0, Color(1.0, 0.92, 0.55), 0.2, randf() * 0.8, PRIO_AMBIENT)
		if elite:
			ring(pos, 3.0, 30.0, 0.16, Color(1.0, 0.88, 0.4), 2.0, PRIO_AMBIENT)
		emit(pos, Vector2.ZERO, 0.07, 9.0, Color(1.0, 0.95, 0.7, 0.9), 1, 0.0)
		Game.shake(1.2)
	if now >= _crit_stop_ms:
		_crit_stop_ms = now + 300
		Game.hit_stop(0.03, 0.1)


## Regular elite died: freeze, kick, warm glow pulse. (Rings/particles come from death_burst.)
func elite_kill_feel(pos: Vector2) -> void:
	Game.hit_stop(0.07, 0.05)
	Game.shake(5.0)
	emit(pos, Vector2.ZERO, 0.22, 34.0, Color(1.0, 0.9, 0.7, 0.55), 1, 0.0)
	star(pos, 28.0, Color(1.0, 0.9, 0.7), 0.3)
	world.flash_screen(Color(1.0, 0.92, 0.75, 0.28), 2.5)


## Unique boss died: long freeze, max shake, 3-ring shockwave, ember shower, white pulse.
## (World's gold "Archive unsealed" flash is stronger and wins on top of this one.)
func boss_kill_feel(pos: Vector2) -> void:
	Game.hit_stop(0.16, 0.03)
	Game.shake(9.0)
	world.flash_screen(Color(1, 1, 1, 0.45), 1.6)
	ring(pos, 6.0, 190.0, 0.7, Color(1.0, 0.85, 0.5), 5.0, PRIO_IMPORTANT)
	ring(pos, 4.0, 130.0, 0.5, Color(1, 1, 1), 3.0, PRIO_IMPORTANT)
	ring(pos, 2.0, 80.0, 0.35, Color(1.0, 0.6, 0.3), 2.0, PRIO_IMPORTANT)
	emit(pos, Vector2.ZERO, 0.35, 60.0, Color(1.0, 0.95, 0.8, 0.6), 1, 0.0)
	star(pos, 46.0, Color(1.0, 0.95, 0.8), 0.5, 0.0, PRIO_IMPORTANT)
	var ray0 := randf() * TAU
	for i in 10:
		beam(pos, ray0 + TAU * float(i) / 10.0, randf_range(90.0, 210.0), randf_range(5.0, 9.0), randf_range(0.35, 0.6), Color(1.0, 0.85, 0.5), PRIO_IMPORTANT)
	for i in 48:
		emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 340.0), randf_range(0.5, 1.1), randf_range(1.5, 3.4), Color.from_hsv(randf_range(0.05, 0.14), 0.6, 1.0), 0, 2.5, 90.0)


## Boss crossed its enrage threshold: callout, red shockwave, kick, red pulse.
func enrage_feel(pos: Vector2) -> void:
	float_text(pos + Vector2(0, -34), "ENRAGED!", Color(1.0, 0.35, 0.25), 26, 1.6, 22.0, 0.5, true)
	ring(pos, 8.0, 140.0, 0.5, Color(1.0, 0.3, 0.2), 4.0, PRIO_IMPORTANT)
	Game.shake(5.0)
	world.flash_screen(Color(1.0, 0.15, 0.1, 0.22), 2.5)


func strike(pos: Vector2, size_scale: float = 0.9) -> void:
	for st in _strikes:
		if st.t >= 0.5:
			st.t = 0.0
			var sp: Sprite2D = st.sp
			sp.position = pos
			sp.scale = Vector2(size_scale, size_scale) * randf_range(0.9, 1.1)
			sp.flip_h = randf() < 0.5
			sp.frame = 0
			sp.visible = true
			return


func dust(pos: Vector2) -> void:
	if _pool_fill > SHED_START and randf() > _shed_scale():
		return
	emit(pos, Vector2(randf_range(-14, 14), randf_range(-12, -4)), 0.4, randf_range(1.5, 2.5), Color(0.55, 0.5, 0.42, 0.55), 0, 3.0, 0.0, false)


# ------------------------------------------------------------------ simulation + drawing
func _process(delta: float) -> void:
	if world == null:
		return
	delta = minf(delta, 1.0 / 30.0)
	_sig_budget = minf(SIG_BUDGET_MAX, _sig_budget + delta * SIG_BUDGET_RATE)
	var p_alive := 0
	for p in _particles:
		if p.life > 0.0:
			p_alive += 1
			p.life -= delta
			p.vel += Vector2(0, p.grav) * delta
			p.vel *= exp(-p.drag * delta)
			p.pos += p.vel * delta
	_pool_fill = float(p_alive) / float(MAX_PARTICLES)
	var s_alive := 0
	for s in _shapes:
		if s.life > 0.0:
			s_alive += 1
			s.life -= delta
	_stat_shapes_alive = s_alive
	for c in _cues:
		if c.ttl > 0.0:
			c.ttl -= delta
	for n in _numbers:
		if n.life > 0.0:
			n.life -= delta
			n.pos += n.vel * delta
			n.vel *= exp(-3.0 * delta)
	for st in _strikes:
		if st.t < 0.5:
			st.t += delta
			var sp: Sprite2D = st.sp
			sp.frame = mini(11, int(st.t * 24.0))
			sp.modulate.a = clampf((0.5 - st.t) * 5.0, 0.0, 1.0)
			if st.t >= 0.5:
				sp.visible = false
	_layer_add.queue_redraw()
	_layer_norm.queue_redraw()
	_layer_num.queue_redraw()


func draw_layer(canvas: Node2D, mode: int) -> void:
	if mode == 2:
		_draw_numbers(canvas)
		return
	var additive := mode == 0
	if additive:
		_draw_motes(canvas)
	for p in _particles:
		if p.life <= 0.0 or p.add != additive:
			continue
		var k: float = p.life / p.max_life
		var c: Color = p.color
		c.a *= clampf(k * 1.6, 0.0, 1.0)
		match p.kind:
			0:
				canvas.draw_rect(Rect2(p.pos - Vector2(p.size, p.size) * 0.5, Vector2(p.size, p.size)), c)
			1:
				canvas.draw_circle(p.pos, p.size * (0.6 + 0.6 * k), c)
			2:
				canvas.draw_line(p.pos, p.pos - p.vel * 0.035, c, maxf(1.0, p.size * k))
			3:
				canvas.draw_rect(Rect2(p.pos, Vector2(p.size * 1.4, p.size)), c)
	for s in _shapes:
		if s.life <= 0.0 or not additive:
			continue
		var t: float = 1.0 - s.life / s.max_life
		var a: float = 1.0 - t
		var col: Color = s.color
		match s.kind:
			0:
				var r: float = lerpf(s.r0, s.r1, 1.0 - pow(1.0 - t, 3.0))
				col.a = a * 0.9
				canvas.draw_arc(s.pos, r, 0.0, TAU, 40, col, maxf(1.0, s.width * a))
			1:
				var sweep: float = s.arc * (0.35 + 0.65 * minf(1.0, t * 2.6))
				var start: float = s.dir - s.flip * s.arc * 0.5
				var end: float = start + s.flip * sweep
				for layer in 3:
					var cc: Color = col.lerp(Color.WHITE, 0.35 * float(layer == 0))
					cc.a = a * (0.28 + 0.3 * float(layer))
					var rr: float = s.r1 * (0.86 + 0.07 * layer)
					canvas.draw_arc(s.pos, rr, minf(start, end), maxf(start, end), 22, cc, s.width * (1.5 - 0.35 * layer) * a + 1.0)
			2:
				var pts := PackedVector2Array()
				var cols := PackedColorArray()
				for i in 12:
					var f := float(i) / 11.0
					var curl: float = sin(f * PI * 1.6 + t * 9.0) * 16.0 * (1.0 - f * 0.4) * s.flip
					var head: float = minf(1.0, t * 3.0 + 0.2)
					var pt: Vector2 = s.pos + Vector2.from_angle(s.dir) * s.r1 * f * head + Vector2.from_angle(s.dir + PI * 0.5) * curl * head
					pts.append(pt)
					var cc2 := col
					cc2.a = a * (0.35 + 0.65 * f)
					cols.append(cc2)
				canvas.draw_polyline_colors(pts, cols, s.width * (1.2 - t * 0.6) + 0.5)
			3:
				var cb := col
				cb.a = a
				canvas.draw_polyline(s.pts, cb, s.width * (0.5 + a), false)
				var cw := Color(1, 1, 1, a)
				canvas.draw_polyline(s.pts, cw, 1.0, false)
			4:
				var pop: float = 1.0 - pow(1.0 - minf(1.0, t * 4.0), 2.0)
				col.a *= a
				_draw_star(canvas, s.pos, s.r1 * (0.3 + 0.7 * pop) * (1.0 - 0.4 * t), s.dir + s.flip * t * 0.9, col)
			5:
				var dr: float = lerpf(s.r0, s.r1, 1.0 - pow(1.0 - t, 2.0))
				if s.width <= 0.0:
					col.a *= a * 0.6
					canvas.draw_circle(s.pos, dr, col)
					canvas.draw_circle(s.pos, dr * 0.5, Color(1, 1, 1, col.a * 0.8))
				else:
					col.a *= a * 0.9
					canvas.draw_arc(s.pos, dr, 0.0, TAU, 40, col, maxf(1.0, s.width * (0.4 + 0.6 * a)))
			6:
				var wl: float = s.r1 * (0.6 + 0.4 * minf(1.0, t * 4.0))
				_draw_wedge(canvas, s.pos, s.dir, s.arc, wl, col, 0.3 * a, 0.9 * a)
			7:
				_draw_beam(canvas, s.pos, s.pos + Vector2.from_angle(s.dir) * s.r1, s.width * (0.35 + 0.65 * a), col, a)
	if additive:
		for c in _cues:
			if c.ttl > 0.0:
				_draw_cue(canvas, c)


# ------------------------------------------------------------------ shared draw helpers
func _draw_star(canvas: Node2D, pos: Vector2, size: float, rot: float, col: Color) -> void:
	# two long crossed diamonds (the 4 tips), two short diagonal ones, and a hot centre
	for k in 2:
		var ax := Vector2.from_angle(rot + PI * 0.5 * float(k))
		var pr := ax.orthogonal()
		canvas.draw_colored_polygon(PackedVector2Array([pos + ax * size, pos + pr * size * 0.16, pos - ax * size, pos - pr * size * 0.16]), col)
	var dc := col
	dc.a *= 0.55
	for k in 2:
		var dx := Vector2.from_angle(rot + PI * 0.25 + PI * 0.5 * float(k))
		var dp := dx.orthogonal()
		canvas.draw_colored_polygon(PackedVector2Array([pos + dx * size * 0.5, pos + dp * size * 0.1, pos - dx * size * 0.5, pos - dp * size * 0.1]), dc)
	canvas.draw_circle(pos, maxf(1.0, size * 0.2), Color(1, 1, 1, col.a))


## Filled sector (apex at pos) with bright edges. fill_a / edge_a multiply col.a.
func _draw_wedge(canvas: Node2D, pos: Vector2, dir: float, arc: float, length: float, col: Color, fill_a: float, edge_a: float) -> void:
	arc = clampf(arc, 0.02, TAU - 0.2)
	var seg := 14
	var pts := PackedVector2Array()
	pts.append(pos)
	for i in seg + 1:
		pts.append(pos + Vector2.from_angle(dir - arc * 0.5 + arc * float(i) / float(seg)) * length)
	var fc := col
	fc.a = col.a * fill_a
	if fc.a > 0.0:
		canvas.draw_colored_polygon(pts, fc)
	var ec := col
	ec.a = col.a * edge_a
	if ec.a > 0.0:
		canvas.draw_line(pos, pts[1], ec, 1.5)
		canvas.draw_line(pos, pts[seg + 1], ec, 1.5)
		canvas.draw_polyline(pts.slice(1), ec, 1.5)


## Three stacked strokes: wide soft glow, mid colour, thin white core. a01 multiplies the alpha.
func _draw_beam(canvas: Node2D, from: Vector2, to: Vector2, width: float, col: Color, a01: float) -> void:
	var g := col
	g.a = col.a * a01 * 0.25
	canvas.draw_line(from, to, g, width * 3.0)
	var m := col
	m.a = col.a * a01 * 0.6
	canvas.draw_line(from, to, m, width * 1.6)
	canvas.draw_line(from, to, Color(1, 1, 1, col.a * a01 * 0.9), maxf(1.0, width * 0.5))


func _draw_cue(canvas: Node2D, c: Cue) -> void:
	var fade: float = clampf(c.ttl / CUE_FADE, 0.0, 1.0)
	var ch: float = c.charge
	match c.kind:
		0:
			var pulse: float = 0.85 + 0.15 * sin(ch * 9.0)
			_draw_wedge(canvas, c.pos, c.dir, c.spread, c.length * (0.55 + 0.45 * ch), c.color, (0.08 + 0.22 * ch) * pulse * fade, (0.35 + 0.6 * ch) * fade)
		1:
			var rad: float = lerpf(c.length, c.r_to, ch * ch)
			var rc: Color = c.color
			rc.a = (0.25 + 0.7 * ch) * fade
			canvas.draw_arc(c.pos, rad, 0.0, TAU, 48, rc, 1.5 + 2.5 * ch)
			var tc: Color = c.color
			tc.a = (0.15 + 0.35 * ch) * fade
			canvas.draw_arc(c.pos, c.r_to, 0.0, TAU, 32, tc, 1.0)
		2:
			var tail := 0.6
			var slices := 5
			for k in slices:
				var sd: float = c.dir - c.flip * tail * (float(k) + 0.5) / float(slices)
				_draw_wedge(canvas, c.pos, sd, tail / float(slices) * 1.05, c.length, c.color, 0.3 * (1.0 - float(k) / float(slices)) * fade, 0.0)
			_draw_beam(canvas, c.pos, c.pos + Vector2.from_angle(c.dir) * c.length, 2.5, c.color, fade)
		3:
			var ph: float = sin(Time.get_ticks_msec() * 0.001 * c.r_to)
			var ar: float = c.length * (1.0 + 0.06 * ph)
			var ac: Color = c.color
			ac.a = (0.07 + 0.03 * ph) * fade
			canvas.draw_circle(c.pos, ar, ac)
			ac.a = (0.35 + 0.15 * ph) * fade
			canvas.draw_arc(c.pos, ar, 0.0, TAU, 40, ac, 1.5)


func _draw_motes(canvas: Node2D) -> void:
	var cam: Vector2 = world.camera.get_screen_center_position() if world.camera != null else Vector2.ZERO
	var t := Time.get_ticks_msec() / 1000.0
	for m in _motes:
		var off: Vector2 = m.pos
		# wrap around the camera so motes stay on screen without spawning anything
		var wx := fposmod(off.x + t * 5.0 * m.s - cam.x * 0.9, 680.0) - 340.0
		var wy := fposmod(off.y - t * 4.0 * m.s - cam.y * 0.9, 400.0) - 200.0
		var p := cam + Vector2(wx, wy) + Vector2(sin(t * 0.6 + m.ph) * 6.0, 0.0)
		var a := 0.10 + 0.08 * sin(t * 1.3 + m.ph)
		canvas.draw_circle(p, 1.0 + m.s * 0.5, Color(0.7, 0.85, 1.0, a))


func _draw_numbers(canvas: Node2D) -> void:
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for n in _numbers:
		if n.life <= 0.0:
			continue
		var sp: Vector2 = xf * n.pos
		var a := clampf(n.life * 4.0, 0.0, 1.0)
		var pop_t := minf(0.35, n.max_life * 0.5)
		var pop: float = 1.0 + n.pop * clampf((n.life - (n.max_life - pop_t)) / pop_t, 0.0, 1.0)
		var fs := int(n.size * pop)
		var w := _font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := sp - Vector2(w * 0.5, 0.0)
		if n.keep_on_screen:
			at.x = clampf(at.x, 8.0, vs.x - w - 8.0)
			at.y = clampf(at.y, float(fs) + 8.0, vs.y - 8.0)
		canvas.draw_string_outline(_font, at, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.05, 0.03, 0.08, a))
		var c: Color = n.color
		c.a = a
		canvas.draw_string(_font, at, n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
