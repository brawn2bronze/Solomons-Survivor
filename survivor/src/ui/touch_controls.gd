class_name TouchControls
extends CanvasLayer
## Phone controls: a transparent floating joystick that anchors wherever the player
## touches (whole screen), plus an on-screen pause button. Visibility follows
## Game.touch_controls_mode (auto/on/off); keyboard play is unaffected - Player
## blends move_vector with Input.get_vector every frame.
## Sits at layer 15: above the HUD (10), below modal pickers (30+) and pause (40).

const BASE_R := 56.0    ## drawn base-ring radius (anchor -> full deflection is TRAVEL)
const KNOB_R := 22.0    ## drawn knob radius
const TRAVEL := 48.0    ## knob offset from anchor at full deflection
const DEADZONE := 0.15  ## fraction of travel that reads as neutral
const RING_COL := Color(0.94, 0.77, 0.36, 0.45)
const KNOB_COL := Color(0.96, 0.94, 0.88, 0.3)
const SHADOW_COL := Color(0.045, 0.04, 0.07, 0.35)


## Full-rect input catcher that also draws the joystick. Touch events arrive through
## gui_input with positions already relative to this control (stretch-safe), and any
## control above it (pause button, modal screens) consumes its own touches first.
class _JoystickView extends Control:
    var tc: TouchControls

    func _gui_input(event: InputEvent) -> void:
        if tc != null:
            tc.handle_event(event)

    func _draw() -> void:
        if tc == null or tc._pointer == -1:
            return
        var c: Vector2 = tc._anchor
        draw_circle(c, TouchControls.BASE_R + 6.0, TouchControls.SHADOW_COL)
        draw_arc(c, TouchControls.BASE_R, 0.0, TAU, 48, TouchControls.RING_COL, 3.0, true)
        draw_circle(c + tc._knob, TouchControls.KNOB_R, TouchControls.SHADOW_COL)
        draw_circle(c + tc._knob, TouchControls.KNOB_R - 3.0, TouchControls.KNOB_COL)


var world
var move_vector := Vector2.ZERO   ## normalized direction, length <= 1; Player reads it every frame

var _enabled := false
var _pointer := -1                ## tracked finger index; -1 = idle
var _anchor := Vector2.ZERO       ## touch-down point (local canvas coords)
var _knob := Vector2.ZERO         ## knob offset from _anchor, clamped to TRAVEL
var _view: _JoystickView
var _pause_b: Button


func setup(world_ref) -> void:
    world = world_ref
    layer = 15
    _view = _JoystickView.new()
    _view.tc = self
    _view.set_anchors_preset(Control.PRESET_FULL_RECT)
    _view.mouse_filter = Control.MOUSE_FILTER_STOP   # re-toggled by _refresh()
    add_child(_view)
    _pause_b = UI.button("II", 24, Vector2(52, 52))
    _pause_b.focus_mode = Control.FOCUS_NONE
    _pause_b.pressed.connect(_on_pause_pressed)
    add_child(_pause_b)
    get_viewport().size_changed.connect(_relayout)
    Game.touch_mode_changed.connect(_refresh)
    _refresh()
    _relayout()


func handle_event(event: InputEvent) -> void:
    if not _enabled:
        return
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            if _pointer == -1 and _can_accept():
                _pointer = t.index
                _anchor = t.position
                _knob = Vector2.ZERO
                move_vector = Vector2.ZERO
                _view.queue_redraw()
        elif t.index == _pointer:
            _end_drag()
    elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _pointer:
        _knob = ((event as InputEventScreenDrag).position - _anchor).limit_length(TRAVEL)
        var v := _knob / TRAVEL
        if v.length() < DEADZONE:
            move_vector = Vector2.ZERO
        else:
            move_vector = v.normalized() * ((v.length() - DEADZONE) / (1.0 - DEADZONE))
        _view.queue_redraw()


## Only live gameplay accepts a new joystick anchor (no joystick under menus,
## drafts, pause, or the game-over beat; pause also suspends this node's input).
func _can_accept() -> bool:
    return world != null and world.sim_running and not get_tree().paused


func _end_drag() -> void:
    _pointer = -1
    _knob = Vector2.ZERO
    move_vector = Vector2.ZERO
    if _view != null:
        _view.queue_redraw()


func _on_pause_pressed() -> void:
    if get_tree().paused or world == null:
        return
    world.try_pause()


## Reacts to the Options touch-mode change: show/hide and stop eating touches when off.
func _refresh() -> void:
    if _view == null:
        return
    _enabled = Game.touch_enabled()
    _view.visible = _enabled
    _view.mouse_filter = Control.MOUSE_FILTER_STOP if _enabled else Control.MOUSE_FILTER_IGNORE
    _pause_b.visible = _enabled
    if not _enabled:
        _end_drag()


func _relayout() -> void:
    if _pause_b == null:
        return
    var vsz := get_viewport().get_visible_rect().size
    _pause_b.position = Vector2(vsz.x - 64.0, 96.0)   # under the kills/coin stack, clear of HUD text
