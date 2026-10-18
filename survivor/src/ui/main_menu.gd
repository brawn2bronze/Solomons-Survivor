class_name MainMenu
extends CanvasLayer
## Title screen v2 - "The Corrupted Archive".
## A rotating Solomon's Seal on the right with the roster's survivors showcased on it (auto-cycling,
## glitch-sliced swaps), scripture-glyph rain, god rays and embers behind, the playable roster marching
## along the ground with the enemy horde's silhouettes opposing them in the back. Everything breathes with
## the menu song via baked curves (MenuMusicCurve): bass pulses the seal and title, hits fire glitch bursts
## and (on the strong ones) lightning, the song's build and climax drive how much is going on.
## A full-screen glitch shader (RGB split, slice tears, scanlines, grain, vignette) sits on top.
## First launch plays a ~6s intro timed to the song's fade-in; later visits replay it at 6x speed.
## Public API is unchanged: signals play / dev / market / seal / quit.

signal play
signal dev
signal market
signal seal
signal quit

const MENU_TRACK := "menu_music"
const HERO_PERIOD := 6.5          # seconds each survivor is showcased before the carousel advances
const SWAP_TIME := 0.6            # glitch-slice transition between survivors
const SLAM_T := 4.2               # intro time at which the title slams in
const INTRO_LEN := 6.2
const HIT_THRESHOLD := 0.5
const MAX_EMBERS := 240
const GLYPH_KINDS := 36
const RAIN_COL_W := 46.0
const RAIN_ROWS := 14
const RING_GLYPHS := 24

