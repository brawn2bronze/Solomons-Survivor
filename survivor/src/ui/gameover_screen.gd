class_name GameOverScreen
extends CanvasLayer
## Run summary with retry / character select / menu. Two entry points: `show_result`
## for a death, `show_victory` for a Withdraw at an Act Cleared screen.

signal action(act: String)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 50
    visible = false


func show_result(world) -> void:
    _show(world, false, false, 0)


## Withdraw summary. `banked` is the escrow that just entered Meta; `forced` marks
## the sealed Act III clear (the demo's true ending).
func show_victory(world, banked: int, forced: bool) -> void:
    _show(world, true, forced, banked)


func _show(world, victory: bool, forced: bool, banked: int) -> void:
    var pl: Player = world.player
    for c in get_children():
        c.queue_free()
    visible = true
    var accent: Color = UI.GOLD if victory else UI.RED
    var dim := ColorRect.new()
    dim.color = Color(0.10, 0.06, 0.0, 0.0) if victory else Color(0.25, 0.0, 0.02, 0.0)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.add_child(center)
    var panel := UI.panel(UI.PANEL, accent, 4, 26)
    center.add_child(panel)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    panel.add_child(v)
    var title_text := "THE FOURTH GATE HOLDS" if forced else "THE SEAL HOLDS"
    var title := UI.label(title_text if victory else "YOU DIED", 76, accent, HORIZONTAL_ALIGNMENT_CENTER)
    v.add_child(title)
    v.add_child(UI.label(pl.def.display_name + "  -  " + pl.def.title, 24, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
    if victory and forced:
        v.add_child(UI.label("The Morning Star has not yet found you worthy.", 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
    var secs := int(world.run_time)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 40)
    grid.add_theme_constant_override("v_separation", 6)
    v.add_child(grid)
    var frag_row: Array = ["Fragments gathered", str(world.run_coins), UI.TEXT]
    if victory:
        frag_row = ["Fragments banked", str(banked), UI.GOLD]
    elif world.run_lost > 0:
        frag_row = ["Fragments lost", str(world.run_lost), UI.CRIMSON]
    var rows := [["Time survived", "%02d:%02d" % [secs / 60, secs % 60], UI.TEXT], ["Level reached", str(pl.level), UI.TEXT], ["Enemies slain", str(pl.kills), UI.TEXT], frag_row,
            ["Weapon", "%s Lv %d%s" % [pl.weapon.def.display_name, pl.weapon.level, ("  (" + pl.weapon.branch_name() + ")") if pl.weapon.branch >= 0 else ""], UI.TEXT],
            ["Passive", "%s Lv %d%s" % [pl.passive.def.display_name, pl.passive.level, ("  (" + pl.passive.branch_name() + ")") if pl.passive.branch >= 0 else ""], UI.TEXT]]
    for row in rows:
        grid.add_child(UI.label(row[0], 22, UI.DIM))
        grid.add_child(UI.label(row[1], 22, row[2]))
    if victory:
        var saved_text: String = "Loadout saved - the next gate is not yet open." if forced else "Loadout saved - continue from Character Select."
        var saved := UI.wrap_label(saved_text, 18, UI.GOLD, 560)
        saved.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        saved.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        v.add_child(saved)
    if not victory and world.run_lost > 0:
        var hint := UI.wrap_label("Fall with Fragments in escrow and they are lost - bank them at the next Act Cleared screen.", 18, UI.CRIMSON, 560)
        hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        v.add_child(hint)
    if world.market_unlocked_now:
        v.add_child(UI.label("THE ARCHIVE IS UNSEALED - find it on the main menu", 20, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    var btns := HBoxContainer.new()
    btns.add_theme_constant_override("separation", 14)
    btns.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(btns)
    var retry := UI.button("Retry" if not victory else "New Run", 22, Vector2(200, 54))
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
