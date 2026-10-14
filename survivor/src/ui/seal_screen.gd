extends CanvasLayer
class_name SealScreen

signal back

const COLOR_BG := Color(0.1, 0.04, 0.18, 0.95)
const COLOR_PANEL := Color(0.15, 0.08, 0.25, 0.9)
const COLOR_GOLD := Color(0.85, 0.65, 0.2)
const COLOR_BRONZE := Color(0.6, 0.4, 0.2)
const COLOR_CRIMSON := Color(0.8, 0.15, 0.2)
const COLOR_CYAN := Color(0.2, 0.8, 0.9)
const COLOR_LOCKED := Color(0.4, 0.4, 0.4, 0.6)
const COLOR_LINE_ACTIVE := Color(0.85, 0.65, 0.2, 0.8)
const COLOR_LINE_INACTIVE := Color(0.2, 0.8, 0.9, 0.4)

const BADGE_SIZE := Vector2(112, 46)
const CIRCLE_DIAMETER := 40.0

# Short canvas labels; full names live in the detail panel + tooltips.
const SHORT_NAMES := {
    "reinforced_walls": "Walls",
    "iron_citadels": "Citadels",
    "unbroken_covenant": "Covenant",
    "enhanced_bindings": "Bindings",
    "consecrated_strikes": "Strikes",
    "solomonic_decree": "Decree",
    "temporal_loops": "Loops",
    "echoes_of_past": "Echoes",
    "foreseen_victory": "Victory",
    "demons_folly": "Folly",
    "soul_siphon": "Siphon",
    "asmodeus_bargain": "Bargain",
    "scholars_focus": "Focus",
    "codex_mastery": "Codex",
    "forbidden_knowledge": "Knowledge",
    "fates_intercession": "Fate",
    "threads_of_fortune": "Threads",
    "moirais_shears": "Shears"
}

var _root: Control
var _header: HBoxContainer
var _tab_bar: HBoxContainer
var _content: HSplitContainer
var _tree_canvas: Control
var _detail_panel: VBoxContainer
var _selected_node_id: String = ""
var _current_tab: String = "seal"

var _tab_buttons: Dictionary = {}
var _node_controls: Dictionary = {}
# Ring order (ascending angle) so tier rings link adjacent branches.
var _branch_order: Array = []


func _ready() -> void:
    layer = 100
    _build_ui()
    _setup_branches()
    Meta.seal_changed.connect(_refresh)
    Meta.hero_seal_changed.connect(_on_hero_seal_changed)
    # Deferred: canvas has no size until first layout, and node layout needs it.
    _refresh.call_deferred()


func _build_ui() -> void:
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)

    var bg := ColorRect.new()
    bg.color = COLOR_BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(bg)

    var margin := MarginContainer.new()
    margin.set_anchors_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 40)
    margin.add_theme_constant_override("margin_right", 40)
    margin.add_theme_constant_override("margin_top", 30)
    margin.add_theme_constant_override("margin_bottom", 30)
    _root.add_child(margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 20)
    margin.add_child(vbox)

    # Header
    _header = HBoxContainer.new()
    _header.add_theme_constant_override("separation", 20)
    vbox.add_child(_header)

    var title := Label.new()
    title.text = "SOLOMON'S SEAL"
    title.add_theme_font_size_override("font_size", 32)
    title.add_theme_color_override("font_color", COLOR_GOLD)
    _header.add_child(title)

    _header.add_child(_make_spacer())

    var balance := Label.new()
    balance.name = "BalanceLabel"
    balance.add_theme_font_size_override("font_size", 24)
    balance.add_theme_color_override("font_color", COLOR_BRONZE)
    _header.add_child(balance)

    var back_btn := Button.new()
    back_btn.text = "BACK"
    back_btn.pressed.connect(func(): back.emit())
    _header.add_child(back_btn)

    # View switch: whole hexagram vs Vessel stub (branch tabs removed, §26).
    _tab_bar = HBoxContainer.new()
    _tab_bar.add_theme_constant_override("separation", 10)
    vbox.add_child(_tab_bar)

    _build_tabs()

    # Content area
    _content = HSplitContainer.new()
    _content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(_content)

    # Tree canvas (custom-drawn hexagram lines + absolutely-positioned badges).
    _tree_canvas = Control.new()
    _tree_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tree_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tree_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _tree_canvas.draw.connect(_on_tree_draw)
    _tree_canvas.resized.connect(_on_canvas_resized)
    _content.add_child(_tree_canvas)

    _detail_panel = VBoxContainer.new()
    _detail_panel.custom_minimum_size.x = 350
    _detail_panel.add_theme_constant_override("separation", 15)
    _content.add_child(_detail_panel)

    _build_detail_placeholder()


