class_name ProjectileManager
extends Node2D
## Pooled projectiles for the player's weapons AND hostile enemy shots. One _draw call paints all of them
## with additive glow trails. Hit detection is a spatial-hash query per projectile (no physics bodies).

const MAX := 360

enum Kind { BULLET, CANNON, SHRAPNEL, WAVE, SKULL, HOLY, HOSTILE, SHURIKEN }

class Pr:
    var alive := false
    var kind := 0
    var pos := Vector2.ZERO
    var vel := Vector2.ZERO
    var life := 0.0
    var dmg := 0.0
    var radius := 4.0
    var pierce := 0
    var color := Color.WHITE
    var hit := {}                 # enemy uid -> next time it can be hit again
    var trail := PackedVector2Array()
    var knock := 0.0
    var shrapnel := 0
    var shr_dmg := 0.35
    var air := false              # hostile: can knock a flying player out of the sky
    var spin := 0.0
    var age := 0.0
    var rehit := 9999.0           # seconds before the same enemy can be hit again (skulls/waves: 9999 = once)
    var grow := 0.0
    var w := 0.0                  # wave arc half-width
    var burn_dps := 0.0           # sets targets ablaze on hit (Archive Brimstone Breath mod)
    var burn_t := 0.0
    var splash_r := 0.0           # hostile: AoE burst when it expires near the player (0 = off)
    var splash_dmg := 0.0
    var splash_falloff := false

var world
var live: Array[Pr] = []
var _skull_tex: Texture2D
var _shuriken_tex: Texture2D
var _free: Array[Pr] = []


func setup(world_ref) -> void:
    world = world_ref
    z_index = 4
    var m := CanvasItemMaterial.new()
    m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    material = m
    _skull_tex = DB.texture("res://art/fx/skull_projectile.png")
    _shuriken_tex = DB.texture("res://art/weapons/shuriken.png")
    for i in MAX:
        var p := Pr.new()
        p.trail.resize(9)
        _free.append(p)


func _take():
    if _free.is_empty():
        return null
    var p: Pr = _free.pop_back()
    p.alive = true
    p.hit.clear()
    p.age = 0.0
    p.rehit = 9999.0
    p.grow = 0.0
    p.shrapnel = 0
    p.knock = 0.0
    p.air = false
    p.burn_dps = 0.0
    p.burn_t = 0.0
    p.splash_r = 0.0
    p.splash_dmg = 0.0
    p.splash_falloff = false
    p.w = 0.0
    p.spin = randf() * TAU
    live.append(p)
    return p


func fire(kind: int, pos: Vector2, dir: Vector2, speed: float, dmg: float, radius: float, pierce: int, life: float, color: Color, opts: Dictionary = {}):
    var p: Pr = _take()
    if p == null:
        return null
    p.kind = kind
    p.pos = pos
    p.vel = dir.normalized() * speed
    p.dmg = dmg
    p.radius = radius
    p.pierce = pierce
    p.life = life
    p.color = color
    p.knock = float(opts.get("knock", 0.0))
    p.shrapnel = int(opts.get("shrapnel", 0))
    p.shr_dmg = float(opts.get("shr_dmg", 0.35))
    p.rehit = float(opts.get("rehit", 9999.0))
    p.grow = float(opts.get("grow", 0.0))
    p.w = float(opts.get("w", 0.0))
    p.burn_dps = float(opts.get("burn_dps", 0.0))
    p.burn_t = float(opts.get("burn_time", 0.0))
    for i in p.trail.size():
        p.trail[i] = pos
    return p


func spawn_hostile(pos: Vector2, vel: Vector2, dmg: float, air: bool, opts: Dictionary = {}) -> void:
    var p: Pr = _take()
    if p == null:
        return
    p.kind = Kind.HOSTILE
    p.pos = pos
    p.vel = vel
    p.dmg = dmg
    p.life = float(opts.get("life", 3.5))
    if String(opts.get("style", "")) == "fireball":
        p.radius = 6.0
        p.color = Color(1.0, 0.6, 0.1)
    else:
        p.radius = 5.0
        p.color = Color(1.0, 0.45, 0.2)
    p.pierce = 0
    p.air = air
    p.splash_r = float(opts.get("splash_radius", 0.0))
    p.splash_dmg = float(opts.get("splash_damage", 0.0))
    p.splash_falloff = bool(opts.get("splash_falloff", false))
    for i in p.trail.size():
        p.trail[i] = pos


func _process(delta: float) -> void:
    if world == null or not world.sim_running:
        return
    delta = minf(delta, 1.0 / 30.0)
    var now: float = world.run_time
    var i := live.size() - 1
    while i >= 0:
        var p: Pr = live[i]
        p.age += delta
        p.life -= delta
        p.pos += p.vel * delta
        if p.grow != 0.0:
            p.radius += p.grow * delta
        for k in range(p.trail.size() - 1):
            p.trail[k] = p.trail[k + 1]
        p.trail[p.trail.size() - 1] = p.pos
        var dead := p.life <= 0.0
        if not dead:
            if p.kind == Kind.HOSTILE:
                if p.pos.distance_squared_to(world.player.global_position) < 14.0 * 14.0:
                    world.player.take_damage(p.dmg, p.air, "Projectile")
                    world.fx.hit_sparks(p.pos, p.vel, p.color, 6)
                    dead = true
            else:
                dead = _hit_enemies(p, now)
        elif p.kind == Kind.HOSTILE and p.splash_r > 0.0:
            _splash(p)
        if dead:
            p.alive = false
            live.remove_at(i)
            _free.append(p)
        i -= 1
    queue_redraw()


