class_name MainMenu
extends CanvasLayer
## Title screen: drifting embers, a parade of the playable roster walking along the bottom, Play / Options / Quit.

signal play
signal dev
signal market
signal seal
signal quit

var _walkers: Array = []
var _embers: Array = []
var _t := 0.0
var _canvas: Embers
var _menu_box: VBoxContainer
var _opts: OptionsPanel
var _bm_hint: Label
var _vsz := Vector2(1280, 720)


class Embers extends Node2D:
    var owner_menu

    func _draw() -> void:
        if owner_menu != null:
            owner_menu.paint(self)


func _ready() -> void:
    layer = 5
    var bg := ColorRect.new()
    bg.color = Color(0.05, 0.02, 0.09)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    _canvas = Embers.new()
    _canvas.owner_menu = self
    add_child(_canvas)
    _vsz = get_viewport().get_visible_rect().size
    for i in 70:
        _embers.append({"p": Vector2(randf() * _vsz.x, randf() * _vsz.y), "s": randf_range(8.0, 30.0), "r": randf_range(1.0, 3.0), "ph": randf() * TAU})
    var roster := DB.playable_roster()
    for i in roster.size():
        var c: CharacterDef = roster[i]
        _walkers.append({"tex": DB.texture(c.sprite), "x": -100.0 - i * 150.0, "sp": randf_range(60.0, 90.0), "ph": randf() * 10.0})
    var title := UI.label("SOLOMON'S", 96, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    title.set_anchors_preset(Control.PRESET_TOP_WIDE)
    title.offset_top = 70.0
    title.offset_bottom = 180.0
    title.add_theme_constant_override("outline_size", 16)
    add_child(title)
    var sub := UI.label("S U R V I V O R", 54, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
    sub.offset_top = 170.0
    sub.offset_bottom = 240.0
    sub.add_theme_constant_override("outline_size", 10)
    add_child(sub)
    # CenterContainer keeps buttons/options centered at any window size (fullscreen expand).
    # Only one of _menu_box / _opts is visible at a time, so they share the center slot.
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.offset_top = 240.0
    center.offset_bottom = -100.0
    add_child(center)
    _menu_box = VBoxContainer.new()
    _menu_box.add_theme_constant_override("separation", 12)
    center.add_child(_menu_box)
    var pb := UI.button("Play", 30, Vector2(280, 62))
    pb.pressed.connect(func() -> void: play.emit())
    _menu_box.add_child(pb)
    var mb := UI.button("Forbidden Archive", 24, Vector2(280, 56))
    mb.pressed.connect(_on_market_pressed)
    if not Meta.market_unlocked:
        mb.text = "Forbidden Archive  [SEALED]"
        mb.modulate = Color(0.62, 0.62, 0.7)
    _menu_box.add_child(mb)
    _bm_hint = UI.label("", 15, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
    _bm_hint.visible = false
    _menu_box.add_child(_bm_hint)
    var sb := UI.button("Solomon's Seal", 24, Vector2(280, 56))
    sb.pressed.connect(func() -> void: seal.emit())
    _menu_box.add_child(sb)
    if Game.DEV_MODE_ENABLED:
        var db := UI.button("Dev Mode", 22, Vector2(280, 54))
        db.pressed.connect(func() -> void: dev.emit())
        _menu_box.add_child(db)
    var ob := UI.button("Options", 26, Vector2(280, 56))
    ob.pressed.connect(_toggle_opts)
    _menu_box.add_child(ob)
    var qb := UI.button("Quit", 26, Vector2(280, 56))
    qb.pressed.connect(func() -> void: quit.emit())
    _menu_box.add_child(qb)
    _opts = OptionsPanel.new()
    _opts.visible = false
    center.add_child(_opts)
    var back := UI.button("Back", 22, Vector2(200, 46))
    back.pressed.connect(_toggle_opts)
    _opts.add_child(back)
    pb.grab_focus()


func _toggle_opts() -> void:
    _opts.visible = not _opts.visible
    _menu_box.visible = not _opts.visible
    if not _opts.visible:
        (_menu_box.get_child(0) as Button).grab_focus()


func _process(delta: float) -> void:
    _t += delta
    _vsz = get_viewport().get_visible_rect().size
    for e in _embers:
        e["p"] = Vector2(e["p"].x + sin(_t * 0.7 + e["ph"]) * 8.0 * delta, e["p"].y - e["s"] * delta)
        if e["p"].y < -10.0:
            e["p"] = Vector2(randf() * _vsz.x, _vsz.y + 10.0)
    for w in _walkers:
        w["x"] += w["sp"] * delta
        if w["x"] > _vsz.x + 140.0:
            w["x"] = -120.0
    _canvas.queue_redraw()


func paint(c: Node2D) -> void:
    var w := _vsz.x
    var gy := _vsz.y - 70.0
    for e in _embers:
        var a: float = 0.35 + 0.35 * sin(_t * 2.0 + float(e["ph"]))
        c.draw_circle(e["p"], e["r"] * 2.2, Color(0.55, 0.25, 1.0, a * 0.15))
        c.draw_circle(e["p"], e["r"], Color(0.95, 0.25, 0.35, a))
    c.draw_rect(Rect2(-4, gy, w + 8, 74), Color(0.07, 0.04, 0.13))
    c.draw_rect(Rect2(-4, gy, w + 8, 3), UI.BRONZE)
    for wk in _walkers:
        var fr: int = 2 + int((_t + float(wk["ph"])) * 9.0) % 4
        var tex: Texture2D = wk["tex"]
        if tex != null:
            c.draw_texture_rect_region(tex, Rect2(Vector2(wk["x"], gy - 90.0), Vector2(128, 128)), Rect2(fr * 64, 0, 64, 64))


## Opens the Forbidden Archive, or explains how to unseal it while it is still sealed.
func _on_market_pressed() -> void:
    if Meta.market_unlocked:
        market.emit()
        return
    Audio.sfx("menu_close")
    _bm_hint.text = Meta.unlock_hint()
    _bm_hint.visible = true
