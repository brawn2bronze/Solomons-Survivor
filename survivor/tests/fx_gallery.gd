extends Node
## Isolated kill-FX preview. Open fx_gallery.tscn and play the scene (F6):
## director paused + godmode, so only the FX you trigger is on screen.
## Kill buttons use the live CharacterDef (procedural until kill_fx_sprite is set).
## Sprite button plays any PNG strip path typed below (try the shipped skull strip
## first), with the frames/fps/life/scale/loops spinners. Copy tuned values into the
## character .tres kill_fx_* fields when happy.

var _world: World
var _status: Label
var _path_edit: LineEdit
var _frames_spin: SpinBox
var _fps_spin: SpinBox
var _life_spin: SpinBox
var _scale_spin: SpinBox
var _loops_spin: SpinBox
var _rate_slider: HSlider
var _rate_label: Label


func _ready() -> void:
	var w: World = World.new()
	add_child(w)
	w.start("paladin")
	_world = w
	w.enemies.director_paused = true
	w.dev_set_godmode(true)
	_build_ui()
	_refresh_status()


func _at() -> Vector2:
	return _world.player.global_position + Vector2(80, 0)


func _on_kill() -> void:
	_world.fx.signature_kill(_at(), false)
	_refresh_status()


func _on_elite() -> void:
	_world.fx.signature_kill(_at(), true)
	_refresh_status()


func _on_sprite() -> void:
	var fx: Dictionary = {
		"path": _path_edit.text.strip_edges(),
		"frames": int(_frames_spin.value),
		"fps": float(_fps_spin.value),
		"life": float(_life_spin.value),
		"scale": float(_scale_spin.value),
		"loops": int(_loops_spin.value),
		"offset": Vector2.ZERO,
		"tint": Color.WHITE,
		"fallback": false,
	}
	if String(fx.get("path", "")) == "":
		_status.text = "Type a PNG strip path first."
		return
	_world.fx.kill_sprite(_at(), 1.0, fx)
	_status.text = "Sprite: %s  %dx @%.0ffps  %.2fs  x%.1f  L%d" % [String(fx["path"]), int(fx["frames"]), float(fx["fps"]), float(fx["life"]), float(fx["scale"]), int(fx["loops"])]


func _on_rate(v: float) -> void:
	_world.dev_set_time_rate(v)
	_rate_label.text = "Time rate x%.2f (slow-mo FX)" % v


func _refresh_status() -> void:
	var kfx: Dictionary = AbilityArt.for_kill(_world.player.def)
	if bool(kfx.get("fallback", true)):
		_status.text = "paladin .tres: procedural fallback (kill_fx_sprite empty)."
	else:
		_status.text = "paladin .tres: %s  %dx @%.0ffps  %.2fs  x%.1f  L%d" % [String(kfx["path"]), int(kfx["frames"]), float(kfx["fps"]), float(kfx["life"]), float(kfx["scale"]), int(kfx["loops"])]


func _build_ui() -> void:
	var cl: CanvasLayer = CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	var panel: PanelContainer = UI.panel()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = 12.0
	panel.offset_right = 326.0
	panel.offset_top = 90.0
	root.add_child(panel)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UI.label("KILL FX LAB (paladin)", 18, UI.GOLD))
	_status = UI.label("", 14, UI.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(UI.label("Live def (signature_kill)", 13, UI.PURPLE))
	v.add_child(_row_buttons(["Kill", "Elite kill"], [_on_kill, _on_elite]))
	v.add_child(UI.label("Sprite tryout (kill_sprite, unsaved)", 13, UI.PURPLE))
	_path_edit = LineEdit.new()
	_path_edit.text = "res://art/fx/skull_projectile.png"
	_path_edit.custom_minimum_size = Vector2(280, 32)
	v.add_child(_path_edit)
	_frames_spin = _spinner(v, "Frames", 2.0, 1.0, 12.0, 1.0)
	_fps_spin = _spinner(v, "FPS", 8.0, 1.0, 24.0, 1.0)
	_life_spin = _spinner(v, "Life s", 0.28, 0.05, 2.0, 0.05)
	_scale_spin = _spinner(v, "Scale", 1.0, 0.1, 4.0, 0.1)
	_loops_spin = _spinner(v, "Loops (0=inf)", 1.0, 0.0, 8.0, 1.0)
	var sb: Button = UI.button("Play sprite", 15, Vector2(140, 36))
	sb.pressed.connect(_on_sprite)
	v.add_child(sb)
	_rate_label = UI.label("Time rate x1.00 (slow-mo FX)", 14, UI.DIM)
	v.add_child(_rate_label)
	_rate_slider = HSlider.new()
	_rate_slider.min_value = 0.1
	_rate_slider.max_value = 1.0
	_rate_slider.step = 0.05
	_rate_slider.value = 1.0
	_rate_slider.custom_minimum_size = Vector2(280, 20)
	_rate_slider.value_changed.connect(_on_rate)
	v.add_child(_rate_slider)


func _row_buttons(labels: Array, cbs: Array) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for i in labels.size():
		var b: Button = UI.button(String(labels[i]), 15, Vector2(140, 36))
		b.pressed.connect(cbs[i])
		h.add_child(b)
	return h


func _spinner(parent: Control, text: String, val: float, lo: float, hi: float, step: float) -> SpinBox:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	h.add_child(UI.label(text, 14, UI.DIM))
	var s: SpinBox = SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(140, 32)
	h.add_child(s)
	return s
