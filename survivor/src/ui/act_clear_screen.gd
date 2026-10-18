class_name ActClearScreen
extends CanvasLayer
## Act Cleared beat (Phase 2). Shown when the unique act boss dies: the run is
## frozen and the player chooses DESCEND (continue into the next act) or
## WITHDRAW (bank the escrowed Fragments and end the run). When the next act is
## sealed (`forced`, the Act III clear in the demo) there is no Descend - the
## sealed card shows with a single Withdraw button.
## Style mirrors LevelUpScreen: panel pop-in, 0.5s "armed" delay before input.

signal descend
signal withdraw

const WITHDRAW_SUB := "Your loadout is saved - Continue this hero from Character Select at the next act. Unsealed (rented) weapons do not follow you out."
const WITHDRAW_SUB_SEALED := "Your loadout is saved, but the gate ahead is sealed - there is no act to continue into. Unsealed (rented) weapons do not follow you out."
const SEALED_TITLE := "THE FOURTH GATE HOLDS."
const SEALED_SUB := "The Morning Star has not yet found you worthy."

var _dim: ColorRect
var _body: Control
var _armed := false
var _descend_b: Button
var _withdraw_b: Button


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 41
    visible = false
    _dim = ColorRect.new()
    _dim.color = Color(0.02, 0.01, 0.05, 0.0)
    _dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_dim)


func hide_screen() -> void:
    visible = false
    _dim.color.a = 0.0
    _armed = false
    _descend_b = null
    _withdraw_b = null
    if _body != null:
        _body.queue_free()
        _body = null


## cleared: the ActDef just finished. next: the following ActDef (may be null).
## at_risk: escrowed Fragments. forced: the next act is sealed (Withdraw only).
func show_clear(cleared, next, at_risk: int, forced: bool, boss_name: String) -> void:
    if _body != null:
        _body.queue_free()
    _descend_b = null
    _withdraw_b = null
    _armed = false
    visible = true
    _dim.color.a = 0.0
    var act_name: String = cleared.display_name if cleared != null else "ACT"
    _body = CenterContainer.new()
    _body.set_anchors_preset(Control.PRESET_FULL_RECT)
    _dim.add_child(_body)
    var box := UI.panel(UI.PANEL, UI.GOLD, 4, 30)
    box.custom_minimum_size = Vector2(900, 0)
    _body.add_child(box)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 16)
    box.add_child(v)
    v.add_child(UI.label("%s CLEARED" % act_name, 72, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    v.add_child(UI.label("%s  -  slain" % boss_name, 24, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
    if forced:
        v.add_child(UI.label(SEALED_TITLE, 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
        v.add_child(UI.label(SEALED_SUB, 22, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER))
    var chosen := HBoxContainer.new()
    chosen.add_theme_constant_override("separation", 46)
    chosen.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(chosen)
    if not forced:
        var dcol := VBoxContainer.new()
        dcol.add_theme_constant_override("separation", 8)
        chosen.add_child(dcol)
        _descend_b = UI.button("DESCEND", 30, Vector2(380, 66))
        _descend_b.mouse_entered.connect(_descend_b.grab_focus)
        _descend_b.pressed.connect(_press_descend)
        dcol.add_child(_descend_b)
        var dsub := UI.wrap_label("Descend to %s: %s" % [next.display_name, next.title], 18, UI.TEXT, 380)
        dsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        dsub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        dcol.add_child(dsub)
        var risk := UI.wrap_label("Fragments at risk: %d. Fall in battle and they are lost." % at_risk, 17, UI.CRIMSON, 380)
        risk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        risk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
        dcol.add_child(risk)
    var wcol := VBoxContainer.new()
    wcol.add_theme_constant_override("separation", 8)
    chosen.add_child(wcol)
    _withdraw_b = UI.button("WITHDRAW", 30, Vector2(380, 66))
    _withdraw_b.mouse_entered.connect(_withdraw_b.grab_focus)
    _withdraw_b.pressed.connect(_press_withdraw)
    wcol.add_child(_withdraw_b)
    var wsub := UI.wrap_label("Withdraw - bank %d Seal Fragments" % at_risk, 18, UI.GOLD, 380)
    wsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    wsub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    wcol.add_child(wsub)
    var whint := UI.wrap_label(WITHDRAW_SUB_SEALED if forced else WITHDRAW_SUB, 17, UI.DIM, 380)
    whint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    whint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    wcol.add_child(whint)
    box.modulate.a = 0.0
    box.scale = Vector2(0.9, 0.9)
    await get_tree().process_frame
    box.pivot_offset = box.size * 0.5
    var tw := create_tween().set_parallel(true)
    tw.tween_property(_dim, "color:a", 0.72, 0.25)
    tw.tween_property(box, "modulate:a", 1.0, 0.3).set_delay(0.08)
    tw.tween_property(box, "scale", Vector2.ONE, 0.35).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    await get_tree().create_timer(0.5, true, false, true).timeout
    _armed = true
    if _descend_b != null:
        _descend_b.grab_focus()
    elif _withdraw_b != null:
        _withdraw_b.grab_focus()


func _press_descend() -> void:
    if not _armed:
        return
    _armed = false
    Audio.sfx("upgrade_selected")
    descend.emit()


func _press_withdraw() -> void:
    if not _armed:
        return
    _armed = false
    Audio.sfx("upgrade_selected")
    withdraw.emit()


func _unhandled_input(event: InputEvent) -> void:
    if not visible or not _armed:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var k: int = event.physical_keycode
        if k == KEY_1 and _descend_b != null:
            _press_descend()
            get_viewport().set_input_as_handled()
        elif k == KEY_2 and _withdraw_b != null:
            _press_withdraw()
            get_viewport().set_input_as_handled()