func _build_tabs() -> void:
    var tabs = [
        {"id": "seal", "name": "Solomon's Seal", "color": COLOR_GOLD},
        {"id": "vessel", "name": "Vessel's Sigil", "color": COLOR_CYAN}
    ]

    for tab_data in tabs:
        var btn := Button.new()
        btn.text = tab_data.name
        btn.toggle_mode = true
        btn.button_pressed = (tab_data.id == _current_tab)
        btn.add_theme_color_override("font_color", tab_data.color)
        btn.pressed.connect(_on_tab_selected.bind(tab_data.id))
        _tab_bar.add_child(btn)
        _tab_buttons[tab_data.id] = btn


func _setup_branches() -> void:
    # Full hexagram: 6 branches x 3 tiers, ascending angle for ring adjacency.
    # Sixth ray (330°) is the Fate draft-utility chain (§30), tiered exactly
    # like the other five; center stub stays reserved for character sigils.
    _branch_order = [
        {"nodes": ["enhanced_bindings", "consecrated_strikes", "solomonic_decree"], "angle": 30.0},
        {"nodes": ["reinforced_walls", "iron_citadels", "unbroken_covenant"], "angle": 90.0},
        {"nodes": ["temporal_loops", "echoes_of_past", "foreseen_victory"], "angle": 150.0},
        {"nodes": ["scholars_focus", "codex_mastery", "forbidden_knowledge"], "angle": 210.0},
        {"nodes": ["demons_folly", "soul_siphon", "asmodeus_bargain"], "angle": 270.0},
        {"nodes": ["fates_intercession", "threads_of_fortune", "moirais_shears"], "angle": 330.0}
    ]


func _on_tab_selected(tab_id: String) -> void:
    _current_tab = tab_id
    _selected_node_id = ""
    for id in _tab_buttons:
        _tab_buttons[id].button_pressed = (id == tab_id)
    _refresh_nodes()


# Public branch switch. Old per-branch ids map to the single hexagram view.
func set_branch(branch_id: String) -> void:
    if branch_id == "vessel":
        _on_tab_selected("vessel")
    else:
        _on_tab_selected("seal")


func _refresh() -> void:
    if not is_instance_valid(_header):
        return
    var balance_label = _header.get_node_or_null("BalanceLabel")
    if balance_label is Label:
        (balance_label as Label).text = "Fragments: %d" % Meta.coins
    _refresh_nodes()


func _on_hero_seal_changed(_hero_id: String) -> void:
    if _current_tab == "vessel":
        _refresh_nodes()


func _on_canvas_resized() -> void:
    # Node positions derive from canvas size — rebuild so badges track it.
    if is_instance_valid(_tree_canvas) and _tree_canvas.size.x > 0.0:
        _refresh_nodes()
    else:
        _tree_canvas.queue_redraw()


func _refresh_nodes() -> void:
    if not is_instance_valid(_tree_canvas):
        return
    # Detach synchronously before freeing: queue_free() alone is deferred,
    # so same-frame rebuilds would stack duplicates (same lesson as PurchaseBtn).
    for node_id in _node_controls:
        var badge = _node_controls[node_id]
        if is_instance_valid(badge):
            _tree_canvas.remove_child(badge)
            badge.queue_free()
    _node_controls.clear()

    if _current_tab == "vessel":
        _build_vessel_placeholder()
    else:
        _build_all_nodes()
        _build_center_stub()

    _tree_canvas.queue_redraw()
    _update_detail()


