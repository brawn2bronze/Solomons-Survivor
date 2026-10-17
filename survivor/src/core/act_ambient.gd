class_name ActAmbient
extends CanvasLayer
## Per-act ambient particle wash (ash / glitch / embers / gold), drawn in one
## `_draw` batch in screen space. Sits at layer 4 (below the vignette layer 5
## and the HUD). Preset swaps fade out/in over ~1.5s. No per-frame allocation.

const COUNT := 70

class Painter:
	extends Node2D
	var host: ActAmbient
	func _draw() -> void:
		host._paint(self)


var world
var _painter: Painter
var _preset := "ash"
var _want := "ash"
var _alpha := 0.0
var _t := 0.0
var _tear_t := 0.0
var _tear_frames := 0
var _tear_y := 0.0
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _spd := PackedFloat32Array()
var _size := PackedFloat32Array()
var _phase := PackedFloat32Array()


func setup(world_ref) -> void:
	world = world_ref
	layer = 4
	_painter = Painter.new()
	_painter.host = self
	add_child(_painter)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for i in COUNT:
		_px.append(rng.randf())
		_py.append(rng.randf())
		_spd.append(rng.randf_range(0.6, 1.4))
		_size.append(rng.randf_range(0.8, 2.6))
		_phase.append(rng.randf() * TAU)
	_alpha = 1.0


func set_act(act: ActDef, instant: bool) -> void:
	_want = String(act.ambient) if act != null else "ash"
	if instant or _want == _preset:
		_preset = _want
		_alpha = 1.0
	if _painter != null:
		_painter.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var rate := delta / 0.75
	if _preset != _want:
		_alpha -= rate
		if _alpha <= 0.0:
			_alpha = 0.0
			_preset = _want
	elif _alpha < 1.0:
		_alpha = minf(1.0, _alpha + rate)
	if _tear_frames > 0:
		_tear_frames -= 1
	elif _preset == "glitch" and Game.fx_flash > 0.0:
		_tear_t -= delta
		if _tear_t <= 0.0:
			_tear_t = randf_range(3.0, 7.0)
			_tear_frames = 1 + (randi() % 2)
			_tear_y = randf()
	if _painter != null:
		_painter.queue_redraw()


func _paint(c: Node2D) -> void:
	if _alpha <= 0.001:
		return
	var vs: Vector2 = c.get_viewport_rect().size
	var a: float = _alpha
	for i in COUNT:
		var px: float = _px[i] * vs.x
		var py: float = _py[i] * vs.y
		var sp: float = _spd[i]
		match _preset:
			"ash":
				py = fposmod(_py[i] + _t * 0.012 * _spd[i], 1.0) * vs.y
				px += sin(_t * 0.4 * _spd[i] + _phase[i]) * 14.0
				c.draw_circle(Vector2(px, py), _size[i], Color(0.7, 0.55, 0.85, 0.05 * a))
			"glitch":
				var step := float(int(_t * 12.0))
				var jx := (fposmod(sin((i * 12.9898) + step * 78.233) * 43758.5453, 1.0) - 0.5) * 6.0
				var cols := [Color(0.2, 0.95, 0.95, 0.5), Color(0.9, 0.3, 0.9, 0.5)]
				var col: Color = cols[i % 2]
				c.draw_rect(Rect2(px + jx, py, _size[i] * 2.0, _size[i] * 0.8), Color(col.r, col.g, col.b, 0.18 * a))
	if _preset == "glitch" and _tear_frames > 0 and Game.fx_flash > 0.0:
		var ty: float = _tear_y * vs.y
		var th: float = 1.0 + float(_tear_frames)
		c.draw_rect(Rect2(0.0, ty, vs.x, th), Color(0.15, 0.9, 0.95, 0.12))
		c.draw_rect(Rect2(vs.x * 0.5, ty, vs.x * 0.5, th), Color(0.9, 0.25, 0.9, 0.10))
	if _preset == "embers":
		for i in COUNT:
			var px: float = _px[i] * vs.x + sin(_t * 0.8 + _phase[i]) * 12.0
			var py: float = fmod(_py[i] * vs.y + _t * 46.0 * _spd[i], vs.y + 40.0)
			var yy := vs.y + 20.0 - py
			var col := Color(1.0, 0.35, 0.12) if i % 2 == 0 else Color(0.9, 0.15, 0.1)
			c.draw_circle(Vector2(px, yy), _size[i] * 1.1, Color(col.r, col.g, col.b, 0.22 * a))
	elif _preset == "gold":
		for i in COUNT:
			var px: float = _px[i] * vs.x + sin(_t * 0.35 + _phase[i]) * 18.0
			var py: float = fmod(_py[i] * vs.y + _t * 14.0 * _spd[i], vs.y + 40.0)
			var yy := vs.y + 20.0 - py
			c.draw_circle(Vector2(px, yy), _size[i] * 1.3, Color(1.0, 0.85, 0.4, 0.20 * a))
