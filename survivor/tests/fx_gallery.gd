extends Node
## FX lab + publisher. Open fx_gallery.tscn and play the scene (F6):
## director paused + godmode, so only the FX you trigger is on screen.
## Pick a character, pick an effect, tune the sprite tryout (unsaved preview),
## then Publish writes the values into the target .tres and applies them
## to the live def. Kill buttons preview the published kill FX; Attack fires
## the real weapon at the training dummy, showing published weapon skins live.
## Kill dummy runs the full death FX quietly (no drops/bestiary).
## Targets: Kill signature -> character .tres; Projectile / Muzzle-flash / Arc
## skins -> weapon .tres (resolved from the character's weapon). Trails,
## casings, sparks, beams, rings, decals and passives (e.g. whip lash) are
## procedural and untouched by this lab.
## Scaling: new characters appear in the picker automatically (DB scans
## data/characters/). New effects need one EFFECTS entry + their resolver;
## picker, writer and preview logic are shared.

## Effect registry. One entry per publishable effect: picker label, .tres field
## names in write order, control roles parallel to fields, value kinds parallel
## to fields ("path", "int", "float", "bool"). Controls live in _controls by role, so a
## new effect reuses the same path box + spinners when its roles match.
const EFFECTS := {
	"kill": {
		"label": "Kill signature",
		"target": "character",
		"fields": ["kill_fx_sprite", "kill_fx_frames", "kill_fx_fps", "kill_fx_life", "kill_fx_scale", "kill_fx_loops"],
		"roles": ["path", "frames", "fps", "life", "scale", "loops"],
		"kinds": ["path", "int", "float", "float", "float", "int"],
	},
	"proj": {
		"label": "Projectile skin",
		"target": "weapon",
		"fields": ["proj_fx_sprite", "proj_fx_frames", "proj_fx_fps", "proj_fx_scale", "proj_fx_fwd", "proj_fx_up", "proj_fx_trail"],
		"roles": ["path", "frames", "fps", "scale", "fwd", "up", "trail"],
		"kinds": ["path", "int", "float", "float", "float", "float", "bool"],
	},
	"muzzle": {
		"label": "Muzzle-flash skin",
		"target": "weapon",
		"fields": ["muzzle_fx_sprite", "muzzle_fx_frames", "muzzle_fx_fps", "muzzle_fx_scale", "muzzle_fx_life", "muzzle_fx_fwd", "muzzle_fx_up"],
		"roles": ["path", "frames", "fps", "scale", "life", "fwd", "up"],
		"kinds": ["path", "int", "float", "float", "float", "float", "float"],
	},
	"arc": {
		"label": "Arc slash skin",
		"target": "weapon",
		"fields": ["arc_fx_sprite", "arc_fx_frames", "arc_fx_fps", "arc_fx_scale"],
		"roles": ["path", "frames", "fps", "scale"],
		"kinds": ["path", "int", "float", "float"],
	},
}
const EFFECT_ORDER := ["kill", "proj", "muzzle"]
## Weapon behaviors that fire skinnable projectiles / muzzle flashes / slash
## arcs. Bite, beam, dash, ring and zone weapons still offer Kill only.
const PROJ_BEHAVIORS := ["revolver", "cannon", "skull", "wave"]
const MUZZLE_BEHAVIORS := ["revolver", "cannon"]
const ARC_BEHAVIORS := ["melee_swipe"]

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
var _fwd_spin: SpinBox
var _up_spin: SpinBox
var _trail_check: CheckBox
var _rate_slider: HSlider
var _rate_label: Label
var _dummy = null            # lab target dummy (training_dummy def: rooted, infinite HP)
var _fx_keys: Array = ["kill"]   # effect rows offered for the current weapon


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
	_dummy = null            # E objects belong to the old EnemyManager; never reuse
	var w: World = World.new()
	add_child(w)
	w.start(char_id)
	_world = w
	w.enemies.director_paused = true
	w.dev_set_godmode(true)
	w.set_no_gems(true)         # lab: kills drop nothing, ever
	_populate_effects()         # weapon part rows depend on the live weapon
	if _rate_slider != null:
		# World.start() reset the clock to 1.0; restore the slider baseline.
		w.dev_set_time_rate(_rate_slider.value)
		_rate_label.text = "Time rate x%.2f (slow-mo FX)" % _rate_slider.value
	_refresh_status()


