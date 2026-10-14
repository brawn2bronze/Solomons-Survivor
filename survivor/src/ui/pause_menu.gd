class_name PauseMenu
extends CanvasLayer
## Pause screen: resume / restart / options / quit, plus a live build + stats readout so a run can be reviewed.

signal action(act: String)

var world
var main_panel: Control
var options_holder: Control
var build_label: Label
var stats_label: Label
var _open := false


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


func _emit(act: String) -> void:
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
        if options_holder.visible:
            _toggle_options()
        else:
            close()
        get_viewport().set_input_as_handled()
