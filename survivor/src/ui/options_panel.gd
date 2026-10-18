class_name OptionsPanel
extends VBoxContainer
## Volume sliders (persisted by the audio manager) + game-feel sliders (shake / hitstop / flash,
## persisted by Game) + fullscreen toggle. Used by main menu and pause menu.

## [row label, Game property] - each property is a 0..1 strength.
const FX_ROWS := [["SHAKE", "fx_shake"], ["HITSTOP", "fx_hitstop"], ["FLASH", "fx_flash"]]

var _fs: CheckButton


func _ready() -> void:
    add_theme_constant_override("separation", 14)
    add_child(UI.label("OPTIONS", 30, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    for ch in ["master", "music", "sfx"]:
        _slider(ch)
    for row in FX_ROWS:
        _fx_slider(String(row[0]), String(row[1]))
    _fs = CheckButton.new()
    _fs.text = "Fullscreen"
    _fs.add_theme_font_size_override("font_size", 20)
    _fs.toggled.connect(_on_fullscreen)
    add_child(_fs)
    call_deferred("_sync_fullscreen")
    _touch_row()


## On-screen joystick + pause button: Auto (touch devices), On (force, e.g. desktop testing), Off.
func _touch_row() -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var l := UI.label("TOUCH", 20, UI.TEXT)
    l.custom_minimum_size = Vector2(110, 0)
    row.add_child(l)
    var pick := OptionButton.new()
    pick.add_item("Auto", 0)
    pick.add_item("On", 1)
    pick.add_item("Off", 2)
    pick.select(clampi(Game.touch_controls_mode, 0, 2))
    pick.add_theme_font_size_override("font_size", 18)
    pick.custom_minimum_size = Vector2(240, 32)
    pick.item_selected.connect(_on_touch_mode)
    row.add_child(pick)
    add_child(row)


func _on_touch_mode(idx: int) -> void:
    Game.set_touch_mode(idx)
    Audio.sfx("button_click")


func _sync_fullscreen() -> void:
    if _fs == null or not is_inside_tree():
        return
    var w := get_window()
    if w == null:
        return
    var is_fs := w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
    _fs.set_pressed_no_signal(is_fs)


func _on_fullscreen(on: bool) -> void:
    # Borderless MODE_FULLSCREEN: works from editor Play and exported builds alike,
    # unlike EXCLUSIVE which asks the display driver to switch resolutions and is
    # often silently ignored (checkbox flips, window does nothing).
    var w := get_window()
    if w != null:
        w.mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
    Audio.sfx("button_click")
    call_deferred("_verify_fullscreen", on)


func _verify_fullscreen(wanted: bool) -> void:
    # If the switch failed, uncheck the box instead of lying about the state.
    if _fs == null or not is_inside_tree():
        return
    var w := get_window()
    if w == null:
        return
    var is_fs := w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
    _fs.set_pressed_no_signal(is_fs)
    if is_fs != wanted:
        push_warning("OptionsPanel: fullscreen request failed (wanted=%s, mode=%d)" % [str(wanted), int(w.mode)])


func _on_volume(v: float, channel: String) -> void:
    Audio.set_volume(channel, v)
    if channel != "music":
        Audio.sfx("xp_pickup", -6.0)


func _slider(channel: String) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var l := UI.label(channel.to_upper(), 20, UI.TEXT)
    l.custom_minimum_size = Vector2(110, 0)
    row.add_child(l)
    var s := HSlider.new()
    s.min_value = 0.0
    s.max_value = 1.0
    s.step = 0.05
    s.value = Audio.volume[channel]
    s.custom_minimum_size = Vector2(240, 28)
    s.value_changed.connect(_on_volume.bind(channel))
    row.add_child(s)
    add_child(row)


func _fx_slider(label: String, key: String) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var l := UI.label(label, 20, UI.TEXT)
    l.custom_minimum_size = Vector2(110, 0)
    row.add_child(l)
    var s := HSlider.new()
    s.min_value = 0.0
    s.max_value = 1.0
    s.step = 0.05
    s.value = float(Game.get(key))
    s.custom_minimum_size = Vector2(240, 28)
    s.value_changed.connect(_on_fx_value.bind(key))
    row.add_child(s)
    add_child(row)


func _on_fx_value(v: float, key: String) -> void:
    Game.set(key, v)
    Game.save_fx_settings()