func _populate_characters() -> void:
	_char_ids.clear()
	_char_btn.clear()
	for c in DB.roster():
		_char_ids.append(String(c.id))
	for i in _char_ids.size():
		_char_btn.add_item(String(_char_ids[i]), i)


## Effect rows follow the live weapon: Kill always, plus the part-swap rows
## the weapon actually draws. Keeps the previous selection when still offered.
func _populate_effects() -> void:
	var keep: String = _effect_key()
	_fx_keys.clear()
	_fx_keys.append("kill")
	var beh: String = _weapon_behavior()
	if beh in PROJ_BEHAVIORS:
		_fx_keys.append("proj")
	if beh in MUZZLE_BEHAVIORS:
		_fx_keys.append("muzzle")
	if beh in ARC_BEHAVIORS:
		_fx_keys.append("arc")
	_fx_btn.clear()
	for i in _fx_keys.size():
		var spec: Dictionary = EFFECTS[_fx_keys[i]]
		_fx_btn.add_item(String(spec.get("label", _fx_keys[i])), i)
	_fx_btn.select(maxi(0, _fx_keys.find(keep)))


## Behavior key of the preview world's live weapon ("" when none yet).
func _weapon_behavior() -> String:
	if is_instance_valid(_world) and _world.player != null and _world.player.weapon != null:
		return String(_world.player.weapon.def.behavior)
	return ""


func _effect_key() -> String:
	if _fx_btn == null or _fx_btn.item_count == 0 or _fx_keys.is_empty():
		return "kill"
	return String(_fx_keys[clampi(_fx_btn.selected, 0, _fx_keys.size() - 1)])


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


func _on_attack_live() -> void:
	if not is_instance_valid(_world) or _world.player == null:
		return
	_ensure_dummy()
	_refresh_status()
	if _dummy == null:
		_status.text += " Dummy unavailable (missing def or pool empty)."
		return
	if _world.player.weapon != null:
		_status.text += " Firing %s at dummy." % String(_world.player.weapon.def.id)
	else:
		_status.text += " (no weapon on this character)."


## Lab target dummy: the training_dummy def (glitch-goblin sprite, "dummy"
## behavior: rooted, infinite HP, zero contact damage, never in spawn tables).
## Timers sit expired with no target, so the real weapon usually fires on the
## next frame, showing published weapon skins live against a real target.
func _ensure_dummy() -> void:
	if _dummy != null and is_instance_valid(_dummy) and bool(_dummy.alive) and is_instance_valid(_world):
		_dummy.pos = _world.player.global_position + Vector2(70, 0)
		_dummy.vel = Vector2.ZERO
		return
	var def = DB.enemies.get("training_dummy")
	if def == null or not is_instance_valid(_world):
		return
	_dummy = _world.enemies.spawn(def, _world.player.global_position + Vector2(70, 0), 1.0, 0.0)


func _on_kill_dummy() -> void:
	if not is_instance_valid(_world):
		return
	_ensure_dummy()
	if _dummy == null or not bool(_dummy.alive):
		_refresh_status()
		_status.text += " No live dummy to kill."
		return
	_world.enemies.slay_quiet(_dummy)
	_dummy = null
	_refresh_status()
	_status.text += " Dummy slain (death FX only — no drops, no bestiary)."


func _on_respawn_dummy() -> void:
	if not is_instance_valid(_world):
		return
	_dummy = null
	_ensure_dummy()
	_refresh_status()
	_status.text += " Dummy respawned." if _dummy != null else " Dummy unavailable."


