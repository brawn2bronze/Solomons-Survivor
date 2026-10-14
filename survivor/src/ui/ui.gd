class_name UI
extends RefCounted
## Shared look for every screen: dark ink panels, gold trim, hard pixel borders, outlined text.

const GOLD := Color(0.94, 0.77, 0.36)
const INK := Color(0.045, 0.04, 0.07)
const PANEL := Color(0.09, 0.08, 0.14, 0.97)
const PANEL_LIGHT := Color(0.14, 0.12, 0.2, 0.98)
const TEXT := Color(0.96, 0.94, 0.88)
const DIM := Color(0.66, 0.64, 0.74)
const RED := Color(0.86, 0.22, 0.26)
const GREEN := Color(0.4, 0.85, 0.5)
const BLUE := Color(0.35, 0.6, 0.95)
const PURPLE := Color(0.7, 0.45, 0.95)
const BRONZE := Color(0.72, 0.5, 0.26)
const CRIMSON := Color(0.75, 0.12, 0.2)
const DEEP_PURPLE := Color(0.16, 0.08, 0.28)
const GLITCH_CYAN := Color(0.3, 0.95, 0.95)
const ESSENCE := Color(0.65, 0.35, 0.95)

const STAT_LABELS := {"max_hp": "HP", "move_speed": "SPEED", "damage": "DAMAGE", "defense": "ARMOR", "regen": "REGEN", "area": "AREA", "cooldown": "COOLDOWN", "pickup_radius": "MAGNET", "luck": "LUCK"}


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 2, pad: int = 8) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.border_color = border
    sb.set_border_width_all(bw)
    sb.set_content_margin_all(pad)
    sb.set_corner_radius_all(0)
    return sb


static func label(text: String, size: int = 16, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var l := Label.new()
    l.text = text
    l.horizontal_alignment = align
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.add_theme_color_override("font_outline_color", INK)
    l.add_theme_constant_override("outline_size", maxi(2, size / 6))
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return l


static func wrap_label(text: String, size: int, color: Color, width: float) -> Label:
    var l := label(text, size, color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.custom_minimum_size = Vector2(width, 0)
    return l


static func button(text: String, size: int = 22, min_size: Vector2 = Vector2(280, 54)) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = min_size
    b.focus_mode = Control.FOCUS_ALL
    b.add_theme_font_size_override("font_size", size)
    b.add_theme_color_override("font_color", TEXT)
    b.add_theme_color_override("font_hover_color", GOLD)
    b.add_theme_color_override("font_focus_color", GOLD)
    b.add_theme_color_override("font_pressed_color", Color.WHITE)
    b.add_theme_color_override("font_outline_color", INK)
    b.add_theme_constant_override("outline_size", 4)
    b.add_theme_stylebox_override("normal", box(PANEL_LIGHT, Color(0.36, 0.3, 0.46)))
    b.add_theme_stylebox_override("hover", box(Color(0.22, 0.18, 0.3), GOLD))
    b.add_theme_stylebox_override("focus", box(Color(0.22, 0.18, 0.3), GOLD))
    b.add_theme_stylebox_override("pressed", box(Color(0.3, 0.24, 0.38), Color.WHITE))
    b.pressed.connect(func() -> void: Audio.sfx("button_click", -4.0))
    b.mouse_entered.connect(b.grab_focus)
    return b


static func bar(fill: Color, bg: Color = Color(0.08, 0.07, 0.1), border: Color = INK) -> ProgressBar:
    var pb := ProgressBar.new()
    pb.show_percentage = false
    pb.min_value = 0.0
    pb.max_value = 1.0
    pb.step = 0.0
    pb.add_theme_stylebox_override("background", box(bg, border, 2, 0))
    pb.add_theme_stylebox_override("fill", box(fill, Color(0, 0, 0, 0), 0, 0))
    pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return pb


static func panel(bg: Color = PANEL, border: Color = GOLD, bw: int = 3, pad: int = 14) -> PanelContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", box(bg, border, bw, pad))
    return p


## Turns {"stat": ["mul"|"add"|"set", v]} into short readable text, e.g. "+10% damage, -20% reload time".
static func describe_ops(ops: Dictionary) -> String:
    var parts: Array[String] = []
    for k in ops.keys():
        var o: Array = ops[k]
        var nm := String(k).replace("_", " ")
        var v: float = float(o[1])
        match String(o[0]):
            "mul":
                var pct := int(round((v - 1.0) * 100.0))
                parts.append("%s%d%% %s" % ["+" if pct >= 0 else "", pct, nm])
            "add":
                parts.append("%s%s %s" % ["+" if v >= 0.0 else "", _num(v), nm])
            "set":
                parts.append("%s = %s" % [nm, _num(v)])
    return ", ".join(parts)


static func _num(v: float) -> String:
    return str(int(v)) if absf(v - round(v)) < 0.001 else "%.2f" % v