func _hexagram_geometry() -> Dictionary:
    # Shared by _build_all_nodes and _on_tree_draw so badges sit on their lines.
    # Tier reach is derived from canvas size so the whole shape always fits.
    var out := {"center": Vector2.ZERO, "branches": []}
    if _tree_canvas.size.x <= 0.0 or _tree_canvas.size.y <= 0.0:
        return out
    var center := _tree_canvas.size / 2.0
    var margin := 62.0
    var avail := minf(_tree_canvas.size.x, _tree_canvas.size.y) / 2.0 - margin
    if avail <= 0.0:
        return {"center": center, "branches": []}
    var radius := avail * 0.5
    var spacing := avail * 0.25
    out["center"] = center
    for branch in _branch_order:
        var angle_rad := deg_to_rad(float(branch.get("angle", 90.0)))
        var direction := Vector2(cos(angle_rad), sin(angle_rad))
        var origin := center + direction * radius
        var positions: Array = []
        var node_ids: Array = branch.get("nodes", [])
        for i in range(node_ids.size()):
            positions.append(origin + direction * (float(i) * spacing))
        out["branches"].append({"nodes": node_ids, "positions": positions, "origin": origin})
    return out


func _build_all_nodes() -> void:
    var geo := _hexagram_geometry()
    if (geo.get("branches", []) as Array).is_empty():
        return
    for branch in geo["branches"]:
        var node_ids: Array = branch.get("nodes", [])
        var positions: Array = branch.get("positions", [])
        for i in range(node_ids.size()):
            var node_id := String(node_ids[i])
            var badge := _make_node_badge(node_id)
            # Center via fixed badge size: badge.size is (0,0) until layout runs.
            var pos: Vector2 = (positions[i] as Vector2) - BADGE_SIZE / 2.0
            pos.x = clampf(pos.x, 0.0, maxf(0.0, _tree_canvas.size.x - BADGE_SIZE.x))
            pos.y = clampf(pos.y, 0.0, maxf(0.0, _tree_canvas.size.y - BADGE_SIZE.y))
            badge.position = pos
            _tree_canvas.add_child(badge)
            _node_controls[node_id] = badge


## Center sigil stub (§29): read-only display of the equipped vessel, reserved
## for future character-sigil development. Display-only (MOUSE_FILTER_IGNORE),
## never purchasable, keyed "__center" so it never collides with seal node ids.
func _sigil_name() -> String:
    var cid := String(Game.selected_character)
    if cid != "" and DB.characters.has(cid):
        return String((DB.characters[cid] as CharacterDef).display_name)
    return "No vessel"


