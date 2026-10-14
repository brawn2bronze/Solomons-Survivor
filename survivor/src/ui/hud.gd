class_name Hud
extends CanvasLayer
## In-run HUD, laid out so the three things that matter (HP, XP/level, time) read in half a second:
## HP top-left with portrait, XP bar across the top, timer top-centre, build slots bottom-left.

class Pips extends Control:
    var level := 1
    var max_level := 8
    var branch_at := 0

    func _draw() -> void:
        var step := 13.0 if max_level <= 8 else 104.0 / float(maxi(max_level, 1))
        for i in max_level:
            var r := Rect2(Vector2(i * step, 0), Vector2(step - 3.0, 10))
            var on := i < level
            var col := UI.GOLD if on else Color(0.2, 0.18, 0.26)
            if branch_at > 0 and i + 1 >= branch_at and on:
                col = UI.PURPLE
            draw_rect(r, UI.INK)
            draw_rect(r.grow(-1.5), col)


var world
var _root: Control
var xp_bar: ProgressBar
var hp_bar: ProgressBar
var armor_bar: ProgressBar
var hp_label: Label
var lv_label: Label
var time_label: Label
var kills_label: Label
var coin_box: HBoxContainer
var coin_label: Label
var debug_label: Label
var announce_label: Label
var elite_box: Control
var elite_bar: ProgressBar
var elite_name: Label
var portrait: TextureRect
var slots: Array = []
var _announce_tween: Tween
var _hp_shown := 1.0
var _last_hp := -1.0
var _debug := false


