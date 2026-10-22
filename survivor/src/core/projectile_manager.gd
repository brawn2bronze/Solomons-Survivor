class_name ProjectileManager
extends Node2D
## Pooled projectiles for the player's weapons AND hostile enemy shots. One _draw call paints all of them
## with additive glow trails. Hit detection is a spatial-hash query per projectile (no physics bodies).

const MAX := 360

enum Kind { BULLET, CANNON, SHRAPNEL, WAVE, SKULL, HOLY, HOSTILE, SHURIKEN, ZONE }

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
    var zone_target := 0.0        # ZONE: disc radius it grows to before popping
    var dist := 0.0               # distance travelled so far (long_barrel ramp)
    var dist_gain := 0.0          # damage multiplier gained per pixel travelled
    var dist_cap := 0.6           # cap on the distance damage ramp
    var ricochet := false         # bounce to a nearby enemy on final pierce
    var ricochet_range := 150.0   # ricochet: enemy search radius
    var ricochet_mult := 0.6      # ricochet: bounced round damage multiplier
    var ricochet_left := 0        # ricochet: bounces still allowed after this one
    var burst_r := 0.0            # friendly AoE burst radius on hit (0 = off)
    var burst_dmg := 0.0
    var skin := {}                # weapon FX skin (AbilityArt.weapon_proj_skin); {} / fallback = procedural head
    var hit_cb := Callable()      # called with the enemy when this projectile lands a hit
    var rebound := false          # turns around at rebound_range and comes back
    var rebound_done := false
    var rebound_range := 0.0
    var catch_radius := 0.0       # the player can catch it within this radius
    var catch_cb := Callable()
    var caught := false

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
    p.zone_target = 0.0
    p.dist = 0.0
    p.dist_gain = 0.0
    p.dist_cap = 0.6
    p.ricochet = false
    p.ricochet_range = 150.0
    p.ricochet_mult = 0.6
    p.ricochet_left = 0
    p.burst_r = 0.0
    p.burst_dmg = 0.0
    p.hit_cb = Callable()
    p.rebound = false
    p.rebound_done = false
    p.rebound_range = 0.0
    p.catch_radius = 0.0
    p.catch_cb = Callable()
    p.caught = false
    p.skin = {}
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
    p.dist_gain = float(opts.get("dist_gain", 0.0))
    p.dist_cap = float(opts.get("dist_cap", 0.6))
    p.ricochet = bool(opts.get("ricochet", false))
    p.ricochet_range = float(opts.get("ricochet_range", 150.0))
    p.ricochet_mult = float(opts.get("ricochet_mult", 0.6))
    p.ricochet_left = int(opts.get("ricochet_bounces", 1))
    p.burst_r = float(opts.get("burst_r", 0.0))
    p.burst_dmg = float(opts.get("burst_dmg", 0.0))
    var cb_hit = opts.get("hit_cb", null)
    if cb_hit is Callable:
        p.hit_cb = cb_hit
    p.rebound = bool(opts.get("rebound", false))
    p.rebound_range = float(opts.get("rebound_range", 0.0))
    p.catch_radius = float(opts.get("catch_radius", 0.0))
    var cb_catch = opts.get("catch_cb", null)
    if cb_catch is Callable:
        p.catch_cb = cb_catch
    if p.rebound and p.rebound_range > 0.0:
        var spd := p.vel.length()
        if spd > 0.0:
            p.life = (p.rebound_range * 2.0) / spd
    var sk = opts.get("skin", {})
    p.skin = sk if sk is Dictionary else {}
    for i in p.trail.size():
        p.trail[i] = pos
    if world != null:
        world.fx.attack_flourish(p.pos, p.vel)
    return p


func spawn_hostile(pos: Vector2, vel: Vector2, dmg: float, air: bool, opts: Dictionary = {}) -> void:
    # Vanish / ambush windows: an untargetable player is not fired at, so no
    # hostile shot spawns at all (covers every enemy attack in one choke point).
    if world != null and world.player != null and world.player.untargetable:
        return
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
    elif String(opts.get("style", "")) == "bone":
        p.radius = 5.0
        p.color = Color(0.93, 0.9, 0.8)
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


