class_name CharacterSelect
extends CanvasLayer
## Roster screen: playable tiles + locked-teaser silhouette tiles on the left, full kit
## breakdown for the highlighted playable on the right (stats, weapon + both
## branches, passive + both branches, playstyles). Locked tiles show "???" + hint
## and cannot be confirmed. Arrows/mouse to browse, Enter/click to pick.

signal confirmed(id: String)
signal back

const COLS := 5

var roster: Array = []
var tiles: Array = []
var sel := 0
var big_sprite: TextureRect
var big_atlas: AtlasTexture
var name_l: Label
var title_l: Label
var blurb_l: Label
var stat_bars: Dictionary = {}
var stat_vals: Dictionary = {}
var weapon_l: Label
var passive_l: Label
var styles_l: Label
var weapon_icon: TextureRect
var passive_icon: TextureRect
var showcase_tex: TextureRect
var showcase_atlas: AtlasTexture
var showcase_label: Label
var _details_scroll: ScrollContainer
var _t := 0.0
var _maxes := {}
var _showcase: Array = []
var _showcase_i := 0
var _showcase_t := 0.0


func _ready() -> void:
    layer = 5
    roster = DB.visible_roster()
    for k in ["max_hp", "move_speed", "damage", "defense", "regen"]:
        var m := 0.001
        for c in DB.playable_roster():
            m = maxf(m, float(c.base_stats.get(k, 0.0)))
        _maxes[k] = m
    var bg := ColorRect.new()
    bg.color = Color(0.045, 0.04, 0.07)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var head := UI.label("CHOOSE YOUR SURVIVOR", 44, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    head.set_anchors_preset(Control.PRESET_TOP_WIDE)
    head.offset_top = 18.0
    head.offset_bottom = 72.0
    bg.add_child(head)
    # Centered content row (tiles + details) so wider fullscreen viewports stay balanced.
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.offset_top = 80.0
    center.offset_bottom = -40.0
    bg.add_child(center)
    var content := HBoxContainer.new()
    content.add_theme_constant_override("separation", 28)
    content.alignment = BoxContainer.ALIGNMENT_CENTER
    center.add_child(content)
    var grid := GridContainer.new()
    grid.columns = COLS
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 10)
    content.add_child(grid)
    for i in roster.size():
        var tile := _make_tile(roster[i], i)
        grid.add_child(tile)
        tiles.append(tile)
    # Footer: hint + Back button (Forbidden Archive pattern), outside the scroll
    # so Back is always reachable. The button is natively tappable for touch.
    var foot := HBoxContainer.new()
    foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    foot.offset_left = 34.0
    foot.offset_right = -34.0
    foot.offset_top = -56.0
    foot.offset_bottom = -8.0
    foot.add_theme_constant_override("separation", 14)
    bg.add_child(foot)
    var hint := UI.label("Arrows / mouse: browse     Enter / click: choose     Esc: back", 18, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT)
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    hint.clip_text = true
    foot.add_child(hint)
    var back_btn := UI.button("Back", 22, Vector2(200, 46))
    back_btn.pressed.connect(_on_back)
    foot.add_child(back_btn)
    _build_details(content)
    _select(0, false)


