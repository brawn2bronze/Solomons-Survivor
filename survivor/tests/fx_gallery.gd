extends Node
## Kill-FX lab + publisher. Open fx_gallery.tscn and play the scene (F6):
## director paused + godmode, so only the FX you trigger is on screen.
## Pick a character, pick an effect, tune the sprite tryout (unsaved preview),
## then Publish writes the values into that character's .tres and applies them
## to the live def, so the Kill buttons preview the published result at once.
## Scaling: new characters appear in the picker automatically (DB scans
## data/characters/). New effects need one EFFECTS entry + their resolver;
## picker, writer and preview logic are shared.

## Effect registry. One entry per publishable effect: picker label, .tres field
## names in write order, control roles parallel to fields, value kinds parallel
## to fields ("path", "int", "float"). Controls live in _controls by role, so a
## new effect reuses the same path box + spinners when its roles match.
const EFFECTS := {
	"kill": {
		"label": "Kill signature",
		"fields": ["kill_fx_sprite", "kill_fx_frames", "kill_fx_fps", "kill_fx_life", "kill_fx_scale", "kill_fx_loops"],
		"roles": ["path", "frames", "fps", "life", "scale", "loops"],
		"kinds": ["path", "int", "float", "float", "float", "int"],
	},
}
const EFFECT_ORDER := ["kill"]

var _world: World
var _status: Label
var _char_btn: OptionButton
var _fx_btn: OptionButton
var _char_ids: Array = []
var _controls: Dictionary = {}
var _path_edit: LineEdit
var _frames_spin: SpinBox
var _fps_spin: SpinBox
var _life_spin: SpinBox
var _scale_spin: SpinBox
var _loops_spin: SpinBox
var _rate_slider: HSlider
var _rate_label: Label


func _ready() -> void:
	_build_ui()
	_populate_characters()
	_populate_effects()
	var def_idx: int = maxi(0, _char_ids.find("paladin"))
	if _char_ids.is_empty():
		_status.text = "No characters in DB."
		return
	_char_btn.select(def_idx)
	_open_world(String(_char_ids[def_idx]))


## (Re)builds the preview world for one character id. Old world leaves the tree
## at once (freed at frame end); the new one boots paused + godmode.
func _open_world(char_id: String) -> void:
	if is_instance_valid(_world):
		remove_child(_world)
		_world.queue_free()
		_world = null
	var w: World = World.new()
	add_child(w)
	w.start(char_id)
	_world = w
	w.enemies.director_paused = true
	w.dev_set_godmode(true)
	_refresh_status()


func _populate_characters() -> void:
	_char_ids.clear()
	_char_btn.clear()
	for c in DB.roster():
		_char_ids.append(String(c.id))
	for i in _char_ids.size():
		_char_btn.add_item(String(_char_ids[i]), i)


func _populate_effects() -> void:
	_fx_btn.clear()
	for i in EFFECT_ORDER.size():
		var spec: Dictionary = EFFECTS[EFFECT_ORDER[i]]
		_fx_btn.add_item(String(spec.get("label", EFFECT_ORDER[i])), i)
	_fx_btn.select(0)


func _effect_key() -> String:
	if _fx_btn == null or _fx_btn.item_count == 0:
		return "kill"
	return String(EFFECT_ORDER[_fx_btn.selected])


func _on_char_selected(idx: int) -> void:
	if idx < 0 or idx >= _char_ids.size():
		return
	_open_world(String(_char_ids[idx]))


func _on_effect_selected(_idx: int) -> void:
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
	if not is_instance_valid(_world) or _world.player == null:
		_status.text = "No preview world."
		return
	var id: String = String(_world.player.def.id)
	var kfx: Dictionary = AbilityArt.for_kill(_world.player.def)
	if bool(kfx.get("fallback", true)):
		_status.text = "%s .tres: procedural fallback (kill_fx_sprite empty)." % id
	else:
		_status.text = "%s .tres: %s  %dx @%.0ffps  %.2fs  x%.1f  L%d" % [id, String(kfx["path"]), int(kfx["frames"]), float(kfx["fps"]), float(kfx["life"]), float(kfx["scale"]), int(kfx["loops"])]


## Publish: validate the tryout controls, upsert the active effect's fields in
## the selected character's .tres (text edit, rest of file untouched), apply the
## same values to the live def, and refresh so Kill previews instantly.
func _on_publish() -> void:
	var effect: String = _effect_key()
	var spec: Dictionary = EFFECTS.get(effect, {})
	var values: Array = _effect_values(spec)
	var path_idx: int = Array(spec.get("roles", [])).find("path")
	var sprite_path: String = String(values[path_idx]) if path_idx >= 0 and path_idx < values.size() else ""
	if sprite_path == "":
		_status.text = "Type a PNG strip path first."
		return
	if not ResourceLoader.exists(sprite_path):
		_status.text = "PNG not found: %s (drop it in art/fx/ first)." % sprite_path
		return
	if _char_btn.selected < 0 or _char_btn.selected >= _char_ids.size():
		_status.text = "Pick a character first."
		return
	var char_id: String = String(_char_ids[_char_btn.selected])
	var tres_path: String = "res://data/characters/%s.tres" % char_id
	if not _write_tres_fields(tres_path, spec, values):
		_status.text = "Publish failed: could not write %s." % tres_path
		return
	_apply_to_live_def(char_id, spec, values)
	_refresh_status()
	_status.text = "Published to %s.tres + live preview. %s" % [char_id, _status.text]