## Ground danger disc (Bone Broker Hellfire Wells, Act III hazards): grows to
## zone_target over `delay` seconds, then pops — damaging the player only if
## inside the radius at that moment. Never hits enemies, never trails.
func spawn_zone(pos: Vector2, radius: float, dmg: float, delay: float, opts: Dictionary = {}) -> void:
    var p: Pr = _take()
    if p == null:
        return
    p.kind = Kind.ZONE
    p.pos = pos
    p.vel = Vector2.ZERO
    p.dmg = dmg
    p.radius = 1.0
    p.zone_target = radius
    p.life = maxf(delay, 0.05)
    p.color = opts.get("color", Color(0.9, 0.4, 0.15))
    p.air = bool(opts.get("air", false))
    for i in p.trail.size():
        p.trail[i] = pos


## Player-side ground trap zone (evolution primitive 4). Damages enemies that
## enter while alive; persists for `duration` seconds. opts: color, tick_interval,
## tick_damage (defaults to dmg per tick), src (hit-gate key).
func spawn_trap_zone(pos: Vector2, radius: float, dmg: float, duration: float, opts: Dictionary = {}) -> void:
    var p: Pr = _take()
    if p == null:
        return
    p.kind = Kind.ZONE
    p.pos = pos
    p.vel = Vector2.ZERO
    p.dmg = dmg
    p.radius = radius
    p.zone_target = radius
    p.life = maxf(duration, 0.1)
    p.color = opts.get("color", Color(0.4, 0.9, 0.4))
    p.air = false
    p.rehit = float(opts.get("tick_interval", 0.5))
    p.skin["trap"] = true
    p.skin["trap_src"] = String(opts.get("src", ""))
    p.skin["trap_radius"] = radius
    p.skin["trap_slow"] = float(opts.get("slow_mult", 1.0))
    p.skin["trap_slow_t"] = float(opts.get("slow_time", 0.0))
    p.skin["trap_stun"] = float(opts.get("stun", 0.0))
    p.skin["trap_contact"] = float(opts.get("contact_mult", 1.0))
    p.skin["trap_contact_t"] = float(opts.get("contact_time", 0.0))
    p.skin["trap_arm"] = float(opts.get("arm", 0.0))
    for i in p.trail.size():
        p.trail[i] = pos