func _build_center_stub() -> void:
    var geo := _hexagram_geometry()
    if (geo.get("branches", []) as Array).is_empty():
        return
    var center: Vector2 = geo["center"]
    var badge := Control.new()
    badge.size = BADGE_SIZE
    badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.tooltip_text = "Vessel's Sigil (%s)" % _sigil_name()
    var pos: Vector2 = center - BADGE_SIZE / 2.0
    pos.x = clampf(pos.x, 0.0, maxf(0.0, _tree_canvas.size.x - BADGE_SIZE.x))
    pos.y = clampf(pos.y, 0.0, maxf(0.0, _tree_canvas.size.y - BADGE_SIZE.y))
    badge.position = pos

    var circle := PanelContainer.new()
    circle.position = Vector2(3, 3)
    circle.size = Vector2(CIRCLE_DIAMETER, CIRCLE_DIAMETER)
    circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = COLOR_PANEL
    style.set_corner_radius_all(int(CIRCLE_DIAMETER / 2.0))
    style.border_color = COLOR_CYAN
    style.set_border_width_all(2)
    circle.add_theme_stylebox_override("panel", style)
    badge.add_child(circle)

    var glyph := Label.new()
    glyph.text = "S"
    glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
    glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    glyph.add_theme_font_size_override("font_size", 16)
    glyph.add_theme_color_override("font_color", COLOR_CYAN)
    glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
    circle.add_child(glyph)

    var name_label := Label.new()
    name_label.text = _sigil_name()
    name_label.position = Vector2(CIRCLE_DIAMETER + 7, 2)
    name_label.size = Vector2(BADGE_SIZE.x - CIRCLE_DIAMETER - 9, 26)
    name_label.add_theme_font_size_override("font_size", 10)
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_label.clip_text = true
    name_label.add_theme_color_override("font_color", Color.WHITE)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(name_label)

    var kind := Label.new()
    kind.text = "SIGIL"
    kind.position = Vector2(CIRCLE_DIAMETER + 7, 26)
    kind.size = Vector2(BADGE_SIZE.x - CIRCLE_DIAMETER - 9, 18)
    kind.add_theme_font_size_override("font_size", 11)
    kind.add_theme_color_override("font_color", COLOR_CYAN)
    kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(kind)

    _tree_canvas.add_child(badge)
    _node_controls["__center"] = badge


func _build_vessel_placeholder() -> void:
    # Stub until hero trees are implemented in HeroSealData (HERO_TREES is empty).
    var placeholder := PanelContainer.new()
    placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
    placeholder.offset_left = 40.0
    placeholder.offset_top = 40.0
    placeholder.offset_right = -40.0
    placeholder.offset_bottom = -40.0
    var style := StyleBoxFlat.new()
    style.bg_color = COLOR_PANEL
    style.border_color = COLOR_CYAN
    style.set_border_width_all(2)
    placeholder.add_theme_stylebox_override("panel", style)

    var label := Label.new()
    label.text = "Select a hero to view their Covenant.\n\n(Hero tree data pending)"
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    placeholder.add_child(label)

    _tree_canvas.add_child(placeholder)
    _node_controls["vessel_placeholder"] = placeholder


func _badge_state(node_id: String, data: Dictionary, current_lvl: int) -> String:
    if current_lvl >= int(data.get("max_level", 1)):
        return "maxed"
    if Meta.are_seal_prereqs_met(node_id):
        return "open"
    return "locked"


