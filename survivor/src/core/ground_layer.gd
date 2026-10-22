class_name GroundLayer
extends Node2D
## Everything that lives under the actors: seamless procedural flagstone floor, deterministic props
## (bones, cracks, rubble, braziers), soft shadows, and ground decals (webs, turds, caltrops).
## Nothing here is a node per object - it is all _draw calls, so it costs a handful of draw batches.

const TILE := 128
const CHUNK := 176.0

var world
var floor_tex: ImageTexture
var shadow_tex: ImageTexture
var _caltrop_tex: Texture2D
var _turd_tex: Texture2D
var _blast_tex: Dictionary = {}
var glow_layer: GroundGlow
var _time := 0.0
var _act: ActDef = null             # act whose colors the flames/glow currently use
var _floor_cache: Dictionary = {}   # act id -> ImageTexture (4 x 128x128, one-shot)
var _floor_prev: ImageTexture       # crossfade source (drawn under the new floor)
var _floor_fade := 1.0              # 0..1, new floor alpha


class GroundGlow extends Node2D:
    var ground: GroundLayer

    func _draw() -> void:
        if ground != null:
            ground.draw_glow(self)


func _ready() -> void:
    floor_tex = _make_floor(_base_palette())
    shadow_tex = _make_shadow()
    glow_layer = GroundGlow.new()
    glow_layer.ground = self
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    glow_layer.material = m
    add_child(glow_layer)


## Fallback palette before the first act (matches Act I violet).
func _base_palette() -> Dictionary:
    if not DB.acts.is_empty() and world != null and world.acts != null:
        var act = world.acts.current()
        if act != null:
            return _act_palette(act)
    return {"a": Color(0.14, 0.1, 0.2), "b": Color(0.18, 0.12, 0.26), "crack": Color(0.05, 0.03, 0.09)}


func _act_palette(act: ActDef) -> Dictionary:
    return {"a": act.floor_a, "b": act.floor_b, "crack": act.crack_col}


static func _hash(x: int, y: int) -> int:
    var n: int = (x * 73856093) ^ (y * 19349663)
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return n & 0x7fffffff


## Same RNG seed every call, so prop geometry stays identical across acts —
## only the palette changes.
func _make_floor(pal: Dictionary) -> ImageTexture:
    var a: Color = pal["a"]
    var b: Color = pal["b"]
    var crack: Color = pal["crack"]
    var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
    var rng := RandomNumberGenerator.new()
    rng.seed = 90210
    var stone := 32
    for sy in range(TILE / stone):
        for sx in range(TILE / stone):
            var off := 16 if sy % 2 == 1 else 0
            var base := a.lerp(b, rng.randf())
            base = base.lerp(a.lerp(b, 0.5), 0.25 if rng.randf() < 0.18 else 0.0)   # tainted stones
            for y in stone:
                for x in stone:
                    var px := (sx * stone + x + off) % TILE
                    var py := sy * stone + y
                    var c := base
                    var n := rng.randf_range(-0.018, 0.018)
                    c = Color(c.r + n, c.g + n, c.b + n * 1.2)
                    if x == 0 or y == 0:
                        c = c.darkened(0.42)                      # mortar
                    elif x == 1 or y == 1:
                        c = c.lightened(0.07)                     # top-left bevel
                    elif x == stone - 1 or y == stone - 1:
                        c = c.darkened(0.14)
                    img.set_pixel(px, py, c)
    # a few hairline cracks that wrap cleanly
    for k in 5:
        var x := rng.randi_range(0, TILE - 1)
        var y := rng.randi_range(0, TILE - 1)
        for step in rng.randi_range(6, 16):
            img.set_pixel(x % TILE, y % TILE, crack)
            x += rng.randi_range(-1, 1) + 1
            y += rng.randi_range(0, 1)
    return ImageTexture.create_from_image(img)


