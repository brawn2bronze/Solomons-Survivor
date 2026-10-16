class_name FxLayer
extends Node2D
## Thin draw target: the FxManager owns all data and paints through this node's _draw.

var manager
var mode := 0    # 0 additive world, 1 normal world, 2 screen-space numbers


func _draw() -> void:
	if manager != null:
		manager.draw_layer(self, mode)