const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float glitch = 0.0;
uniform float aberr = 0.0012;
uniform float flash = 0.0;
uniform float time_s = 0.0;
uniform float vig = 0.4;
uniform float scan = 0.05;
uniform float grain = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 30.0);
	float tick = floor(time_s * 16.0);
	float h = hash(vec2(band, tick));
	float tear = step(1.0 - glitch * 0.45, h) * (hash(vec2(band + 11.0, tick)) - 0.5) * 0.12 * glitch;
	uv.x += tear;
	float split = aberr + glitch * 0.006 + step(0.92, h) * glitch * 0.012;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	col *= 1.0 - scan * mod(floor(FRAGCOORD.y), 2.0);
	float d = distance(SCREEN_UV, vec2(0.5));
	col *= 1.0 - vig * smoothstep(0.32, 0.9, d);
	col += (hash(SCREEN_UV * 931.0 + time_s) - 0.5) * grain;
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(col, 1.0);
}
"""

static var _intro_seen := false    # full cinematic intro once per launch

var _vsz := Vector2(1280, 720)
var _t := 0.0
var _intro_t := 0.0
var _intro_speed := 1.0
var _slammed := false
var _slam := 0.0

# song-driven signals, all 0..1
var _mood := 0.3
var _low_s := 0.0
var _hit_prev := 0.0
var _hit_cd := 0.0
var _glitch := 0.0
var _flash := 0.0
var _seal_kick := 0.0
var _bolt_cd := 0.0
var _bolts: Array = []
var _ember_acc := 0.0
var _corrupt_t := 0.0
var _leaving := false             # a screen transition is running; input is swallowed
var _leave_k := 0.0               # 0..1 fade-to-black used by the transition

# scene nodes
var _back: Stage
var _glow: Stage
var _front: Stage
var _veil: ColorRect
var _post_mat: ShaderMaterial
var _title: Label
var _title_r: Label
var _title_c: Label
var _sub: Label
var _title_base := Vector2.ZERO
var _menu_box: VBoxContainer
var _menu_left := 80.0
var _buttons: Array = []
var _bm_hint: Label
var _seal_hint: Label
var _name_l: Label
var _role_l: Label
var _opts_overlay: Control
var _opts: OptionsPanel
var _opts_back: Button

# content
var _glyphs: Array = []
var _gp := PackedVector2Array()        # scratch buffers for batched glyph drawing
var _gc := PackedColorArray()
var _rain: Array = []
var _embers: Array = []
var _ring_gl: Array = []
var _roster: Array = []
var _hero_tex: Array = []
var _hero_i := 0
var _hero_t := 0.0
var _hero_a := 0.0
var _swap_t := -1.0
var _swap_to := 0
var _walkers: Array = []
var _foes: Array = []
var _foe_span := 1800.0
var _seal_draw := 0.0
var _title_text := "SOLOMON'S"


class Stage extends Node2D:
    var owner_menu
    var stage_id := 0

    func _draw() -> void:
        if owner_menu != null:
            owner_menu.paint(self, stage_id)


func _ready() -> void:
    layer = 5
    _vsz = get_viewport().get_visible_rect().size
    _intro_speed = 6.0 if _intro_seen else 1.0
    _intro_seen = true
    _make_glyphs()
    _make_rain()
    _load_sprites()
    var bg := ColorRect.new()
    bg.color = Color(0.03, 0.015, 0.06)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)
    _back = _make_stage(0, false)
    _glow = _make_stage(1, true)
    _front = _make_stage(2, false)
    _build_title()
    _build_menu()
    _build_plate()
    _build_options()
    _veil = ColorRect.new()
    _veil.color = Color(0, 0, 0, 1)
    _veil.set_anchors_preset(Control.PRESET_FULL_RECT)
    _veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_veil)
    _build_post()
    get_viewport().size_changed.connect(_layout)
    _layout()
    Audio.music(MENU_TRACK)
    if not _buttons.is_empty():
        (_buttons[0] as Button).grab_focus()


# ------------------------------------------------------------------ construction
func _make_stage(id: int, additive: bool) -> Stage:
    var s := Stage.new()
    s.owner_menu = self
    s.stage_id = id
    if additive:
        var m := CanvasItemMaterial.new()
        m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        s.material = m
    add_child(s)
    return s


func _title_label(col: Color, ghost: bool) -> Label:
    var l := UI.label(_title_text, 96, col, HORIZONTAL_ALIGNMENT_LEFT)
    if ghost:
        l.add_theme_constant_override("outline_size", 0)
        var m := CanvasItemMaterial.new()
        m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        l.material = m
    add_child(l)
    l.modulate.a = 0.0
    return l


func _build_title() -> void:
    _title_r = _title_label(Color(1.0, 0.12, 0.2, 0.6), true)
    _title_c = _title_label(Color(0.2, 0.9, 1.0, 0.6), true)
    _title = _title_label(UI.GOLD, false)
    _sub = UI.label("S U R V I V O R", 54, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
    _sub.add_theme_constant_override("outline_size", 10)
    _sub.modulate.a = 0.0
    add_child(_sub)


func _add_btn(text: String, size: int, min_size: Vector2) -> Button:
    var b := UI.button(text, size, min_size)
    b.self_modulate.a = 0.0
    b.focus_entered.connect(_on_btn_focus)
    _menu_box.add_child(b)
    _buttons.append(b)
    return b


func _build_menu() -> void:
    _menu_box = VBoxContainer.new()
    _menu_box.add_theme_constant_override("separation", 8)
    add_child(_menu_box)
    var pb := _add_btn("Play", 30, Vector2(300, 56))
    pb.pressed.connect(_go.bind(play))
    var mb := _add_btn("Forbidden Archive", 24, Vector2(300, 46))
    mb.pressed.connect(_on_market_pressed)
    if not Meta.market_unlocked:
        mb.text = "Forbidden Archive  [SEALED]"
        mb.modulate = Color(0.62, 0.62, 0.7)
    _bm_hint = UI.label("", 15, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT)
    _bm_hint.visible = false
    _menu_box.add_child(_bm_hint)
    var sb := _add_btn("Solomon's Seal", 24, Vector2(300, 46))
    sb.pressed.connect(_on_seal_pressed)
    if not Meta.market_unlocked:
        sb.text = "Solomon's Seal  [SEALED]"
        sb.modulate = Color(0.62, 0.62, 0.7)
    _seal_hint = UI.label("", 15, UI.DIM, HORIZONTAL_ALIGNMENT_LEFT)
    _seal_hint.visible = false
    _menu_box.add_child(_seal_hint)
    if Game.DEV_MODE_ENABLED:
        var db := _add_btn("Dev Mode", 22, Vector2(300, 44))
        db.pressed.connect(func() -> void: dev.emit())
    var ob := _add_btn("Options", 26, Vector2(300, 46))
    ob.pressed.connect(_toggle_opts)
    var qb := _add_btn("Quit", 26, Vector2(300, 46))
    qb.pressed.connect(func() -> void: quit.emit())


func _build_plate() -> void:
    _name_l = UI.label("", 40, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
    _name_l.add_theme_constant_override("outline_size", 8)
    _name_l.custom_minimum_size = Vector2(640, 0)
    _name_l.modulate.a = 0.0
    add_child(_name_l)
    _role_l = UI.label("", 20, UI.DIM, HORIZONTAL_ALIGNMENT_CENTER)
    _role_l.custom_minimum_size = Vector2(640, 0)
    _role_l.modulate.a = 0.0
    add_child(_role_l)
    _apply_plate()


func _build_options() -> void:
    _opts_overlay = Control.new()
    _opts_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _opts_overlay.visible = false
    add_child(_opts_overlay)
    var dim := ColorRect.new()
    dim.color = Color(0.02, 0.01, 0.05, 0.78)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _opts_overlay.add_child(dim)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _opts_overlay.add_child(center)
    var wrap := UI.panel(UI.PANEL, UI.GOLD, 3, 22)
    center.add_child(wrap)
    _opts = OptionsPanel.new()
    wrap.add_child(_opts)
    _opts_back = UI.button("Back", 22, Vector2(200, 46))
    _opts_back.pressed.connect(_toggle_opts)
    _opts.add_child(_opts_back)


func _build_post() -> void:
    var pl := CanvasLayer.new()
    pl.layer = 6
    add_child(pl)
    var rect := ColorRect.new()
    rect.color = Color(0, 0, 0, 0)        # if the shader ever fails to compile this stays invisible
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sh := Shader.new()
    sh.code = POST_SHADER
    _post_mat = ShaderMaterial.new()
    _post_mat.shader = sh
    rect.material = _post_mat
    pl.add_child(rect)


func _layout() -> void:
    _vsz = get_viewport().get_visible_rect().size
    _menu_left = clampf(_vsz.x * 0.07, 36.0, 120.0)
    var fs: int = int(clampf(_vsz.y * 0.125, 60.0, 112.0))
    _title_base = Vector2(_menu_left, _vsz.y * 0.05)
    for l in [_title, _title_r, _title_c]:
        l.add_theme_font_size_override("font_size", fs)
        l.position = _title_base
    _title.add_theme_constant_override("outline_size", int(float(fs) * 0.16))
    _sub.add_theme_font_size_override("font_size", int(float(fs) * 0.5))
    _sub.position = Vector2(_menu_left + 6.0, _title_base.y + float(fs) * 1.12)
    _menu_box.position = Vector2(_menu_left, _vsz.y * 0.36)
    var sc := _seal_center()
    _name_l.position = Vector2(sc.x - 320.0, _plate_y())
    _role_l.position = Vector2(sc.x - 320.0, _plate_y() + 54.0)


func _plate_y() -> float:
    return _vsz.y * 0.03


func _seal_center() -> Vector2:
    return Vector2(_vsz.x * 0.70, _vsz.y * 0.47)


func _seal_radius() -> float:
    return minf(_vsz.y * 0.33, _vsz.x * 0.20)


# ------------------------------------------------------------------ content setup
func _make_glyphs() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 7731
    for g in GLYPH_KINDS:
        var pts := PackedVector2Array()
        var n: int = rng.randi_range(2, 4)
        var prev: int = rng.randi_range(0, 8)
        for k in n:
            var nxt: int = rng.randi_range(0, 8)
            while nxt == prev:
                nxt = rng.randi_range(0, 8)
            pts.append(_lattice(prev))
            pts.append(_lattice(nxt))
            prev = nxt if rng.randf() < 0.6 else rng.randi_range(0, 8)
        _glyphs.append(pts)
    for i in RING_GLYPHS:
        _ring_gl.append(randi() % GLYPH_KINDS)


func _lattice(i: int) -> Vector2:
    return Vector2(float(i % 3) - 1.0, floorf(float(i) / 3.0) - 1.0) * 0.5


func _rand_glyph_row(n: int) -> Array:
    var a: Array = []
    for i in n:
        a.append(randi() % GLYPH_KINDS)
    return a


func _make_rain() -> void:
    var n: int = int(ceil(2200.0 / RAIN_COL_W))
    for i in n:
        _rain.append({
            "x": float(i) * RAIN_COL_W + randf_range(-8.0, 8.0),
            "y": randf() * 900.0,
            "spd": randf_range(18.0, 46.0),
            "len": randi_range(6, 13),
            "off": randi() % RAIN_ROWS,
            "b": randf_range(0.5, 1.0),
            "gl": _rand_glyph_row(RAIN_ROWS),
        })


func _load_sprites() -> void:
    _roster = DB.playable_roster()
    for i in _roster.size():
        var cd: CharacterDef = _roster[i]
        var htex: Texture2D = DB.texture(cd.sprite)
        _hero_tex.append(htex)
        _walkers.append({"tex": htex, "x": -100.0 - float(i) * 150.0, "sp": randf_range(60.0, 90.0), "ph": randf() * 10.0})
    var ids: Array = DB.enemies.keys()
    ids.sort()
    var fx := 0.0
    for id in ids:
        var d = DB.enemies[id]
        if d == null:
            continue
        var path := String(d.sprite)
        if path == "":
            continue
        var etex: Texture2D = DB.texture(path)
        if etex == null:
            continue
        var frames: int = maxi(1, int(d.frames))
        var fw: float = float(etex.get_width()) / float(frames)
        var fh: float = float(etex.get_height())
        if fh <= 0.0 or fw <= 0.0:
            continue
        var target: float = clampf(fh * float(d.sprite_scale) * 1.1, 56.0, 190.0)
        _foes.append({"tex": etex, "fw": fw, "fh": fh, "k": target / fh, "frames": frames, "x": fx + randf_range(0.0, 80.0), "sp": randf_range(12.0, 26.0), "ph": randf() * 6.0})
        fx += 210.0
    _foe_span = maxf(fx, 1800.0)


func _apply_plate() -> void:
    if _roster.is_empty():
        return
    var c: CharacterDef = _roster[_hero_i]
    _name_l.text = String(c.display_name).to_upper()
    _name_l.add_theme_color_override("font_color", c.color.lightened(0.25))
    _role_l.text = String(c.title)


# ------------------------------------------------------------------ input
func _toggle_opts() -> void:
    _opts_overlay.visible = not _opts_overlay.visible
    if _opts_overlay.visible:
        _opts_back.grab_focus()
    elif not _buttons.is_empty():
        (_buttons[0] as Button).grab_focus()


func _input(event: InputEvent) -> void:
    if _leaving:
        get_viewport().set_input_as_handled()
        return
    if _opts_overlay != null and _opts_overlay.visible:
        if event.is_action_pressed("ui_cancel"):
            _toggle_opts()
            get_viewport().set_input_as_handled()
        return
    if _intro_t < SLAM_T and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
        _intro_t = SLAM_T            # any key / click skips ahead to the title slam
        get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed("ui_left"):
        _request_hero(_hero_i - 1)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("ui_right"):
        _request_hero(_hero_i + 1)
        get_viewport().set_input_as_handled()
    else:
        var mb := event as InputEventMouseButton
        if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.position.distance_to(_seal_center()) < _seal_radius() * 0.8:
                _request_hero(_hero_i + 1)


func _request_hero(i: int) -> void:
    if _roster.size() < 2 or _swap_t >= 0.0 or _hero_a < 0.5:
        return
    _swap_to = posmod(i, _roster.size())
    _swap_t = 0.0
    _hero_t = 0.0
    _glitch = maxf(_glitch, 0.55 * _flash_scale())
    Audio.sfx("button_click", -12.0, 1.4)


## Opens the Forbidden Archive, or explains how to unseal it while it is still sealed.
func _on_market_pressed() -> void:
    if Meta.market_unlocked:
        _go(market)
        return
    Audio.sfx("menu_close")
    _bm_hint.text = Meta.unlock_hint()
    _bm_hint.visible = true
    _glitch = maxf(_glitch, 0.6 * _flash_scale())      # "denied" jolt
    _corrupt_t = 0.12


## Opens Solomon's Seal, or explains how to unseal it while it is still sealed.
func _on_seal_pressed() -> void:
    if Meta.market_unlocked:
        _go(seal)
        return
    Audio.sfx("menu_close")
    _seal_hint.text = Meta.unlock_hint()
    _seal_hint.visible = true
    _glitch = maxf(_glitch, 0.6 * _flash_scale())      # "denied" jolt
    _corrupt_t = 0.12


## Leaves the title screen with a short glitch-out (fade to black), then emits the signal.
func _go(sig: Signal) -> void:
    if _leaving:
        return
    _leaving = true
    var ff: float = _flash_scale()
    _glitch = maxf(_glitch, 0.9 * ff)
    _flash = maxf(_flash, 0.2 * ff)
    _seal_kick = 1.0
    var tw := create_tween()
    tw.tween_property(self, "_leave_k", 1.0, 0.32)
    tw.tween_callback(_finish_go.bind(sig))


func _finish_go(sig: Signal) -> void:
    sig.emit()
    call_deferred("_reset_leave")


func _reset_leave() -> void:
    _leaving = false
    _leave_k = 0.0


## Tiny tactile tick whenever the focused menu entry changes (not during the intro).
func _on_btn_focus() -> void:
    if _intro_t < SLAM_T + 0.8:
        return
    _glitch = maxf(_glitch, 0.12 * _flash_scale())
    _seal_kick = maxf(_seal_kick, 0.25)


# ------------------------------------------------------------------ per-frame update
func _process(delta: float) -> void:
    delta = minf(delta, 0.05)
    _t += delta
    _vsz = get_viewport().get_visible_rect().size
    _step_intro(delta)
    _step_audio(delta)
    _step_stage(delta)
    _step_hero(delta)
    _step_ui(delta)
    _back.queue_redraw()
    _glow.queue_redraw()
    _front.queue_redraw()


func _step_intro(delta: float) -> void:
    _intro_t = minf(_intro_t + delta * _intro_speed, INTRO_LEN + 1.0)
    _seal_draw = smoothstep(1.2, 4.0, _intro_t)
    _hero_a = smoothstep(3.0, 4.4, _intro_t)
    if not _slammed and _intro_t >= SLAM_T:
        _slammed = true
        _slam = 1.0
        _glitch = _flash_scale()
        _flash = 0.3 * _flash_scale()
        _seal_kick = 1.0
        _burst_embers(36, 1.0)
        _lightning()
        if _intro_speed < 2.0:
            Audio.sfx("elite_enemy_spawn", -6.0, 0.8)


## Reads the baked song curves at the live playback position (or a synthetic ~100 BPM pulse if the
## song isn't audible), updates the smoothed signals and fires hit events on rising edges.
func _step_audio(delta: float) -> void:
    var mt: float = -1.0
    if Audio.has_method("music_time"):
        mt = float(Audio.call("music_time"))      # dynamic call: works even before audio_manager.gd is updated
    var low: float
    var hit: float
    if mt >= 0.0:
        var s: Vector3 = MenuMusicCurve.sample(mt)
        _mood = lerpf(_mood, s.x, 1.0 - exp(-delta * 4.0))
        low = s.y
        hit = s.z
    else:
        var beat: float = _t * (100.0 / 60.0)
        _mood = lerpf(_mood, 0.5 + 0.2 * sin(_t * 0.1), 1.0 - exp(-delta * 2.0))
        low = pow(1.0 - fposmod(beat, 1.0), 3.0) * 0.8
        hit = 0.7 if (fposmod(beat, 1.0) < 0.1 and int(beat) % 4 == 0) else 0.0
    var k: float = 40.0 if low > _low_s else 10.0
    _low_s = lerpf(_low_s, low, 1.0 - exp(-delta * k))
    _hit_cd -= delta
    _bolt_cd -= delta
    if hit >= HIT_THRESHOLD and _hit_prev < HIT_THRESHOLD and _hit_cd <= 0.0 and _intro_t > 1.5:
        _hit_cd = 0.18
        _on_hit(hit)
    _hit_prev = hit
    _glitch *= exp(-delta * 5.0)
    if _glitch < 0.01:
        _glitch = 0.0
    _flash *= exp(-delta * 6.0)
    _seal_kick *= exp(-delta * 7.0)
    _slam *= exp(-delta * 4.0)


func _on_hit(s: float) -> void:
    var ff: float = _flash_scale()
    _glitch = maxf(_glitch, (0.25 + 0.55 * s) * ff)
    _seal_kick = maxf(_seal_kick, s)
    _burst_embers(5 + int(10.0 * s), s)
    if randf() < 0.35:
        _corrupt_t = 0.09
    for i in 2:
        _ring_gl[randi() % RING_GLYPHS] = randi() % GLYPH_KINDS
    if s >= 0.85 and _mood > 0.4 and _bolt_cd <= 0.0 and _intro_t > SLAM_T + 0.3:
        _bolt_cd = 1.4
        _lightning()
        _flash = maxf(_flash, 0.14 * ff)


func _flash_scale() -> float:
    var v = Game.get("fx_flash")
    if v == null:
        return 1.0
    return clampf(float(v), 0.0, 1.0)


func _burst_embers(n: int, s: float) -> void:
    var sc := _seal_center()
    var rad := _seal_radius()
    for i in n:
        var a: float = randf() * TAU
        var p: Vector2 = sc + Vector2.from_angle(a) * rad * randf_range(0.85, 1.0)
        var v: Vector2 = Vector2.from_angle(a) * randf_range(20.0, 80.0) * (0.6 + 0.6 * s) + Vector2(0.0, -30.0)
        _spawn_ember(p, v, randf_range(0.6, 1.3), randf_range(1.2, 2.6), Color(1.0, 0.55 + randf() * 0.35, 0.25))


func _spawn_ember(p: Vector2, v: Vector2, life: float, r: float, col: Color) -> void:
    if _embers.size() >= MAX_EMBERS:
        _embers.remove_at(0)
    _embers.append({"p": p, "v": v, "life": life, "max": life, "r": r, "col": col, "ph": randf() * TAU})


func _lightning() -> void:
    var sc := _seal_center()
    var x: float = sc.x + randf_range(-_seal_radius() * 1.3, _seal_radius() * 1.3)
    var y := -20.0
    var end_y: float = sc.y + _seal_radius() * randf_range(0.2, 0.7)
    var pts := PackedVector2Array()
    pts.append(Vector2(x, y))
    var steps := 12
    for i in steps:
        y += (end_y + 20.0) / float(steps)
        x += randf_range(-34.0, 34.0)
        pts.append(Vector2(x, y))
    _bolts.append({"pts": pts, "life": 0.22, "max": 0.22})


func _step_stage(delta: float) -> void:
    # ambient embers rise faster and thicker as the song builds
    _ember_acc += delta * (6.0 + 34.0 * _mood)
    while _ember_acc >= 1.0:
        _ember_acc -= 1.0
        var col := Color(0.95, 0.25, 0.35) if randf() < 0.55 else (Color(0.95, 0.7, 0.3) if randf() < 0.6 else Color(0.6, 0.35, 1.0))
        _spawn_ember(Vector2(randf() * _vsz.x, _vsz.y + 10.0), Vector2(randf_range(-12.0, 12.0), -randf_range(30.0, 80.0) * (0.6 + 0.8 * _mood)), randf_range(4.0, 7.0), randf_range(1.0, 3.0), col)
    var i := _embers.size() - 1
    while i >= 0:
        var e: Dictionary = _embers[i]
        var v: Vector2 = e["v"]
        v.x += sin(_t * 0.9 + float(e["ph"])) * 10.0 * delta
        e["v"] = v
        e["p"] = Vector2(e["p"]) + v * delta
        e["life"] = float(e["life"]) - delta
        if float(e["life"]) <= 0.0:
            _embers.remove_at(i)
        i -= 1
    # scripture rain
    for rc in _rain:
        rc["y"] = float(rc["y"]) + float(rc["spd"]) * (0.6 + 0.9 * _mood) * delta
        if float(rc["y"]) - float(rc["len"]) * 21.0 > _vsz.y + 30.0:
            rc["y"] = -randf_range(0.0, 200.0)
            rc["gl"] = _rand_glyph_row(RAIN_ROWS)
            rc["len"] = randi_range(6, 13)
            rc["off"] = randi() % RAIN_ROWS
        if randf() < delta * (0.7 + 6.0 * _glitch):
            var g: Array = rc["gl"]
            g[randi() % RAIN_ROWS] = randi() % GLYPH_KINDS
    # parades
    for wk in _walkers:
        wk["x"] = float(wk["x"]) + float(wk["sp"]) * delta
        if float(wk["x"]) > _vsz.x + 140.0:
            wk["x"] = -120.0
    for f in _foes:
        f["x"] = float(f["x"]) - float(f["sp"]) * (0.7 + 0.8 * _mood) * delta
        if float(f["x"]) + float(f["fw"]) * float(f["k"]) < -40.0:
            f["x"] = float(f["x"]) + _foe_span
    var b := _bolts.size() - 1
    while b >= 0:
        var bd: Dictionary = _bolts[b]
        bd["life"] = float(bd["life"]) - delta
        if float(bd["life"]) <= 0.0:
            _bolts.remove_at(b)
        b -= 1


func _step_hero(delta: float) -> void:
    if _roster.size() < 2:
        return
    if _swap_t >= 0.0:
        var prev := _swap_t
        _swap_t += delta / SWAP_TIME
        if prev < 0.5 and _swap_t >= 0.5:
            _hero_i = _swap_to
            _apply_plate()
            _burst_embers(14, 0.8)
        if _swap_t >= 1.0:
            _swap_t = -1.0
    else:
        _hero_t += delta
        if _hero_t >= HERO_PERIOD and _intro_t > INTRO_LEN:
            _request_hero(_hero_i + 1)


func _step_ui(delta: float) -> void:
    var it: float = _intro_t
    _veil.color.a = maxf(1.0 - smoothstep(0.0, 1.6, it), _leave_k)
    # title: corrupt flicker, chromatic ghosts, slam
    _corrupt_t -= delta
    var txt: String = _title_text if _corrupt_t <= 0.0 else _corrupt(_title_text)
    if _title.text != txt:
        _title.text = txt
        _title_r.text = txt
        _title_c.text = txt
    var title_a: float = clampf((it - SLAM_T) / 0.25, 0.0, 1.0)
    var gs: float = 2.0 + 12.0 * _glitch
    var jx: float = randf_range(-1.0, 1.0) * _glitch * 4.0
    var ts: float = 1.0 + 0.012 * _low_s + 0.22 * _slam
    for l in [_title, _title_r, _title_c]:
        l.modulate.a = title_a
        l.scale = Vector2(ts, ts)
        l.pivot_offset = Vector2(0.0, l.size.y * 0.5)
    _title.position = _title_base + Vector2(jx, 0.0)
    _title_r.position = _title_base + Vector2(-gs, 0.0)
    _title_c.position = _title_base + Vector2(gs, 0.0)
    _sub.modulate.a = clampf((it - SLAM_T - 0.3) / 0.6, 0.0, 1.0)
    # menu entries stagger in after the slam
    var n := _buttons.size()
    for i in n:
        var btn := _buttons[i] as Button
        btn.self_modulate.a = clampf((it - SLAM_T - 0.5 - float(i) * 0.14) / 0.45, 0.0, 1.0)
    _menu_box.position.x = _menu_left - 30.0 * (1.0 - clampf((it - SLAM_T - 0.4) / 0.6, 0.0, 1.0))
    # name plate follows the showcase, dips during a swap
    var amp: float = 0.0
    if _swap_t >= 0.0:
        amp = sin(clampf(_swap_t, 0.0, 1.0) * PI)
    _name_l.modulate.a = _hero_a * (1.0 - amp)
    _role_l.modulate.a = _hero_a * (1.0 - amp)
    # glitch shader
    var ff: float = _flash_scale()
    _post_mat.set_shader_parameter("glitch", clampf(_glitch, 0.0, 1.0))
    _post_mat.set_shader_parameter("flash", clampf(_flash, 0.0, 0.5) * ff)
    _post_mat.set_shader_parameter("time_s", _t)
    _post_mat.set_shader_parameter("aberr", 0.0010 + 0.0016 * _low_s)


func _corrupt(s: String) -> String:
    var out := s
    var pool := "01#?/\\|<>=+"
    for k in 2:
        var i: int = randi() % out.length()
        out = out.substr(0, i) + pool[randi() % pool.length()] + out.substr(i + 1)
    return out


# ------------------------------------------------------------------ painting
func paint(c: Node2D, id: int) -> void:
    match id:
        0:
            _paint_back(c)
        1:
            _paint_glow(c)
        2:
            _paint_front(c)


func _paint_back(c: Node2D) -> void:
    var w: float = _vsz.x
    var h: float = _vsz.y
    var top := Color(0.02, 0.01, 0.05)
    var bot := Color(0.12, 0.04, 0.16)
    c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]), PackedColorArray([top, top, bot, bot]))
    _paint_rain(c)
    _fog(c, h * 0.50, h * 0.32, 14.0, Color(0.30, 0.12, 0.48), 0.10 + 0.10 * _mood)
    var gy: float = h - 70.0
    c.draw_rect(Rect2(-4, gy, w + 8, 74), Color(0.07, 0.04, 0.13))
    c.draw_rect(Rect2(-4, gy, w + 8, 3), UI.BRONZE)
    _paint_foes(c, gy)


func _paint_rain(c: Node2D) -> void:
    var base_a: float = (0.07 + 0.13 * _mood) * (0.6 + 0.4 * _seal_draw)
    var step := 21.0
    for rc in _rain:
        var x: float = rc["x"]
        if x > _vsz.x + 30.0:
            continue
        var head: float = rc["y"]
        var n: int = rc["len"]
        var gl: Array = rc["gl"]
        var bright: float = rc["b"]
        var off: int = rc["off"]
        _gp.clear()
        _gc.clear()
        for k in n:
            var gy: float = head - float(k) * step
            if gy < -20.0 or gy > _vsz.y + 20.0:
                continue
            var f: float = 1.0 - float(k) / float(n)
            var a: float = base_a * bright * f * f
            var tint := Color(0.62, 0.42, 1.0, a)
            if k == 0:
                tint = Color(1.0, 0.82, 0.55, minf(1.0, a * 3.0))
            _push_glyph(int(gl[(k + off) % RAIN_ROWS]), Vector2(x, gy), 15.0, 0.0, tint)
        if _gp.size() > 0:
            c.draw_multiline_colors(_gp, _gc, 1.5)


## Appends one glyph's segments (and one colour per segment) to the scratch buffers.
func _push_glyph(gid: int, pos: Vector2, size: float, rot: float, col: Color) -> void:
    var src: PackedVector2Array = _glyphs[gid]
    var cs: float = cos(rot)
    var sn: float = sin(rot)
    for i in src.size():
        var v: Vector2 = src[i] * size
        _gp.append(pos + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs))
        if i % 2 == 0:
            _gc.append(col)


## Drifting fog band: soft top and bottom edges, alpha varying along x, tiling seamlessly.
func _fog(c: Node2D, y: float, h: float, drift: float, col: Color, alpha: float) -> void:
    var seg := 8
    var sw: float = (_vsz.x * 1.5) / float(seg)
    var tile: float = sw * float(seg)
    var off: float = fposmod(_t * drift, tile)
    for tile_i in 2:
        var x0: float = -off + float(tile_i) * tile - _vsz.x * 0.25
        for i in seg:
            var xa: float = x0 + float(i) * sw
            var xb: float = xa + sw
            if xa > _vsz.x or xb < 0.0:
                continue
            var va: float = alpha * (0.55 + 0.45 * sin(float(i % seg) * 2.399))
            var vb: float = alpha * (0.55 + 0.45 * sin(float((i + 1) % seg) * 2.399))
            var ca := Color(col.r, col.g, col.b, va)
            var cb := Color(col.r, col.g, col.b, vb)
            var c0 := Color(col.r, col.g, col.b, 0.0)
            var ym: float = y + h * 0.5
            c.draw_polygon(PackedVector2Array([Vector2(xa, y), Vector2(xb, y), Vector2(xb, ym), Vector2(xa, ym)]), PackedColorArray([c0, c0, cb, ca]))
            c.draw_polygon(PackedVector2Array([Vector2(xa, ym), Vector2(xb, ym), Vector2(xb, y + h), Vector2(xa, y + h)]), PackedColorArray([ca, cb, c0, c0]))


func _paint_foes(c: Node2D, gy: float) -> void:
    var tint := Color(0.09, 0.04, 0.16, 0.92)
    for f in _foes:
        var tex: Texture2D = f["tex"]
        var fw: float = f["fw"]
        var fh: float = f["fh"]
        var k: float = f["k"]
        var frames: int = f["frames"]
        var fr: int = int(_t * 6.0 + float(f["ph"])) % frames
        var sz := Vector2(fw, fh) * k
        c.draw_texture_rect_region(tex, Rect2(Vector2(float(f["x"]), gy + 38.0 - sz.y), sz), Rect2(float(fr) * fw, 0.0, fw, fh), tint)


func _paint_glow(c: Node2D) -> void:
    var sc := _seal_center()
    var rad: float = _seal_radius()
    var dim: float = 0.25 + 0.75 * _seal_draw
    for i in 7:
        var rr: float = rad * (0.35 + 0.22 * float(i))
        c.draw_circle(sc, rr, Color(0.45, 0.15, 0.7, (0.035 + 0.03 * _mood + 0.03 * _low_s) * (1.0 - float(i) / 8.0) * dim))
    _paint_rays(c)
    _paint_seal(c)
    _paint_aura(c)
    _paint_embers(c)
    _paint_bolts(c)


func _paint_rays(c: Node2D) -> void:
    var a0: float = (0.04 + 0.07 * _mood + 0.05 * _low_s) * smoothstep(0.0, 1.0, _seal_draw)
    var apex := Vector2(_seal_center().x, -80.0)
    var reach: float = _vsz.y * 1.5
    for i in 7:
        var ang: float = PI * 0.5 + (float(i) - 3.0) * 0.17 + sin(_t * 0.17 + float(i) * 1.3) * 0.05
        var wid: float = 0.045 + 0.02 * sin(_t * 0.31 + float(i))
        var p1: Vector2 = apex + Vector2.from_angle(ang - wid) * reach
        var p2: Vector2 = apex + Vector2.from_angle(ang + wid) * reach
        var hot := Color(1.0, 0.78, 0.45, a0)
        var cold := Color(1.0, 0.78, 0.45, 0.0)
        c.draw_polygon(PackedVector2Array([apex, p1, p2]), PackedColorArray([hot, cold, cold]))


## Three stacked strokes (wide faint, mid, thin bright) so lines read as glowing.
func _line3(c: Node2D, a: Vector2, b: Vector2, col: Color, alpha: float, width: float) -> void:
    c.draw_line(a, b, Color(col.r, col.g, col.b, alpha * 0.14), width * 5.0, true)
    c.draw_line(a, b, Color(col.r, col.g, col.b, alpha * 0.4), width * 2.2, true)
    c.draw_line(a, b, Color(col.r, col.g, col.b, alpha), width, true)


func _arc3(c: Node2D, center: Vector2, radius: float, a0: float, a1: float, col: Color, alpha: float, width: float) -> void:
    if absf(a1 - a0) < 0.01:
        return
    var n: int = maxi(8, int(radius * absf(a1 - a0) / 6.0))
    c.draw_arc(center, radius, a0, a1, n, Color(col.r, col.g, col.b, alpha * 0.14), width * 5.0, true)
    c.draw_arc(center, radius, a0, a1, n, Color(col.r, col.g, col.b, alpha * 0.4), width * 2.2, true)
    c.draw_arc(center, radius, a0, a1, n, Color(col.r, col.g, col.b, alpha), width, true)


func _paint_seal(c: Node2D) -> void:
    var p: float = clampf(_seal_draw, 0.0, 1.0)
    if p <= 0.0:
        return
    var sc := _seal_center()
    var rad: float = _seal_radius() * (1.0 + 0.035 * _seal_kick + 0.012 * _low_s)
    var glow: float = clampf(0.5 + 0.3 * _mood + 0.3 * _low_s, 0.0, 1.0)
    var rot: float = _t * 0.06
    var gold: Color = UI.GOLD
    var top: float = -PI * 0.5
    # outer double ring
    _arc3(c, sc, rad, top, top + TAU * p, gold, glow, 2.0)
    _arc3(c, sc, rad * 0.93, top, top + TAU * p, gold, glow * 0.55, 1.0)
    # tick ring
    var tp := PackedVector2Array()
    var ticks := 72
    var shown: int = int(float(ticks) * p)
    for i in shown:
        var a: float = float(i) / float(ticks) * TAU - rot * 0.5
        var tick_len: float = 0.03 if i % 6 == 0 else 0.015
        tp.append(sc + Vector2.from_angle(a) * rad * 0.93)
        tp.append(sc + Vector2.from_angle(a) * rad * (0.93 - tick_len))
    if tp.size() > 0:
        c.draw_multiline(tp, Color(gold.r, gold.g, gold.b, 0.5 * glow), 1.0)
    # ring of glyphs (a few mutate on every hit)
    if p > 0.5:
        var ga: float = clampf((p - 0.5) * 2.0, 0.0, 1.0)
        _gp.clear()
        _gc.clear()
        for i in RING_GLYPHS:
            var a: float = float(i) / float(RING_GLYPHS) * TAU + rot * 0.8
            var pos: Vector2 = sc + Vector2.from_angle(a) * rad * 0.865
            _push_glyph(int(_ring_gl[i]), pos, rad * 0.045, a + PI * 0.5, Color(1.0, 0.85, 0.5, 0.55 * glow * ga))
        c.draw_multiline_colors(_gp, _gc, 1.5)
    # hexagram: triangle A points up, triangle B down; edges draw on in sequence
    var hr: float = rad * 0.80
    var vs: Array = []
    for i in 6:
        var base: float = -PI * 0.5 + float(i) * (TAU / 3.0) if i < 3 else PI * 0.5 + float(i - 3) * (TAU / 3.0)
        vs.append(sc + Vector2.from_angle(base + rot) * hr)
    var edges: Array = [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3]]
    var seg_p: float = p * 6.0
    for e in 6:
        var frac: float = clampf(seg_p - float(e), 0.0, 1.0)
        if frac <= 0.0:
            continue
        var va: Vector2 = vs[edges[e][0]]
        var vb: Vector2 = vs[edges[e][1]]
        _line3(c, va, va.lerp(vb, frac), gold, glow, 1.6)
    if p > 0.8:
        for v in vs:
            c.draw_circle(v, 9.0, Color(1.0, 0.85, 0.5, 0.12 * glow))
            c.draw_circle(v, 4.5, Color(1.0, 0.92, 0.65, glow))
    # inner rings: crimson full ring + a dashed ring turning the other way
    var crim: Color = UI.CRIMSON.lightened(0.25)
    _arc3(c, sc, rad * 0.50, top, top + TAU * p, crim, glow * 0.7, 1.5)
    if p > 0.6:
        for i in 12:
            var a0: float = float(i) / 12.0 * TAU - rot * 1.2
            c.draw_arc(sc, rad * 0.40, a0, a0 + 0.28, 8, Color(gold.r, gold.g, gold.b, 0.5 * glow), 2.0, true)


func _paint_aura(c: Node2D) -> void:
    if _roster.is_empty() or _hero_a <= 0.0:
        return
    var cd: CharacterDef = _roster[_hero_i]
    var sc := _seal_center()
    var rad: float = _seal_radius()
    var col: Color = cd.color
    for i in 6:
        var rr: float = rad * (0.18 + 0.075 * float(i))
        c.draw_circle(sc + Vector2(0.0, rad * 0.06), rr, Color(col.r, col.g, col.b, (0.05 - 0.007 * float(i)) * (0.7 + 0.5 * _low_s) * _hero_a))


func _paint_embers(c: Node2D) -> void:
    for e in _embers:
        var p: Vector2 = e["p"]
        var lf: float = float(e["life"]) / float(e["max"])
        var a: float = clampf(lf * 2.0, 0.0, 1.0) * (0.55 + 0.45 * sin(_t * 9.0 + float(e["ph"])))
        var col: Color = e["col"]
        var r: float = e["r"]
        c.draw_circle(p, r * 2.6, Color(col.r, col.g, col.b, a * 0.16))
        c.draw_circle(p, r, Color(col.r, col.g, col.b, a))


func _paint_bolts(c: Node2D) -> void:
    for b in _bolts:
        var pts: PackedVector2Array = b["pts"]
        var a: float = clampf(float(b["life"]) / float(b["max"]), 0.0, 1.0)
        c.draw_polyline(pts, Color(0.7, 0.55, 1.0, a * 0.25), 9.0, true)
        c.draw_polyline(pts, Color(0.85, 0.75, 1.0, a * 0.6), 3.5, true)
        c.draw_polyline(pts, Color(1, 1, 1, a), 1.5, true)


func _paint_front(c: Node2D) -> void:
    var gy: float = _vsz.y - 70.0
    _paint_walkers(c, gy)
    _paint_hero(c)
    _paint_pips(c)
    _fog(c, gy - 40.0, 90.0, 24.0, Color(0.35, 0.15, 0.5), 0.12 + 0.08 * _mood)
    _paint_focus(c)


func _paint_walkers(c: Node2D, gy: float) -> void:
    var bob: float = -3.0 * _low_s
    for wk in _walkers:
        var tex: Texture2D = wk["tex"]
        if tex == null:
            continue
        var fr: int = 2 + int((_t + float(wk["ph"])) * 9.0) % 4
        c.draw_texture_rect_region(tex, Rect2(Vector2(float(wk["x"]), gy - 90.0 + bob), Vector2(128, 128)), Rect2(fr * 64, 0, 64, 64))


func _ellipse(center: Vector2, rx: float, ry: float, n: int) -> PackedVector2Array:
    var pts := PackedVector2Array()
    for i in n:
        var a: float = float(i) / float(n) * TAU
        pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
    return pts


func _paint_hero(c: Node2D) -> void:
    if _roster.is_empty() or _hero_a <= 0.0:
        return
    var tex: Texture2D = _hero_tex[_hero_i]
    if tex == null:
        return
    var sc := _seal_center()
    var s: float = float(maxi(2, int(round(_vsz.y / 180.0))))    # whole-number scale keeps pixels crisp
    var sz := Vector2(64.0, 64.0) * s
    var bob: float = sin(_t * 2.2) * 2.0 - 3.0 * _low_s
    var tl: Vector2 = sc - sz * 0.5 + Vector2(0.0, bob - s * 3.0)
    var foot := Vector2(sc.x, tl.y + sz.y - s * 4.0)
    c.draw_colored_polygon(_ellipse(foot, s * 15.0, s * 4.0, 18), Color(0, 0, 0, 0.45 * _hero_a))
    var fr: int = int(_t * 2.2) % 2
    var amp: float = 0.0
    if _swap_t >= 0.0:
        amp = sin(clampf(_swap_t, 0.0, 1.0) * PI)
    var col := Color(1, 1, 1, _hero_a * (1.0 - 0.85 * amp))
    if amp <= 0.01:
        c.draw_texture_rect_region(tex, Rect2(tl, sz), Rect2(float(fr) * 64.0, 0.0, 64.0, 64.0), col)
        return
    # swap in progress: draw the sprite as horizontal slices thrown sideways
    var strips := 16
    var sh: float = 64.0 / float(strips)
    for i in strips:
        var off: float = sin(float(i) * 12.9898 + floorf(_t * 28.0) * 4.1) * amp * 18.0 * s
        c.draw_texture_rect_region(tex, Rect2(tl + Vector2(off, float(i) * sh * s), Vector2(sz.x, sh * s)), Rect2(float(fr) * 64.0, float(i) * sh, 64.0, sh), col)


func _paint_pips(c: Node2D) -> void:
    var n := _roster.size()
    if n < 2 or _hero_a <= 0.0:
        return
    var sc := _seal_center()
    var y: float = _plate_y() + 94.0
    var x0: float = sc.x - float(n - 1) * 10.0
    for i in n:
        var on: bool = i == _hero_i
        var col: Color = UI.GOLD if on else Color(0.35, 0.3, 0.45, 0.9)
        col.a *= _hero_a
        c.draw_rect(Rect2(Vector2(x0 + float(i) * 20.0 - 4.0, y - 4.0), Vector2(8, 8)), col)


## Gold diamond that slides beside the focused menu entry.
func _paint_focus(c: Node2D) -> void:
    if _opts_overlay.visible:
        return
    var fo := get_viewport().gui_get_focus_owner()
    if fo == null or not _buttons.has(fo):
        return
    var r: Rect2 = (fo as Button).get_global_rect()
    var cy: float = r.position.y + r.size.y * 0.5
    var cx: float = r.position.x - 20.0 + sin(_t * 5.0) * 3.0
    var d := 7.0
    var a: float = clampf((_intro_t - SLAM_T - 0.8) / 0.4, 0.0, 1.0)
    c.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy - d), Vector2(cx + d, cy), Vector2(cx, cy + d), Vector2(cx - d, cy)]), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a))