## Act transition: build/cache the act's floor texture and crossfade over 4s
## (previous floor at full alpha, new floor rising). instant = hard swap.
func apply_theme(act: ActDef, instant: bool) -> void:
    _act = act
    var pal := _act_palette(act)
    var tex: ImageTexture = _floor_cache.get(act.id)
    if tex == null:
        tex = _make_floor(pal)
        _floor_cache[act.id] = tex
    if instant or floor_tex == null:
        floor_tex = tex
        _floor_prev = null
        _floor_fade = 1.0
    else:
        _floor_prev = floor_tex
        floor_tex = tex
        _floor_fade = 0.0
    queue_redraw()
    if glow_layer != null:
        glow_layer.queue_redraw()


func _make_shadow() -> ImageTexture:
    var w := 24
    var h := 12
    var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
    for y in h:
        for x in w:
            var dx := (float(x) + 0.5 - w * 0.5) / (w * 0.5)
            var dy := (float(y) + 0.5 - h * 0.5) / (h * 0.5)
            var d := sqrt(dx * dx + dy * dy)
            img.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d, 0.0, 1.0) * 0.55))
    return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
    _time += delta
    if _floor_fade < 1.0:
        _floor_fade = minf(1.0, _floor_fade + delta / 4.0)
        if _floor_fade >= 1.0:
            _floor_prev = null
    queue_redraw()
    if glow_layer != null:
        glow_layer.queue_redraw()


func _view_rect() -> Rect2:
    var half: Vector2 = Game.VIEW * 0.5 + Vector2(80, 80)
    return Rect2(world.cam_pos - half, half * 2.0)


func _draw() -> void:
    if world == null or world.player == null:
        return
    var vr := _view_rect()
    # floor
    var o := Vector2(floorf(vr.position.x / TILE) * TILE, floorf(vr.position.y / TILE) * TILE)
    var size := Vector2(ceilf(vr.size.x / TILE) + 1.0, ceilf(vr.size.y / TILE) + 1.0) * TILE
    # floor (crossfade: previous floor at full alpha, new floor rising)
    if _floor_prev != null:
        draw_texture_rect(_floor_prev, Rect2(o, size), true)
        draw_texture_rect(floor_tex, Rect2(o, size), true, Color(1, 1, 1, _floor_fade))
    else:
        draw_texture_rect(floor_tex, Rect2(o, size), true)
    # props
    var cx0 := floori(vr.position.x / CHUNK)
    var cx1 := floori(vr.end.x / CHUNK)
    var cy0 := floori(vr.position.y / CHUNK)
    var cy1 := floori(vr.end.y / CHUNK)
    for cx in range(cx0, cx1 + 1):
        for cy in range(cy0, cy1 + 1):
            _prop(cx, cy)
    # decals
    for d in world.decals:
        _decal(d)
    # shadows
    _shadow(world.player.global_position, 1.0 if not world.player.flying else 0.7, 6.0 if world.player.flying else 0.0)
    for e in world.enemies.active:
        var air: float = 4.0 if e.def.height == 1 else 0.0
        _shadow(e.pos, e.radius / 9.0 * e.def.sprite_scale, air)


func _shadow(pos: Vector2, s: float, lift: float) -> void:
    var w := 22.0 * s
    var h := 10.0 * s
    draw_texture_rect(shadow_tex, Rect2(pos + Vector2(-w * 0.5, -h * 0.5 + 1.0 + lift * 0.6), Vector2(w, h)), false)


## Braziers: the fixed r % 11 == 5 residue, plus bonus hash residues when the
## act sets brazier_bonus (e.g. Act III's crimson halls). Shared by _prop and
## draw_glow so a brazier always glows iff it draws a flame.
func _is_brazier(r: int) -> bool:
    if r % 11 == 5:
        return true
    var bonus: float = _act.brazier_bonus if _act != null else 0.0
    return bonus > 0.0 and float((r >> 12) % 100) < bonus * 100.0


func _flame_core() -> Color:
    return _act.flame_core if _act != null else Color(0.6, 0.25, 1.0)


func _flame_glow() -> Color:
    return _act.flame_glow if _act != null else Color(0.55, 0.25, 1.0)