func setup(world_ref) -> void:
    world = world_ref
    layer = 10
    var root := Control.new()
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)
    _root = root
    root.resized.connect(_relayout)
    get_viewport().size_changed.connect(_relayout)

    xp_bar = UI.bar(Color(0.35, 0.62, 1.0), Color(0.06, 0.06, 0.12, 0.9), UI.INK)
    xp_bar.position = Vector2(0, 0)
    xp_bar.size = Vector2(1280, 16)
    root.add_child(xp_bar)
    lv_label = UI.label("LV 1", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    lv_label.position = Vector2(0, -2)
    lv_label.size = Vector2(1280, 20)
    root.add_child(lv_label)

    var pf := UI.panel(UI.INK, UI.GOLD, 2, 0)
    pf.position = Vector2(12, 26)
    pf.custom_minimum_size = Vector2(72, 72)
    root.add_child(pf)
    portrait = TextureRect.new()
    portrait.custom_minimum_size = Vector2(72, 72)
    portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    var tex := DB.texture(world.player.def.sprite)
    var at := AtlasTexture.new()
    at.atlas = tex
    at.region = Rect2(0, 0, 64, 64)
    portrait.texture = at
    pf.add_child(portrait)

    hp_bar = UI.bar(UI.RED, Color(0.16, 0.05, 0.07), UI.INK)
    hp_bar.position = Vector2(94, 34)
    hp_bar.size = Vector2(300, 26)
    root.add_child(hp_bar)
    hp_label = UI.label("100 / 100", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    hp_label.position = Vector2(94, 34)
    hp_label.size = Vector2(300, 26)
    hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    root.add_child(hp_label)
    armor_bar = UI.bar(Color(1.0, 0.82, 0.4), Color(0.1, 0.08, 0.05), UI.INK)
    armor_bar.position = Vector2(94, 64)
    armor_bar.size = Vector2(300, 10)
    armor_bar.visible = false
    root.add_child(armor_bar)

    time_label = UI.label("00:00", 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    time_label.position = Vector2(490, 20)
    time_label.size = Vector2(300, 52)
    root.add_child(time_label)

    kills_label = UI.label("0", 26, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
    kills_label.position = Vector2(1000, 26)
    kills_label.size = Vector2(264, 32)
    root.add_child(kills_label)
    coin_box = HBoxContainer.new()                 # Forbidden Archive fragments collected this run
    coin_box.alignment = BoxContainer.ALIGNMENT_END
    coin_box.add_theme_constant_override("separation", 6)
    coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    coin_box.position = Vector2(1000, 60)
    coin_box.size = Vector2(264, 30)
    root.add_child(coin_box)
    coin_box.add_child(CoinIcon.new())
    coin_label = UI.label("0", 26, UI.ESSENCE, HORIZONTAL_ALIGNMENT_RIGHT)
    coin_box.add_child(coin_label)

    elite_box = Control.new()
    elite_box.position = Vector2(440, 78)
    elite_box.visible = false
    root.add_child(elite_box)
    elite_name = UI.label("", 16, Color(1.0, 0.6, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
    elite_name.size = Vector2(400, 20)
    elite_box.add_child(elite_name)
    elite_bar = UI.bar(Color(0.85, 0.3, 0.2), Color(0.12, 0.05, 0.05), UI.INK)
    elite_bar.position = Vector2(0, 22)
    elite_bar.size = Vector2(400, 14)
    elite_box.add_child(elite_bar)

    announce_label = UI.label("", 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    announce_label.position = Vector2(0, 150)
    announce_label.size = Vector2(1280, 56)
    announce_label.modulate.a = 0.0
    root.add_child(announce_label)

    debug_label = UI.label("", 14, UI.DIM, HORIZONTAL_ALIGNMENT_RIGHT)
    debug_label.position = Vector2(900, 690)
    debug_label.size = Vector2(368, 22)
    root.add_child(debug_label)

    for i in 3:
        slots.append(_make_slot(root, Vector2(12 + i * 262, 616)))
    _relayout()


## Re-pin every fixed-position element to the live viewport size (fullscreen expand).
func _relayout() -> void:
    if _root == null or xp_bar == null or coin_box == null:
        return
    var vsz := get_viewport().get_visible_rect().size
    var w := vsz.x
    var h := vsz.y
    xp_bar.position = Vector2(0, 0)
    xp_bar.size = Vector2(w, 16)
    lv_label.position = Vector2(0, 0)
    lv_label.size = Vector2(w, 20)
    time_label.position = Vector2((w - 300.0) * 0.5, 20)
    kills_label.position = Vector2(w - 276.0, 26)
    coin_box.position = Vector2(w - 276.0, 60)
    elite_box.position = Vector2((w - 400.0) * 0.5, 78)
    announce_label.position = Vector2(0, 150)
    announce_label.size = Vector2(w, 56)
    debug_label.position = Vector2(w - 380.0, h - 30.0)
    for i in slots.size():
        var p: Control = (slots[i] as Dictionary)["panel"]
        p.position = Vector2(12 + i * 262, h - 104.0)


func _make_slot(root: Control, pos: Vector2) -> Dictionary:
    var p := UI.panel(Color(0.07, 0.06, 0.11, 0.9), Color(0.36, 0.3, 0.46), 2, 8)
    p.position = pos
    p.custom_minimum_size = Vector2(250, 92)
    root.add_child(p)
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 2)
    p.add_child(v)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 8)
    v.add_child(top)
    var icon := TextureRect.new()
    icon.custom_minimum_size = Vector2(40, 40)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    top.add_child(icon)
    var nv := VBoxContainer.new()
    nv.add_theme_constant_override("separation", 0)
    nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(nv)
    var name_l := UI.label("", 18, UI.GOLD)
    nv.add_child(name_l)
    var sub := UI.label("", 14, UI.DIM)
    nv.add_child(sub)
    var status := UI.label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
    top.add_child(status)
    var pips := Pips.new()
    pips.custom_minimum_size = Vector2(104, 12)
    v.add_child(pips)
    return {"name": name_l, "status": status, "sub": sub, "pips": pips, "panel": p, "icon": icon}


func announce(text: String, danger: bool) -> void:
    announce_label.text = text
    announce_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if danger else UI.GOLD)
    if _announce_tween != null:
        _announce_tween.kill()
    announce_label.modulate.a = 0.0
    announce_label.scale = Vector2(1.4, 1.4)
    announce_label.pivot_offset = announce_label.size * 0.5
    _announce_tween = create_tween()
    _announce_tween.set_parallel(true)
    _announce_tween.tween_property(announce_label, "modulate:a", 1.0, 0.12)
    _announce_tween.tween_property(announce_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    _announce_tween.chain().tween_interval(1.4)
    _announce_tween.chain().tween_property(announce_label, "modulate:a", 0.0, 0.5)


func _process(delta: float) -> void:
    var pl: Player = world.player
    if pl == null:
        return
    xp_bar.value = float(pl.xp) / float(pl.xp_next)
    _set_text(lv_label, "LV %d" % pl.level)
    var hp_k := clampf(pl.hp / pl.max_hp, 0.0, 1.0)
    _hp_shown = lerpf(_hp_shown, hp_k, minf(1.0, delta * 10.0))
    hp_bar.value = _hp_shown
    _set_text(hp_label, "%d / %d" % [ceili(pl.hp), int(pl.max_hp)])
    var low := hp_k < 0.3
    hp_bar.modulate = Color(1, 1, 1).lerp(Color(1.5, 0.7, 0.7), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)) if low else Color.WHITE
    if pl.hp < _last_hp:
        hp_bar.scale = Vector2(1.03, 1.15)
    hp_bar.scale = hp_bar.scale.lerp(Vector2.ONE, minf(1.0, delta * 14.0))
    _last_hp = pl.hp
    armor_bar.visible = pl.armor > 0.0
    if pl.armor > 0.0 and pl.passive != null:
        armor_bar.value = clampf(pl.armor / maxf(1.0, float(pl.passive.p.get("armor_hp", 1.0))), 0.0, 1.0)
    var secs := int(world.run_time)
    _set_text(time_label, "%02d:%02d" % [secs / 60, secs % 60])
    _set_text(kills_label, "%d kills" % pl.kills)
    _set_text(coin_label, str(world.run_coins))
    _update_slot(slots[0], pl.weapon)
    _update_slot(slots[1], pl.passive)
    if pl.chest_weapons.is_empty():
        _set_text(slots[2]["name"] as Label, "Treasure")
        _set_text(slots[2]["status"] as Label, "--")
        _set_text(slots[2]["sub"] as Label, "Elite chests")
        (slots[2]["icon"] as TextureRect).texture = null
        slots[2]["_icon_path"] = ""
        var pips0: Pips = slots[2]["pips"]
        if pips0.level != 0 or pips0.max_level != 5 or pips0.branch_at != 0:
            pips0.level = 0
            pips0.max_level = 5
            pips0.branch_at = 0
            pips0.queue_redraw()
    else:
        _update_slot(slots[2], pl.chest_weapons[0])
        if pl.chest_weapons.size() > 1:
            _set_text(slots[2]["sub"] as Label, "x%d weapons" % pl.chest_weapons.size())
        if pl.rented_weapon_id != "" and pl.chest_weapons[0].def.id == pl.rented_weapon_id:
            var _sub: Label = slots[2]["sub"]
            if not _sub.text.ends_with("  (unsealed)"):
                _set_text(_sub, _sub.text + "  (unsealed)")
    var at: AtlasTexture = portrait.texture
    var region := Rect2(64.0 * float(int(Time.get_ticks_msec() / 400) % 2), 0, 64, 64)
    if at.region != region:
        at.region = region
    # elite bar
    var elites: Array = world.enemies.elites
    if elites.is_empty():
        elite_box.visible = false
    else:
        var e = elites[0]
        for cand in elites:                         # a unique boss owns the bar while it is alive
            if cand.def.boss_time > 0.0:
                e = cand
                break
        elite_box.visible = true
        _set_text(elite_name, e.def.display_name.to_upper())
        elite_bar.value = clampf(e.hp / e.max_hp, 0.0, 1.0)
    if Input.is_key_pressed(KEY_F3) and not _debug:
        _debug = true
        debug_label.visible = not debug_label.visible
    elif not Input.is_key_pressed(KEY_F3):
        _debug = false
    if debug_label.visible:
        _set_text(debug_label, "%d FPS   enemies %d   proj %d   gems %d" % [Engine.get_frames_per_second(), world.enemies.alive_count(), world.projectiles.live.size(), world.gems.live.size()])


## _process runs every frame: assigning Label.text forces a Control relayout even
## when the string is identical, so only assign on actual change (perf, no visual change).
func _set_text(l: Label, s: String) -> void:
    if l.text != s:
        l.text = s


func _update_slot(s: Dictionary, ab: Ability) -> void:
    if ab == null:
        return
    var art: Dictionary = AbilityArt.icon_for_ability(ab.def, ab.branch)
    var path := String(art.get("path", ""))
    var frames := maxi(1, int(art.get("frames", 1)))
    var fps := float(art.get("fps", 8.0))
    # _update_slot runs every frame: only rebuild the AtlasTexture when the art changes.
    if String(s.get("_icon_path", "")) != path or int(s.get("_icon_frames", -1)) != frames:
        s["_icon_path"] = path
        s["_icon_frames"] = frames
        var tex: Texture2D = DB.texture(path)
        if tex != null:
            var at := AtlasTexture.new()
            at.atlas = tex
            at.region = AbilityArt.frame_region(tex, frames, 0)
            (s["icon"] as TextureRect).texture = at
        else:
            (s["icon"] as TextureRect).texture = null
    elif frames > 1:
        # Simple frame cycle for multi-frame strips (no spin/pulse in HUD slots).
        var cur := (s["icon"] as TextureRect).texture as AtlasTexture
        if cur != null and cur.atlas != null:
            var seed := float(abs(path.hash()) % 100) / 100.0 * 7.0
            cur.region = AbilityArt.frame_region(cur.atlas, frames, int(Time.get_ticks_msec() / 1000.0 * fps + seed) % frames)
    _set_text(s["name"] as Label, ab.def.display_name)
    var sub := "Lv %d" % ab.level
    if ab.branch >= 0:
        sub += "  -  " + ab.branch_name()
    if ab.needs_evo(2) or ab.needs_evo(1):
        sub += "  -  EVOLUTION READY"
    elif ab.needs_branch():
        sub += "  -  CHOOSE PATH"
    _set_text(s["sub"] as Label, sub)
    _set_text(s["status"] as Label, ab.hud_line())
    var pips: Pips = s["pips"]
    if pips.level != ab.level or pips.max_level != ab.max_level_now() or pips.branch_at != ab.branch_level:
        pips.level = ab.level
        pips.max_level = ab.max_level_now()
        pips.branch_at = ab.branch_level
        pips.queue_redraw()
