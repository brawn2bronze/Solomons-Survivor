class_name EvoModule
extends RefCounted
## Base class for every evolution option. One instance per picked option per ability.
## State lives here; `ab` is the owning Ability. Read this option's namespaced tuning
## params via `p(key, fallback)` which reads `ab.flags[id][key]`.
var ab: Ability
var id := ""

func p(key: String, fallback: Variant = 0.0) -> Variant:
	var d: Variant = ab.flags.get(id, {})
	if d is Dictionary:
		return (d as Dictionary).get(key, fallback)
	return fallback

func on_ready() -> void:
	pass

func update(_delta: float) -> void:
	pass

## Before an attack resolves; may edit ctx (dir, radius, arc, origin, mult, cancel).
func on_attack(_ctx: Dictionary) -> void:
	pass

## The ability's own signature pulse fired (not a weapon swing). ctx: {origin, radius, ...}.
func on_flash(_ctx: Dictionary) -> void:
	pass

## After a hit lands. ctx: {e, amount}.
func on_hit(_ctx: Dictionary) -> void:
	pass

## Player took damage. ctx: {amount}.
func on_hurt(_ctx: Dictionary) -> void:
	pass

## The other ability fired its main action. ctx: {src, ...}.
func on_player_cast(_ctx: Dictionary) -> void:
	pass

## An enemy died. ctx: none (e passed directly).
func on_kill(_e) -> void:
	pass

func draw(_canvas: Node2D) -> void:
	pass