func _make_node_badge(node_id: String) -> Control:
    var data = GlobalSealData.get_node_data(node_id)
    var current_lvl = Meta.get_seal_level(node_id)
    var max_lvl = int(data.get("max_level", 1))
    var state := _badge_state(node_id, data, current_lvl)

    var badge := Control.new()
    badge.size = BADGE_SIZE
    badge.mouse_filter = Control.MOUSE_FILTER_STOP
    badge.tooltip_text = "%s  (%d/%d)" % [String(data.get("name", node_id)), current_lvl, max_lvl]
    # Every badge is inspectable, locked included — only the purchase
    # button is gated (§26 inspect-yes/buy-no).
    badge.gui_input.connect(_on_node_clicked.bind(node_id))

    var circle := PanelContainer.new()
    circle.position = Vector2(3, 3)
    circle.size = Vector2(CIRCLE_DIAMETER, CIRCLE_DIAMETER)
    circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = COLOR_PANEL
    style.set_corner_radius_all(int(CIRCLE_DIAMETER / 2.0))
    if state == "maxed":
        style.border_color = COLOR_BRONZE
        style.set_border_width_all(3)
    elif state == "open":
        style.border_color = COLOR_GOLD
        style.set_border_width_all(2)
    else:
        style.border_color = COLOR_LOCKED
        style.set_border_width_all(1)
    circle.add_theme_stylebox_override("panel", style)
    badge.add_child(circle)

    var lvl := Label.new()
    lvl.text = "%d" % current_lvl
    lvl.set_anchors_preset(Control.PRESET_FULL_RECT)
    lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lvl.add_theme_font_size_override("font_size", 16)
    if state == "maxed":
        lvl.add_theme_color_override("font_color", COLOR_BRONZE)
    elif state == "open":
        lvl.add_theme_color_override("font_color", COLOR_GOLD)
    else:
        lvl.add_theme_color_override("font_color", COLOR_LOCKED)
    lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    circle.add_child(lvl)

    var name_label := Label.new()
    name_label.text = String(SHORT_NAMES.get(node_id, data.get("name", node_id)))
    name_label.position = Vector2(CIRCLE_DIAMETER + 7, 2)
    name_label.size = Vector2(BADGE_SIZE.x - CIRCLE_DIAMETER - 9, 26)
    name_label.add_theme_font_size_override("font_size", 10)
    name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    name_label.clip_text = true
    if state == "locked":
        name_label.add_theme_color_override("font_color", COLOR_LOCKED)
    else:
        name_label.add_theme_color_override("font_color", Color.WHITE)
    name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(name_label)

    var pips := Label.new()
    pips.text = "%d/%d" % [current_lvl, max_lvl]
    pips.position = Vector2(CIRCLE_DIAMETER + 7, 26)
    pips.size = Vector2(BADGE_SIZE.x - CIRCLE_DIAMETER - 9, 18)
    pips.add_theme_font_size_override("font_size", 11)
    if state == "maxed":
        pips.add_theme_color_override("font_color", COLOR_BRONZE)
    elif state == "open":
        pips.add_theme_color_override("font_color", COLOR_CYAN)
    else:
        pips.add_theme_color_override("font_color", COLOR_LOCKED)
    pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
    badge.add_child(pips)

    return badge


func _on_node_clicked(event: InputEvent, node_id: String) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _selected_node_id = node_id
        _update_detail()


func _segment_lit(node_a: String, node_b: String) -> bool:
    # Connect-the-dots rule (§26): a segment is solid only when both
    # endpoints are purchased; otherwise it stays faint.
    return Meta.get_seal_level(node_a) > 0 and Meta.get_seal_level(node_b) > 0


func _on_tree_draw() -> void:
    if _current_tab == "vessel":
        return
    var geo := _hexagram_geometry()
    var branches: Array = geo.get("branches", [])
    if branches.is_empty():
        return
    var center: Vector2 = geo["center"]

    # Seal-center sigil.
    _tree_canvas.draw_circle(center, 6.0, COLOR_GOLD)
    _tree_canvas.draw_arc(center, 12.0, 0.0, TAU, 24, COLOR_GOLD, 1.5)

    # Ley lines center -> branch origin. Lit when the branch root is owned.
    for branch in branches:
        var node_ids: Array = branch.get("nodes", [])
        var origin: Vector2 = branch.get("origin", center)
        if node_ids.is_empty():
            continue
        var lit := Meta.get_seal_level(String(node_ids[0])) > 0
        var line_color := COLOR_LINE_ACTIVE if lit else COLOR_LINE_INACTIVE
        _tree_canvas.draw_line(center, origin, line_color, 2.0)
        _tree_canvas.draw_circle(origin, 4.0, line_color)

    # Tier chains along each ray: segment i links tier i-1 -> tier i.
    for branch in branches:
        var node_ids: Array = branch.get("nodes", [])
        var positions: Array = branch.get("positions", [])
        var prev_id := String(node_ids[0]) if not node_ids.is_empty() else ""
        var prev_pos: Vector2 = branch.get("origin", center)
        for i in range(positions.size()):
            var node_id := String(node_ids[i])
            var node_pos: Vector2 = positions[i]
            var line_color := COLOR_LINE_ACTIVE if _segment_lit(prev_id, node_id) else COLOR_LINE_INACTIVE
            _tree_canvas.draw_line(prev_pos, node_pos, line_color, 3.0)
            prev_id = node_id
            prev_pos = node_pos

    # Tier rings between adjacent branches: the shape visibly completes.
    var tier_count := 3
    for t in range(tier_count):
        for k in range(branches.size()):
            var b0: Dictionary = branches[k]
            var b1: Dictionary = branches[(k + 1) % branches.size()]
            var ids0: Array = b0.get("nodes", [])
            var ids1: Array = b1.get("nodes", [])
            var pos0: Array = b0.get("positions", [])
            var pos1: Array = b1.get("positions", [])
            if t >= ids0.size() or t >= ids1.size():
                continue
            var id0 := String(ids0[t])
            var id1 := String(ids1[t])
            var line_color := COLOR_LINE_ACTIVE if _segment_lit(id0, id1) else COLOR_LINE_INACTIVE
            _tree_canvas.draw_line(pos0[t] as Vector2, pos1[t] as Vector2, line_color, 2.0)


