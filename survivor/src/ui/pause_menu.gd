class_name PauseMenu
extends CanvasLayer
## Pause screen: resume / restart / options / quit, plus a live build + stats readout so a run can be reviewed.

signal action(act: String)

var world
var main_panel: Control
var options_holder: Control
var confirm_holder: Control
var confirm_label: Label
var confirm_yes_btn: Button
var build_label: Label
var stats_label: Label
var _open := false
var _pending_act := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	visible = false


func setup(world_ref) -> void:
	world = world_ref
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := HBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 30)
	dim.add_child(center)

	var left := UI.panel()
	center.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(UI.label("PAUSED", 48, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	main_panel = VBoxContainer.new()
	main_panel.add_theme_constant_override("separation", 10)
	lv.add_child(main_panel)
	var resume := UI.button("Resume")
	resume.pressed.connect(close)
	main_panel.add_child(resume)
	var restart := UI.button("Restart Run")
	restart.pressed.connect(func() -> void: _emit("retry"))
	main_panel.add_child(restart)
	var opts := UI.button("Options")
	opts.pressed.connect(_toggle_options)
	main_panel.add_child(opts)
	var sel := UI.button("Character Select")
	sel.pressed.connect(func() -> void: _emit("select"))
	main_panel.add_child(sel)
	var quit := UI.button("Quit to Menu")
	quit.pressed.connect(func() -> void: _emit("menu"))
	main_panel.add_child(quit)
	options_holder = OptionsPanel.new()
	options_holder.visible = false
	lv.add_child(options_holder)
	confirm_holder = UI.panel()
	confirm_holder.visible = false
	lv.add_child(confirm_holder)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	confirm_holder.add_child(cv)
	cv.add_child(UI.label("ABANDON RUN?", 28, UI.CRIMSON, HORIZONTAL_ALIGNMENT_CENTER))
	confirm_label = UI.wrap_label("", 18, UI.TEXT, 360)
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(confirm_label)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 14)
	cv.add_child(crow)
	confirm_yes_btn = UI.button("Abandon", 20, Vector2(180, 50))
	confirm_yes_btn.pressed.connect(_confirm_yes)
	crow.add_child(confirm_yes_btn)
	var keep := UI.button("Keep Playing", 20, Vector2(180, 50))
	keep.pressed.connect(_cancel_confirm)
	crow.add_child(keep)

	var right := UI.panel(UI.PANEL, Color(0.36, 0.3, 0.46))
	right.custom_minimum_size = Vector2(430, 0)
	center.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(UI.label("CURRENT BUILD", 24, UI.GOLD))
	build_label = UI.wrap_label("", 17, UI.TEXT, 400)
	rv.add_child(build_label)
	rv.add_child(UI.label("STATS", 24, UI.GOLD))
	stats_label = UI.wrap_label("", 17, UI.TEXT, 400)
	rv.add_child(stats_label)


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	options_holder.visible = false
	confirm_holder.visible = false
	_pending_act = ""
	main_panel.visible = true
	get_tree().paused = true
	Audio.sfx("menu_open")
	_refresh()
	(main_panel.get_child(0) as Button).grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	Audio.sfx("menu_close")


## Abandoning (restart / character select / menu) forfeits the escrow, so confirm
## first when the player is carrying unbanked Fragments.
func _emit(act: String) -> void:
	if (act == "retry" or act == "select" or act == "menu") and world != null and world.run_coins > 0 and not Game.dev_active:
		_ask_abandon(act)
		return
	_do_emit(act)


func _ask_abandon(act: String) -> void:
	_pending_act = act
	confirm_label.text = "Unbanked Fragments (%d) will be lost. Bank them at an Act Cleared screen." % world.run_coins
	main_panel.visible = false
	options_holder.visible = false
	confirm_holder.visible = true
	Audio.sfx("menu_open")
	confirm_yes_btn.grab_focus()


func _confirm_yes() -> void:
	var act := _pending_act
	_pending_act = ""
	_do_emit(act)


func _cancel_confirm() -> void:
	_pending_act = ""
	confirm_holder.visible = false
	main_panel.visible = true
	(main_panel.get_child(0) as Button).grab_focus()


func _do_emit(act: String) -> void:
	_open = false
	visible = false
	get_tree().paused = false
	action.emit(act)


func _toggle_options() -> void:
	options_holder.visible = not options_holder.visible
	main_panel.visible = not options_holder.visible
	if options_holder.visible:
		var back := options_holder.get_node_or_null("BackBtn")
		if back == null:
			var b := UI.button("Back", 20, Vector2(200, 46))
			b.name = "BackBtn"
			b.pressed.connect(_toggle_options)
			options_holder.add_child(b)
	else:
		(main_panel.get_child(0) as Button).grab_focus()


func _refresh() -> void:
	var pl: Player = world.player
	var t := ""
	for ab in [pl.weapon, pl.passive]:
		t += "%s  Lv %d" % [ab.def.display_name, ab.level]
		t += ("  (%s)\n" % ab.branch_name()) if ab.branch >= 0 else "\n"
	var ups := ""
	for id in pl.upgrade_levels.keys():
		ups += "%s %d   " % [DB.upgrades[id].display_name, pl.upgrade_levels[id]]
	build_label.text = t + (ups if ups != "" else "No stat upgrades yet")
	var s := ""
	for k in ["max_hp", "move_speed", "damage", "defense", "regen", "cooldown", "area", "pickup_radius"]:
		var v: float = pl.stat(k)
		s += "%s  %s\n" % [UI.STAT_LABELS[k], ("%.2f" % v) if v < 10.0 else str(int(round(v)))]
	s += "Kills %d   Level %d   Time %02d:%02d" % [pl.kills, pl.level, int(world.run_time) / 60, int(world.run_time) % 60]
	stats_label.text = s


func _unhandled_input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("pause"):
		if confirm_holder.visible:
			_cancel_confirm()
		elif options_holder.visible:
			_toggle_options()
		else:
			close()
		get_viewport().set_input_as_handled()