## Reads the active effect's values from the shared controls by role.
func _effect_values(spec: Dictionary) -> Array:
	var roles: Array = spec.get("roles", [])
	var kinds: Array = spec.get("kinds", [])
	var out: Array = []
	for i in roles.size():
		var ctl = _controls.get(String(roles[i]))
		var kind: String = String(kinds[i]) if i < kinds.size() else "float"
		if ctl is LineEdit:
			out.append(ctl.text.strip_edges())
		elif ctl is SpinBox:
			if kind == "int":
				out.append(int(ctl.value))
			else:
				out.append(float(ctl.value))
		else:
			out.append(null)
	return out


## Formats one value as a .tres literal (quoted path, bare int, dotted float).
func _tres_literal(value, kind: String) -> String:
	match kind:
		"path":
			return "\"%s\"" % String(value).c_escape()
		"int":
			return str(int(value))
		_:
			var f: float = float(value)
			if f == floorf(f):
				return "%.1f" % f
			return str(f)


## Upserts field lines in a .tres by plain text edit: existing lines replaced in
## place, missing ones appended. Whole-file rewrite keeps LF endings; a read-back
## pass verifies every line landed before reporting success.
func _write_tres_fields(tres_path: String, spec: Dictionary, values: Array) -> bool:
	if not FileAccess.file_exists(tres_path):
		return false
	var fh := FileAccess.open(tres_path, FileAccess.READ)
	if fh == null:
		return false
	var lines: PackedStringArray = fh.get_as_text().split("\n")
	fh.close()
	var fields: Array = spec.get("fields", [])
	var kinds: Array = spec.get("kinds", [])
	var pending := {}
	for i in fields.size():
		var fname: String = String(fields[i])
		var fkind: String = String(kinds[i]) if i < kinds.size() else "float"
		pending[fname] = "%s = %s" % [fname, _tres_literal(values[i], fkind)]
	for n in lines.size():
		var stripped: String = lines[n].strip_edges()
		for f in pending.keys():
			var key: String = String(f)
			if stripped == key or stripped.begins_with(key + " =") or stripped.begins_with(key + "="):
				lines[n] = String(pending[f])
				pending.erase(f)
				break
		if pending.is_empty():
			break
	for f in pending.keys():
		lines.append(String(pending[f]))
	var out := FileAccess.open(tres_path, FileAccess.WRITE)
	if out == null:
		return false
	out.store_string("\n".join(lines))
	out.close()
	var check := FileAccess.open(tres_path, FileAccess.READ)
	if check == null:
		return false
	var text: String = check.get_as_text()
	check.close()
	for i in fields.size():
		var fname: String = String(fields[i])
		var fkind: String = String(kinds[i]) if i < kinds.size() else "float"
		if not text.contains("%s = %s" % [fname, _tres_literal(values[i], fkind)]):
			return false
	return true


## Applies published values to the live preview def (same object DB holds for
## this session), so the Kill buttons play them with no scene restart.
func _apply_to_live_def(char_id: String, spec: Dictionary, values: Array) -> void:
	if not is_instance_valid(_world) or _world.player == null:
		return
	if String(_world.player.def.id) != char_id:
		return
	var fields: Array = spec.get("fields", [])
	for i in fields.size():
		_world.player.def.set(String(fields[i]), values[i])


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
	v.add_child(UI.label("KILL FX LAB", 18, UI.GOLD))
	v.add_child(UI.label("Character (.tres target)", 13, UI.PURPLE))
	_char_btn = OptionButton.new()
	_char_btn.custom_minimum_size = Vector2(280, 32)
	v.add_child(_char_btn)
	_char_btn.item_selected.connect(_on_char_selected)
	v.add_child(UI.label("Effect", 13, UI.PURPLE))
	_fx_btn = OptionButton.new()
	_fx_btn.custom_minimum_size = Vector2(280, 32)
	v.add_child(_fx_btn)
	_fx_btn.item_selected.connect(_on_effect_selected)
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
	_controls["path"] = _path_edit
	_controls["frames"] = _frames_spin
	_controls["fps"] = _fps_spin
	_controls["life"] = _life_spin
	_controls["scale"] = _scale_spin
	_controls["loops"] = _loops_spin
	var sb: Button = UI.button("Play sprite", 15, Vector2(140, 36))
	sb.pressed.connect(_on_sprite)
	v.add_child(sb)
	var pb: Button = UI.button("Publish to .tres", 15, Vector2(170, 36))
	pb.pressed.connect(_on_publish)
	v.add_child(pb)
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