func _make_tile(c: CharacterDef, i: int) -> Button:
    var b := Button.new()
    var locked: bool = int(c.get("roster_status")) == CharacterDef.RosterStatus.LOCKED_TEASER
    b.custom_minimum_size = Vector2(124, 168)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_stylebox_override("normal", UI.box(UI.PANEL, Color(0.26, 0.22, 0.34), 2, 0))
    b.add_theme_stylebox_override("hover", UI.box(UI.PANEL_LIGHT, UI.DIM, 3, 0) if locked else UI.box(UI.PANEL_LIGHT, c.color.lightened(0.2), 3, 0))
    b.add_theme_stylebox_override("pressed", UI.box(UI.PANEL_LIGHT, Color.WHITE, 3, 0))
    var v := VBoxContainer.new()
    v.set_anchors_preset(Control.PRESET_FULL_RECT)
    v.mouse_filter = Control.MOUSE_FILTER_IGNORE
    v.add_theme_constant_override("separation", 0)
    b.add_child(v)
    var tr := TextureRect.new()
    tr.custom_minimum_size = Vector2(124, 128)
    tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var at := AtlasTexture.new()
    at.atlas = DB.texture(c.sprite)
    at.region = Rect2(0, 0, 64, 64)
    tr.texture = at
    tr.set_meta("atlas", at)
    if locked:
        tr.modulate = Color(0, 0, 0, 1)
    v.add_child(tr)
    var nl := UI.label("???", 15, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER) if locked else UI.label(c.display_name, 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    nl.custom_minimum_size = Vector2(124, 30)
    nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    v.add_child(nl)
    b.set_meta("atlas", at)
    b.set_meta("color", c.color)
    b.set_meta("locked", locked)
    b.mouse_entered.connect(func() -> void: _select(i, true))
    b.pressed.connect(func() -> void: _tap(i))
    return b


func _build_details(parent: Control) -> void:
    var panel := UI.panel(UI.PANEL, UI.GOLD, 3, 14)
    panel.custom_minimum_size = Vector2(536, 0)
    parent.add_child(panel)
    # Scrollable card body: long kit text (weapon + passive + playstyles) can exceed
    # the viewport even at 1280x720, so the gold frame stays put while content scrolls.
    # Touch-drag scrolls natively; mouse wheel works; footer hint stays visible below.
    _details_scroll = ScrollContainer.new()
    _details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(_details_scroll)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _details_scroll.add_child(v)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 14)
    v.add_child(top)
    var sp := PanelContainer.new()
    sp.add_theme_stylebox_override("panel", UI.box(UI.INK, Color(0.36, 0.3, 0.46), 2, 0))
    top.add_child(sp)
    big_sprite = TextureRect.new()
    big_sprite.custom_minimum_size = Vector2(128, 128)
    big_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    big_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    big_atlas = AtlasTexture.new()
    big_atlas.region = Rect2(0, 0, 64, 64)
    big_sprite.texture = big_atlas
    sp.add_child(big_sprite)
    var nv := VBoxContainer.new()
    nv.add_theme_constant_override("separation", 2)
    nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(nv)
    name_l = UI.label("", 34, UI.GOLD)
    nv.add_child(name_l)
    title_l = UI.label("", 18, UI.DIM)
    nv.add_child(title_l)
    blurb_l = UI.wrap_label("", 15, UI.TEXT, 350)
    nv.add_child(blurb_l)
    var sg := GridContainer.new()
    sg.columns = 2
    sg.add_theme_constant_override("h_separation", 20)
    sg.add_theme_constant_override("v_separation", 3)
    v.add_child(sg)
    for k in ["max_hp", "move_speed", "damage", "defense", "regen"]:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 8)
        var l := UI.label(UI.STAT_LABELS[k], 14, UI.DIM)
        l.custom_minimum_size = Vector2(62, 0)
        row.add_child(l)
        var pb := UI.bar(UI.GREEN if k != "damage" else UI.RED)
        pb.custom_minimum_size = Vector2(120, 12)
        pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(pb)
        var vl := UI.label("", 14, UI.TEXT)
        row.add_child(vl)
        sg.add_child(row)
        stat_bars[k] = pb
        stat_vals[k] = vl
    v.add_child(_hdr("WEAPON"))
    var wrow := HBoxContainer.new()
    wrow.add_theme_constant_override("separation", 10)
    v.add_child(wrow)
    weapon_icon = TextureRect.new()
    weapon_icon.custom_minimum_size = Vector2(48, 48)
    weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    wrow.add_child(weapon_icon)
    weapon_l = UI.wrap_label("", 14, UI.TEXT, 440)
    weapon_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    wrow.add_child(weapon_l)
    v.add_child(_hdr("PASSIVE"))
    var prow := HBoxContainer.new()
    prow.add_theme_constant_override("separation", 10)
    v.add_child(prow)
    passive_icon = TextureRect.new()
    passive_icon.custom_minimum_size = Vector2(48, 48)
    passive_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    passive_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    prow.add_child(passive_icon)
    passive_l = UI.wrap_label("", 14, UI.TEXT, 440)
    passive_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    prow.add_child(passive_l)
    v.add_child(_hdr("ABILITY SHOWCASE"))
    var srow := HBoxContainer.new()
    srow.add_theme_constant_override("separation", 10)
    v.add_child(srow)
    showcase_tex = TextureRect.new()
    showcase_tex.custom_minimum_size = Vector2(96, 96)
    showcase_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    showcase_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    srow.add_child(showcase_tex)
    showcase_atlas = AtlasTexture.new()
    showcase_tex.texture = showcase_atlas
    showcase_label = UI.wrap_label("", 14, UI.DIM, 400)
    showcase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    srow.add_child(showcase_label)
    v.add_child(_hdr("PLAYSTYLES"))
    styles_l = UI.wrap_label("", 14, UI.TEXT, 500)
    v.add_child(styles_l)
    _fit_details_height()
    get_viewport().size_changed.connect(_fit_details_height)