func _prop(cx: int, cy: int) -> void:
    var r := _hash(cx, cy)
    var base := Vector2(cx * CHUNK, cy * CHUNK)
    var px := base + Vector2(float(r % 120) + 20.0, float((r >> 8) % 120) + 20.0)
    if _is_brazier(r):
        _draw_brazier(px, r)
        return
    match r % 11:
        0, 1:                                                                     # bone pile
            for i in 5:
                var a := float((r >> (i * 3)) & 7) / 8.0 * TAU
                var q := px + Vector2.from_angle(a) * float(3 + i * 2)
                draw_line(q, q + Vector2.from_angle(a + 1.2) * 6.0, Color(0.62, 0.6, 0.55), 2.0)
            draw_circle(px + Vector2(2, -2), 3.5, Color(0.7, 0.68, 0.62))
            draw_rect(Rect2(px + Vector2(0, -1), Vector2(2, 2)), Color(0.1, 0.1, 0.12))
        2, 3:                                                                     # crack
            var pts := PackedVector2Array([px])
            var q2 := px
            for i in 6:
                q2 += Vector2(float((r >> (i * 4)) % 9) - 3.0, float((r >> (i * 4 + 2)) % 7) - 2.0)
                pts.append(q2)
            draw_polyline(pts, Color(0.05, 0.05, 0.08, 0.8), 1.5)
        4:                                                                        # rubble
            for i in 4:
                var q3 := px + Vector2(float((r >> (i * 5)) % 22) - 10.0, float((r >> (i * 5 + 2)) % 12) - 5.0)
                var s := float(3 + (r >> (i * 2)) % 4)
                draw_colored_polygon(PackedVector2Array([q3 + Vector2(-s, 0), q3 + Vector2(-s * 0.4, -s), q3 + Vector2(s * 0.6, -s * 0.7), q3 + Vector2(s, 0)]), Color(0.2, 0.14, 0.28))
                draw_line(q3 + Vector2(-s, 0), q3 + Vector2(-s * 0.4, -s), Color(0.32, 0.22, 0.42), 1.0)
        6:                                                                        # fragment seep
            draw_circle(px, 9.0, Color(0.14, 0.08, 0.22, 0.55))
            draw_circle(px + Vector2(6, 3), 6.0, Color(0.18, 0.1, 0.28, 0.5))


func _draw_brazier(px: Vector2, r: int) -> void:
    draw_rect(Rect2(px + Vector2(-5, -2), Vector2(10, 7)), Color(0.18, 0.16, 0.2))
    draw_rect(Rect2(px + Vector2(-6, -4), Vector2(12, 3)), Color(0.3, 0.27, 0.32))
    draw_rect(Rect2(px + Vector2(-3, 5), Vector2(6, 3)), Color(0.12, 0.11, 0.14))
    var f := sin(_time * 11.0 + float(r % 7)) * 1.5
    var core := _flame_core()
    var edge := core.lightened(0.35)
    draw_colored_polygon(PackedVector2Array([px + Vector2(-4, -4), px + Vector2(-1 + f * 0.3, -12 + f), px + Vector2(1, -8), px + Vector2(3 - f * 0.3, -14 - f), px + Vector2(4, -4)]), core)
    draw_colored_polygon(PackedVector2Array([px + Vector2(-2, -4), px + Vector2(0, -9 + f * 0.5), px + Vector2(2, -4)]), edge)


func draw_glow(c: Node2D) -> void:
    if world == null or world.player == null:
        return
    var vr := _view_rect()
    vr = vr.grow(60.0)
    var glow := _flame_glow()
    for cx in range(floori(vr.position.x / CHUNK), floori(vr.end.x / CHUNK) + 1):
        for cy in range(floori(vr.position.y / CHUNK), floori(vr.end.y / CHUNK) + 1):
            var r := _hash(cx, cy)
            if not _is_brazier(r):
                continue
            var base := Vector2(cx * CHUNK, cy * CHUNK)
            var px := base + Vector2(float(r % 120) + 20.0, float((r >> 8) % 120) + 20.0) + Vector2(0, -6)
            var fl := 0.85 + 0.15 * sin(_time * 9.0 + float(r % 13)) + 0.06 * sin(_time * 23.0)
            for i in 6:
                var rad := 120.0 * (1.0 - float(i) / 6.0) * fl
                c.draw_circle(px, rad, Color(glow.r, glow.g, glow.b, 0.028))
    # decal glow: prayer aura on the player etc. handled by the player node itself