## Evolution primitive 6: intercept hostile projectiles in a radius.
## mode: "destroy" removes them, "reflect" turns them friendly, "absorb" removes.
## dir/arc_rad optionally restrict the intercept to a cone (TAU = full circle).
## Returns the number intercepted. cooldown handled by caller.
func intercept(center: Vector2, radius: float, mode: String = "destroy", dir: Vector2 = Vector2.ZERO, arc_rad: float = TAU) -> int:
    if world == null:
        return 0
    var n := 0
    var r2 := radius * radius
    var cone := arc_rad < TAU - 0.001 and dir.length_squared() > 0.0
    var i := live.size() - 1
    while i >= 0:
        var p: Pr = live[i]
        var in_range := p.kind == Kind.HOSTILE and p.pos.distance_squared_to(center) <= r2 + p.radius * p.radius
        if in_range and cone:
            var to := p.pos - center
            if to.length_squared() > 0.0001 and absf(dir.angle_to(to)) > arc_rad * 0.5:
                in_range = false
        if in_range:
            if mode == "reflect":
                p.kind = Kind.BULLET
                p.color = Color(1.0, 0.85, 0.4)
                p.hit.clear()
                var tgt = world.enemies.nearest(p.pos, 600.0, {})
                if tgt != null:
                    p.vel = (tgt.pos - p.pos).normalized() * maxf(p.vel.length(), 1.0)
                else:
                    p.vel = -p.vel
                n += 1
                i -= 1
            else:
                live.remove_at(i)
                _free.append(p)
                n += 1
                i -= 1
        else:
            i -= 1
    return n


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
        p.dist += p.vel.length() * delta
        if p.grow != 0.0:
            p.radius += p.grow * delta
        for k in range(p.trail.size() - 1):
            p.trail[k] = p.trail[k + 1]
        p.trail[p.trail.size() - 1] = p.pos
        var dead := p.life <= 0.0
        var caught := false
        if p.rebound and not p.rebound_done and p.rebound_range > 0.0 and p.dist >= p.rebound_range:
            p.rebound_done = true
            p.vel = -p.vel
            p.hit.clear()
            if world != null:
                world.fx.ring(p.pos, 4.0, 18.0, 0.2, p.color, 2.0)
        if p.catch_radius > 0.0 and world != null and world.player != null:
            if p.pos.distance_to(world.player.global_position) <= p.catch_radius:
                caught = true
                if p.catch_cb.is_valid():
                    p.catch_cb.call(p)
        if p.kind == Kind.ZONE:
            if bool(p.skin.get("trap", false)):
                # persistent player trap: damages enemies on its tick, never the player
                p.radius = p.zone_target
                _zone_tick(p, now, delta)
            else:
                # growing-disc telegraph; grows toward zone_target over its life
                var total: float = p.life + p.age
                if total > 0.0:
                    p.radius = p.zone_target * clampf(p.age / total, 0.0, 1.0)
                if dead:
                    world.fx.ring(p.pos, p.radius * 0.6, p.radius, 0.22, p.color, 3.0)
                    world.fx.hit_sparks(p.pos, Vector2.UP, p.color, 8)
                    if p.pos.distance_to(world.player.global_position) <= p.radius:
                        world.player.take_damage(p.dmg, p.air, "Hellfire", p.pos)
        elif not dead and not caught:
            if p.kind == Kind.HOSTILE:
                if p.pos.distance_squared_to(world.player.global_position) < 14.0 * 14.0:
                    world.player.take_damage(p.dmg, p.air, "Projectile", p.pos)
                    world.fx.hit_sparks(p.pos, p.vel, p.color, 6)
                    dead = true
            else:
                dead = _hit_enemies(p, now)
        elif p.kind == Kind.HOSTILE and p.splash_r > 0.0:
            _splash(p)
        if dead or caught:
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
    world.player.take_damage(dmg, p.air, "Splash", p.pos)
    world.fx.ring(p.pos, 4.0, p.splash_r, 0.25, p.color, 3.0)
    world.fx.hit_sparks(p.pos, p.vel, p.color, 10)


func _zone_tick(p: Pr, now: float, delta: float) -> void:
    var arm := float(p.skin.get("trap_arm", 0.0))
    if arm > 0.0:
        p.skin["trap_arm"] = arm - delta
        return
    var hits: Array[EnemyManager.E] = world.enemies.query_ground_circle(p.pos, p.radius)
    var src := String(p.skin.get("trap_src", ""))
    var slow_mult := float(p.skin.get("trap_slow", 1.0))
    var slow_time := float(p.skin.get("trap_slow_t", 0.0))
    var stun_t := float(p.skin.get("trap_stun", 0.0))
    var cmult := float(p.skin.get("trap_contact", 1.0))
    var ctime := float(p.skin.get("trap_contact_t", 0.0))
    for e in hits:
        if slow_time > 0.0:
            world.enemies.slow(e, slow_mult, slow_time)
        if stun_t > 0.0:
            world.enemies.stun(e, stun_t)
        if ctime > 0.0:
            e.contact_mult = minf(e.contact_mult, cmult)
            e.contact_mult_t = maxf(e.contact_mult_t, ctime)
        if p.dmg <= 0.0:
            continue
        if float(p.hit.get(e.uid, -1.0)) > now:
            continue
        p.hit[e.uid] = now + p.rehit
        world.enemies.damage(e, p.dmg, (e.pos - p.pos), 0.0, p.color, src)