func _tryout_dict() -> Dictionary:
	return {
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


func _on_sprite() -> void:
	var fx: Dictionary = _tryout_dict()
	if String(fx.get("path", "")) == "":
		_status.text = "Type a PNG strip path first."
		return
	_world.fx.kill_sprite(_at(), 1.0, fx)
	_status.text = "Sprite: %s  %dx @%.0ffps  %.2fs  x%.1f  L%d" % [String(fx["path"]), int(fx["frames"]), float(fx["fps"]), float(fx["life"]), float(fx["scale"]), int(fx["loops"])]


func _on_rate(v: float) -> void:
	if not is_instance_valid(_world):
		return
	_world.dev_set_time_rate(v)
	_rate_label.text = "Time rate x%.2f (slow-mo FX)" % v


func _refresh_status() -> void:
	if not is_instance_valid(_world) or _world.player == null:
		_status.text = "No preview world."
		return
	var id: String = String(_world.player.def.id)
	var kfx: Dictionary = AbilityArt.for_kill(_world.player.def)
	var base: String = ""
	if bool(kfx.get("fallback", true)):
		base = "%s .tres: procedural fallback (kill_fx_sprite empty)." % id
	else:
		base = "%s .tres: %s  %dx @%.0ffps  %.2fs  x%.1f  L%d" % [id, String(kfx["path"]), int(kfx["frames"]), float(kfx["fps"]), float(kfx["life"]), float(kfx["scale"]), int(kfx["loops"])]
	if _world.player.weapon != null:
		var wdef = _world.player.weapon.def
		var wid: String = String(wdef.id)
		var psk: Dictionary = AbilityArt.weapon_proj_skin(wdef)
		if bool(psk.get("fallback", true)):
			base += " %s proj: procedural." % wid
		else:
			base += " %s proj: %s %dx @%.0ffps x%.1f." % [wid, String(psk["path"]), int(psk["frames"]), float(psk["fps"]), float(psk["scale"])]
			if float(psk.get("fwd", 0.0)) != 0.0 or float(psk.get("up", 0.0)) != 0.0:
				base += " nudge(%.0f,%.0f)." % [float(psk["fwd"]), float(psk["up"])]
			if not bool(psk.get("trail", true)):
				base += " no trail."
		if String(wdef.behavior) in MUZZLE_BEHAVIORS:
			var msk: Dictionary = AbilityArt.weapon_muzzle_skin(wdef)
			if bool(msk.get("fallback", true)):
				base += " Muzzle: procedural."
			else:
				base += " Muzzle: %s %dx @%.0ffps x%.1f." % [String(msk["path"]), int(msk["frames"]), float(msk["fps"]), float(msk["scale"])]
				if float(msk.get("fwd", 0.0)) != 0.0 or float(msk.get("up", 0.0)) != 0.0:
					base += " nudge(%.0f,%.0f)." % [float(msk["fwd"]), float(msk["up"])]
		if String(wdef.behavior) in ARC_BEHAVIORS:
			var ask: Dictionary = AbilityArt.weapon_arc_skin(wdef)
			if bool(ask.get("fallback", true)):
				base += " Arc: procedural."
			else:
				base += " Arc: %s %dx @%.0ffps x%.1f." % [String(ask["path"]), int(ask["frames"]), float(ask["fps"]), float(ask["scale"])]
	else:
		base += " (no weapon on this character)."
	if _dummy != null and is_instance_valid(_dummy) and bool(_dummy.alive):
		base += " Dummy: alive."
	else:
		base += " Dummy: slain."
	_status.text = base


## Publish: validate the tryout controls, upsert the active effect's fields in
## the target .tres (character .tres for Kill, weapon .tres for part skins;
## text edit, rest of file untouched), apply the same values to the live def,
## and refresh so the buttons preview them with no scene restart.
func _on_publish() -> void:
	var effect: String = _effect_key()
	var spec: Dictionary = EFFECTS.get(effect, {})
	var values: Array = _effect_values(spec)
	var path_idx: int = Array(spec.get("roles", [])).find("path")
	var sprite_path: String = String(values[path_idx]) if path_idx >= 0 and path_idx < values.size() else ""
	if sprite_path == "":
		_status.text = "Type a PNG strip path first."
		return
	sprite_path = sprite_path.replace("\\", "/")
	if not sprite_path.begins_with("res://"):
		_status.text = "Path must live in the project: res://art/fx/name.png (no C:\\ paths — they break exports)."
		return
	if not ResourceLoader.exists(sprite_path):
		_status.text = "PNG not found: %s (drop it in art/fx/ first)." % sprite_path
		return
	var target_id := ""
	var tres_path := ""
	var live_def = null
	if String(spec.get("target", "character")) == "weapon":
		if not is_instance_valid(_world) or _world.player == null or _world.player.weapon == null:
			_status.text = "No live weapon to publish to."
			return
		target_id = String(_world.player.weapon.def.id)
		tres_path = "res://data/weapons/%s.tres" % target_id
		live_def = _world.player.weapon.def
	else:
		if _char_btn.selected < 0 or _char_btn.selected >= _char_ids.size():
			_status.text = "Pick a character first."
			return
		target_id = String(_char_ids[_char_btn.selected])
		tres_path = "res://data/characters/%s.tres" % target_id
		if is_instance_valid(_world) and _world.player != null and String(_world.player.def.id) == target_id:
			live_def = _world.player.def
	if not _write_tres_fields(tres_path, spec, values):
		_status.text = "Publish failed: could not write %s." % tres_path
		return
	if live_def != null:
		_apply_to_live_def(live_def, spec, values)
	_refresh_status()
	_status.text = "Published to %s.tres + live preview. %s" % [target_id, _status.text]


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
		elif ctl is CheckBox:
			out.append(bool(ctl.button_pressed))
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
		"bool":
			return "true" if bool(value) else "false"
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


## Applies published values to a live def object (same object DB holds for
## this session), so the preview buttons play them with no scene restart.
func _apply_to_live_def(live_def, spec: Dictionary, values: Array) -> void:
	var fields: Array = spec.get("fields", [])
	for i in fields.size():
		live_def.set(String(fields[i]), values[i])


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
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -12.0
	root.add_child(panel)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UI.label("FX Lab", 18, UI.GOLD))
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
	v.add_child(UI.label("Live def (kill signature + weapon skins)", 13, UI.PURPLE))
	v.add_child(_row_buttons(["Kill", "Elite kill", "Attack"], [_on_kill, _on_elite, _on_attack_live]))
	var cap := UI.label("Kill writes the character .tres. Projectile/Muzzle/Arc write the weapon .tres. Fwd/Up nudge skins in aim space; trail checkbox hides the hardcoded trail. Casings, sparks, passives stay procedural.", 12, UI.DIM)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cap)
	v.add_child(UI.label("Target dummy", 13, UI.PURPLE))
	v.add_child(_row_buttons(["Kill dummy", "Respawn dummy"], [_on_kill_dummy, _on_respawn_dummy]))
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
	_fwd_spin = _spinner(v, "Fwd px (aim)", 0.0, -64.0, 64.0, 1.0)
	_up_spin = _spinner(v, "Up px (aim)", 0.0, -64.0, 64.0, 1.0)
	_trail_check = CheckBox.new()
	_trail_check.text = "Hardcoded trail"
	_trail_check.button_pressed = true
	v.add_child(_trail_check)
	_controls["path"] = _path_edit
	_controls["frames"] = _frames_spin
	_controls["fps"] = _fps_spin
	_controls["life"] = _life_spin
	_controls["scale"] = _scale_spin
	_controls["loops"] = _loops_spin
	_controls["fwd"] = _fwd_spin
	_controls["up"] = _up_spin
	_controls["trail"] = _trail_check
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
