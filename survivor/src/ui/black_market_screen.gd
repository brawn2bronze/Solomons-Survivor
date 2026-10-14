class_name BlackMarketScreen
extends CanvasLayer
## Forbidden Archive shop, opened from the main menu once the unlock boss has been slain. Two tabs:
## one-battle unsealings (consumed when the next run starts) and permanent bindings.
## Cards are built from DB.market (MarketItemDef .tres files), so new listings need no code here.

signal back

enum Tab { RENTALS, UPGRADES }

const CARD_SIZE := Vector2(392, 150)
const ICON_BOX := 72.0
const ICON_PX := 64.0
const TOAST_SECONDS := 1.6
const DIM_BUTTON := Color(0.7, 0.55, 0.55)
const TAB_OFF := Color(0.62, 0.62, 0.7)

var _tab: int = Tab.RENTALS
var _focus_id := ""
var _coin_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _armed_label: Label
var _disarm_btn: Button
var _progress: ProgressBar
var _progress_label: Label
var _tab_btns: Array[Button] = []
var _toast: Label
var _toast_tween: Tween
var _icons: Array = []
var _t := 0.0


func _ready() -> void:
    layer = 5
    var bg := ColorRect.new()
    bg.color = Color(0.035, 0.03, 0.06)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(bg)
    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 36)
    margin.add_theme_constant_override("margin_right", 36)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_bottom", 18)
    add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margin.add_child(root)

    # header: title, one-line explainer, coin balance
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 14)
    root.add_child(head)
    var title := UI.label("THE FORBIDDEN ARCHIVE", 40, UI.GOLD)
    title.add_theme_constant_override("outline_size", 10)
    head.add_child(title)
    var sub := UI.label("Unseal for one battle. Bind forever.", 18, UI.DIM)
    sub.size_flags_vertical = Control.SIZE_SHRINK_END
    head.add_child(sub)
    var head_gap := Control.new()
    head_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(head_gap)
    head.add_child(CoinIcon.new())
    _coin_label = UI.label("0", 40, UI.GOLD)
    head.add_child(_coin_label)

    var scribe := UI.label("Ah, another of Solomon's puppets. Bring me the essence of my brethren, and I shall show you weapons even the King feared to wield...", 15, UI.DIM)
    root.add_child(scribe)

    # tabs + collection progress
    var tabs := HBoxContainer.new()
    tabs.add_theme_constant_override("separation", 10)
    root.add_child(tabs)
    var tab_names: Array[String] = ["Unseal for One Battle", "Permanent Binding"]
    for i in tab_names.size():
        var tb := UI.button(tab_names[i], 22, Vector2(300, 46))
        tb.pressed.connect(_set_tab.bind(i))
        tabs.add_child(tb)
        _tab_btns.append(tb)
    var tab_gap := Control.new()
    tab_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    tabs.add_child(tab_gap)
    _progress_label = UI.label("", 18, UI.TEXT)
    _progress_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    tabs.add_child(_progress_label)
    _progress = UI.bar(UI.PURPLE, Color(0.1, 0.08, 0.16), UI.INK)
    _progress.custom_minimum_size = Vector2(200, 18)
    _progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    tabs.add_child(_progress)

    # card grid
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root.add_child(_scroll)
    _grid = GridContainer.new()
    _grid.columns = 3
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _grid.add_theme_constant_override("h_separation", 12)
    _grid.add_theme_constant_override("v_separation", 12)
    _scroll.add_child(_grid)

    # footer: armed rental, toast, back
    var foot := HBoxContainer.new()
    foot.add_theme_constant_override("separation", 14)
    root.add_child(foot)
    _armed_label = UI.label("", 22, UI.TEXT)
    _armed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    foot.add_child(_armed_label)
    _disarm_btn = UI.button("Disarm", 18, Vector2(130, 42))
    _disarm_btn.pressed.connect(_on_disarm)
    foot.add_child(_disarm_btn)
    _toast = UI.label("", 22, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    _toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _toast.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _toast.modulate.a = 0.0
    foot.add_child(_toast)
    var back_btn := UI.button("Back", 22, Vector2(200, 46))
    back_btn.pressed.connect(_on_back)
    foot.add_child(back_btn)

    _rebuild()
    if not Meta.market_unlocked:
        _flash(Meta.unlock_hint(), UI.RED)


func _process(delta: float) -> void:
    _t += delta
    for ic in _icons:
        var at: AtlasTexture = ic["atlas"]
        var frames: int = int(ic["frames"])
        var fi: int = int((_t + float(ic["seed"])) * float(ic["fps"])) % frames
        at.region = AbilityArt.frame_region(at.atlas, frames, fi)


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        get_viewport().set_input_as_handled()
        _on_back()


# ------------------------------------------------------------------ build
## Rebuild the card grid + header for the current tab. Called after every purchase / arm / tab change.
func _rebuild() -> void:
    for c in _grid.get_children():
        c.queue_free()
    _icons.clear()
    var kind: int = MarketItemDef.Kind.RENTAL if _tab == Tab.RENTALS else MarketItemDef.Kind.MOD
    var focus_btn: Button = null
    var first_btn: Button = null
    for it in DB.market_items(kind):
        var item: MarketItemDef = it
        var card: Control = _make_card(item)
        _grid.add_child(card)
        var action: Button = card.get_meta("action") as Button
        if not action.disabled:
            if first_btn == null:
                first_btn = action
            if item.id == _focus_id:
                focus_btn = action
    for i in _tab_btns.size():
        _tab_btns[i].modulate = Color.WHITE if i == _tab else TAB_OFF
    _coin_label.text = str(Meta.coins)
    var total_mods: int = DB.market_items(MarketItemDef.Kind.MOD).size()
    var owned_mods: int = Meta.owned_mod_count()
    _progress.value = float(owned_mods) / float(maxi(1, total_mods))
    _progress_label.text = "Bindings owned  %d / %d" % [owned_mods, total_mods]
    if Meta.armed_rental != "":
        var wd: WeaponDef = DB.weapons.get(Meta.armed_rental)
        var wname: String = wd.display_name if wd != null else Meta.armed_rental
        _armed_label.text = "Unsealed for next battle: %s  (%d left)" % [wname, Meta.rental_count(Meta.armed_rental)]
        _armed_label.add_theme_color_override("font_color", UI.GREEN)
        _disarm_btn.visible = true
    else:
        _armed_label.text = "No seal broken - unseal a weapon to start your next run with it"
        _armed_label.add_theme_color_override("font_color", UI.DIM)
        _disarm_btn.visible = false
    var target: Button = focus_btn if focus_btn != null else first_btn
    if target == null:
        target = _tab_btns[_tab]
    target.call_deferred("grab_focus")


func _make_card(item: MarketItemDef) -> Control:
    var weapon: WeaponDef = DB.weapons.get(item.weapon_id)
    var is_mod: bool = item.kind == MarketItemDef.Kind.MOD
    var accent: Color = weapon.color if weapon != null else UI.GOLD
    var owned: bool = is_mod and Meta.owns_mod(item.id)
    var stock: int = 0 if is_mod else Meta.rental_count(item.weapon_id)
    var armed: bool = (not is_mod) and Meta.armed_rental == item.weapon_id
    var affordable: bool = Meta.can_afford(Meta.get_market_price(item.cost))
    # Legendary gate: silhouette-locked until its per-weapon prerequisite is met
    # (see Player.is_legendary_unlocked). Locked cards show ??? + the unlock hint.
    var locked_legend: bool = (not is_mod) and weapon != null and int(weapon.rarity) == 2 and not Player.is_legendary_unlocked(item.weapon_id)
    var panel: Control = UI.panel(UI.PANEL, accent.darkened(0.25), 3, 10)
    panel.custom_minimum_size = CARD_SIZE
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", 12)
    panel.add_child(h)

    # icon (weapon art via AbilityArt, or the listing's own placeholder icon)
    var backdrop := ColorRect.new()
    backdrop.color = accent.darkened(0.55)
    backdrop.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
    backdrop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(backdrop)
    var art: Dictionary = _icon_for(item, weapon)
    var base_tex: Texture2D = DB.texture(String(art.get("path", "")))
    if base_tex != null:
        var tex := TextureRect.new()
        tex.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
        tex.size = Vector2(ICON_PX, ICON_PX)
        tex.position = Vector2((ICON_BOX - ICON_PX) * 0.5, (ICON_BOX - ICON_PX) * 0.5)
        tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var frames: int = maxi(1, int(art.get("frames", 1)))
        var at := AtlasTexture.new()
        at.atlas = base_tex
        at.region = AbilityArt.frame_region(base_tex, frames, 0)
        tex.texture = at
        if locked_legend:
            tex.modulate = Color(0, 0, 0, 1)
        backdrop.add_child(tex)
        if frames > 1:
            _icons.append({"atlas": at, "frames": frames, "fps": float(art.get("fps", 8.0)), "seed": randf() * 3.0})

    # name, effect, status
    var mid := VBoxContainer.new()
    mid.add_theme_constant_override("separation", 3)
    mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h.add_child(mid)
    var title_text: String = item.weapon_id
    var desc: String = ""
    if locked_legend:
        title_text = "???"
        var hint: String = String(weapon.unlock_hint)
        desc = hint if hint != "" else "Sealed. Its prerequisite is yet unwritten."
    elif is_mod:
        title_text = item.display_name
        desc = item.description
    elif weapon != null:
        title_text = weapon.display_name
        desc = weapon.description.trim_prefix("Forbidden weapon. ").trim_prefix("Treasure weapon. ")
    mid.add_child(UI.wrap_label(title_text, 22, UI.GOLD, 170))
    mid.add_child(UI.wrap_label(desc, 13, UI.TEXT, 170))
    var status_text: String = ""
    var status_col: Color = UI.DIM
    if is_mod:
        if owned:
            status_text = "OWNED"
            status_col = UI.GREEN
        elif weapon != null:
            status_text = "for the %s" % weapon.display_name
    elif armed:
        status_text = "UNSEALED for next battle"
        status_col = UI.GREEN
    elif locked_legend:
        status_text = "SEALED"
        status_col = UI.RED
    elif stock > 0:
        status_text = "In stock: %d" % stock
        status_col = UI.GOLD
    mid.add_child(UI.label(status_text, 14, status_col))

    # cost + actions
    var right := VBoxContainer.new()
    right.add_theme_constant_override("separation", 6)
    right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    h.add_child(right)
    var cost_row := HBoxContainer.new()
    cost_row.alignment = BoxContainer.ALIGNMENT_CENTER
    cost_row.add_theme_constant_override("separation", 4)
    right.add_child(cost_row)
    cost_row.add_child(CoinIcon.new())
    var cost_col: Color = UI.GOLD if (affordable or owned) else UI.RED
    cost_row.add_child(UI.label(str(Meta.get_market_price(item.cost)), 22, cost_col))
    var action: Button
    if owned:
        action = UI.button("OWNED", 18, Vector2(104, 40))
        action.disabled = true
    elif locked_legend:
        action = UI.button("SEALED", 18, Vector2(104, 40))
        action.disabled = true
    else:
        action = UI.button("BIND" if is_mod else "UNSEAL", 18, Vector2(104, 40))
        action.pressed.connect(_on_buy.bind(item.id))
        if not affordable:
            action.modulate = DIM_BUTTON
    right.add_child(action)
    if (not is_mod) and (not locked_legend) and stock > 0:
        var arm_btn := UI.button("WIELDING" if armed else "WIELD", 16, Vector2(104, 34))
        arm_btn.disabled = armed
        arm_btn.pressed.connect(_on_arm.bind(item.weapon_id))
        right.add_child(arm_btn)
    panel.set_meta("action", action)
    return panel


## Listing icon: its own placeholder when set, else the weapon's art, else the grey silhouette.
func _icon_for(item: MarketItemDef, weapon: WeaponDef) -> Dictionary:
    if item.icon != "":
        return {"path": item.icon, "frames": 1, "fps": 8.0}
    if weapon != null:
        return AbilityArt.icon_for_ability(weapon, -1)
    return {"path": AbilityArt.WEAPON_FALLBACK, "frames": 1, "fps": 8.0}


# ------------------------------------------------------------------ actions
func _set_tab(idx: int) -> void:
    if idx == _tab:
        return
    _tab = idx
    _focus_id = ""
    Audio.sfx("button_click")
    _rebuild()


func _on_buy(item_id: String) -> void:
    var item: MarketItemDef = DB.market.get(item_id)
    if item == null:
        return
    var wdef: WeaponDef = DB.weapons.get(item.weapon_id)
    if wdef != null and int(wdef.rarity) == 2 and not Player.is_legendary_unlocked(item.weapon_id):
        Audio.sfx("menu_close")
        var hint: String = String(wdef.unlock_hint)
        _flash(hint if hint != "" else "Sealed.", UI.RED)
        return
    _focus_id = item_id
    var price := Meta.get_market_price(item.cost)
    if not Meta.can_afford(price):
        Audio.sfx("menu_close")
        _flash("Not enough fragments - you need %d" % price, UI.RED)
        return
    if not Meta.buy_item(item_id):
        Audio.sfx("menu_close")
        _flash("You can't hold any more of those", UI.RED)
        return
    Audio.sfx("market_purchase")
    var weapon: WeaponDef = DB.weapons.get(item.weapon_id)
    var wname: String = weapon.display_name if weapon != null else item.weapon_id
    if item.kind == MarketItemDef.Kind.MOD:
        _flash("%s bound to the %s" % [item.display_name, wname], UI.GREEN)
    else:
        _flash("%s unsealed - wield it in your next battle" % wname, UI.GREEN)
    _rebuild()


func _on_arm(weapon_id: String) -> void:
    _focus_id = ""
    var wdef: WeaponDef = DB.weapons.get(weapon_id)
    if wdef != null and int(wdef.rarity) == 2 and not Player.is_legendary_unlocked(weapon_id):
        Audio.sfx("menu_close")
        return
    if Meta.arm_rental(weapon_id):
        Audio.sfx("button_click")
    _rebuild()


func _on_disarm() -> void:
    Meta.disarm_rental()
    Audio.sfx("button_click")
    _rebuild()


func _on_back() -> void:
    Audio.sfx("menu_close")
    back.emit()


func _flash(text: String, col: Color) -> void:
    _toast.text = text
    _toast.add_theme_color_override("font_color", col)
    if _toast_tween != null:
        _toast_tween.kill()
    _toast.modulate.a = 1.0
    _toast_tween = create_tween()
    _toast_tween.tween_interval(TOAST_SECONDS)
    _toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
