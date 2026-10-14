class_name GameOverScreen
extends CanvasLayer
## Run summary with retry / character select / menu.

signal action(act: String)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 50
    visible = false


func show_result(world) -> void:
    var pl: Player = world.player
    for c in get_children():
        c.queue_free()
    visible = true
    var dim := ColorRect.new()
    dim.color = Color(0.25, 0.0, 0.02, 0.0)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.add_child(center)
    var panel := UI.panel(UI.PANEL, UI.RED, 4, 26)
    center.add_child(panel)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    panel.add_child(v)
    var title := UI.label("YOU DIED", 76, UI.RED, HORIZONTAL_ALIGNMENT_CENTER)
    v.add_child(title)
    v.add_child(UI.label(pl.def.display_name + "  -  " + pl.def.title, 24, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
    var secs := int(world.run_time)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 40)
    grid.add_theme_constant_override("v_separation", 6)
    v.add_child(grid)
    for row in [["Time survived", "%02d:%02d" % [secs / 60, secs % 60]], ["Level reached", str(pl.level)], ["Enemies slain", str(pl.kills)], ["Fragments gathered", str(world.run_coins)],
            ["Weapon", "%s Lv %d%s" % [pl.weapon.def.display_name, pl.weapon.level, ("  (" + pl.weapon.branch_name() + ")") if pl.weapon.branch >= 0 else ""]],
            ["Passive", "%s Lv %d%s" % [pl.passive.def.display_name, pl.passive.level, ("  (" + pl.passive.branch_name() + ")") if pl.passive.branch >= 0 else ""]]]:
        grid.add_child(UI.label(row[0], 22, UI.DIM))
        grid.add_child(UI.label(row[1], 22, UI.TEXT))
    if world.market_unlocked_now:
        v.add_child(UI.label("THE ARCHIVE IS UNSEALED - find it on the main menu", 20, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    var btns := HBoxContainer.new()
    btns.add_theme_constant_override("separation", 14)
    btns.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(btns)
    var retry := UI.button("Retry", 22, Vector2(200, 54))
    retry.pressed.connect(func() -> void: action.emit("retry"))
    btns.add_child(retry)
    var sel := UI.button("Character Select", 22, Vector2(240, 54))
    sel.pressed.connect(func() -> void: action.emit("select"))
    btns.add_child(sel)
    var menu := UI.button("Main Menu", 22, Vector2(200, 54))
    menu.pressed.connect(func() -> void: action.emit("menu"))
    btns.add_child(menu)
    panel.modulate.a = 0.0
    panel.scale = Vector2(0.85, 0.85)
    await get_tree().process_frame
    panel.pivot_offset = panel.size * 0.5
    var tw := create_tween().set_parallel(true)
    tw.tween_property(dim, "color:a", 0.6, 0.6)
    tw.tween_property(panel, "modulate:a", 1.0, 0.5).set_delay(0.3)
    tw.tween_property(panel, "scale", Vector2.ONE, 0.5).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    await tw.finished
    retry.grab_focus()