## Cap the card body to the live viewport (header 80px + footer 40px + panel
## padding reserved) so the card can never run off-screen; same pattern as
## dev_overlay `_fit_scroll_height`. CenterContainer only centers minimum
## sizes, so the scroll area needs an explicit pixel height.
func _fit_details_height() -> void:
    if _details_scroll == null:
        return
    var h: float = maxf(300.0, get_viewport().get_visible_rect().size.y - 160.0)
    _details_scroll.custom_minimum_size = Vector2(0, h)


func _hdr(t: String) -> Label:
    return UI.label(t, 16, UI.PURPLE)


func _select(i: int, sound: bool) -> void:
    if i == sel and sound:
        return
    sel = i
    if sound:
        Audio.sfx("button_click", -10.0, 1.3)
    var c: CharacterDef = roster[i]
    if int(c.get("roster_status")) == CharacterDef.RosterStatus.LOCKED_TEASER:
        big_atlas.atlas = DB.texture(c.sprite)
        big_sprite.modulate = Color(0, 0, 0, 1)
        name_l.text = "???"
        name_l.add_theme_color_override("font_color", UI.DIM)
        title_l.text = "Locked"
        blurb_l.text = String(c.get("unlock_hint")) if String(c.get("unlock_hint")) != "" else "Locked - unlocks in the full release."
        for k in stat_bars.keys():
            (stat_bars[k] as ProgressBar).value = 0.04
            (stat_vals[k] as Label).text = "???"
        weapon_l.text = "??? - locked"
        passive_l.text = "??? - locked"
        weapon_icon.texture = null
        passive_icon.texture = null
        _showcase.clear()
        showcase_atlas.atlas = null
        showcase_label.text = "Locked"
        showcase_tex.modulate = Color(0, 0, 0, 1)
        styles_l.text = blurb_l.text
        for j in tiles.size():
            var lb: Button = tiles[j]
            var lcol: Color = lb.get_meta("color")
            if j == i:
                lb.add_theme_stylebox_override("normal", UI.box(UI.PANEL_LIGHT, UI.DIM, 4, 0))
            else:
                lb.add_theme_stylebox_override("normal", UI.box(UI.PANEL, lcol.darkened(0.55), 2, 0))
        return
    big_atlas.atlas = DB.texture(c.sprite)
    big_sprite.modulate = Color(1, 1, 1, 1)
    showcase_tex.modulate = Color(1, 1, 1, 1)
    name_l.text = c.display_name
    name_l.add_theme_color_override("font_color", c.color.lightened(0.25))
    title_l.text = c.title
    blurb_l.text = c.blurb
    for k in stat_bars.keys():
        var v: float = float(c.base_stats.get(k, 0.0))
        (stat_bars[k] as ProgressBar).value = clampf(v / float(_maxes[k]), 0.04, 1.0)
        (stat_vals[k] as Label).text = ("%.1f" % v) if v < 10.0 else str(int(v))
    weapon_l.text = _ability_text(DB.weapons[c.weapon_id])
    passive_l.text = _ability_text(DB.passives[c.passive_id])
    _set_ability_icon(weapon_icon, DB.weapons[c.weapon_id], -1)
    _set_ability_icon(passive_icon, DB.passives[c.passive_id], -1)
    _build_showcase(c)
    var st := ""
    for s in c.playstyles:
        st += "- " + String(s) + "\n"
    if c.flags.get("flying", false):
        st += "* Flies: ground melee cannot hit you; aerial hits ground you for 5s\n"
    if c.flags.has("low_hp_scaling"):
        st += "* Gets stronger the lower your health"
    styles_l.text = st.strip_edges()
    for j in tiles.size():
        var b: Button = tiles[j]
        var col: Color = b.get_meta("color")
        if j == i:
            b.add_theme_stylebox_override("normal", UI.box(UI.PANEL_LIGHT, UI.GOLD, 4, 0))
        else:
            b.add_theme_stylebox_override("normal", UI.box(UI.PANEL, col.darkened(0.55), 2, 0))


func _set_ability_icon(tr: TextureRect, def, branch: int) -> void:
    if def == null:
        tr.texture = null
        return
    var art: Dictionary = AbilityArt.icon_for_ability(def, branch)
    var tex: Texture2D = DB.texture(String(art.get("path", "")))
    if tex == null:
        tr.texture = null
        return
    var at := AtlasTexture.new()
    at.atlas = tex
    at.region = AbilityArt.frame_region(tex, maxi(1, int(art.get("frames", 1))), 0)
    tr.texture = at


