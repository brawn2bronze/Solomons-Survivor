class_name CoinIcon
extends Control
## Tiny drawn fragment shard shared by the HUD counter and the Black Market (no art asset needed).

const SIZE := 26.0


func _init() -> void:
    custom_minimum_size = Vector2(SIZE, SIZE)
    mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
    var c: Vector2 = size * 0.5
    var r: float = minf(size.x, size.y) * 0.46
    var shard := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.62, 0), c + Vector2(0, r), c + Vector2(-r * 0.62, 0)])
    draw_colored_polygon(shard, Color(0.28, 0.12, 0.5))
    draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.78), c + Vector2(r * 0.46, 0), c + Vector2(0, r * 0.78), c + Vector2(-r * 0.46, 0)]), UI.ESSENCE)
    draw_line(c + Vector2(0, -r * 0.78), c + Vector2(0, r * 0.78), Color(0.85, 0.65, 1.0), 1.5)
    draw_circle(c + Vector2(-r * 0.18, -r * 0.3), r * 0.14, Color(0.95, 0.88, 1.0))
