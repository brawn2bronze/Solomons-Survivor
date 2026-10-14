class_name FxManager
extends Node2D
## All transient visual feedback: sparks, death bursts, slash arcs, rings, damage numbers, floating text,
## impact-feel tiers (shake + hit-stop + pulse), ambient dust.
## Everything is a pooled struct drawn from two _draw layers (additive glow + normal), so there are
## no per-particle nodes. Caps keep the worst case bounded.

const MAX_PARTICLES := 640
const MAX_SHAPES := 96
const MAX_NUMBERS := 60

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
	var kind := 0            # 0 ring, 1 slash arc, 2 lash polyline, 3 bolt polyline
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


func _shape() -> Shape:
	if _shapes.size() < MAX_SHAPES:
		var s := Shape.new()
		_shapes.append(s)
		return s
	for s in _shapes:
		if s.life <= 0.0:
			return s
	return _shapes[0]


func hit_sparks(pos: Vector2, dir: Vector2, color: Color, count: int = 4) -> void:
	var base := dir.angle() if dir.length() > 0.1 else randf() * TAU
	for i in count:
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
	for i in 5:
		emit(pos + dir * 6.0, Vector2.from_angle(a + randf_range(-0.35, 0.35)) * randf_range(120.0, 260.0), randf_range(0.06, 0.12), 2.0, color, 2, 6.0)
	# ejected casing
	emit(pos, Vector2.from_angle(a + PI * 0.5 * signf(randf() - 0.5)) * randf_range(40.0, 80.0) + Vector2(0, -40), 0.55, 2.0, Color(0.95, 0.75, 0.3), 3, 2.0, 260.0, false)


func ring(pos: Vector2, r0: float, r1: float, life: float, color: Color, width: float = 2.0) -> void:
	var s := _shape()
	s.kind = 0
	s.pos = pos
	s.r0 = r0
	s.r1 = r1
	s.life = life
	s.max_life = life
	s.color = color
	s.width = width


func slash_arc(pos: Vector2, dir: float, radius: float, arc: float, color: Color, flip: float = 1.0, life: float = 0.16) -> void:
	var s := _shape()
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


func lash(pos: Vector2, dir: float, length: float, color: Color) -> void:
	var s := _shape()
	s.kind = 2
	s.pos = pos
	s.dir = dir
	s.r1 = length
	s.life = 0.18
	s.max_life = 0.18
	s.color = color
	s.width = 3.0
	s.flip = 1.0 if randf() < 0.5 else -1.0


func bolt(points: PackedVector2Array, color: Color, life: float = 0.18) -> void:
	var s := _shape()
	s.kind = 3
	s.pts = points
	s.life = life
	s.max_life = life
	s.color = color
	s.width = 2.5


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


# ------------------------------------------------------------------ impact feel tiers
## Each tier is one call from gameplay code and bundles shake + hit-stop + pulse. All three
## respect the Options sliders (via Game / World), and the cheap ones are rate-limited in real
## time so a build that crits 30x/sec gets texture, not a strobe or a stutter.

## Crit on an enemy: tiny ring + pop + nudge, hit-stop at most ~3x/sec.
func crit_feel(pos: Vector2, elite: bool) -> void:
	var now := Time.get_ticks_msec()
	if now >= _crit_fx_ms:
		_crit_fx_ms = now + 90
		ring(pos, 3.0, 30.0 if elite else 22.0, 0.16, Color(1.0, 0.88, 0.4), 2.0)
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
	world.flash_screen(Color(1.0, 0.92, 0.75, 0.28), 2.5)


## Unique boss died: long freeze, max shake, 3-ring shockwave, ember shower, white pulse.
## (World's gold "Archive unsealed" flash is stronger and wins on top of this one.)
func boss_kill_feel(pos: Vector2) -> void:
	Game.hit_stop(0.16, 0.03)
	Game.shake(9.0)
	world.flash_screen(Color(1, 1, 1, 0.45), 1.6)
	ring(pos, 6.0, 190.0, 0.7, Color(1.0, 0.85, 0.5), 5.0)
	ring(pos, 4.0, 130.0, 0.5, Color(1, 1, 1), 3.0)
	ring(pos, 2.0, 80.0, 0.35, Color(1.0, 0.6, 0.3), 2.0)
	emit(pos, Vector2.ZERO, 0.35, 60.0, Color(1.0, 0.95, 0.8, 0.6), 1, 0.0)
	for i in 48:
		emit(pos, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 340.0), randf_range(0.5, 1.1), randf_range(1.5, 3.4), Color.from_hsv(randf_range(0.05, 0.14), 0.6, 1.0), 0, 2.5, 90.0)


## Boss crossed its enrage threshold: callout, red shockwave, kick, red pulse.
func enrage_feel(pos: Vector2) -> void:
	float_text(pos + Vector2(0, -34), "ENRAGED!", Color(1.0, 0.35, 0.25), 26, 1.6, 22.0, 0.5, true)
	ring(pos, 8.0, 140.0, 0.5, Color(1.0, 0.3, 0.2), 4.0)
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
	emit(pos, Vector2(randf_range(-14, 14), randf_range(-12, -4)), 0.4, randf_range(1.5, 2.5), Color(0.55, 0.5, 0.42, 0.55), 0, 3.0, 0.0, false)


# ------------------------------------------------------------------ simulation + drawing
func _process(delta: float) -> void:
	if world == null:
		return
	delta = minf(delta, 1.0 / 30.0)
	for p in _particles:
		if p.life > 0.0:
			p.life -= delta
			p.vel += Vector2(0, p.grav) * delta
			p.vel *= exp(-p.drag * delta)
			p.pos += p.vel * delta
	for s in _shapes:
		if s.life > 0.0:
			s.life -= delta
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
