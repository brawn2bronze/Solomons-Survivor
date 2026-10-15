class_name CoinIcon
extends Control
## Seal Fragment coin shared by the HUD counter and the Black Market.
## Animated 12-frame strip (art/pickups/seal.png); the old drawn shard
## stays as fallback until the import lands.

const SIZE := 26.0
const STRIP := "res://art/pickups/seal.png"
const FRAMES := 12
const FPS := 8.0

var _tex: Texture2D
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex = DB.texture(STRIP)
	_t = randf() * (float(FRAMES) / FPS)


func _process(delta: float) -> void:
	if _tex == null:
		return
	_t += delta
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		_draw_shard()
		return
	var cw: float = _tex.get_size().x / float(FRAMES)
	var ch: float = _tex.get_size().y
	var idx: int = int(_t * FPS) % FRAMES
	draw_texture_rect_region(_tex, Rect2(Vector2.ZERO, size), Rect2(Vector2(cw * float(idx), 0.0), Vector2(cw, ch)))


func _draw_shard() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.46
	var shard := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.62, 0), c + Vector2(0, r), c + Vector2(-r * 0.62, 0)])
	draw_colored_polygon(shard, Color(0.28, 0.12, 0.5))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.78), c + Vector2(r * 0.46, 0), c + Vector2(0, r * 0.78), c + Vector2(-r * 0.46, 0)]), UI.ESSENCE)
	draw_line(c + Vector2(0, -r * 0.78), c + Vector2(0, r * 0.78), Color(0.85, 0.65, 1.0), 1.5)
	draw_circle(c + Vector2(-r * 0.18, -r * 0.3), r * 0.14, Color(0.95, 0.88, 1.0))