## 5-slot ability showcase: base (pre-branch) + wA/wB/pA/pB branch strips.
## Missing slots fall back to the weapon/passive card icons so the row always renders.
func _build_showcase(c: CharacterDef) -> void:
    _showcase.clear()
    _showcase_i = 0
    _showcase_t = 0.0
    var anims: Dictionary = c.ability_anims
    var order: Array = ["base", "wA", "wB", "pA", "pB"]
    var labels := {"base": "Base kit (pre-branch)", "wA": "Weapon A", "wB": "Weapon B", "pA": "Passive A", "pB": "Passive B"}
    for slot in order:
        var s := String(slot)
        if anims.has(s):
            var a: Dictionary = anims[s]
            _showcase.append({"label": String(labels[s]), "path": String(a.get("sprite", "")), "frames": maxi(1, int(a.get("frames", 1))), "fps": float(a.get("fps", 8.0))})
    if _showcase.is_empty():
        var w = DB.weapons.get(c.weapon_id)
        var p = DB.passives.get(c.passive_id)
        if w != null:
            var wa: Dictionary = AbilityArt.icon_for_ability(w, -1)
            _showcase.append({"label": "Weapon (base art)", "path": String(wa.get("path", "")), "frames": int(wa.get("frames", 1)), "fps": float(wa.get("fps", 8.0))})
        if p != null:
            var pa: Dictionary = AbilityArt.icon_for_ability(p, -1)
            _showcase.append({"label": "Passive (base art)", "path": String(pa.get("path", "")), "frames": int(pa.get("frames", 1)), "fps": float(pa.get("fps", 8.0))})
    _show_slot()


func _show_slot() -> void:
    if _showcase.is_empty():
        showcase_label.text = "No ability art yet."
        showcase_atlas.atlas = null
        return
    var cur: Dictionary = _showcase[_showcase_i % _showcase.size()]
    var tex: Texture2D = DB.texture(String(cur.get("path", "")))
    if tex == null:
        showcase_atlas.atlas = null
    else:
        showcase_atlas.atlas = tex
        showcase_atlas.region = AbilityArt.frame_region(tex, maxi(1, int(cur.get("frames", 1))), 0)
    showcase_label.text = "%s (%d/%d)" % [String(cur.get("label", "")), _showcase_i % _showcase.size() + 1, _showcase.size()]


func _ability_text(a: AbilityDef) -> String:
    var s := "%s - %s\n" % [a.display_name, a.description]
    s += "  A  %s: %s\n" % [a.branches[0]["name"], a.branches[0]["desc"]]
    s += "  B  %s: %s" % [a.branches[1]["name"], a.branches[1]["desc"]]
    return s


func _confirm(i: int) -> void:
    var c: CharacterDef = roster[i]
    if int(c.get("roster_status")) != CharacterDef.RosterStatus.PLAYABLE:
        Audio.sfx("menu_close", -10.0, 0.8)
        return
    Audio.sfx("character_select")
    confirmed.emit(c.id)


## Touch has no hover: first tap previews the kit card, second tap on the
## already-selected tile confirms. Mouse path is unchanged (hover always
## selects before click, so click confirms immediately). Keyboard unchanged.
func _tap(i: int) -> void:
    if i == sel:
        _confirm(i)
    else:
        _select(i, true)


func _on_back() -> void:
    Audio.sfx("menu_close")
    back.emit()


func _process(delta: float) -> void:
    _t += delta
    for j in tiles.size():
        var at: AtlasTexture = tiles[j].get_meta("atlas")
        var fr := int(_t * 2.5) % 2 if j != sel else 2 + int(_t * 9.0) % 4
        at.region = Rect2(fr * 64, 0, 64, 64)
    big_atlas.region = Rect2((2 + int(_t * 9.0) % 4) * 64, 0, 64, 64)
    if _showcase.size() > 1:
        _showcase_t += delta
        if _showcase_t >= 1.4:
            _showcase_t = 0.0
            _showcase_i = (_showcase_i + 1) % _showcase.size()
            _show_slot()
    if showcase_atlas.atlas != null and not _showcase.is_empty():
        var cur: Dictionary = _showcase[_showcase_i % _showcase.size()]
        var frames := maxi(1, int(cur.get("frames", 1)))
        if frames > 1:
            var fi := int(_t * float(cur.get("fps", 8.0))) % frames
            showcase_atlas.region = AbilityArt.frame_region(showcase_atlas.atlas, frames, fi)


func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    var n := roster.size()
    var moved := -1
    if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
        moved = (sel + 1) % n
    elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
        moved = (sel - 1 + n) % n
    elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
        moved = (sel + COLS) % n
    elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
        moved = (sel - COLS + n) % n
    if moved >= 0:
        _select(moved, true)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_confirm") or event.is_action_pressed("ui_accept"):
        _confirm(sel)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
        _on_back()
        get_viewport().set_input_as_handled()
