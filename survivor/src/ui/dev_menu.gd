class_name DevMenu
extends CanvasLayer
## Pre-run sandbox setup (minimal): character + enemy sprite whitelist + elites-only.
## All other cheats (godmode, spawn rate, time skip, builds, gem/level locks)
## live in the in-game F1 DevOverlay.

signal start_requested(cfg: Dictionary)
signal back

var _cfg: Dictionary = {}
var _char_pick: OptionButton
var _enemy_checks: Dictionary = {}
var _elite_check: CheckBox
var _count_label: Label
var _start_b: Button


func _ready() -> void:
	layer = 5
	_cfg = Game.default_dev_config()
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.04, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var head := UI.label("DEV SANDBOX SETUP", 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 12.0
	head.offset_bottom = 60.0
	bg.add_child(head)
	var sub := UI.label("Pick a fighter + sprite filter — all other cheats live in-game (F1)", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 58.0
	sub.offset_bottom = 82.0
	bg.add_child(sub)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 86.0
	center.offset_bottom = -10.0
	bg.add_child(center)
	var panel := UI.panel(UI.PANEL, UI.GOLD, 3, 16)
	panel.custom_minimum_size = Vector2(760, 540)
	center.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(728, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pv.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	# Character
	v.add_child(UI.label("CHARACTER", 16, UI.PURPLE))
	_char_pick = OptionButton.new()
	_char_pick.custom_minimum_size = Vector2(400, 32)
	var roster := DB.roster()
	for i in roster.size():
		_char_pick.add_item(roster[i].display_name, i)
		_char_pick.set_item_metadata(i, roster[i].id)
	_char_pick.select(maxi(0, _find_meta(_char_pick, Game.selected_character)))
	v.add_child(_char_pick)
	# Enemy whitelist (sprite isolation)
	var enemy_head := HBoxContainer.new()
	enemy_head.add_theme_constant_override("separation", 12)
	v.add_child(enemy_head)
	enemy_head.add_child(UI.label("ENEMY SPRITES", 16, UI.PURPLE))
	_count_label = UI.label("", 14, UI.DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemy_head.add_child(_count_label)
	v.add_child(UI.label("Check = only spawn these. Uncheck all = normal director pool.", 14, UI.DIM))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	v.add_child(presets)
	var all_b := UI.button("All", 15, Vector2(110, 34))
	all_b.pressed.connect(_on_preset_all)
	presets.add_child(all_b)
	var none_b := UI.button("None", 15, Vector2(110, 34))
	none_b.pressed.connect(_on_preset_none)
	presets.add_child(none_b)
	var brute_b := UI.button("Brute only", 15, Vector2(140, 34))
	brute_b.pressed.connect(_on_preset_brute)
	presets.add_child(brute_b)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var eids: Array = DB.enemies.keys()
	eids.sort()
	for eid in eids:
		var d = DB.enemies[eid]
		var c := CheckBox.new()
		c.text = "%s (%s)%s" % [d.display_name, eid, " [ELITE]" if d.is_elite else ""]
		c.toggled.connect(_on_enemy_toggled.bind(eid))
		grid.add_child(c)
		_enemy_checks[eid] = c
	_elite_check = CheckBox.new()
	_elite_check.text = "Elites only"
	_elite_check.button_pressed = bool(_cfg.get("elite_only", false))
	_elite_check.toggled.connect(_on_elite_toggled)
	v.add_child(_elite_check)
	v.add_child(UI.label("Godmode, director pause, spawn rate, time skip, builds, gem/level locks → F1 overlay in-game.", 14, UI.DIM))
	_update_count()
	# Sticky footer: outside the scroll so START is always reachable.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(foot)
	_start_b = UI.button("START SANDBOX", 24, Vector2(280, 54))
	_start_b.pressed.connect(_on_start)
	foot.add_child(_start_b)
	var back_b := UI.button("Back", 20, Vector2(180, 50))
	back_b.pressed.connect(func() -> void: back.emit())
	foot.add_child(back_b)
	_start_b.grab_focus()


func _find_meta(pick: OptionButton, id: String) -> int:
	for i in pick.item_count:
		if String(pick.get_item_metadata(i)) == id:
			return i
	return 0


func _selected_count() -> int:
	var n := 0
	for eid in _enemy_checks.keys():
		if (_enemy_checks[eid] as CheckBox).button_pressed:
			n += 1
	return n


func _update_count() -> void:
	var n := _selected_count()
	if n == 0:
		_count_label.text = "normal pool"
	else:
		_count_label.text = "%d isolated" % n


func _on_enemy_toggled(_on: bool, _eid: String) -> void:
	_update_count()


func _on_elite_toggled(_on: bool) -> void:
	pass


func _on_preset_all() -> void:
	for eid in _enemy_checks.keys():
		(_enemy_checks[eid] as CheckBox).button_pressed = true
	_update_count()


func _on_preset_none() -> void:
	for eid in _enemy_checks.keys():
		(_enemy_checks[eid] as CheckBox).button_pressed = false
	_update_count()


func _on_preset_brute() -> void:
	for eid in _enemy_checks.keys():
		(_enemy_checks[eid] as CheckBox).button_pressed = (eid == "goblin_brute")
	_elite_check.button_pressed = true
	_update_count()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_confirm") or event.is_action_pressed("ui_accept"):
		_on_start()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		back.emit()
		get_viewport().set_input_as_handled()


func _on_start() -> void:
	var allowed: Array = []
	for eid in _enemy_checks.keys():
		if (_enemy_checks[eid] as CheckBox).button_pressed:
			allowed.append(eid)
	_cfg["character"] = String(_char_pick.get_item_metadata(_char_pick.selected))
	_cfg["allowed_enemies"] = allowed
	_cfg["elite_only"] = _elite_check.button_pressed
	Game.dev_config = _cfg.duplicate(true)
	Game.dev_active = true
	Game.selected_character = String(_cfg["character"])
	start_requested.emit(Game.dev_config)