func _decal(d: Dictionary) -> void:
    var pos: Vector2 = d["pos"]
    match String(d["kind"]):
        "web":
            var r: float = float(d["r"])
            var load_k: float = float(d.get("load", 0.0))
            var life_a: float = 0.55 + 0.25 * (1.0 - load_k)
            var col := Color(0.92, 0.92, 1.0, life_a)
            var tremble := sin(_time * 30.0) * load_k * 1.2
            for i in 10:
                var a := TAU * float(i) / 10.0
                draw_line(pos, pos + Vector2.from_angle(a) * (r + tremble), col, 1.0)
            for k in [0.28, 0.55, 0.8, 1.0]:
                var pts := PackedVector2Array()
                for i in 11:
                    var a2 := TAU * float(i) / 10.0
                    var rr: float = r * k * (0.92 + 0.08 * sin(a2 * 5.0))
                    pts.append(pos + Vector2.from_angle(a2) * rr)
                draw_polyline(pts, col, 1.0)
            draw_circle(pos, r, Color(0.9, 0.9, 1.0, 0.05))
        "radiant_road":
            var rt: float = float(d.get("t", 0.0))
            var rlife: float = float(d.get("life", 3.0))
            var fade: float = clampf((rlife - rt) / 0.6, 0.0, 1.0)
            var rr: float = float(d.get("r", 20.0))
            var pulse: float = 0.5 + 0.5 * sin(_time * 4.0 + pos.x * 0.03)
            draw_circle(pos, rr, Color(1.0, 0.86, 0.34, 0.10 * fade))
            draw_arc(pos, rr, 0.0, TAU, 24, Color(1.0, 0.92, 0.55, (0.40 + 0.15 * pulse) * fade), 2.0)
            draw_arc(pos, rr * 0.55, 0.0, TAU, 16, Color(1.0, 1.0, 0.82, 0.24 * fade), 1.0)
        "consecration":
            var ct: float = float(d.get("t", 0.0))
            var clife: float = float(d.get("life", 5.0))
            var cr: float = float(d.get("r", 100.0))
            var cfade: float = clampf((clife - ct) / 0.45, 0.0, 1.0) * clampf(ct * 6.0, 0.0, 1.0)
            var cpulse: float = 0.5 + 0.5 * sin(_time * 3.5 + pos.x * 0.02)
            draw_circle(pos, cr, Color(1.0, 0.9, 0.55, 0.065 * cfade))
            draw_circle(pos, cr * 0.7, Color(1.0, 0.82, 0.38, 0.055 * cfade))
            draw_arc(pos, cr, 0.0, TAU, 48, Color(1.0, 0.94, 0.66, (0.38 + 0.16 * cpulse) * cfade), 2.0)
            draw_arc(pos, cr * 0.7, 0.0, TAU, 36, Color(1.0, 0.88, 0.45, 0.28 * cfade), 1.2)
            for i in 8:
                var ca: float = TAU * float(i) / 8.0 + _time * 0.18
                draw_line(pos + Vector2.from_angle(ca) * cr * 0.34, pos + Vector2.from_angle(ca) * cr * 0.78, Color(1.0, 0.95, 0.7, 0.22 * cfade), 1.2)
            draw_circle(pos, 3.0 + cpulse * 1.5, Color(1.0, 1.0, 0.84, 0.5 * cfade))
        "sanctuary":
            var st: float = float(d.get("t", 0.0))
            var slife: float = float(d.get("life", 5.0))
            var sr: float = float(d.get("r", 160.0))
            var sfade: float = clampf((slife - st) / 0.5, 0.0, 1.0) * clampf(st * 5.0, 0.0, 1.0)
            var spulse: float = 0.5 + 0.5 * sin(_time * 3.0)
            draw_circle(pos, sr, Color(0.9, 0.95, 1.0, 0.075 * sfade))
            draw_arc(pos, sr, 0.0, TAU, 56, Color(1.0, 0.98, 0.82, (0.45 + 0.18 * spulse) * sfade), 3.0)
            draw_arc(pos, sr * 0.72, 0.0, TAU, 40, Color(0.95, 1.0, 0.9, 0.24 * sfade), 1.5)
            draw_arc(pos, sr * 0.4, 0.0, TAU, 28, Color(1.0, 0.98, 0.85, 0.18 * sfade), 1.0)
            for i in 12:
                var sa: float = TAU * float(i) / 12.0 - _time * 0.12
                draw_line(pos + Vector2.from_angle(sa) * sr * 0.5, pos + Vector2.from_angle(sa) * sr * 0.98, Color(1.0, 0.98, 0.86, 0.18 * sfade), 1.5)
        "judgement_tell":
            var jt: float = float(d.get("t", 0.0))
            var jlife: float = float(d.get("life", 1.2))
            var jr: float = float(d.get("r", 900.0))
            var jk: float = clampf(jt / maxf(jlife, 0.01), 0.0, 1.0)
            var jpulse: float = 0.5 + 0.5 * sin(_time * 10.0)
            draw_circle(pos, jr, Color(1.0, 0.9, 0.5, 0.018 + 0.022 * jk))
            for jf in [0.35, 0.65, 1.0]:
                draw_arc(pos, jr * float(jf), 0.0, TAU, 64, Color(1.0, 0.92, 0.6, (0.12 + 0.28 * jk) * (1.0 - float(jf) * 0.35)), 2.0)
            for i in 16:
                var ja: float = TAU * float(i) / 16.0 + _time * 0.35
                draw_line(pos + Vector2.from_angle(ja) * jr * 0.38, pos + Vector2.from_angle(ja) * jr * (0.82 + 0.08 * jpulse), Color(1.0, 0.94, 0.62, 0.08 + 0.16 * jk), 2.0)
            draw_circle(pos, 10.0 + jk * 20.0, Color(1.0, 0.96, 0.7, 0.25 + 0.35 * jk))
        "turd":
            var poison: bool = bool(d.get("poison", false))
            var t: float = float(d["t"])
            var fade: float = clampf((15.0 - t) * 0.5, 0.35, 1.0)
            var tpop: float = minf(1.0, t * 5.0 + 0.25)
            if _turd_tex == null:
                _turd_tex = DB.texture("res://art/passives/turd.png")
            draw_circle(pos + Vector2(0, 1), 5.5, Color(0, 0, 0, 0.35 * fade))
            if poison:
                var gs := Color(0.5, 1.0, 0.3, 0.16 * fade)
                draw_circle(pos, 16.0 + sin(t * 4.0) * 2.0, gs)
            if _turd_tex != null:
                var ts: float = 22.0 * tpop
                draw_texture_rect(_turd_tex, Rect2(pos - Vector2(ts, ts) * 0.5, Vector2(ts, ts)), false, Color(1, 1, 1, fade))
            else:
                var body := Color(0.36, 0.22, 0.1) if not poison else Color(0.28, 0.4, 0.12)
                body.a = fade
                draw_circle(pos, 4.5, body)
                draw_circle(pos + Vector2(0, -3), 3.3, body.lightened(0.08))
                draw_rect(Rect2(pos + Vector2(-2, -4), Vector2(1, 1)), Color(1, 1, 1, fade * 0.6))
        "caltrop":
            var ct: float = float(d["t"])
            var cr: float = float(d.get("r", 14.0))
            var clife: float = float(d.get("life", 12.0))
            var cfade: float = clampf((clife - ct) * 0.5, 0.35, 1.0)
            var pop: float = minf(1.0, ct * 5.0 + 0.25)
            if _caltrop_tex == null:
                _caltrop_tex = DB.texture("res://art/weapons/caltrops.png")
            draw_circle(pos + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.35 * cfade))
            draw_circle(pos, cr, Color(0.8, 0.8, 0.85, 0.05 * cfade))
            if _caltrop_tex != null:
                # Designed sprite: per-drop fixed rotation, 3-frame cycle + breathing scale.
                var cseed: float = fmod(absf(pos.x * 12.9898 + pos.y * 78.233), TAU)
                var cfr := int(ct * 6.0 + cseed * 2.0) % 3
                var cs := 26.0 * pop
                draw_set_transform(pos, cseed, Vector2.ONE * (0.92 + 0.08 * sin(ct * 5.0 + cseed)))
                draw_texture_rect_region(_caltrop_tex, Rect2(Vector2(-cs, -cs) * 0.5, Vector2(cs, cs)), Rect2(cfr * 32, 0, 32, 32), Color(1, 1, 1, cfade))
                draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
            else:
                draw_circle(pos, 3.0, Color(0.72, 0.74, 0.8, cfade))
            var glint: float = 0.5 + 0.5 * sin(ct * 5.0)
            draw_circle(pos, 2.8 + glint, Color(1, 1, 1, 0.06 * cfade))
        "blast":
            var bt: float = float(d["t"])
            var blife: float = float(d.get("life", 0.35))
            var bsize: float = float(d.get("size", 96.0))
            var bpath: String = String(d.get("tex", "res://art/weapons/dynamite.png"))
            var bfade: float = clampf(1.0 - bt / maxf(blife, 0.01), 0.0, 1.0)
            var btex: Texture2D = _blast_tex.get(bpath)
            if btex == null:
                btex = DB.texture(bpath)
                _blast_tex[bpath] = btex
            draw_circle(pos + Vector2(0, 1), 6.0, Color(0, 0, 0, 0.35 * bfade))
            if btex != null:
                var bfr: int = int(bt / maxf(blife, 0.01) * 3.0) % 3
                var bbreathe: float = 1.0 + 0.1 * sin(bt * 22.0)
                var bs: float = bsize * bbreathe
                draw_texture_rect_region(btex, Rect2(pos - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), Rect2(bfr * 32, 0, 32, 32), Color(1, 1, 1, bfade))
        "node":
            var nt: float = float(d["t"])
            var nr: float = float(d.get("r", 46.0))
            var nlife: float = float(d.get("life", 6.0))
            var nfade: float = clampf((nlife - nt) * 0.5, 0.35, 1.0)
            var npulse: float = 0.8 + 0.2 * sin(nt * 6.0)
            draw_circle(pos + Vector2(0, 1), 10.0, Color(0, 0, 0, 0.35 * nfade))
            draw_circle(pos, nr, Color(0.55, 0.95, 0.65, 0.06 * nfade))
            draw_arc(pos, nr, 0.0, TAU, 40, Color(0.55, 0.95, 0.65, 0.4 * nfade), 1.5)
            draw_circle(pos, 9.0 * npulse, Color(0.35, 0.6, 0.35, nfade))
            draw_circle(pos + Vector2(0, -3), 6.0 * npulse, Color(0.55, 0.9, 0.55, nfade))
            draw_circle(pos + Vector2(0, -6), 3.0, Color(0.85, 1.0, 0.7, nfade))
            for i in 6:
                var na := TAU * float(i) / 6.0 + nt * 0.4
                draw_line(pos, pos + Vector2.from_angle(na) * nr * 0.7, Color(0.55, 0.95, 0.65, 0.35 * nfade), 1.5)
        "bloom":
            var bt: float = float(d["t"])
            var blife: float = float(d.get("life", 6.0))
            var bfade: float = clampf((blife - bt) * 0.5, 0.35, 1.0)
            var bbreathe: float = 1.0 + 0.12 * sin(bt * 5.0 + pos.x)
            draw_circle(pos + Vector2(0, 1), 6.0, Color(0, 0, 0, 0.35 * bfade))
            draw_circle(pos, 10.0 * bbreathe, Color(0.95, 0.8, 0.45, 0.35 * bfade))
            draw_circle(pos, 5.0 * bbreathe, Color(0.95, 0.8, 0.45, bfade))
            draw_circle(pos + Vector2(0, -2), 2.5, Color(1.0, 0.95, 0.7, bfade))