## Expired hostile round with a splash payload: catches near-misses in its blast.
## Direct hits already dealt their damage, so the blast only fires on expiry.
func _splash(p: Pr) -> void:
    var d: float = p.pos.distance_to(world.player.global_position)
    if d > p.splash_r:
        return
    var dmg: float = p.splash_dmg
    if p.splash_falloff:
        dmg *= clampf(1.0 - d / p.splash_r, 0.25, 1.0)
    world.player.take_damage(dmg, p.air, "Splash")
    world.fx.ring(p.pos, 4.0, p.splash_r, 0.25, p.color, 3.0)
    world.fx.hit_sparks(p.pos, p.vel, p.color, 10)


func _hit_enemies(p: Pr, now: float) -> bool:
    var hits: Array[EnemyManager.E] = world.enemies.query_circle(p.pos, p.radius)
    for e in hits:
        var next_ok: float = p.hit.get(e.uid, -1.0)
        if next_ok > now:
            continue
        p.hit[e.uid] = now + p.rehit
        world.enemies.damage(e, p.dmg, p.vel, p.knock, p.color)
        if p.burn_t > 0.0 and e.alive:
            world.enemies.burn(e, p.burn_dps, p.burn_t)
        if p.shrapnel > 0:
            _shrapnel(p, e)
        if p.kind == Kind.CANNON:
            world.fx.ring(p.pos, 4.0, 26.0, 0.18, Color(1.0, 0.7, 0.3), 2.0)
            Game.shake(1.6)
        if p.pierce <= 0:
            return true
        p.pierce -= 1
    return false


func _shrapnel(p: Pr, e: EnemyManager.E) -> void:
    var base := p.vel.angle()
    for i in p.shrapnel:
        var a := base + (float(i) / float(p.shrapnel) - 0.5) * 2.4 + randf_range(-0.2, 0.2)
        var s: Pr = fire(Kind.SHRAPNEL, e.pos, Vector2.from_angle(a), 320.0, p.dmg * p.shr_dmg, 3.0, 1, 0.45, Color(1.0, 0.85, 0.4))
        if s != null:
            s.hit[e.uid] = 1.0e9          # shrapnel never re-hits the enemy it spawned from


func _draw() -> void:
    for p in live:
        var c: Color = p.color
        # trail: a tapered polyline, brighter and thicker near the head
        var n: int = p.trail.size()
        var tw: float = 1.0
        match p.kind:
            Kind.BULLET: tw = 2.0
            Kind.CANNON: tw = p.radius * 1.6
            Kind.SHRAPNEL: tw = 1.4
            Kind.SHURIKEN: tw = 1.5
            Kind.SKULL: tw = p.radius * 0.9
            Kind.HOSTILE: tw = 4.0
        if p.kind != Kind.WAVE and p.kind != Kind.HOLY:
            for k in range(n - 1):
                var f := float(k + 1) / float(n)
                var tc := c
                tc.a = f * f * 0.75
                draw_line(p.trail[k], p.trail[k + 1], tc, maxf(1.0, tw * f))
        match p.kind:
            Kind.BULLET:
                draw_circle(p.pos, 3.2, Color(c.r, c.g, c.b, 0.35))
                draw_circle(p.pos, 1.8, Color(1, 1, 0.9, 1))
            Kind.CANNON:
                draw_circle(p.pos, p.radius * 1.7, Color(c.r, c.g, c.b, 0.25))
                draw_circle(p.pos, p.radius, c)
                draw_circle(p.pos, p.radius * 0.55, Color(1, 0.95, 0.8, 1))
            Kind.SHRAPNEL:
                draw_circle(p.pos, 2.0, Color(1, 0.95, 0.7, 1))
            Kind.SHURIKEN:
                # Textured spinning blade: cycles the 3-frame 32px strip and rotates in flight.
                if _shuriken_tex != null:
                    var sh_s := 30.0
                    var sh_fr := int(p.age * 10.0) % 3
                    var sh_fade := clampf(minf(p.life * 2.0, p.age * 4.0), 0.0, 1.0)
                    draw_set_transform(p.pos, p.spin + p.age * 14.0, Vector2.ONE)
                    draw_texture_rect_region(_shuriken_tex, Rect2(Vector2(-sh_s, -sh_s) * 0.5, Vector2(sh_s, sh_s)), Rect2(sh_fr * 32, 0, 32, 32), Color(1, 1, 1, sh_fade))
                    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
            Kind.HOSTILE:
                draw_circle(p.pos, 8.0, Color(c.r, c.g, c.b, 0.25))
                draw_circle(p.pos, 4.5, c)
                draw_circle(p.pos, 2.2, Color(1, 0.95, 0.7))
            Kind.SKULL:
                if _skull_tex != null:
                    var s: float = 26.0 * p.radius / 12.0
                    var fr := int(p.age * 8.0) % 2
                    var fade := clampf(minf(p.life * 2.0, p.age * 4.0), 0.0, 1.0)
                    draw_texture_rect_region(_skull_tex, Rect2(p.pos - Vector2(s, s) * 0.5, Vector2(s, s)), Rect2(fr * 64, 0, 64, 64), Color(1, 1, 1, 0.62 * fade))
            Kind.WAVE, Kind.HOLY:
                var dir: float = p.vel.angle()
                var life_k := clampf(p.life * 3.0, 0.0, 1.0)
                for ring_i in 3:
                    var rr: float = p.radius * (1.0 + ring_i * 0.35) * 0.9
                    var ac := c
                    ac.a = life_k * (0.75 - ring_i * 0.2)
                    draw_arc(p.pos - p.vel.normalized() * ring_i * 5.0, rr, dir - p.w, dir + p.w, 14, ac, 2.5 - ring_i * 0.5)
