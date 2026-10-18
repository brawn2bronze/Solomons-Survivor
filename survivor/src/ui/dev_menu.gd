class_name DevMenu
extends CanvasLayer
## Pre-run sandbox setup: character + time/director/locks/survival + enemy sprite whitelist.
## Everything here lands in Game.dev_config and applies atomically before frame 1,
## so no hurry-toggling in-game. DevOverlay mirrors the same keys live via F1.

signal start_requested(cfg: Dictionary)
signal back

var _cfg: Dictionary = {}
var _char_pick: OptionButton
var _enemy_checks: Dictionary = {}
var _elite_check: CheckBox
var _count_label: Label
var _start_b: Button
var _time_spin: SpinBox
var _rate_slider: HSlider
var _rate_label: Label
var _mult_slider: HSlider
var _mult_label: Label
var _pause_check: CheckBox
var _nogems_check: CheckBox
var _nolevels_check: CheckBox
var _notreas_check: CheckBox
var _god_check: CheckBox


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
	var sub := UI.label("Start state is fully configured here — F1 overlay mirrors it in-game", 16, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
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
	# TIME: jump-in clock + slow-mo inspection rate.
	v.add_child(UI.label("TIME", 16, UI.PURPLE))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	v.add_child(time_row)
	time_row.add_child(UI.label("Jump in at (s)", 14, UI.DIM))
	_time_spin = SpinBox.new()
	_time_spin.min_value = 0.0
	_time_spin.max_value = 1500.0
	_time_spin.step = 10.0
	_time_spin.value = float(_cfg.get("start_time", 0.0))
	_time_spin.custom_minimum_size = Vector2(140, 32)
	time_row.add_child(_time_spin)
	var a1 := UI.button("Act I", 14, Vector2(80, 32))
	a1.pressed.connect(_set_time_preset.bind(0))
	time_row.add_child(a1)
	var a2 := UI.button("Act II", 14, Vector2(80, 32))
	a2.pressed.connect(_set_time_preset.bind(1))
	time_row.add_child(a2)
	var a3 := UI.button("Act III", 14, Vector2(80, 32))
	a3.pressed.connect(_set_time_preset.bind(2))
	time_row.add_child(a3)
	var boss_b := UI.button("Boss - 10s", 14, Vector2(120, 32))
	boss_b.pressed.connect(_on_preset_boss_time)
	time_row.add_child(boss_b)
	_rate_label = UI.label("Time rate x%.2f (slow-mo FX inspection)" % float(_cfg.get("time_rate", 1.0)), 14, UI.DIM)
	v.add_child(_rate_label)
	_rate_slider = HSlider.new()
	_rate_slider.min_value = 0.1
	_rate_slider.max_value = 1.0
	_rate_slider.step = 0.05
	_rate_slider.value = clampf(float(_cfg.get("time_rate", 1.0)), 0.1, 1.0)
	_rate_slider.custom_minimum_size = Vector2(400, 20)
	_rate_slider.value_changed.connect(_on_rate_changed)
	v.add_child(_rate_slider)
	# DIRECTOR: hard pause (zero spawns) + rate.
	v.add_child(UI.label("DIRECTOR", 16, UI.PURPLE))
	_pause_check = CheckBox.new()
	_pause_check.text = "Pause director (zero spawns; manual spawns still work)"
	_pause_check.button_pressed = bool(_cfg.get("director_paused", false))
	v.add_child(_pause_check)
	_mult_label = UI.label("Spawn rate x%.1f" % float(_cfg.get("spawn_mult", 1.0)), 14, UI.DIM)
	v.add_child(_mult_label)
	_mult_slider = HSlider.new()
	_mult_slider.min_value = 0.0
	_mult_slider.max_value = 10.0
	_mult_slider.step = 0.5
	_mult_slider.value = float(_cfg.get("spawn_mult", 1.0))
	_mult_slider.custom_minimum_size = Vector2(400, 20)
	_mult_slider.value_changed.connect(_on_mult_changed)
	v.add_child(_mult_slider)
	# LOCKS: drop/XP suppression for clean boss tests.
	v.add_child(UI.label("LOCKS", 16, UI.PURPLE))
	_nogems_check = CheckBox.new()
	_nogems_check.text = "No gem drops"
	_nogems_check.button_pressed = bool(_cfg.get("no_gems", false))
	v.add_child(_nogems_check)
	_nolevels_check = CheckBox.new()
	_nolevels_check.text = "No level-ups (freeze XP)"
	_nolevels_check.button_pressed = bool(_cfg.get("no_levels", false))
	v.add_child(_nolevels_check)
	_notreas_check = CheckBox.new()
	_notreas_check.text = "No treasure drops"
	_notreas_check.button_pressed = bool(_cfg.get("no_treasures", false))
	v.add_child(_notreas_check)
	# SURVIVAL
	v.add_child(UI.label("SURVIVAL", 16, UI.PURPLE))
	_god_check = CheckBox.new()
	_god_check.text = "Godmode (infinite HP)"
	_god_check.button_pressed = bool(_cfg.get("godmode", false))
	v.add_child(_god_check)
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
	v.add_child(UI.label("Same toggles live in-game via F1; pre-run values are the run's start state.", 14, UI.DIM))
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


func _on_rate_changed(v: float) -> void:
	_rate_label.text = "Time rate x%.2f (slow-mo FX inspection)" % v


func _on_mult_changed(v: float) -> void:
	_mult_label.text = "Spawn rate x%.1f" % v


func _on_preset_boss_time() -> void:
	var boss = DB.enemies.get("bone_broker")
	if boss != null:
		_time_spin.value = maxf(0.0, float(boss.boss_time) - 10.0)


## Jump the sandbox clock to the start of act `idx` (0 = Act I, 1 = Act II, ...).
func _set_time_preset(idx: int) -> void:
	if idx >= 0 and idx < DB.acts.size():
		_time_spin.value = float(DB.acts[idx].clock_start)


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
	_cfg["start_time"] = maxf(0.0, float(_time_spin.value))
	_cfg["time_rate"] = clampf(float(_rate_slider.value), 0.1, 1.0)
	_cfg["director_paused"] = _pause_check.button_pressed
	_cfg["spawn_mult"] = float(_mult_slider.value)
	_cfg["no_gems"] = _nogems_check.button_pressed
	_cfg["no_levels"] = _nolevels_check.button_pressed
	_cfg["no_treasures"] = _notreas_check.button_pressed
	_cfg["godmode"] = _god_check.button_pressed
	Game.dev_config = _cfg.duplicate(true)
	Game.dev_active = true
	Game.selected_character = String(_cfg["character"])
	start_requested.emit(Game.dev_config)