func _build_detail_placeholder() -> void:
    var label := Label.new()
    label.name = "DetailLabel"
    label.text = "Select a node to view details"
    label.autowrap_mode = TextServer.AUTOWRAP_WORD
    label.add_theme_color_override("font_color", COLOR_GOLD)
    _detail_panel.add_child(label)


func _unmet_prereq_names(node_id: String) -> Array:
    var missing: Array = []
    var data = GlobalSealData.get_node_data(node_id)
    for prereq_id in data.get("prerequisites", []):
        if Meta.get_seal_level(String(prereq_id)) <= 0:
            var pdata = GlobalSealData.get_node_data(String(prereq_id))
            missing.append(String(pdata.get("name", prereq_id)))
    return missing


func _update_detail() -> void:
    if not is_instance_valid(_detail_panel):
        return
    # Clear any stale purchase button before rebuilding. queue_free() alone is
    # deferred to end of frame, so detach synchronously to avoid same-frame
    # duplicates / double-presses when clicks or _refresh land back-to-back.
    var existing_btn = _detail_panel.get_node_or_null("PurchaseBtn")
    if existing_btn:
        _detail_panel.remove_child(existing_btn)
        existing_btn.queue_free()

    var label = _detail_panel.get_node_or_null("DetailLabel")
    if label == null:
        label = Label.new()
        (label as Node).name = "DetailLabel"
        (label as Label).autowrap_mode = TextServer.AUTOWRAP_WORD
        (label as Label).add_theme_color_override("font_color", COLOR_GOLD)
        _detail_panel.add_child(label)

    if _selected_node_id.is_empty():
        (label as Label).text = "Select a node to view details"
        return

    var data = GlobalSealData.get_node_data(_selected_node_id)
    if data.is_empty():
        (label as Label).text = "Select a node to view details"
        return
    var current_lvl = Meta.get_seal_level(_selected_node_id)
    var is_maxed = current_lvl >= int(data.get("max_level", 1))
    var missing = _unmet_prereq_names(_selected_node_id)

    var text = "%s\n\n" % String(data.get("name", _selected_node_id))
    text += "%s\n\n" % String(data.get("desc", ""))
    text += "Level: %d / %d\n" % [current_lvl, int(data.get("max_level", 1))]

    if not missing.is_empty():
        text += "Requires: %s\n" % ", ".join(missing)

    if not is_maxed:
        var cost = GlobalSealData.get_cost(_selected_node_id, current_lvl)
        text += "Cost: %d Fragments\n" % cost

    (label as Label).text = text

    # Inspect-yes/buy-no: the button appears only when actually purchasable.
    if not is_maxed and missing.is_empty():
        var btn := Button.new()
        btn.name = "PurchaseBtn"
        btn.text = "REFORGE SEAL"
        btn.pressed.connect(_on_purchase.bind(_selected_node_id))
        _detail_panel.add_child(btn)


func _on_purchase(node_id: String) -> void:
    if Meta.purchase_seal(node_id):
        _refresh()


func _make_spacer() -> Control:
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return spacer
