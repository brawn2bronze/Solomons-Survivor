class_name ActBanner
extends CanvasLayer
## Act intro banner: "ACT II" / title / subtitle, fading in over 0.4s, holding
## ~2.6s, fading out over 0.6s. Shown at run start and at every begin_act.
## Placed around y=230 so it clears the existing announce label at y=150.

signal done

var _root: Control
var _num: Label
var _title: Label
var _sub: Label
var _state := 0
var _t := 0.0
var _alpha := 0.0


func _ready() -> void:
    layer = 12
    process_mode = Node.PROCESS_MODE_ALWAYS
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)
    _num = UI.label("", 64, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    _num.position = Vector2(0, 230)
    _num.size = Vector2(_vp().x, 72)
    _root.add_child(_num)
    _title = UI.label("", 40, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
    _title.position = Vector2(0, 300)
    _title.size = Vector2(_vp().x, 48)
    _root.add_child(_title)
    _sub = UI.label("", 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
    _sub.position = Vector2(0, 350)
    _sub.size = Vector2(_vp().x, 28)
    _root.add_child(_sub)
    _num.modulate.a = 0.0
    _title.modulate.a = 0.0
    _sub.modulate.a = 0.0


func _vp() -> Vector2:
    return Vector2(get_viewport().get_visible_rect().size)


func show_act(act: ActDef) -> void:
    if act == null:
        return
    _num.text = act.display_name
    _title.text = act.title
    _sub.text = act.subtitle
    _state = 1
    _t = 0.0
    _alpha = 0.0


func _process(delta: float) -> void:
    if _state == 0:
        return
    var want := _vp()
    for l in [_num, _title, _sub]:
        l.size.x = want.x
    _t += delta
    if _state == 1:
        _alpha = minf(1.0, _alpha + delta / 0.4)
        if _alpha >= 1.0:
            _state = 2
            _t = 0.0
    elif _state == 2:
        if _t >= 2.6:
            _state = 3
            _t = 0.0
    elif _state == 3:
        _alpha = maxf(0.0, _alpha - delta / 0.6)
        if _alpha <= 0.0:
            _state = 0
            done.emit()
    _num.modulate.a = _alpha
    _title.modulate.a = _alpha
    _sub.modulate.a = _alpha
