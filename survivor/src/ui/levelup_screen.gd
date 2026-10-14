class_name LevelUpScreen
extends CanvasLayer
## Level-up pick screen. Cards pop in staggered with a celebratory title; keys 1-4, arrows + Enter, or click.
## Pausing is handled by the World; this node only presents choices and emits the pick.

signal chosen(choice: Dictionary)
signal dev_reroll
signal dev_skip
signal utility_reroll
signal utility_skip
signal utility_banish(choice_id: String)

var dim: ColorRect
var title: Label
var subtitle: Label
var row: HBoxContainer
var _choices: Array = []
var _cards: Array[Button] = []
var _armed := false
var _dev_row: HBoxContainer
var _util_row: HBoxContainer
var _reroll_b: Button
var _skip_b: Button
var _banish_b: Button
var _u_rerolls := 0
var _u_skips := 0
var _u_banishes := 0
var _banish_mode := false
var _icon_t := 0.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 30
    visible = false
    dim = ColorRect.new()
    dim.color = Color(0.02, 0.01, 0.05, 0.0)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(dim)
    title = UI.label("LEVEL UP!", 72, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    title.set_anchors_preset(Control.PRESET_TOP_WIDE)
    title.offset_top = 56.0
    title.offset_bottom = 146.0
    title.add_theme_constant_override("outline_size", 12)
    dim.add_child(title)
    subtitle = UI.label("", 22, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
    subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
    subtitle.offset_top = 146.0
    subtitle.offset_bottom = 176.0
    dim.add_child(subtitle)
    # Card row lives in a full-rect CenterContainer so it stays centered at any viewport size.
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.offset_top = 190.0
    center.offset_bottom = -20.0
    dim.add_child(center)
    row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 26)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(row)
    # Dev sandbox: reroll / skip the open draft. Hidden in normal runs.
    var dock := CenterContainer.new()
    dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    dock.offset_top = -70.0
    dock.offset_bottom = -16.0
    dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dim.add_child(dock)
    _dev_row = HBoxContainer.new()
    _dev_row.add_theme_constant_override("separation", 12)
    dock.add_child(_dev_row)
    var reroll_b := UI.button("Reroll draft (dev)", 15, Vector2(210, 40))
    reroll_b.pressed.connect(_on_dev_button.bind(true))
    _dev_row.add_child(reroll_b)
    var skip_b := UI.button("Skip (dev)", 15, Vector2(160, 40))
    skip_b.pressed.connect(_on_dev_button.bind(false))
    _dev_row.add_child(skip_b)
    _dev_row.visible = false
    # Fate utility row (§29): run-local reroll / skip / banish stock from the
    # seal tree. Sits above the dev row; hidden when the run has no stock.
    var util_dock := CenterContainer.new()
    util_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    util_dock.offset_top = -124.0
    util_dock.offset_bottom = -78.0
    util_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dim.add_child(util_dock)
    _util_row = HBoxContainer.new()
    _util_row.add_theme_constant_override("separation", 12)
    util_dock.add_child(_util_row)
    _reroll_b = UI.button("Reroll (0)", 15, Vector2(170, 40))
    _reroll_b.pressed.connect(_on_util_reroll_pressed)
    _util_row.add_child(_reroll_b)
    _skip_b = UI.button("Skip (0)", 15, Vector2(150, 40))
    _skip_b.pressed.connect(_on_util_skip_pressed)
    _util_row.add_child(_skip_b)
    _banish_b = UI.button("Banish (0)", 15, Vector2(170, 40))
    _banish_b.toggle_mode = true
    _banish_b.toggled.connect(_on_banish_toggled)
    _util_row.add_child(_banish_b)
    _util_row.visible = false


func show_choices(choices: Array, level: int, title_text: String = "LEVEL UP!", subtitle_text: String = "") -> void:
    _choices = choices
    for c in _cards:
        c.queue_free()
    _cards.clear()
    _armed = false
    visible = true
    _dev_row.visible = Game.dev_active and Game.DEV_MODE_ENABLED
    _banish_mode = false
    if _banish_b != null:
        _banish_b.button_pressed = false
    title.text = title_text
    if subtitle_text != "":
        subtitle.text = subtitle_text
    else:
        subtitle.text = "You reached level %d  -  choose an upgrade" % level
    for i in choices.size():
        var card := _make_card(choices[i], i)
        row.add_child(card)
        _cards.append(card)
    var tw := create_tween().set_parallel(true)
    tw.tween_property(dim, "color:a", 0.78, 0.18)
    title.pivot_offset = title.size * 0.5
    title.scale = Vector2(1.7, 1.7)
    title.modulate.a = 0.0
    tw.tween_property(title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_property(title, "modulate:a", 1.0, 0.15)
    for i in _cards.size():
        var c := _cards[i]
        c.pivot_offset = c.custom_minimum_size * 0.5
        c.scale = Vector2(0.4, 0.4)
        c.modulate.a = 0.0
        tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_delay(0.12 + i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        tw.tween_property(c, "modulate:a", 1.0, 0.15).set_delay(0.12 + i * 0.08)
    await get_tree().create_timer(0.45, true, false, true).timeout
    _armed = true
    _refresh_util()
    if not _cards.is_empty():
        _cards[0].grab_focus()


func hide_screen() -> void:
    visible = false
    dim.color.a = 0.0
    _banish_mode = false
    if _banish_b != null:
        _banish_b.button_pressed = false
    _refresh_util()


## Frame-by-frame use-preview for card icons. Multi-frame strips cycle regions;
## single-frame weapons add motion: shuriken spins, caltrops pulse. Runs only
## while the picker is open. Per-card seed desyncs identical icons.
func _process(delta: float) -> void:
    if not visible or _cards.is_empty():
        return
    _icon_t += delta
    for c in _cards:
        if not is_instance_valid(c):
            continue
        var art: Dictionary = c.get_meta("art")
        var tex: TextureRect = c.get_meta("icon_tex")
        var atlas: AtlasTexture = c.get_meta("icon_atlas")
        if art.is_empty() or tex == null:
            continue
        var frames := maxi(1, int(art.get("frames", 1)))
        var fps := float(art.get("fps", 8.0))
        var preview := String(art.get("preview", "none"))
        var seed := float(c.get_meta("icon_seed"))
        if atlas.atlas != null and frames > 1:
            var fi := int((_icon_t + seed) * fps) % frames
            atlas.region = AbilityArt.frame_region(atlas.atlas, frames, fi)
        if preview == "spin":
            tex.rotation += delta * 4.2
        elif preview == "pulse":
            var s := 1.0 + 0.09 * sin((_icon_t + seed) * 6.0)
            tex.scale = Vector2(s, s)
            tex.pivot_offset = Vector2(42, 42)


func _make_card(ch: Dictionary, idx: int) -> Button:
    var accent: Color = ch["color"]
    var b := Button.new()
    b.custom_minimum_size = Vector2(268, 392)
    b.focus_mode = Control.FOCUS_ALL
    b.add_theme_stylebox_override("normal", UI.box(UI.PANEL, accent.darkened(0.25), 3, 0))
    b.add_theme_stylebox_override("hover", UI.box(UI.PANEL_LIGHT, accent.lightened(0.3), 4, 0))
    b.add_theme_stylebox_override("focus", UI.box(UI.PANEL_LIGHT, accent.lightened(0.3), 4, 0))
    b.add_theme_stylebox_override("pressed", UI.box(UI.PANEL_LIGHT, Color.WHITE, 4, 0))
    var v := VBoxContainer.new()
    v.set_anchors_preset(Control.PRESET_FULL_RECT)
    v.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_theme_constant_override("separation", 8)
    b.add_child(v)
    var band := ColorRect.new()
    band.color = accent.darkened(0.35)
    band.custom_minimum_size = Vector2(0, 30)
    band.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_child(band)
    var tag := UI.label(String(ch["tag"]), 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    tag.set_anchors_preset(Control.PRESET_FULL_RECT)
    tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    band.add_child(tag)
    var holder := CenterContainer.new()
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_child(holder)
    var backdrop := ColorRect.new()
    backdrop.color = accent.darkened(0.55)
    backdrop.custom_minimum_size = Vector2(96, 96)
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(backdrop)
    var art: Dictionary = ch.get("art", {})
    var tex := TextureRect.new()
    tex.custom_minimum_size = Vector2(84, 84)
    tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tex.pivot_offset = Vector2(42, 42)
    backdrop.add_child(tex)
    var mono := UI.label(String(ch.get("mono", "")), 44, accent.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER)
    mono.set_anchors_preset(Control.PRESET_FULL_RECT)
    mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
    backdrop.add_child(mono)
    var base_tex: Texture2D = DB.texture(String(art.get("path", "")))
    var atlas := AtlasTexture.new()
    if base_tex != null:
        atlas.atlas = base_tex
        atlas.region = AbilityArt.frame_region(base_tex, int(art.get("frames", 1)), 0)
        tex.texture = atlas
        mono.visible = false
    else:
        mono.visible = true
    b.set_meta("art", art)
    b.set_meta("icon_tex", tex)
    b.set_meta("icon_atlas", atlas)
    b.set_meta("icon_seed", float(idx) * 0.37)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(margin)
    var inner := VBoxContainer.new()
    inner.add_theme_constant_override("separation", 6)
    inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    margin.add_child(inner)
    inner.add_child(UI.wrap_label(String(ch["title"]), 24, UI.GOLD, 236))
    inner.add_child(UI.label(String(ch["sub"]), 16, accent.lightened(0.2)))
    inner.add_child(UI.wrap_label(String(ch["desc"]), 16, UI.TEXT, 236))
    var hint := UI.label("[%d]" % (idx + 1), 18, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
    v.add_child(hint)
    b.pressed.connect(_pick.bind(idx))
    b.mouse_entered.connect(func() -> void: b.grab_focus())
    b.focus_entered.connect(func() -> void: Audio.sfx("button_click", -14.0, 1.4))
    return b


func _pick(idx: int) -> void:
    if not _armed or idx >= _choices.size():
        return
    _armed = false
    if _banish_mode:
        # Toggle-then-pick (§29): the click banishes instead of choosing.
        _banish_mode = false
        if _banish_b != null:
            _banish_b.button_pressed = false
        var key := _choice_key(_choices[idx])
        Audio.sfx("upgrade_selected")
        utility_banish.emit(key)
        return
    var ch: Dictionary = _choices[idx]
    Audio.sfx("upgrade_selected")
    var c := _cards[idx]
    var tw := create_tween()
    tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.08)
    tw.tween_property(c, "modulate:a", 0.0, 0.1)
    await tw.finished
    chosen.emit(ch)


## Dev sandbox buttons: reroll re-drafts, skip discards. Gated by _armed like picks.
func _on_dev_button(reroll: bool) -> void:
    if not visible or not _armed:
        return
    _armed = false
    if reroll:
        dev_reroll.emit()
    else:
        dev_skip.emit()


## Fate utility (§30): same keys the World banish filter uses — "type:id", plus
## ":b<branch>" for branch-pair cards so one branch never seals the other.
func _choice_key(ch: Dictionary) -> String:
    var key := "%s:%s" % [String(ch.get("type", "")), String(ch.get("id", ""))]
    if int(ch.get("branch", -1)) >= 0:
        key += ":b%d" % int(ch.get("branch", 0))
    if ch.has("evo"):
        key += ":e%dt%d" % [int(ch.get("evo", 0)), int(ch.get("tier", 1))]
    return key


## Stock push from World after every draft open / utility spend.
func set_utility(rerolls: int, skips: int, banishes: int) -> void:
    _u_rerolls = maxi(0, rerolls)
    _u_skips = maxi(0, skips)
    _u_banishes = maxi(0, banishes)
    _refresh_util()


func _refresh_util() -> void:
    if _util_row == null:
        return
    var any := (_u_rerolls + _u_skips + _u_banishes) > 0
    _util_row.visible = visible and any
    if _reroll_b != null:
        _reroll_b.text = "Reroll (%d)" % _u_rerolls
        _reroll_b.disabled = not _armed or _u_rerolls <= 0
    if _skip_b != null:
        _skip_b.text = "Skip (%d)" % _u_skips
        _skip_b.disabled = not _armed or _u_skips <= 0
    if _banish_b != null:
        _banish_b.text = "Banish (%d)" % _u_banishes
        _banish_b.disabled = not _armed or _u_banishes <= 0
        if _banish_b.disabled and _banish_mode:
            _banish_mode = false
            _banish_b.button_pressed = false


func _on_util_reroll_pressed() -> void:
    if not visible or not _armed or _u_rerolls <= 0:
        return
    utility_reroll.emit()


func _on_util_skip_pressed() -> void:
    if not visible or not _armed or _u_skips <= 0:
        return
    utility_skip.emit()


func _on_banish_toggled(on: bool) -> void:
    if _u_banishes <= 0 or not _armed:
        _banish_mode = false
        if _banish_b != null and _banish_b.button_pressed:
            _banish_b.button_pressed = false
        return
    _banish_mode = on
    if on:
        Audio.sfx("button_click", -14.0, 1.1)


func _unhandled_input(event: InputEvent) -> void:
    if not visible or not _armed:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var k: int = event.physical_keycode
        if k >= KEY_1 and k <= KEY_4:
            _pick(k - KEY_1)
            get_viewport().set_input_as_handled()