func _hit_enemies(p: Pr, now: float) -> bool:
    var hits: Array[EnemyManager.E] = world.enemies.query_circle(p.pos, p.radius)
    for e in hits:
        var next_ok: float = p.hit.get(e.uid, -1.0)
        if next_ok > now:
            continue
        p.hit[e.uid] = now + p.rehit
        var dealt: float = p.dmg
        if p.dist_gain > 0.0:
            dealt *= 1.0 + minf(p.dist_cap, p.dist * p.dist_gain)
        world.enemies.damage(e, dealt, p.vel, p.knock, p.color)
        if p.hit_cb.is_valid():
            p.hit_cb.call(e)
        if p.burst_r > 0.0:
            _burst(p, e.pos, e.uid)
        if p.burn_t > 0.0 and e.alive:
            world.enemies.burn(e, p.burn_dps, p.burn_t)
        if p.shrapnel > 0:
            _shrapnel(p, e)
        if p.kind == Kind.CANNON:
            world.fx.ring(p.pos, 4.0, 26.0, 0.18, Color(1.0, 0.7, 0.3), 2.0)
            Game.shake(1.6)
        if p.pierce <= 0:
            if p.ricochet:
                _ricochet(p, e)
            return true
        p.pierce -= 1
    return false


## Ricochet round: on its final pierce, bounce a weaker round at a nearby enemy.
func _ricochet(p: Pr, from_e: EnemyManager.E) -> void:
    var nxt: EnemyManager.E = world.enemies.nearest(from_e.pos, p.ricochet_range, {from_e.uid: true})
    if nxt == null:
        return
    var dir: Vector2 = (nxt.pos - from_e.pos).normalized()
    var b: Pr = fire(Kind.BULLET, from_e.pos, dir, p.vel.length(), p.dmg * p.ricochet_mult, p.radius, 0, 0.5, p.color)
    if b != null:
        b.hit[from_e.uid] = 1.0e9
        b.ricochet_left = p.ricochet_left - 1
        if b.ricochet_left > 0:
            b.ricochet = true
            b.ricochet_range = p.ricochet_range
            b.ricochet_mult = p.ricochet_mult
        world.fx.star(from_e.pos, 6.0, p.color)


## Friendly burst on hit (dead_mans_hand Ace): small AoE that skips the direct target.
func _burst(p: Pr, center: Vector2, skip_uid: int) -> void:
    world.fx.ring(center, 6.0, p.burst_r, 0.22, p.color, 3.0)
    world.fx.hit_sparks(center, Vector2.UP, p.color, 10)
    Game.shake(1.2)
    for e2 in world.enemies.query_circle(center, p.burst_r):
        if e2.uid == skip_uid:
            continue
        world.enemies.damage(e2, p.burst_dmg, (e2.pos - center), 60.0, p.color)


func _shrapnel(p: Pr, e: EnemyManager.E) -> void:
    var base := p.vel.angle()
    for i in p.shrapnel:
        var a := base + (float(i) / float(p.shrapnel) - 0.5) * 2.4 + randf_range(-0.2, 0.2)
        var s: Pr = fire(Kind.SHRAPNEL, e.pos, Vector2.from_angle(a), 320.0, p.dmg * p.shr_dmg, 3.0, 1, 0.45, Color(1.0, 0.85, 0.4))
        if s != null:
            s.hit[e.uid] = 1.0e9          # shrapnel never re-hits the enemy it spawned from
            s.skin = p.skin               # sub-munitions inherit the weapon skin


