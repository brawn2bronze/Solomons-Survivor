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
var _blast_tex: Dictionary = {}
var glow_layer: GroundGlow
var _time := 0.0


class GroundGlow extends Node2D:
    var ground: GroundLayer

    func _draw() -> void:
        if ground != null:
            ground.draw_glow(self)


func _ready() -> void:
    floor_tex = _make_floor()
    shadow_tex = _make_shadow()
    glow_layer = GroundGlow.new()
    glow_layer.ground = self
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    glow_layer.material = m
    add_child(glow_layer)


static func _hash(x: int, y: int) -> int:
    var n: int = (x * 73856093) ^ (y * 19349663)
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return n & 0x7fffffff


func _make_floor() -> ImageTexture:
    var img := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
    var rng := RandomNumberGenerator.new()
    rng.seed = 90210
    var stone := 32
    for sy in range(TILE / stone):
        for sx in range(TILE / stone):
            var off := 16 if sy % 2 == 1 else 0
            var base := Color(0.14, 0.1, 0.2).lerp(Color(0.18, 0.12, 0.26), rng.randf())
            base = base.lerp(Color(0.16, 0.1, 0.24), 0.25 if rng.randf() < 0.18 else 0.0)   # tainted stones
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
            img.set_pixel(x % TILE, y % TILE, Color(0.05, 0.03, 0.09))
            x += rng.randi_range(-1, 1) + 1
            y += rng.randi_range(0, 1)
    return ImageTexture.create_from_image(img)


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


func _prop(cx: int, cy: int) -> void:
    var r := _hash(cx, cy)
    var base := Vector2(cx * CHUNK, cy * CHUNK)
    var px := base + Vector2(float(r % 120) + 20.0, float((r >> 8) % 120) + 20.0)
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
        5:                                                                        # brazier
            draw_rect(Rect2(px + Vector2(-5, -2), Vector2(10, 7)), Color(0.18, 0.16, 0.2))
            draw_rect(Rect2(px + Vector2(-6, -4), Vector2(12, 3)), Color(0.3, 0.27, 0.32))
            draw_rect(Rect2(px + Vector2(-3, 5), Vector2(6, 3)), Color(0.12, 0.11, 0.14))
            var f := sin(_time * 11.0 + float(r % 7)) * 1.5
            draw_colored_polygon(PackedVector2Array([px + Vector2(-4, -4), px + Vector2(-1 + f * 0.3, -12 + f), px + Vector2(1, -8), px + Vector2(3 - f * 0.3, -14 - f), px + Vector2(4, -4)]), Color(0.6, 0.25, 1.0))
            draw_colored_polygon(PackedVector2Array([px + Vector2(-2, -4), px + Vector2(0, -9 + f * 0.5), px + Vector2(2, -4)]), Color(0.95, 0.7, 1.0))
        6:                                                                        # fragment seep
            draw_circle(px, 9.0, Color(0.14, 0.08, 0.22, 0.55))
            draw_circle(px + Vector2(6, 3), 6.0, Color(0.18, 0.1, 0.28, 0.5))


func draw_glow(c: Node2D) -> void:
    if world == null or world.player == null:
        return
    var vr := _view_rect()
    vr = vr.grow(60.0)
    for cx in range(floori(vr.position.x / CHUNK), floori(vr.end.x / CHUNK) + 1):
        for cy in range(floori(vr.position.y / CHUNK), floori(vr.end.y / CHUNK) + 1):
            var r := _hash(cx, cy)
            if r % 11 != 5:
                continue
            var base := Vector2(cx * CHUNK, cy * CHUNK)
            var px := base + Vector2(float(r % 120) + 20.0, float((r >> 8) % 120) + 20.0) + Vector2(0, -6)
            var fl := 0.85 + 0.15 * sin(_time * 9.0 + float(r % 13)) + 0.06 * sin(_time * 23.0)
            for i in 6:
                var rad := 120.0 * (1.0 - float(i) / 6.0) * fl
                c.draw_circle(px, rad, Color(0.55, 0.25, 1.0, 0.028))
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
        "turd":
            var poison: bool = bool(d.get("poison", false))
            var t: float = float(d["t"])
            var body := Color(0.36, 0.22, 0.1) if not poison else Color(0.28, 0.4, 0.12)
            var fade: float = clampf((15.0 - t) * 0.5, 0.35, 1.0)
            body.a = fade
            draw_circle(pos + Vector2(0, 1), 5.5, Color(0, 0, 0, 0.35 * fade))
            draw_circle(pos, 4.5, body)
            draw_circle(pos + Vector2(0, -3), 3.3, body.lightened(0.08))
            draw_circle(pos + Vector2(0, -5.5), 2.0, body.lightened(0.16))
            draw_rect(Rect2(pos + Vector2(-2, -4), Vector2(1, 1)), Color(1, 1, 1, fade * 0.6))
            if poison:
                var gs := Color(0.5, 1.0, 0.3, 0.16 * fade)
                draw_circle(pos, 16.0 + sin(t * 4.0) * 2.0, gs)
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