## Skinned projectile head (weapon proj_fx_*). Faces travel direction, advances
## with age, fades at end of life like the skull head. Returns false when there
## is no usable skin so the caller draws its procedural head instead.
func _draw_skin(p: Pr, sk: Dictionary) -> bool:
    if sk.is_empty() or bool(sk.get("fallback", true)):
        return false
    var tex: Texture2D = DB.texture(String(sk.get("path", "")))
    if tex == null:
        return false
    var frames: int = maxi(1, int(sk.get("frames", 1)))
    var fps: float = maxf(1.0, float(sk.get("fps", 8.0)))
    var sc: float = maxf(0.1, float(sk.get("scale", 1.0)))
    var cw: float = tex.get_size().x / float(frames)
    var ch: float = tex.get_size().y
    var fr: int = int(p.age * fps) % frames
    var fade: float = clampf(minf(p.life * 2.0, p.age * 4.0), 0.0, 1.0)
    # Calibration nudge in travel space (px, pre-scale): fwd along velocity,
    # up screen-up of velocity. Keeps art centered on truth (p.pos = hitbox).
    var dir: Vector2 = p.vel.normalized()
    var org: Vector2 = p.pos + dir * float(sk.get("fwd", 0.0)) + Vector2(dir.y, -dir.x) * float(sk.get("up", 0.0))
    draw_set_transform(org, p.vel.angle(), Vector2(sc, sc))
    draw_texture_rect_region(tex, Rect2(Vector2(-cw, -ch) * 0.5, Vector2(cw, ch)), Rect2(fr * cw, 0, cw, ch), Color(1, 1, 1, fade))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    return true


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
        var sk: Dictionary = p.skin if p.skin is Dictionary else {}
        var hide_trail: bool = not sk.is_empty() and not bool(sk.get("fallback", true)) and not bool(sk.get("trail", true))
        if p.kind != Kind.WAVE and p.kind != Kind.HOLY and p.kind != Kind.ZONE and not hide_trail:
            for k in range(n - 1):
                var f := float(k + 1) / float(n)
                var tc := c
                tc.a = f * f * 0.75
                draw_line(p.trail[k], p.trail[k + 1], tc, maxf(1.0, tw * f))
        match p.kind:
            Kind.BULLET:
                if not _draw_skin(p, sk):
                    draw_circle(p.pos, 3.2, Color(c.r, c.g, c.b, 0.35))
                    draw_circle(p.pos, 1.8, Color(1, 1, 0.9, 1))
            Kind.CANNON:
                if not _draw_skin(p, sk):
                    draw_circle(p.pos, p.radius * 1.7, Color(c.r, c.g, c.b, 0.25))
                    draw_circle(p.pos, p.radius, c)
                    draw_circle(p.pos, p.radius * 0.55, Color(1, 0.95, 0.8, 1))
            Kind.SHRAPNEL:
                if not _draw_skin(p, sk):
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
                if not _draw_skin(p, sk):
                    if _skull_tex != null:
                        var s: float = 26.0 * p.radius / 12.0
                        var fr := int(p.age * 8.0) % 2
                        var fade := clampf(minf(p.life * 2.0, p.age * 4.0), 0.0, 1.0)
                        draw_texture_rect_region(_skull_tex, Rect2(p.pos - Vector2(s, s) * 0.5, Vector2(s, s)), Rect2(fr * 64, 0, 64, 64), Color(1, 1, 1, 0.62 * fade))
            Kind.WAVE, Kind.HOLY:
                if not _draw_skin(p, sk):
                    var dir: float = p.vel.angle()
                    var life_k := clampf(p.life * 3.0, 0.0, 1.0)
                    for ring_i in 3:
                        var rr: float = p.radius * (1.0 + ring_i * 0.35) * 0.9
                        var ac := c
                        ac.a = life_k * (0.75 - ring_i * 0.2)
                        draw_arc(p.pos - p.vel.normalized() * ring_i * 5.0, rr, dir - p.w, dir + p.w, 14, ac, 2.5 - ring_i * 0.5)
            Kind.ZONE:
                # hellfire well: growing filled disc, brighter + pulsing toward the pop
                var k := clampf(p.radius / maxf(p.zone_target, 1.0), 0.0, 1.0)
                var pulse := 1.0 + 0.12 * sin(p.age * 18.0) * k
                draw_circle(p.pos, p.radius * pulse, Color(c.r, c.g, c.b, 0.16 + 0.2 * k))
                draw_arc(p.pos, p.radius * pulse, 0.0, TAU, 28, Color(c.r, c.g, c.b, 0.55 + 0.35 * k), 2.5)
                draw_arc(p.pos, p.radius * pulse * 0.72, 0.0, TAU, 22, Color(1.0, 0.85, 0.5, 0.18 + 0.3 * k), 1.5)
