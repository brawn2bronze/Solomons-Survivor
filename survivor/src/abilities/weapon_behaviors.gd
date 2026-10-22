class_name WeaponBehaviors
extends RefCounted
## One inner class per behavior key used by WeaponDef.behavior. Numbers come from the data Resources.

static func make(key: String) -> Ability:
    match key:
        "revolver": return Revolver.new()
        "cannon": return Cannon.new()
        "melee_swipe": return MeleeSwipe.new()
        "melee_bite": return MeleeBite.new()
        "chain_lightning": return ChainLightning.new()
        "wave": return Screech.new()
        "skull": return SkullSummon.new()
        "goose_charge": return GooseCharge.new()
        "pickup_volley": return PickupVolley.new()
        "pickup_blast": return PickupBlast.new()
        "pickup_caltrops": return PickupCaltrops.new()
        "pickup_buff": return PickupBuff.new()
        "pickup_ward": return PickupWard.new()
        "flicker_strike": return FlickerStrike.new()
        "mycelium_net": return MyceliumNet.new()
        "worm_ride": return WormRide.new()
    return null


static func jagged(a: Vector2, b: Vector2, segs: int = 6, amp: float = 9.0) -> PackedVector2Array:
    var pts := PackedVector2Array()
    var d := b - a
    var n := d.orthogonal().normalized()
    pts.append(a)
    for i in range(1, segs):
        var f := float(i) / float(segs)
        pts.append(a + d * f + n * randf_range(-amp, amp))
    pts.append(b)
    return pts


# =============================================================================================== Cowboy
class Revolver extends Ability:
    var ammo := 0
    var shot_t := 0.0
    var reload_t := 0.0
    var reload_total := 1.0
    var reloading := false
    var fan_t := 0.0          # fan_the_hammer cooldown
    var still_t := 0.0        # dead_eye stillness meter
    var armed := false        # dead_eye: standing still, next shot is a slug
    var showdown_t := 0.0     # showdown re-mark cadence
    var first_shot := false   # quickdraw: true until the first shot after a reload
    var reload_hurt := false  # quickdraw: took a hit during the current reload
    var shot_index := 0       # dead_mans_hand: 0-based index within the cylinder
    const DEAD_EYE_CUE := 9101

    func on_ready() -> void:
        ammo = int(p["shots"])
        first_shot = true

    func on_player_hurt(_amount: float) -> void:
        if reloading:
            reload_hurt = true

    ## fast_hands (whip evolution) calls this to instantly top off the cylinder.
    func reload_now() -> void:
        ammo = int(p["shots"])
        reloading = false
        reload_t = 0.0
        shot_index = 0
        first_shot = true

    func update(delta: float) -> void:
        var moving := EvoPrims.is_moving(player)
        if moving and armed and has_evo("dead_eye"):
            armed = false
            still_t = 0.0
            world().fx.clear_cues(DEAD_EYE_CUE)
        if reloading:
            var rate := 1.0
            if has_evo("running_reload"):
                rate = float(evo_param("running_reload", "moving_rate", 2.5)) if moving else float(evo_param("running_reload", "still_rate", 0.7))
            reload_t -= delta * rate * maxf(0.25, player.reload_mult)
            if reload_t <= 0.0:
                reloading = false
                ammo = int(p["shots"])
                shot_index = 0
                first_shot = true
                world().fx.emit(player.global_position + Vector2(0, -16), Vector2.ZERO, 0.12, 9.0, Color(1.0, 0.9, 0.5), 1, 0.0)
                Audio.sfx("button_click", -10.0, 1.8, 0.02)
            return
        if has_evo("showdown"):
            showdown_t -= delta
            if showdown_t <= 0.0:
                showdown_t = 0.5
                _mark_showdown()
        if has_evo("fan_the_hammer"):
            fan_t -= delta
            if fan_t <= 0.0 and ammo > 0 and shot_t <= 0.0:
                var near: EnemyManager.E = world().enemies.nearest(player.global_position, float(evo_param("fan_the_hammer", "trigger_range", 80.0)), {})
                if near != null:
                    _fan(near)
                    return
        if has_evo("dead_eye"):
            if moving:
                still_t = 0.0
                if armed:
                    armed = false
                    world().fx.clear_cues(DEAD_EYE_CUE)
            else:
                still_t += delta
                if not armed and still_t >= float(evo_param("dead_eye", "still_time", 0.7)):
                    armed = true
                    world().fx.cue_converge(DEAD_EYE_CUE, 0, player.global_position, 90.0, 18.0, Color(1.0, 0.85, 0.4), 1.0)
        shot_t -= delta
        if shot_t > 0.0:
            return
        var tgt: EnemyManager.E = player.target()
        if tgt == null or tgt.pos.distance_to(player.global_position) > float(p["range"]):
            return
        var slug := false
        if armed and has_evo("dead_eye"):
            slug = true
            armed = false
            still_t = 0.0
            world().fx.clear_cues(DEAD_EYE_CUE)
        _shoot(tgt, slug)
        ammo -= 1
        shot_index += 1
        shot_t = float(p["shot_interval"]) * cd()
        if ammo <= 0:
            reloading = true
            reload_total = float(p["reload_time"]) * cd()
            reload_t = reload_total
            reload_hurt = false

    ## Point-blank cylinder dump (fan_the_hammer): several rounds in a wide arc.
    func _fan(tgt: EnemyManager.E) -> void:
        var dir: Vector2 = (tgt.pos - player.global_position).normalized()
        var n2: int = maxi(1, ammo)
        var col := Color(1.0, 0.82, 0.35)
        var half := float(evo_param("fan_the_hammer", "fan_deg", 70.0)) * 0.5
        for i in n2:
            var a := dir.rotated(deg_to_rad(lerpf(-half, half, float(i) / float(maxi(n2 - 1, 1)))))
            var o := player.fire_origin(i, a)
            world().projectiles.fire(ProjectileManager.Kind.BULLET, o, a, float(p["speed"]), dmg(), float(p["radius"]), int(p["pierce"]), float(p["range"]) * 0.5 / float(p["speed"]), col, {"skin": AbilityArt.weapon_proj_skin(def), "knock": 30.0})
        world().fx.muzzle(player.fire_origin(0, dir), dir, col, AbilityArt.weapon_muzzle_skin(def))
        world().fx.wedge(player.global_position, dir.angle(), deg_to_rad(float(evo_param("fan_the_hammer", "fan_deg", 70.0))), float(p["range"]) * 0.5, 0.18, col)
        Audio.sfx("revolver_shot", -6.0)
        Game.shake(1.6)
        ammo = 0
        fan_t = float(evo_param("fan_the_hammer", "cooldown", 4.0)) * cd()
        reloading = true
        reload_total = float(p["reload_time"]) * cd()
        reload_t = reload_total
        reload_hurt = false
        player.impulse(-dir * 40.0)

    ## Mark the toughest enemy in range; hits on it gain a mid-range damage peak.
    func _mark_showdown() -> void:
        var r := float(p["range"])
        var best: EnemyManager.E = null
        for e in world().enemies.query_circle(player.global_position, r):
            if best == null or e.max_hp > best.max_hp:
                best = e
        if best != null:
            world().enemies.mark(best, "showdown", 2.0, "showdown")

    func _showdown_mult(dist: float, rng: float) -> float:
        var peak := float(evo_param("showdown", "peak", 0.6))
        var f := 1.0 - absf(dist / maxf(rng, 1.0) - 0.5) * 2.0
        return 1.0 + minf(peak * clampf(f, 0.0, 1.0), float(evo_param("showdown", "bonus_max", 0.5)))

    func _shoot(tgt: EnemyManager.E, slug: bool) -> void:
        var origin := player.global_position
        var dist := tgt.pos.distance_to(origin)
        var dir: Vector2 = (tgt.pos - origin).normalized()
        var n: int = player.scaled_count(int(p["count"]))
        var col := Color(1.0, 0.82, 0.35)
        var mult := 1.0
        var pierce := int(p["pierce"])
        var quick := false
        if has_evo("quickdraw") and first_shot:
            quick = true
            mult *= float(evo_param("quickdraw", "first_mult", 3.0))
            if not reload_hurt:
                pierce = int(evo_param("quickdraw", "perfect_pierce", 99))
        first_shot = false
        if slug:
            mult *= float(evo_param("dead_eye", "mult", 3.0))
            pierce = int(evo_param("dead_eye", "pierce", 99))
        if has_evo("showdown") and world().enemies.has_mark(tgt, "showdown"):
            mult *= _showdown_mult(dist, float(p["range"]))
        var ace := has_evo("dead_mans_hand") and shot_index == int(p["shots"]) - 1
        if ace:
            mult *= 2.0
        var single := quick or slug
        for i in n:
            if single and i > 0:
                break
            var spread := deg_to_rad(randf_range(-1.0, 1.0) * float(p["spread_deg"])) + (0.0 if i == 0 else randf_range(-0.14, 0.14))
            var o := player.fire_origin(i, dir)
            var opts := {"skin": AbilityArt.weapon_proj_skin(def), "knock": 30.0}
            if has_evo("ricochet_rounds"):
                opts["ricochet"] = true
                opts["ricochet_range"] = float(evo_param("ricochet_rounds", "range", 140.0))
                opts["ricochet_mult"] = float(evo_param("ricochet_rounds", "mult", 0.6))
                opts["ricochet_bounces"] = int(evo_param("ricochet_rounds", "bounces", 1))
            if has_evo("long_barrel"):
                opts["dist_gain"] = float(evo_param("long_barrel", "per_100px", 0.1)) / 100.0
                opts["dist_cap"] = float(evo_param("long_barrel", "cap", 0.6))
            if ace and i == 0:
                opts["burst_r"] = float(evo_param("dead_mans_hand", "burst_radius", 70.0))
                opts["burst_dmg"] = dmg() * float(evo_param("dead_mans_hand", "burst_mult", 2.5))
            world().projectiles.fire(ProjectileManager.Kind.BULLET, o, dir.rotated(spread), float(p["speed"]), dmg() * mult, float(p["radius"]), pierce, float(p["range"]) / float(p["speed"]), col, opts)
        world().fx.muzzle(player.fire_origin(0, dir), dir, col, AbilityArt.weapon_muzzle_skin(def))
        if slug:
            world().fx.beam_between(origin, origin + dir * float(p["range"]), 3.0, 0.16, col)
            Game.shake(2.2)
        elif quick:
            world().fx.lash(origin, dir.angle(), 40.0, col)
            Game.shake(1.4)
        else:
            Audio.sfx("revolver_shot", -7.0)
            Game.shake(0.9)
        player.impulse(-dir * 28.0)

    func draw_overlay(c: Node2D) -> void:
        var shots := int(p["shots"])
        if reloading:
            var k := 1.0 - reload_t / maxf(reload_total, 0.01)
            c.draw_arc(Vector2(0, -16), 19.0, -PI * 0.5, -PI * 0.5 + TAU * k, 28, Color(1.0, 0.85, 0.4, 0.95), 2.5)
            c.draw_arc(Vector2(0, -16), 19.0, 0.0, TAU, 28, Color(0, 0, 0, 0.25), 1.0)
        else:
            for i in shots:
                var a := -PI * 0.5 + (float(i) / float(shots)) * TAU
                var pos := Vector2(0, -16) + Vector2.from_angle(a) * 19.0
                c.draw_circle(pos, 1.7, Color(1.0, 0.85, 0.4, 0.9) if i < ammo else Color(0.2, 0.2, 0.2, 0.5))
            if armed:
                c.draw_arc(Vector2(0, -16), 23.0, 0.0, TAU, 28, Color(1.0, 0.95, 0.6, 0.9), 2.0)

    func hud_line() -> String:
        return "RELOAD" if reloading else "%d/%d" % [ammo, int(p["shots"])]


# =============================================================================================== Pirate
class Cannon extends Ability:
    ## Analytic tracer for the evolutions that have to follow a shot themselves:
    ## pooled projectiles get recycled, so their Pr cannot be tracked by reference.
    class Tracer:
        var kind := 0                # 0 = chain shot, 1 = burning pitch trail
        var origin := Vector2.ZERO
        var dir := Vector2.ZERO
        var speed := 0.0
        var dist := 0.0
        var max_dist := 0.0
        var next_at := 0.0
        var count := 0
        var spread := 0.0
        var width := 0.0
        var dmg := 0.0
        var gate: Dictionary = {}

    var reload_t := 0.6
    var reload_total := 1.0
    var charging := 0.0
    # Pirate evolutions (hand cannon)
    var tracers: Array = []         # chain_shot / burning_pitch tracers
    var phantom_t := 0.0             # phantom_broadside: countdown to the next rake
    var phantom_tell := 0.0          # phantom_broadside: tell seconds left
    var phantom_dir := Vector2.ZERO
    var phantom_gate: Dictionary = {}
    var primed: Dictionary = {}      # primed_powder: uid -> {pos, t, gen}

    func update(delta: float) -> void:
        _update_tracers(delta)
        if has_evo("phantom_broadside"):
            _update_phantom(delta)
        if has_evo("primed_powder"):
            _update_primed(delta)
        if charging > 0.0:
            charging -= delta
            if charging <= 0.0:
                _fire()
                reload_total = float(p["reload_time"]) * cd()
                reload_t = reload_total
            return
        reload_t -= delta * maxf(0.25, player.reload_mult)
        if reload_t <= 0.0:
            var tgt: EnemyManager.E = player.target()
            if tgt != null and tgt.pos.distance_to(player.global_position) < float(p["range"]):
                charging = 0.32
                Audio.sfx("button_click", -6.0, 0.6, 0.0)

    func _fire() -> void:
        var tgt: EnemyManager.E = player.target()
        var dir: Vector2 = player.aim_dir() if tgt == null else (tgt.pos - player.global_position).normalized()
        var col := Color(1.0, 0.55, 0.2)
        var near: Array = world().enemies.query_circle(player.global_position, float(p["range"]))
        var mortar := has_evo("bombard") and not near.is_empty()
        if mortar:
            _fire_mortar(dir, col)
        else:
            _fire_balls(dir, col)
        var m := player.fire_origin(0, dir)
        world().fx.muzzle(m, dir, col, AbilityArt.weapon_muzzle_skin(def))
        for k in 10:
            world().fx.emit(m, Vector2.from_angle(dir.angle() + randf_range(-0.5, 0.5)) * randf_range(40.0, 150.0), randf_range(0.3, 0.6), randf_range(3.0, 6.0), Color(0.6, 0.6, 0.6, 0.6), 1, 3.0, 0.0, false)
        Audio.sfx("hand_cannon", -3.0)
        Game.shake(5.0)
        _recoil(dir)

    ## ---- hand cannon evolutions ------------------------------------------------------------
    func _fire_balls(dir: Vector2, col: Color) -> void:
        var n: int = player.scaled_count(int(p["count"]))
        var opts := {"skin": AbilityArt.weapon_proj_skin(def), "knock": 240.0, "shrapnel": int(p["shrapnel"]), "shr_dmg": float(p["shrapnel_damage"])}
        if has_evo("rebound"):
            opts["rebound"] = true
            opts["rebound_range"] = float(p["range"])
            opts["catch_radius"] = float(evo_param("rebound", "catch_radius", 18.0))
            opts["catch_cb"] = Callable(self, "_catch_ball")
        if has_evo("primed_powder"):
            opts["hit_cb"] = Callable(self, "_prime_enemy")
        var lead := player.fire_origin(0, dir)
        for i in n:
            var o := player.fire_origin(i, dir)
            var d := dir.rotated(0.0 if i == 0 else randf_range(-0.16, 0.16))
            world().projectiles.fire(ProjectileManager.Kind.CANNON, o, d, float(p["speed"]), dmg(), float(p["radius"]), int(p["pierce"]), float(p["range"]) / float(p["speed"]), col, opts)
        if has_evo("chain_shot"):
            _start_chain(lead, dir)
        if has_evo("broadside"):
            _fire_broadside(dir, col)
        if has_evo("burning_pitch"):
            _start_pitch(lead, dir)

    ## chain_shot: a linked pair whose chain sweeps enemies along the shot.
    func _start_chain(origin: Vector2, dir: Vector2) -> void:
        var tr := Tracer.new()
        tr.kind = 0
        tr.origin = origin
        tr.dir = dir
        tr.speed = float(p["speed"])
        tr.max_dist = float(p["range"])
        tr.spread = float(evo_param("chain_shot", "spread", 0.12))
        tr.width = float(evo_param("chain_shot", "chain_width", 6.0))
        tr.dmg = dmg() * float(evo_param("chain_shot", "chain_mult", 0.5))
        tracers.append(tr)

    ## burning_pitch: a fire trail dropped along the shot path.
    func _start_pitch(origin: Vector2, dir: Vector2) -> void:
        var tr := Tracer.new()
        tr.kind = 1
        tr.origin = origin
        tr.dir = dir
        tr.speed = float(p["speed"])
        tr.max_dist = float(p["range"])
        tr.next_at = float(evo_param("burning_pitch", "spacing", 40.0))
        tracers.append(tr)

    func _update_tracers(delta: float) -> void:
        if tracers.is_empty():
            return
        var now: float = world().run_time
        for i in range(tracers.size() - 1, -1, -1):
            var tr: Tracer = tracers[i]
            var d0 := tr.dist
            tr.dist += tr.speed * delta
            var d1 := tr.dist
            if tr.kind == 0 and tr.width > 0.0:
                var half := tr.spread * 0.5
                var a0 := tr.origin + tr.dir.rotated(-half) * d0
                var a1 := tr.origin + tr.dir.rotated(-half) * d1
                var b0 := tr.origin + tr.dir.rotated(half) * d0
                var b1 := tr.origin + tr.dir.rotated(half) * d1
                EvoPrims.gated_segment_hit(world(), a0, a1, tr.width * 0.5, tr.dmg, tr.gate, now, 0.5, tr.dir, 30.0, "chain_shot")
                EvoPrims.gated_segment_hit(world(), b0, b1, tr.width * 0.5, tr.dmg, tr.gate, now, 0.5, tr.dir, 30.0, "chain_shot")
                world().fx.beam_between(a1, b1, 2.0, 0.08, Color(0.95, 0.85, 0.65, 0.85))
            elif tr.kind == 1:
                var cap := int(evo_param("burning_pitch", "max_patches", 10))
                var spacing := float(evo_param("burning_pitch", "spacing", 40.0))
                while tr.count < cap and d1 >= tr.next_at:
                    _drop_pitch(tr.origin + tr.dir * tr.next_at)
                    tr.next_at += spacing
                    tr.count += 1
            if tr.dist >= tr.max_dist:
                tracers.remove_at(i)

    func _drop_pitch(pos: Vector2) -> void:
        var radius := float(evo_param("burning_pitch", "radius", 26.0))
        var life := float(evo_param("burning_pitch", "life", 3.0))
        var mult := float(evo_param("burning_pitch", "dps_mult", 0.3))
        world().projectiles.spawn_trap_zone(pos, radius, dmg() * mult * 0.5, life, {"color": Color(1.0, 0.45, 0.15), "src": "burning_pitch", "tick_interval": 0.5})

    ## broadside: extra port and starboard balls, but only while moving.
    func _fire_broadside(dir: Vector2, col: Color) -> void:
        if player.vel.length() < float(evo_param("broadside", "min_speed", 30.0)):
            return
        var n2: int = int(evo_param("broadside", "side_balls", 2))
        var mult := float(evo_param("broadside", "side_mult", 0.7))
        for i in n2:
            var side := 1.0 if i % 2 == 0 else -1.0
            var d := dir.rotated(side * PI * 0.5)
            var o := player.global_position + Vector2(0, -14) + d * 10.0
            world().projectiles.fire(ProjectileManager.Kind.CANNON, o, d, float(p["speed"]) * 0.85, dmg() * mult, float(p["radius"]) * 0.7, 1, float(p["range"]) / float(p["speed"]), col, {"skin": AbilityArt.weapon_proj_skin(def), "knock": 120.0})
        world().fx.muzzle(player.global_position + Vector2(0, -14), dir.rotated(PI * 0.5), col, AbilityArt.weapon_muzzle_skin(def))

    ## bombard: a mortar shell that lands on the densest cluster after a tell.
    func _fire_mortar(dir: Vector2, col: Color) -> void:
        var spot := EvoPrims.densest_cluster(world(), player.global_position, float(p["range"]), 70.0, [player.global_position])
        var delay := float(evo_param("bombard", "delay", 0.7))
        var blast := _blast_radius()
        var amount := dmg()
        world().fx.ring(spot, blast * 0.15, blast, delay, Color(col.r, col.g, col.b, 0.85), 3.0)
        world().fx.wedge(player.global_position, dir.angle(), deg_to_rad(28.0), float(p["range"]), delay, Color(col.r, col.g, col.b, 0.35))
        after(delay, func() -> void: _mortar_hit(spot, blast, amount))

    func _blast_radius() -> float:
        return float(evo_param("bombard", "blast", 64.0)) * float(evo_param("bombard", "radius_mult", 1.4)) * player.stat("area")

    func _mortar_hit(pos: Vector2, blast: float, amount: float) -> void:
        world().fx.ring(pos, 8.0, blast, 0.3, Color(1.0, 0.55, 0.2), 4.0)
        world().fx.hit_sparks(pos, Vector2.UP, Color(1.0, 0.6, 0.25), 12)
        Game.shake(3.0)
        for e in world().enemies.query_circle(pos, blast):
            world().enemies.damage(e, amount, (e.pos - pos).normalized(), 120.0, Color(1.0, 0.55, 0.2), "bombard")

    ## kickback: a short invulnerable backstep plus a close muzzle cone.
    func _recoil(dir: Vector2) -> void:
        if not has_evo("kickback"):
            player.impulse(-dir * 130.0)
            return
        var back := float(evo_param("kickback", "backstep", 60.0))
        var inv := float(evo_param("kickback", "time", 0.15))
        player.blink_to(player.global_position - dir * back, inv)
        _muzzle_cone(dir)

    func _muzzle_cone(dir: Vector2) -> void:
        var half := deg_to_rad(float(evo_param("kickback", "cone_deg", 50.0)) * 0.5)
        var rng := float(evo_param("kickback", "cone_range", 90.0))
        var amount := dmg() * float(evo_param("kickback", "cone_mult", 0.6))
        var origin := player.global_position
        var col := Color(1.0, 0.6, 0.25)
        for e in world().enemies.query_arc(origin, dir, rng, half):
            world().enemies.damage(e, amount, (e.pos - origin).normalized(), 60.0, col, "kickback")
        world().fx.wedge(origin, dir.angle(), half * 2.0, rng, 0.18, Color(1.0, 0.6, 0.25, 0.8))

    ## rebound: the ball swings back; catch it to cut the reload.
    func _catch_ball(_pr) -> void:
        reload_t = maxf(0.0, reload_t - float(evo_param("rebound", "reload_refund", 1.0)))
        world().fx.ring(player.global_position, 6.0, 30.0, 0.25, Color(1.0, 0.85, 0.4), 2.5)
        Audio.sfx("coin_pickup", -7.0, 0.8, 0.0)

    ## phantom_broadside: a ghost galleon rakes a wide lane on a timer.
    func _update_phantom(delta: float) -> void:
        if phantom_tell > 0.0:
            phantom_tell -= delta
            if phantom_tell <= 0.0:
                _phantom_fire()
            return
        phantom_t -= delta
        if phantom_t <= 0.0:
            phantom_t = float(evo_param("phantom_broadside", "every", 18.0))
            phantom_tell = float(evo_param("phantom_broadside", "tell", 1.0))
            phantom_dir = player.aim_dir()
            var half := deg_to_rad(float(evo_param("phantom_broadside", "lane_width", 140.0)) * 0.5)
            var length := float(evo_param("phantom_broadside", "length", 700.0))
            world().fx.wedge(player.global_position, phantom_dir.angle(), half * 2.0, length, phantom_tell, Color(0.8, 0.9, 1.0, 0.45))
            Audio.sfx("screech", -8.0, 0.7, 0.0)

    func _phantom_fire() -> void:
        var length := float(evo_param("phantom_broadside", "length", 700.0))
        var width := float(evo_param("phantom_broadside", "lane_width", 140.0))
        var amount := dmg() * float(evo_param("phantom_broadside", "mult", 1.5))
        var origin := player.global_position
        var to := origin + phantom_dir * length
        EvoPrims.gated_segment_hit(world(), origin, to, width * 0.5, amount, phantom_gate, world().run_time, 0.5, phantom_dir, 60.0, "phantom_broadside")
        world().fx.beam_between(origin, to, width * 0.4, 0.35, Color(0.85, 0.92, 1.0, 0.9))
        Audio.sfx("screech", -3.0)
        Game.shake(3.0)

    ## primed_powder: a hit primes the enemy; the fuse blast never re-primes.
    func _prime_enemy(e) -> void:
        if e == null or not e.alive:
            return
        var uid: int = e.uid
        if primed.has(uid):
            return
        var fuse := float(evo_param("primed_powder", "fuse", 2.0))
        primed[uid] = {"pos": e.pos, "t": fuse, "gen": 0}
        world().fx.ring(e.pos, 4.0, 22.0, 0.25, Color(1.0, 0.8, 0.35, 0.9), 2.0)
        after(fuse, func() -> void: _explode_primed(uid))

    func _explode_primed(uid: int) -> void:
        if not primed.has(uid):
            return
        var rec: Dictionary = primed[uid]
        primed.erase(uid)
        var pos: Vector2 = rec["pos"]
        var gen: int = int(rec["gen"])
        var radius := float(evo_param("primed_powder", "radius", 50.0))
        var amount := dmg() * float(evo_param("primed_powder", "mult", 0.6))
        var col := Color(1.0, 0.7, 0.3)
        world().fx.ring(pos, 6.0, radius, 0.28, col, 3.0)
        world().fx.hit_sparks(pos, Vector2.UP, col, 10)
        Game.shake(2.2)
        var max_gen := int(evo_param("primed_powder", "generations", 1))
        for e in world().enemies.query_circle(pos, radius):
            world().enemies.damage(e, amount, (e.pos - pos).normalized(), 90.0, col, "primed_powder")
            if gen + 1 < max_gen and not primed.has(e.uid):
                primed[e.uid] = {"pos": e.pos, "t": float(evo_param("primed_powder", "fuse", 2.0)), "gen": gen + 1}

    func _update_primed(delta: float) -> void:
        for k in primed.keys():
            var rec: Dictionary = primed[k]
            rec["t"] = float(rec["t"]) - delta
            if float(rec["t"]) <= -1.0:
                primed.erase(k)

    func draw_overlay(c: Node2D) -> void:
        if charging > 0.0:
            var k := 1.0 - charging / 0.32
            var dir := player.aim_dir()
            c.draw_circle(Vector2(0, -14) + dir * 14.0, 3.0 + 8.0 * k, Color(1.0, 0.6, 0.2, 0.35 + 0.5 * k))
        elif reload_t > 0.0:
            var k2 := clampf(1.0 - reload_t / maxf(reload_total, 0.01), 0.0, 1.0)
            c.draw_arc(Vector2(0, -16), 19.0, -PI * 0.5, -PI * 0.5 + TAU * k2, 28, Color(1.0, 0.55, 0.25, 0.95), 2.5)

    func hud_line() -> String:
        return "FIRING" if charging > 0.0 else ("READY" if reload_t <= 0.0 else "RELOAD")


# =============================================================================================== Ninja / Paladin / Minotaur
class MeleeSwipe extends Ability:
    var flip := 1.0
    var charge_t := 5.0
    # Ninja evolutions (katana)
    var mom_idle := 0.0            # momentum_edge: seconds since last moving
    var combo := 0                 # unbroken_combo: connected swings since the last finisher
    var weave_hit: Dictionary = {} # weaving_blades: uid -> cooldown seconds
    var cut_t := 0.0               # thousand_cuts: flurry seconds remaining
    var cut_tick := 0.0
    var cut_target = null          # thousand_cuts: locked enemy
    var reprisal_t := 0.0          # reprisal: cooldown
    var ambush_t := 0.0            # vanish ambush window (set by Flash Bombs)
    var ambush_mult := 2.5         # vanish ambush damage multiplier
    # Paladin evolutions (greatsword)
    var gs_advance := 0.0          # crusaders_march: Advance stacks
    var gs_mirror_waves: Array = [] # mirror_wave: tracked wave paths
    var gs_dawn_life := 0.0        # dawnbreaker: active beam time
    var gs_dawn_angle := 0.0
    var gs_dawn_center := Vector2.ZERO
    var gs_dawn_gate: Dictionary = {}
    var gs_road: Array = []        # pilgrims_road: live radiant tiles
    var gs_road_last := Vector2.INF
    var gs_road_tick := 0.0
    var gs_fervor := 0.0           # fervor: stack count
    var gs_fervor_t := 0.0         # fervor: time until decay begins
    var gs_retribution := 0.0      # retribution: stored charge
    var gs_leap_t := -1.0          # holy_leap: cooldown
    var gs_still := 0.0            # bulwark_stance: still time
    var gs_guard_dir := Vector2.ZERO
    var gs_guard_on := false

    func update(delta: float) -> void:
        t -= delta
        if reprisal_t > 0.0:
            reprisal_t -= delta
        if ambush_t > 0.0:
            ambush_t -= delta
        if has_evo("momentum_edge"):
            mom_idle = 0.0 if player.is_moving() else mom_idle + delta
        if has_evo("weaving_blades"):
            _weaving(delta)
        if cut_t > 0.0:
            _cut_tick(delta)
        if _greatsword_update(delta):
            return
        if flags.get("charge", false):
            charge_t -= delta
            if charge_t <= 0.0 and player.dash_t <= 0.0:
                _try_charge()
        if t > 0.0:
            return
        var r := float(p["radius"]) * player.stat("area")
        if has_evo("momentum_edge"):
            var fade := float(evo_param("momentum_edge", "fade", 0.6))
            var down: float = 0.0 if mom_idle <= fade else 4.0
            var mom := meter("katana_mom", delta, player.is_moving(), float(evo_param("momentum_edge", "build_per_sec", 2.5)), down, float(evo_param("momentum_edge", "max_stacks", 5.0)))
            r *= 1.0 + float(evo_param("momentum_edge", "radius_per_stack", 0.06)) * mom
        var dir := Vector2.ZERO
        var has_dir := false
        if has_evo("wayfinder") and player.is_moving():
            dir = player.last_dir
            has_dir = true
        else:
            var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, r * 1.3, {})
            if tgt != null:
                dir = (tgt.pos - player.global_position).normalized()
                has_dir = true
        if not has_dir:
            t = 0.04
            return
        var fv := _fervor_bonus()
        t = float(p["cooldown"]) * cd() / maxf(0.25, 1.0 + fv)
        if has_evo("dawnbreaker") and nth("greatsword_dawn", int(evo_param("dawnbreaker", "every", 5))):
            var dtell := float(evo_param("dawnbreaker", "tell", 0.4))
            var dcenter := player.global_position
            if dtell > 0.0:
                world().fx.ring(dcenter, 12.0, float(p["radius"]) * player.stat("area"), dtell, def.color, 3.0)
                after(dtell, func() -> void: _begin_dawn(dcenter))
            else:
                _begin_dawn(dcenter)
            return
        if has_evo("moonfall_whirl") and nth("katana_whirl", int(evo_param("moonfall_whirl", "every", 5))):
            var tell := float(evo_param("moonfall_whirl", "tell", 0.4))
            if tell > 0.0:
                var tdir := dir
                var tr := r
                world().fx.ring(player.global_position, tr * 0.3, tr, tell, def.color, 2.0)
                after(tell, func() -> void: _whirl(tdir, tr))
            else:
                _whirl(dir, r)
            return
        if has_evo("thousand_cuts") and nth("katana_cuts", int(evo_param("thousand_cuts", "every", 8))) and _start_cuts():
            return
        _swipe(dir, r)

    func _swipe(dir: Vector2, r: float) -> void:
        flip = -flip
        var origin := player.global_position + Vector2(0, -10)
        var amount := dmg()
        var knock := float(p["knockback"])
        var atk_ctx := {"dir": dir, "radius": r, "origin": origin, "mult": 1.0, "cancel": false}
        hook("on_attack", atk_ctx)
        if bool(atk_ctx.get("cancel", false)):
            return
        dir = atk_ctx.get("dir", dir)
        r = float(atk_ctx.get("radius", r))
        origin = atk_ctx.get("origin", origin)
        amount = dmg() * float(atk_ctx.get("mult", 1.0)) * (1.0 + _fervor_bonus())
        if ambush_t > 0.0:
            amount *= ambush_mult
            knock *= 1.5
            ambush_t = 0.0
        var finisher_at := int(evo_param("unbroken_combo", "finisher_at", 6))
        var finisher := has_evo("unbroken_combo") and combo >= finisher_at - 1
        if finisher:
            amount *= float(evo_param("unbroken_combo", "finisher_mult", 2.2))
            knock *= 1.8
            world().fx.ring(origin, r * 0.4, r, 0.22, def.color, 3.0)
        var hit_n: int = _slash_at(origin, dir, r, amount, knock)
        if has_evo("retribution") and gs_retribution > 0.05:
            _retribution_nova(origin)
        Audio.sfx(def.audio_event, -5.0)
        var heavy := float(p["damage"]) >= 28.0
        if hit_n > 0:
            Game.shake(2.5 if heavy else 1.2)
            if heavy:
                var now: float = Time.get_ticks_msec() / 1000.0
                if not flags.has("last_heavy") or now - float(flags.get("last_heavy", 0.0)) > 0.60:
                    flags["last_heavy"] = now
                    Game.hit_stop(0.035, 0.05)
        player.impulse(dir * (60.0 if heavy else 30.0))
        if flags.get("wave", false):
            _fire_wave(origin, dir)
            var extra := int(gs_advance)
            for i in extra:
                var off := deg_to_rad(12.0) * float(i + 1) * (-1.0 if i % 2 == 0 else 1.0)
                _fire_wave(origin, dir.rotated(off))
        if has_evo("unbroken_combo") and hit_n > 0:
            combo += 1
            if combo >= finisher_at:
                combo = 0
        if has_evo("afterimage"):
            var at := origin
            var adir := dir
            var ar := r
            var aknock := knock
            after(float(evo_param("afterimage", "delay", 0.6)), func() -> void: _slash_at(at, adir, ar, dmg() * float(evo_param("afterimage", "mult", 0.7)), aknock * 0.7))

    ## Shared arc slash: damage + fx only (no audio/impulse), so evolutions can
    ## replay it (afterimage) without repeating the whole swing.
    func _slash_at(origin: Vector2, dir: Vector2, r: float, amount: float, knock: float) -> int:
        var arc := deg_to_rad(float(p["arc_deg"]))
        var d := dir
        if p.get("alternate", false):
            d = dir.rotated(flip * 0.35)
        var hits: Array[EnemyManager.E] = world().enemies.query_arc(origin, d, r, arc)
        var col: Color = def.color
        for e in hits:
            world().enemies.damage(e, amount, e.pos - origin, knock, col)
        world().fx.slash_arc(origin, d.angle(), r, arc, col, flip, 0.18 if def.id == "katana" else 0.24, FxManager.PRIO_NORMAL, AbilityArt.weapon_arc_skin(def))
        world().fx.attack_flourish(origin, d)
        for i in 6:
            world().fx.emit(origin + d * r * 0.8, Vector2.from_angle(d.angle() + flip * randf_range(0.2, 1.4)) * randf_range(60.0, 140.0), 0.15, 2.0, col, 2, 5.0)
        _fervor_add(hits.size())
        return hits.size()

    ## moonfall_whirl (Lv16): full spinning slash every 5th swing.
    func _whirl(dir: Vector2, r: float) -> void:
        flip = -flip
        var origin := player.global_position + Vector2(0, -10)
        var amount := dmg() * float(evo_param("moonfall_whirl", "mult", 1.2))
        var col: Color = def.color
        for e in world().enemies.query_circle(origin, r):
            world().enemies.damage(e, amount, e.pos - origin, float(evo_param("moonfall_whirl", "knockback", 160.0)), col)
        world().fx.slash_arc(origin, dir.angle(), r, TAU, col, flip, 0.24, FxManager.PRIO_NORMAL, AbilityArt.weapon_arc_skin(def))
        world().fx.ring(origin, r * 0.3, r, 0.3, col, 3.0)
        Audio.sfx(def.audio_event, -4.0)
        player.invuln = maxf(player.invuln, float(evo_param("moonfall_whirl", "invuln", 0.25)))
        player.impulse(dir * 40.0)
        Game.shake(2.4)

    ## weaving_blades (Lv8): free half-damage slash when brushing past enemies at speed.
    func _weaving(delta: float) -> void:
        for k in weave_hit.keys():
            weave_hit[k] = float(weave_hit[k]) - delta
            if weave_hit[k] <= 0.0:
                weave_hit.erase(k)
        if player.vel.length() < float(evo_param("weaving_blades", "min_speed", 60.0)):
            return
        var origin := player.global_position + Vector2(0, -10)
        for e in world().enemies.query_circle(origin, float(evo_param("weaving_blades", "pass_radius", 30.0))):
            if weave_hit.has(e.uid):
                continue
            weave_hit[e.uid] = float(evo_param("weaving_blades", "per_enemy_icd", 1.2))
            world().enemies.damage(e, dmg() * float(evo_param("weaving_blades", "mult", 0.6)), e.pos - origin, 30.0, def.color, "katana_weave")
            world().fx.emit(e.pos + Vector2(0, -12), Vector2.ZERO, 0.2, 8.0, def.color, 1, 0.0)

    ## thousand_cuts (Lv16): every 8th swing locks a 1s flurry onto the toughest
    ## nearby enemy (elites weighted first). Returns false if nothing is in range.
    func _start_cuts() -> bool:
        var origin := player.global_position + Vector2(0, -10)
        var reach := float(p["radius"]) * player.stat("area") * 3.0
        var best = null
        var best_score := -1.0
        for e in world().enemies.query_circle(origin, reach):
            var score: float = e.hp + (100000.0 if e.is_elite else 0.0)
            if score > best_score:
                best_score = score
                best = e
        if best == null:
            return false
        cut_target = best
        cut_t = float(evo_param("thousand_cuts", "duration", 1.0))
        cut_tick = 0.0
        Audio.sfx(def.audio_event, -5.0)
        world().fx.ring(best.pos, 6.0, 40.0, 0.25, def.color, 3.0)
        return true

    func _cut_tick(delta: float) -> void:
        cut_t -= delta
        player.add_buff("thousand_cuts", 0.15, {}, {"move_speed": float(evo_param("thousand_cuts", "move_mult", 0.4))})
        var tgt = cut_target
        if tgt == null or not tgt.alive:
            cut_t = 0.0
            cut_target = null
            return
        cut_tick -= delta
        if cut_tick <= 0.0:
            cut_tick = float(evo_param("thousand_cuts", "duration", 1.0)) / maxf(float(evo_param("thousand_cuts", "cuts", 10.0)), 1.0)
            var origin := player.global_position + Vector2(0, -10)
            world().enemies.damage(tgt, dmg() * float(evo_param("thousand_cuts", "cut_mult", 0.5)), tgt.pos - origin, 8.0, def.color, "thousand_cuts")
            world().fx.emit(tgt.pos + Vector2(0, -12), Vector2.ZERO, 0.12, 7.0, def.color, 1, 0.0)
        if cut_t <= 0.0:
            cut_target = null

    # ------------------------------------------------------------------ greatsword
    func _greatsword_update(delta: float) -> bool:
        if has_evo("crusaders_march") and player.is_walking():
            gs_advance = minf(float(evo_param("crusaders_march", "max_stacks", 3.0)), gs_advance + float(evo_param("crusaders_march", "build_per_sec", 0.7)) * delta)
        if has_evo("fervor"):
            if gs_fervor_t > 0.0:
                gs_fervor_t -= delta
            elif gs_fervor > 0.0:
                var rate := float(evo_param("fervor", "max_stacks", 10.0)) / maxf(float(evo_param("fervor", "decay", 3.0)), 0.1)
                gs_fervor = maxf(0.0, gs_fervor - rate * delta)
        for i in range(gs_mirror_waves.size() - 1, -1, -1):
            var w: Dictionary = gs_mirror_waves[i]
            w["t"] = float(w["t"]) - delta
            w["pos"] = Vector2(w["pos"]) + Vector2(w["dir"]) * 380.0 * delta
            if float(w["t"]) <= 0.0:
                gs_mirror_waves.remove_at(i)
                continue
            var n: int = world().projectiles.intercept(w["pos"], float(w["r"]), "reflect")
            if n > 0:
                world().fx.ring(w["pos"], 5.0, 28.0, 0.2, Color(1.0, 0.9, 0.55), 2.0)
                Game.shake(1.0)
        if gs_dawn_life > 0.0:
            gs_dawn_life -= delta
            gs_dawn_angle += float(evo_param("dawnbreaker", "turn_rate", 0.9)) * delta
            var beams := int(evo_param("dawnbreaker", "beams", 8))
            var blen := float(p["radius"]) * player.stat("area") * 4.0
            var bdmg := dmg(float(evo_param("dawnbreaker", "mult", 0.6)))
            for i in beams:
                var a := gs_dawn_angle + TAU * float(i) / float(beams)
                var bdir := Vector2.from_angle(a)
                var bend := gs_dawn_center + bdir * blen
                world().fx.beam_between(gs_dawn_center, bend, 7.0, 0.08, def.color)
                EvoPrims.gated_segment_hit(world(), gs_dawn_center, bend, 14.0, bdmg, gs_dawn_gate, world().run_time, 0.35, bdir, 80.0, "dawnbreaker")
        if has_evo("pilgrims_road"):
            _pilgrims_road(delta)
        if has_evo("holy_leap"):
            if gs_leap_t < 0.0:
                gs_leap_t = float(evo_param("holy_leap", "cooldown", 7.0))
            gs_leap_t -= delta
            if gs_leap_t <= 0.0:
                var tgt = _toughest(player.global_position, float(evo_param("holy_leap", "range", 220.0)))
                if tgt == null:
                    gs_leap_t = 0.5
                else:
                    gs_leap_t = float(evo_param("holy_leap", "cooldown", 7.0)) * cd()
                    var ldir: Vector2 = (tgt.pos - player.global_position).normalized()
                    var land: Vector2 = tgt.pos - ldir * 24.0
                    player.blink_to(land, 0.14)
                    var slam_r := float(evo_param("holy_leap", "radius", 70.0)) * player.stat("area")
                    var stun_s := float(evo_param("holy_leap", "stun", 0.8))
                    for e in world().enemies.query_circle(land, slam_r):
                        world().enemies.damage(e, dmg(), e.pos - land, 160.0, def.color, "holy_leap")
                        world().enemies.stun(e, stun_s)
                    world().fx.ring(land, 10.0, slam_r, 0.3, def.color, 4.0)
                    world().fx.star(land, slam_r * 0.5, Color(1.0, 0.95, 0.7), 0.3)
                    Audio.sfx(def.audio_event, -3.0)
                    Game.shake(3.5)
                    return true
        if has_evo("bulwark_stance"):
            var nearest = world().enemies.nearest(player.global_position, 190.0, {})
            if nearest != null and not player.is_walking():
                gs_still += delta
                gs_guard_dir = (nearest.pos - player.global_position).normalized()
                gs_guard_on = gs_still >= float(evo_param("bulwark_stance", "still_time", 1.0))
            else:
                gs_still = 0.0
                gs_guard_on = false
            if gs_guard_on:
                var guard_arc := deg_to_rad(float(evo_param("bulwark_stance", "arc_deg", 120.0)))
                var gn: int = world().projectiles.intercept(player.global_position, 38.0, "destroy", gs_guard_dir, guard_arc)
                if gn > 0:
                    world().fx.ring(player.global_position, 8.0, 38.0, 0.16, Color(1.0, 0.92, 0.55), 2.0)
        return false

    func _fervor_bonus() -> float:
        if not has_evo("fervor"):
            return 0.0
        var cap := float(evo_param("fervor", "bonus_cap", 0.35))
        var max_s := maxf(float(evo_param("fervor", "max_stacks", 10.0)), 1.0)
        return cap * clampf(gs_fervor / max_s, 0.0, 1.0)

    func _fervor_add(n: int) -> void:
        if n <= 0 or not has_evo("fervor"):
            return
        gs_fervor = minf(float(evo_param("fervor", "max_stacks", 10.0)), gs_fervor + float(n))
        gs_fervor_t = float(evo_param("fervor", "decay", 3.0))

    func _fire_wave(origin: Vector2, dir: Vector2) -> void:
        var opts := {"skin": AbilityArt.weapon_proj_skin(def), "w": 0.75, "knock": 60.0}
        if has_evo("fervor"):
            opts["hit_cb"] = func(_e) -> void: _fervor_add(1)
        world().projectiles.fire(ProjectileManager.Kind.HOLY, origin, dir, 380.0, dmg(float(p["wave_damage"])), 24.0, 999, 0.75, Color(1.0, 0.93, 0.6), opts)
        if has_evo("mirror_wave"):
            gs_mirror_waves.append({"pos": origin, "dir": dir.normalized(), "t": 0.75, "r": float(evo_param("mirror_wave", "reflect_radius", 30.0))})

    func _begin_dawn(center: Vector2) -> void:
        gs_dawn_center = center
        gs_dawn_angle = 0.0
        gs_dawn_life = float(evo_param("dawnbreaker", "life", 1.5))
        gs_dawn_gate.clear()
        world().fx.ring(center, 12.0, float(p["radius"]) * player.stat("area"), 0.3, def.color, 4.0)
        Audio.sfx(def.audio_event, -3.0)
        Game.shake(3.0)

    func _pilgrims_road(delta: float) -> void:
        var ppos := player.global_position
        if player.is_walking():
            var spacing := float(evo_param("pilgrims_road", "spacing", 28.0))
            if gs_road_last == Vector2.INF or gs_road_last.distance_to(ppos) >= spacing:
                gs_road_last = ppos
                var rr := maxf(16.0, float(p["radius"]) * player.stat("area") * 0.45)
                var life := float(evo_param("pilgrims_road", "life", 3.0))
                var dec := {"kind": "radiant_road", "pos": ppos, "r": rr, "t": 0.0, "life": life, "dead": false}
                world().add_decal(dec)
                gs_road.append({"pos": ppos, "r": rr, "t": 0.0, "life": life, "decal": dec})
        var on_road := false
        for i in range(gs_road.size() - 1, -1, -1):
            var tile: Dictionary = gs_road[i]
            tile["t"] = float(tile["t"]) + delta
            var dec2: Dictionary = tile["decal"]
            dec2["t"] = tile["t"]
            if float(tile["t"]) >= float(tile["life"]):
                dec2["dead"] = true
                gs_road.remove_at(i)
            elif ppos.distance_to(tile["pos"]) <= float(tile["r"]) + 8.0:
                on_road = true
        if on_road:
            player.add_buff("pilgrims_road", 0.12, {}, {"move_speed": 1.0 + float(evo_param("pilgrims_road", "speed_bonus", 0.15))})
        gs_road_tick -= delta
        if gs_road_tick <= 0.0:
            gs_road_tick = 0.25
            var burn_dps := dmg(float(evo_param("pilgrims_road", "dps_mult", 0.3)))
            for tile2 in gs_road:
                for e in world().enemies.query_ground_circle(tile2["pos"], float(tile2["r"])):
                    world().enemies.burn(e, burn_dps, 0.45)

    func _retribution_nova(origin: Vector2) -> void:
        var charge := clampf(gs_retribution, 0.0, float(evo_param("retribution", "charge_cap", 1.0)))
        gs_retribution = 0.0
        if charge <= 0.05:
            return
        var nr := float(evo_param("retribution", "radius", 90.0)) * player.stat("area")
        var mult := 1.0 + charge * (float(evo_param("retribution", "mult_cap", 2.0)) - 1.0)
        for e in world().enemies.query_circle(origin, nr):
            world().enemies.damage(e, dmg() * mult, e.pos - origin, float(evo_param("retribution", "knockback", 200.0)), def.color, "retribution")
        world().fx.ring(origin, 12.0, nr, 0.3, Color(1.0, 0.9, 0.55), 4.0)
        Game.shake(2.5)

    func _toughest(origin: Vector2, max_r: float):
        var best = null
        var best_score := -1.0
        for e in world().enemies.query_ground_circle(origin, max_r):
            var score: float = e.hp + (100000.0 if e.is_elite else 0.0)
            if score > best_score:
                best_score = score
                best = e
        return best

    func incoming_damage_mult(_amount: float, source_pos: Vector2, _source: String) -> float:
        if not has_evo("bulwark_stance") or not gs_guard_on or not source_pos.is_finite():
            return 1.0
        var to := source_pos - player.global_position
        if to.length_squared() < 0.001:
            return 1.0
        var arc := deg_to_rad(float(evo_param("bulwark_stance", "arc_deg", 120.0)))
        if absf(gs_guard_dir.angle_to(to)) <= arc * 0.5:
            return 1.0 - clampf(float(evo_param("bulwark_stance", "reduce", 0.6)), 0.0, 0.95)
        return 1.0

    func draw_overlay(c: Node2D) -> void:
        if has_evo("fervor") and gs_fervor > 0.0:
            var k := _fervor_bonus() / maxf(float(evo_param("fervor", "bonus_cap", 0.35)), 0.01)
            c.draw_arc(Vector2(0, -16), 24.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, Color(1.0, 0.55, 0.25, 0.9), 2.0)
        if has_evo("bulwark_stance") and gs_guard_on:
            var arc := deg_to_rad(float(evo_param("bulwark_stance", "arc_deg", 120.0)))
            var a := gs_guard_dir.angle()
            var rr := float(p["radius"]) * player.stat("area") * 0.7
            c.draw_arc(Vector2(0, -10), rr, a - arc * 0.5, a + arc * 0.5, 20, Color(1.0, 0.9, 0.5, 0.8), 3.0)

    ## reprisal (Lv16): a cross-slash on being hurt (6s cooldown).
    func on_player_hurt(amount: float) -> void:
        if has_evo("unbroken_combo"):
            combo = 0
        if has_evo("reprisal") and reprisal_t <= 0.0:
            reprisal_t = float(evo_param("reprisal", "cooldown", 6.0))
            _reprisal()
        if has_evo("crusaders_march") and bool(evo_param("crusaders_march", "clear_on_hurt", true)):
            gs_advance = 0.0
        if has_evo("retribution"):
            gs_retribution = minf(float(evo_param("retribution", "charge_cap", 1.0)), gs_retribution + amount * float(evo_param("retribution", "charge_per_hp", 0.01)))

    func _reprisal() -> void:
        var origin := player.global_position + Vector2(0, -10)
        var r := float(p["radius"]) * player.stat("area") * 1.1
        var arc := deg_to_rad(float(p["arc_deg"]))
        var col: Color = def.color
        var base := player.last_dir.angle()
        for off in [0.0, PI * 0.5]:
            var d := Vector2.from_angle(base + off)
            for e in world().enemies.query_arc(origin, d, r, arc):
                world().enemies.damage(e, dmg() * float(evo_param("reprisal", "mult", 1.5)), e.pos - origin, float(evo_param("reprisal", "knockback", 220.0)), col, "reprisal")
            world().fx.slash_arc(origin, base + off, r, arc, col, 1.0, 0.2, FxManager.PRIO_NORMAL, AbilityArt.weapon_arc_skin(def))
        world().fx.ring(origin, r * 0.4, r, 0.25, col, 3.0)
        Audio.sfx(def.audio_event, -3.0)
        Game.shake(3.0)

    ## Vanish ambush: Flash Bombs arms the next swing for extra damage.
    func set_ambush(seconds: float, mult: float = 2.5) -> void:
        ambush_t = maxf(ambush_t, seconds)
        ambush_mult = mult

    func _try_charge() -> void:
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, 320.0)
        charge_t = float(p["charge_interval"]) * randf_range(0.7, 1.3) * cd()
        if tgt == null:
            return
        var dir: Vector2 = (tgt.pos - player.global_position).normalized()
        player.start_dash(dir, 230.0, 540.0, {"damage": dmg(float(p["charge_damage"])), "hit_radius": 22.0, "impale": true, "invuln": true, "color": def.color})
        Audio.sfx("horn_swipe", -2.0, 0.65)
        world().fx.ring(player.global_position, 4.0, 40.0, 0.25, Color(1.0, 0.8, 0.5), 3.0)


# =============================================================================================== Spider
class MeleeBite extends Ability:
    func update(delta: float) -> void:
        t -= delta
        if t > 0.0:
            return
        var reach := float(p["range"]) * player.stat("area")
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, reach + 12.0)
        if tgt == null:
            t = 0.03
            return
        t = float(p["cooldown"]) * cd()
        var origin := player.global_position + Vector2(0, -10)
        var dir: Vector2 = (tgt.pos - origin).normalized()
        var hits: Array[EnemyManager.E] = world().enemies.query_arc(origin, dir, reach, deg_to_rad(80.0))
        var paralysed := 0
        for e in hits:
            world().enemies.damage(e, dmg(), dir, 40.0, Color(0.85, 0.5, 1.0))
            if randf() < float(p["paralysis_chance"]):
                world().enemies.stun(e, float(p["paralysis_time"]))
                paralysed += 1
                world().fx.emit(e.pos + Vector2(0, -12), Vector2.ZERO, 0.35, 10.0, Color(1.0, 0.95, 0.4), 1, 0.0)
        var ang := dir.angle()
        for s in [-1.0, 1.0]:
            var a: float = ang + s * 0.22
            world().fx.emit(origin + Vector2.from_angle(a) * reach * 0.4, Vector2.from_angle(a) * 260.0, 0.1, 2.5, Color(1, 1, 1), 2, 4.0)
            world().fx.emit(origin + Vector2.from_angle(a) * reach * 0.8, Vector2.from_angle(a) * 120.0, 0.16, 2.0, Color(0.8, 0.4, 1.0), 2, 4.0)
        Audio.sfx("fang_bite", -6.0)
        world().fx.attack_flourish(origin, dir)
        if paralysed > 0:
            Game.shake(1.5)
        player.impulse(dir * 90.0)


# =============================================================================================== Wizard
class ChainLightning extends Ability:
    var orbs: Array = []

    func update(delta: float) -> void:
        _update_orbs(delta)
        t -= delta
        if t > 0.0:
            return
        var tgt: EnemyManager.E = player.target()
        if tgt == null or tgt.pos.distance_to(player.global_position) > float(p["range"]):
            t = 0.05
            return
        t = float(p["cooldown"]) * cd()
        var used: Dictionary = {}
        var bolts: int = player.scaled_count(1)
        for b in bolts:
            var first: EnemyManager.E = tgt if b == 0 else world().enemies.nearest(player.global_position, float(p["range"]), used)
            if first == null:
                break
            used[first.uid] = true
            _zap(first, b)
        Audio.sfx("lightning_bolt", -5.0)

    func _zap(first: EnemyManager.E, idx: int) -> void:
        var col := Color(0.55, 0.85, 1.0)
        var hit: Dictionary = {}
        hit[first.uid] = true
        var from := player.fire_origin(idx, (first.pos - player.global_position).normalized()) + Vector2(0, -6)
        var cur: EnemyManager.E = first
        for i in int(p["chains"]) + 1:
            world().enemies.damage(cur, dmg() * (1.0 if i == 0 else 0.8), Vector2.ZERO, 0.0, col)
            world().fx.bolt(WeaponBehaviors.jagged(from, cur.pos + Vector2(0, -8)), col, 0.2)
            world().fx.attack_flourish(player.global_position, cur.pos - player.global_position)
            world().fx.emit(cur.pos + Vector2(0, -8), Vector2.ZERO, 0.1, 9.0, Color(0.85, 0.95, 1.0), 1, 0.0)
            from = cur.pos + Vector2(0, -8)
            var nxt: EnemyManager.E = world().enemies.nearest(cur.pos, float(p["chain_range"]), hit)
            if nxt == null:
                break
            hit[nxt.uid] = true
            cur = nxt
        world().fx.strike(first.pos)
        if flags.get("orb", false):
            _place_orb(first.pos)

    func _place_orb(pos: Vector2) -> void:
        if orbs.size() >= 3:
            orbs.pop_front()
        orbs.append({"pos": pos, "t": float(p["orb_time"]), "tick": 0.2})
        world().fx.ring(pos, 3.0, 22.0, 0.25, Color(0.7, 0.9, 1.0), 2.0)

    func _update_orbs(delta: float) -> void:
        for i in range(orbs.size() - 1, -1, -1):
            var o: Dictionary = orbs[i]
            o["t"] = float(o["t"]) - delta
            o["tick"] = float(o["tick"]) - delta
            var pos: Vector2 = o["pos"]
            world().fx.emit(pos + Vector2(0, -6), Vector2.ZERO, 0.07, 6.0 + sin(o["t"] * 20.0), Color(0.6, 0.85, 1.0), 1, 0.0)
            if float(o["tick"]) <= 0.0:
                o["tick"] = 0.55
                var targets: Array[EnemyManager.E] = world().enemies.query_circle(pos, float(p["chain_range"]))
                var n := 0
                for e in targets:
                    if n >= int(p["orb_chains"]):
                        break
                    n += 1
                    world().enemies.damage(e, dmg(float(p["orb_damage"])), Vector2.ZERO, 0.0, Color(0.6, 0.85, 1.0))
                    world().fx.bolt(WeaponBehaviors.jagged(pos + Vector2(0, -6), e.pos + Vector2(0, -8), 4, 5.0), Color(0.6, 0.85, 1.0), 0.14)
            if float(o["t"]) <= 0.0:
                orbs.remove_at(i)


# =============================================================================================== Harpy
class Screech extends Ability:
    var queued := 0
    var gap_t := 0.0

    func update(delta: float) -> void:
        if queued > 0:
            gap_t -= delta
            if gap_t <= 0.0:
                queued -= 1
                gap_t = float(p["gap"])
                _emit_wave()
            return
        t -= delta
        if t > 0.0:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, float(p["distance"]) + 40.0)
        if tgt == null:
            t = 0.05
            return
        t = float(p["cooldown"]) * cd()
        queued = maxi(1, int(round(float(p["consecutive"]))))
        gap_t = 0.0

    func _emit_wave() -> void:
        var dir := player.aim_dir()
        var dist := float(p["distance"]) * player.stat("area")
        var speed := float(p["speed"])
        var origin := player.global_position + Vector2(0, -14)
        for i in player.scaled_count(1):
            var d := dir.rotated(0.0 if i == 0 else (float(i) * 0.35 * (1.0 if i % 2 == 0 else -1.0)))
            world().projectiles.fire(ProjectileManager.Kind.WAVE, origin, d, speed, dmg(), float(p["width"]) * 0.5, 999, dist / speed, Color(1.0, 0.95, 0.75), {"skin": AbilityArt.weapon_proj_skin(def), "w": 0.85, "knock": 50.0, "rehit": 9999.0, "grow": 26.0})
        world().fx.ring(origin, 3.0, 30.0, 0.2, Color(1.0, 0.95, 0.75), 2.0)
        Audio.sfx("screech", -6.0)
        Game.shake(1.0)


# =============================================================================================== Necromancer
class SkullSummon extends Ability:
    func update(delta: float) -> void:
        t -= delta
        if t > 0.0:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, float(p["range"]))
        if tgt == null:
            t = 0.05
            return
        t = float(p["cooldown"]) * cd()
        var count := maxi(1, int(round(float(p["count"]))))
        count = player.scaled_count(count)
        var base_dir: Vector2 = (tgt.pos - player.global_position).normalized()
        for i in count:
            var off := (float(i) - float(count - 1) * 0.5) * 0.42
            var d := base_dir.rotated(off)
            var size := float(p["size"])
            world().projectiles.fire(ProjectileManager.Kind.SKULL, player.global_position + Vector2(0, -16), d, float(p["speed"]), dmg(), 11.0 * size, 999, float(p["life"]), Color(0.45, 1.0, 0.9), {"skin": AbilityArt.weapon_proj_skin(def), "rehit": 0.45, "knock": 25.0})
        world().fx.ring(player.global_position + Vector2(0, -16), 3.0, 24.0, 0.25, Color(0.45, 1.0, 0.9), 2.0)
        Audio.sfx("skull_projectile", -6.0)


# =============================================================================================== Goose
class GooseCharge extends Ability:
    func update(delta: float) -> void:
        t -= delta
        if t > 0.0 or player.dash_t > 0.0:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, 420.0)
        if tgt == null:
            t = 0.1
            return
        t = float(p["interval"]) * cd()
        var dir: Vector2 = (tgt.pos - player.global_position).normalized()
        var fr := float(p["fear_radius"]) * player.stat("area")
        var opts := {"fear_radius": fr, "fear_time": float(p["fear_time"]), "invuln": false, "color": Color(1, 1, 1)}
        if float(p["charge_damage"]) > 0.0:
            opts["damage"] = float(p["charge_damage"]) * player.stat("damage")
            opts["hit_radius"] = 16.0
        player.start_dash(dir, float(p["distance"]), float(p["charge_speed"]), opts)
        world().fx.attack_flourish(player.global_position, dir)
        world().fx.ring(player.global_position, 6.0, fr, 0.45, Color(1.0, 1.0, 0.8), 3.0)
        world().fx.ring(player.global_position, 2.0, fr * 0.6, 0.3, Color(1, 1, 1), 2.0)
        Audio.sfx("goose_charge", -3.0)
        Game.shake(2.0)


# =============================================================================================== Treasure chest pickups (ported from bare-bones-survivor export)
class PickupVolley extends Ability:
    const AKIMBO_OFFSET := 9.0                       # px between the two hands
    const HEAVY_RADIUS := 1.7                        # Dead-Eye slug size multiplier
    const HEAVY_COLOR := Color(1.0, 0.95, 0.7)
    const BURN_COLOR := Color(1.0, 0.45, 0.15)
    var volley_t := 0.0
    var shot_n := 0
    var volley_n := 0

    func on_ready() -> void:
        volley_t = float(p["cooldown"]) * 0.5

    func update(delta: float) -> void:
        volley_t -= delta
        if volley_t > 0.0:
            return
        var attack_range: float = float(p["range"])
        var tgt: EnemyManager.E = player.target()
        if tgt == null or not tgt.alive or tgt.pos.distance_to(player.global_position) > attack_range:
            tgt = world().enemies.nearest(player.global_position, attack_range)
        if tgt == null:
            volley_t = 0.05
            return
        volley_t = float(p["cooldown"]) * cd()
        var dir: Vector2 = (tgt.pos - player.global_position).normalized()
        var n: int = player.scaled_count(int(p["count"]))
        var spread: float = deg_to_rad(float(p["spread_deg"]))
        var kind: int = ProjectileManager.Kind.CANNON if def.id == "pickup_blunderbuss" else (ProjectileManager.Kind.SHURIKEN if def.id == "pickup_shurikens" else ProjectileManager.Kind.BULLET)
        var col: Color = def.color
        # ---- Black Market mods (flags come from the owned MarketItemDef listings) ----
        var pierce: int = int(p["pierce"])
        var radius: float = float(p["radius"])
        var dmg_mult: float = 1.0
        var opts: Dictionary = {"knock": float(p["knockback"]), "skin": AbilityArt.weapon_proj_skin(def)}
        var burn_dps: float = mod_f("burn_dps")                       # Brimstone Breath
        if burn_dps > 0.0:
            opts["burn_dps"] = burn_dps * player.stat("damage")
            opts["burn_time"] = mod_f("burn_time", 3.0)
            col = BURN_COLOR
        shot_n += 1
        volley_n += 1
        var heavy_every: int = int(mod_f("heavy_every"))              # Dead-Eye
        var heavy: bool = heavy_every > 0 and shot_n % heavy_every == 0
        if heavy:
            dmg_mult = mod_f("heavy_mult", 3.0)
            pierce += int(mod_f("heavy_pierce"))
            radius *= HEAVY_RADIUS
            col = HEAVY_COLOR
        var hands: int = 2 if has_mod("akimbo") else 1                # Akimbo
        for h in hands:
            var side: float = 0.0
            if hands > 1:
                side = (-1.0 + 2.0 * float(h)) * AKIMBO_OFFSET
            for i in n:
                var off: float = 0.0
                if n > 1:
                    off = -spread * 0.5 + spread * float(i) / float(n - 1)
                var d: Vector2 = dir.rotated(off + randf_range(-0.03, 0.03))
                var o: Vector2 = player.fire_origin(i, d) + d.orthogonal() * side
                world().projectiles.fire(kind, o, d, float(p["speed"]), dmg(dmg_mult), radius, pierce, float(p["range"]) / float(p["speed"]), col, opts)
        var ring_every: int = int(mod_f("ring_every"))                # Storm Nova
        if ring_every > 0 and volley_n % ring_every == 0:
            _fire_ring(kind, col, pierce, opts)
        world().fx.muzzle(player.fire_origin(0, dir), dir, col, AbilityArt.weapon_muzzle_skin(def))
        Audio.sfx(def.audio_event, -7.0, 0.8 if heavy else 1.0)
        if heavy:
            Game.shake(2.5)
        if def.id == "pickup_blunderbuss" or def.id == "pickup_aa12":
            Game.shake(2.0)
            player.impulse(-dir * 40.0)

    ## Storm Nova: a full ring of the weapon's own projectiles around the player.
    func _fire_ring(kind: int, col: Color, pierce: int, opts: Dictionary) -> void:
        var ring_n: int = maxi(3, int(mod_f("ring_count", 8.0)))
        var base_a: float = randf() * TAU
        var centre: Vector2 = player.global_position + Vector2(0, -14)
        for k in ring_n:
            var d: Vector2 = Vector2.from_angle(base_a + TAU * float(k) / float(ring_n))
            world().projectiles.fire(kind, centre + d * 10.0, d, float(p["speed"]), dmg(), float(p["radius"]), pierce, float(p["range"]) / float(p["speed"]), col, opts)
        world().fx.ring(centre, 6.0, 70.0, 0.25, col, 2.0)

    func hud_line() -> String:
        if volley_t <= 0.0:
            return "READY"
        return "%0.1fs" % volley_t


class PickupBlast extends Ability:
    const CLUSTER_DELAY := 0.14      # seconds between aftershocks
    const CLUSTER_RADIUS := 0.55     # aftershock radius vs the main blast
    const CLUSTER_DAMAGE := 0.5      # aftershock damage vs the main blast
    var blast_t := 0.0
    var blasts: Array = []
    var pending: Array = []

    func on_ready() -> void:
        blast_t = float(p["cooldown"]) * 0.5

    func update(delta: float) -> void:
        for i in range(blasts.size() - 1, -1, -1):
            var b: Dictionary = blasts[i]
            b["t"] = float(b["t"]) + delta
            if float(b["t"]) >= float(b["life"]):
                b["dead"] = true
                blasts.remove_at(i)
        for i in range(pending.size() - 1, -1, -1):                   # Cluster Charges aftershocks
            var pb: Dictionary = pending[i]
            pb["t"] = float(pb["t"]) - delta
            if float(pb["t"]) <= 0.0:
                pending.remove_at(i)
                var pat: Vector2 = pb["at"]
                _detonate(pat, float(pb["r"]), float(pb["dmg"]), true)
        blast_t -= delta
        if blast_t > 0.0:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, float(p["range"]))
        if tgt == null:
            blast_t = 0.1
            return
        blast_t = float(p["cooldown"]) * cd()
        var at: Vector2 = tgt.pos
        var r: float = float(p["radius"]) * player.stat("area")
        _detonate(at, r, dmg(), false)
        var cluster_n: int = int(mod_f("cluster"))
        for k in cluster_n:
            var off: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(r * 0.35, r * 0.9)
            pending.append({"t": CLUSTER_DELAY * float(k + 1), "at": at + off, "r": r * CLUSTER_RADIUS, "dmg": dmg(CLUSTER_DAMAGE)})

    ## One explosion: damage + optional stun (Concussion Charge), rings, sparks, decal. Mini blasts are the Cluster aftershocks.
    func _detonate(at: Vector2, r: float, damage_amount: float, mini: bool) -> void:
        world().fx.attack_flourish(player.global_position, at - player.global_position)
        var col: Color = def.color
        var stun_t: float = mod_f("stun")
        for e in world().enemies.query_circle(at, r):
            world().enemies.damage(e, damage_amount, e.pos - at, 160.0, col)
            if stun_t > 0.0 and e.alive:
                world().enemies.stun(e, stun_t)
        world().fx.ring(at, 6.0, r, 0.35, col, 4.0)
        world().fx.ring(at, 2.0, r * 0.6, 0.25, Color(1, 1, 1), 2.0)
        for i in (6 if mini else 14):
            world().fx.emit(at + Vector2.from_angle(randf() * TAU) * randf_range(0.0, r * 0.5), Vector2.from_angle(randf() * TAU) * randf_range(60.0, 240.0), randf_range(0.25, 0.5), randf_range(1.5, 3.0), col, 0, 4.0, 60.0, false)
        world().fx.strike(at, 0.35 if mini else 0.7)
        var bsize: float = clampf(r * 0.75, 40.0 if mini else 64.0, 128.0)
        var btex: String = "res://art/weapons/dynamite.png" if def.id == "pickup_dynamite" else "res://art/weapons/keg.png"
        var bd := {"kind": "blast", "pos": at, "t": 0.0, "dead": false, "tex": btex, "size": bsize, "life": 0.35}
        blasts.append(bd)
        world().add_decal(bd)
        Audio.sfx(def.audio_event, -9.0 if mini else -3.0, 1.0 if mini else 0.7)
        if mini:
            return
        if def.id == "pickup_keg":
            Game.shake(4.0)
            Game.hit_stop(0.04, 0.05)
        else:
            Game.shake(2.5)

    func hud_line() -> String:
        if blast_t <= 0.0:
            return "READY"
        return "%0.1fs" % blast_t


class PickupCaltrops extends Ability:
    var caltrops: Array = []
    var scan_t := 0.0

    func on_ready() -> void:
        t = 0.5

    func update(delta: float) -> void:
        var now: float = world().run_time
        t -= delta
        if t <= 0.0:
            t = float(p["interval"]) * cd()
            _drop()
        scan_t -= delta
        var check := scan_t <= 0.0
        if check:
            scan_t = 0.12
        for i in range(caltrops.size() - 1, -1, -1):
            var d: Dictionary = caltrops[i]
            d["t"] = float(d["t"]) + delta
            if bool(d["dead"]) or float(d["t"]) >= float(p["lifetime"]):
                d["dead"] = true
                caltrops.remove_at(i)
                continue
            if not check:
                continue
            d["r"] = float(p["radius"]) * player.stat("area")
            var cpos: Vector2 = d["pos"]
            # Ground trap: skip flying enemies (height == 1).
            for e in world().enemies.query_ground_circle(cpos, float(d["r"])):
                var slot: Dictionary = d["seen"]
                if float(slot.get(e.uid, -9.0)) > now:
                    continue
                slot[e.uid] = now + float(p["rehit"])
                world().enemies.damage(e, dmg(), e.pos - cpos, 18.0, def.color)
                var slow_mult: float = mod_f("slow_mult", 1.0)          # Barbed Tangle
                if slow_mult < 1.0 and e.alive:
                    world().enemies.slow(e, slow_mult, mod_f("slow_time", 2.0))
                world().fx.emit(e.pos + Vector2(0, -6), Vector2(0, -40.0), 0.2, 2.0, def.color, 1, 1.0)
                Audio.sfx(def.audio_event, -12.0, 1.2, 0.2)

    func _drop() -> void:
        var pos := player.global_position + Vector2(randf_range(-16.0, 16.0), randf_range(-12.0, 12.0))
        while caltrops.size() >= int(round(float(p["max_caltrops"]))):
            var old: Dictionary = caltrops.pop_front()
            old["dead"] = true
        var d := {"kind": "caltrop", "pos": pos, "t": 0.0, "dead": false, "seen": {}, "r": float(p["radius"]), "life": float(p["lifetime"])}
        caltrops.append(d)
        world().add_decal(d)
        world().fx.emit(pos, Vector2(0, -20.0), 0.2, 2.0, def.color, 1, 1.0)
        Audio.sfx(def.audio_event, -14.0, 1.4, 0.2)
        world().fx.attack_flourish(player.global_position, player.aim_dir())

    func hud_line() -> String:
        return "%d/%d" % [caltrops.size(), int(round(float(p["max_caltrops"])))]


class PickupBuff extends Ability:
    var buff_cd := 0.0
    var active_t := 0.0

    func on_ready() -> void:
        buff_cd = float(p["cooldown"]) * 0.4

    func update(delta: float) -> void:
        if active_t > 0.0:
            active_t -= delta
        buff_cd -= delta
        if buff_cd > 0.0:
            return
        buff_cd = float(p["cooldown"]) * cd()
        var dur: float = float(p["duration"])
        active_t = dur
        player.add_buff("pickup_energy", dur, {}, {"damage": 2.0, "move_speed": 1.5})
        world().fx.level_up_burst(player.global_position + Vector2(0, -10))
        world().announce("ENERGIZED!", false)
        var heal_pct: float = mod_f("heal_pct")                         # Hearty Meal
        if heal_pct > 0.0:
            player.heal(player.max_hp * heal_pct)
        Audio.sfx(def.audio_event, 0.0, 1.2)

    func hud_line() -> String:
        if active_t > 0.0:
            return "x2 %ds" % maxi(0, ceili(active_t))
        return "%ds" % maxi(0, ceili(buff_cd))


class PickupWard extends Ability:
    var ward_cd := 0.0
    var active_t := 0.0

    func on_ready() -> void:
        ward_cd = float(p["cooldown"]) * 0.4

    func update(delta: float) -> void:
        if active_t > 0.0:
            active_t -= delta
            if active_t <= 0.0:
                if player.armor > 0.0:
                    player.armor = 0.0
                player.remove_buff("pickup_cloak")
                ward_cd = float(p["cooldown"]) * cd()
            return
        ward_cd -= delta
        if ward_cd > 0.0:
            return
        var dur: float = float(p["duration"])
        active_t = dur
        player.armor = float(p["armor_hp"])
        player.add_buff("pickup_cloak", dur, {}, {"damage": 1.1})
        world().fx.ring(player.global_position + Vector2(0, -12), 6.0, 90.0, 0.4, Color(0.5, 0.6, 1.0), 3.0)
        world().announce("CLOAK OF ARMOR", false)
        Audio.sfx(def.audio_event, -2.0, 0.8)
        var pulse_r: float = mod_f("pulse_r")                           # Warding Pulse
        if pulse_r > 0.0:
            _pulse(pulse_r * player.stat("area"))

    ## Warding Pulse: raising the ward shoves, stuns and damages everything close.
    func _pulse(r: float) -> void:
        var at: Vector2 = player.global_position
        var stun_t: float = mod_f("pulse_stun", 1.0)
        var knock: float = mod_f("pulse_knock", 220.0)
        var amount: float = dmg()
        for e in world().enemies.query_circle(at, r):
            world().enemies.damage(e, amount, e.pos - at, knock, def.color)
            if e.alive:
                world().enemies.stun(e, stun_t)
        world().fx.ring(at + Vector2(0, -12), 8.0, r, 0.4, Color(0.7, 0.8, 1.0), 4.0)
        Game.shake(3.0)

    func hud_line() -> String:
        if active_t > 0.0:
            return "ARMOR %d" % int(player.armor)
        return "%ds" % maxi(0, ceili(ward_cd))


# =============================================================================================== Fun-Guy
class MyceliumNet extends Ability:
    const BURST_INFECT_CAP := 8
    const SPORE_RANGE_PAD := 60.0
    const SPORE_HIT_R := 8.0
    const INFECT_TICK := 0.5

    var anim_t := 0.0
    var nodes: Array = []
    var threads: Array = []
    var spores: Array = []
    var infected: Dictionary = {}
    var bursts: Array = []
    var gate: Dictionary = {}

    func on_ready() -> void:
        t = float(p["cooldown"]) * 0.5

    func update(delta: float) -> void:
        anim_t += delta
        var area: float = player.stat("area")
        t -= delta
        if t <= 0.0:
            var tgt: EnemyManager.E = _nearest_ground(player.global_position, float(p["reach"]))
            if tgt == null:
                t = 0.05
            else:
                t = maxf(0.2, float(p["cooldown"]) * cd())
                _spawn_node(tgt.pos, area)
        _step_nodes(delta, area)
        if float(p.get("threads_enabled", 1.0)) > 0.5:
            _rebuild_threads(area)
            _thread_hits(area)
        else:
            threads.clear()
        _step_spores(delta)
        _step_infection(delta)
        _resolve_bursts(area)
        if gate.size() > 256:
            for k in gate.keys():
                if float(gate[k]) < anim_t:
                    gate.erase(k)

    func _spawn_node(pos: Vector2, area: float) -> void:
        nodes.append({"pos": pos, "age": 0.0, "volley": float(p["launch_interval"]), "dead": false, "t": 0.0, "r": float(p["node_radius"]) * area, "life": float(p["node_life"])})
        var d: Dictionary = {"kind": "node", "pos": pos, "t": 0.0, "dead": false, "r": float(p["node_radius"]) * area, "life": float(p["node_life"])}
        nodes[nodes.size() - 1]["decal"] = d
        world().add_decal(d)
        while nodes.size() > int(round(float(p["max_nodes"]))):
            _expire_node(0, area)
        _blast(pos, float(p["node_radius"]) * area, float(p["pop_dmg"]) * player.stat("damage"), true)
        world().fx.attack_flourish(player.global_position, pos - player.global_position)
        world().fx.ring(pos, 4.0, float(p["node_radius"]) * area, 0.3, def.color, 3.0)
        Audio.sfx(def.audio_event, -6.0)
        Game.shake(1.0)

    func _expire_node(i: int, area: float) -> void:
        var n: Dictionary = nodes[i]
        nodes.remove_at(i)
        (n["decal"] as Dictionary)["dead"] = true
        if float(p["expire_burst_dmg"]) > 0.0:
            var pos: Vector2 = n["pos"]
            _blast(pos, float(p["expire_burst_radius"]) * area, float(p["expire_burst_dmg"]) * player.stat("damage"), false)
            world().fx.ring(pos, 4.0, float(p["expire_burst_radius"]) * area, 0.35, Color(0.9, 1.0, 0.6), 3.0)
            Audio.sfx(def.audio_event, -8.0, 1.4)

    func _step_nodes(delta: float, area: float) -> void:
        for i in range(nodes.size() - 1, -1, -1):
            var n: Dictionary = nodes[i]
            n["age"] = float(n["age"]) + delta
            n["t"] = float(n["t"]) + delta
            if float(n["age"]) >= float(p["node_life"]):
                _expire_node(i, area)
            elif float(p.get("ballistic", 0.0)) > 0.5:
                n["volley"] = float(n["volley"]) - delta
                if float(n["volley"]) <= 0.0:
                    if _fire_volley(n["pos"]):
                        n["volley"] = maxf(0.2, float(p["launch_interval"]) * cd())
                    else:
                        n["volley"] = 0.0

    func _rebuild_threads(area: float) -> void:
        threads.clear()
        var reach: float = float(p["link_range"]) * area
        var reach_sq: float = reach * reach
        var seen := {}
        for i in nodes.size():
            var cands: Array = []
            for j in nodes.size():
                if j == i:
                    continue
                var d: float = (nodes[i]["pos"] as Vector2).distance_squared_to(nodes[j]["pos"])
                if d <= reach_sq:
                    cands.append([d, j])
            cands.sort_custom(func(a, b): return a[0] < b[0])
            for k in mini(cands.size(), int(round(float(p["links_per_node"])))):
                var j: int = int(cands[k][1])
                var key: int = mini(i, j) * 100 + maxi(i, j)
                if not seen.has(key):
                    seen[key] = true
                    threads.append([(nodes[i]["pos"] as Vector2), (nodes[j]["pos"] as Vector2)])

    func _thread_hits(area: float) -> void:
        if threads.is_empty():
            return
        var half: float = float(p["thread_half_width"]) * area
        var dmg_tick: float = float(p["thread_dmg"]) * player.stat("damage")
        for e in world().enemies.active.duplicate():
            if not e.alive or e.def.height == 1:
                continue
            if float(gate.get(e.uid, -9.0)) > anim_t:
                continue
            for seg in threads:
                var a: Vector2 = seg[0]
                var b: Vector2 = seg[1]
                var q: Vector2 = Geometry2D.get_closest_point_to_segment(e.pos, a, b)
                if q.distance_to(e.pos) <= half + e.radius:
                    world().enemies.damage(e, dmg_tick, e.pos - q, 12.0, def.color)
                    world().enemies.slow(e, 1.0 - float(p["thread_slow"]), 0.5)
                    gate[e.uid] = anim_t + float(p["thread_tick"])
                    break

    func _fire_volley(from: Vector2) -> bool:
        var tgt: EnemyManager.E = world().enemies.nearest(from, float(p["launch_range"]))
        if tgt == null or not tgt.alive:
            return false
        var count: int = maxi(1, int(round(float(p["spores_per_volley"]))))
        var base_dir: Vector2 = (tgt.pos - from).normalized()
        if base_dir.length() < 0.5:
            base_dir = Vector2.RIGHT
        for k in count:
            var off: float = (float(k) - float(count - 1) * 0.5) * deg_to_rad(9.0)
            spores.append({"pos": from, "vel": base_dir.rotated(off) * float(p["spore_speed"]), "left": float(p["launch_range"]) + SPORE_RANGE_PAD})
        Audio.sfx(def.audio_event, -10.0, 1.5)
        return true

    func _step_spores(delta: float) -> void:
        for i in range(spores.size() - 1, -1, -1):
            var s: Dictionary = spores[i]
            var step: Vector2 = (s["vel"] as Vector2) * delta
            s["pos"] = (s["pos"] as Vector2) + step
            s["left"] = float(s["left"]) - step.length()
            var done: bool = float(s["left"]) <= 0.0
            if not done:
                for e in world().enemies.query_circle(s["pos"], SPORE_HIT_R):
                    if not e.alive:
                        continue
                    world().enemies.damage(e, float(p["spore_dmg"]) * player.stat("damage"), s["vel"].normalized(), 20.0, def.color)
                    _infect(e)
                    world().fx.emit(e.pos + Vector2(0, -6), Vector2(0, -30.0), 0.25, 3.0, def.color, 1, 2.0)
                    done = true
                    break
            if done:
                spores.remove_at(i)

    func _infect(e: EnemyManager.E) -> void:
        if float(p["infect_time"]) <= 0.0:
            return
        if infected.has(e.uid):
            var r: Dictionary = infected[e.uid]
            if r["e"] == e:
                r["left"] = float(p["infect_time"])
                world().enemies.infect(e, float(p["infect_time"]))
                return
        infected[e.uid] = {"e": e, "uid": e.uid, "left": float(p["infect_time"]), "tick": INFECT_TICK, "dps": float(p["infect_dps"]) * player.stat("damage"), "last_pos": e.pos, "burst": float(p["burst_dmg"]) * player.stat("damage"), "burst_r": float(p["burst_radius"])}
        world().enemies.infect(e, float(p["infect_time"]))

    func _step_infection(delta: float) -> void:
        for id in infected.keys():
            var r: Dictionary = infected[id]
            var e: EnemyManager.E = r["e"]
            var stale: bool = e == null or not is_instance_valid(e) or int(e.uid) != int(r["uid"])
            if stale or not e.alive:
                if not stale and float(p["burst_dmg"]) > 0.0:
                    bursts.append({"pos": r["last_pos"], "dmg": float(r["burst"]), "radius": float(r["burst_r"])})
                infected.erase(id)
                continue
            r["last_pos"] = e.pos
            r["left"] = float(r["left"]) - delta
            r["tick"] = float(r["tick"]) - delta
            if float(r["tick"]) <= 0.0:
                r["tick"] = float(r["tick"]) + INFECT_TICK
                world().enemies.damage(e, float(r["dps"]) * INFECT_TICK, Vector2.ZERO, 0.0, def.color)
                if e.alive:
                    world().enemies.infect(e, 0.6)
            if float(r["left"]) <= 0.0:
                infected.erase(id)

    func _resolve_bursts(area: float) -> void:
        if bursts.is_empty():
            return
        var queue: Array = bursts.duplicate()
        bursts.clear()
        for b in queue:
            var hit: Array = _blast(b["pos"], float(b["radius"]) * area, float(b["dmg"]), false)
            world().fx.ring(b["pos"], 4.0, float(b["radius"]) * area, 0.35, Color(0.9, 1.0, 0.6), 4.0)
            Audio.sfx(def.audio_event, -8.0, 1.2)
            var n := 0
            for e in hit:
                if n >= BURST_INFECT_CAP:
                    break
                if e.alive and float(e.infect_t) <= 0.0:
                    _infect(e)
                    n += 1

    func _nearest_ground(from: Vector2, rng: float) -> EnemyManager.E:
        var best: EnemyManager.E = null
        var best_d: float = rng * rng
        for e in world().enemies.active:
            if not e.alive or e.def.height == 1:
                continue
            var d: float = from.distance_squared_to(e.pos)
            if d <= best_d:
                best_d = d
                best = e
        return best

    func _blast(center: Vector2, radius: float, amount: float, ground_only: bool) -> Array:
        var hit: Array = []
        var targets: Array = world().enemies.query_ground_circle(center, radius) if ground_only else world().enemies.query_circle(center, radius)
        for e in targets:
            if not e.alive:
                continue
            world().enemies.damage(e, amount, e.pos - center, 60.0, def.color)
            hit.append(e)
        return hit

    func draw_overlay(c: Node2D) -> void:
        var pulse: float = 0.75 + 0.25 * sin(anim_t * 6.0)
        for seg in threads:
            var a: Vector2 = (seg[0] as Vector2) - player.global_position
            var b: Vector2 = (seg[1] as Vector2) - player.global_position
            c.draw_line(a, b, Color(0.55, 0.95, 0.65, 0.30 * pulse), 6.0, true)
            c.draw_line(a, b, Color(0.85, 1.0, 0.9, 0.9), 2.0, true)
        for s in spores:
            c.draw_circle((s["pos"] as Vector2) - player.global_position, 4.0, Color(0.9, 1.0, 0.6))
        if t > 0.0 and float(p["cooldown"]) > 0.0:
            var k: float = 1.0 - t / maxf(maxf(0.2, float(p["cooldown"]) * cd()), 0.01)
            c.draw_arc(Vector2(0, -16), 19.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(k, 0.0, 1.0), 28, Color(0.55, 0.95, 0.65, 0.95), 2.5)

    func hud_line() -> String:
        return "N%d S%d I%d" % [nodes.size(), spores.size(), infected.size()]


# =============================================================================================== Rare chest pickup: Shamir's Tooth (flicker_strike)
# Every cooldown, teleports the player to the toughest enemies in range (top HP,
# up to count), stabs each for heavy damage, then snaps back to the start.
# Covered by player.invuln for the whole sequence; damage flows through the
# normal EnemyManager.damage path (kills -> on_kill / coins / XP).
class FlickerStrike extends Ability:
    const SLASH_RADIUS := 52.0
    const SLASH_ARC := 2.6
    var seq_t := 0.0
    var state := 0          # 0 idle, 1 hopping, 2 returning
    var targets: Array = []
    var hop_i := 0
    var hop_t := 0.0
    var origin := Vector2.ZERO

    func on_ready() -> void:
        seq_t = float(p["cooldown"]) * 0.5

    func update(delta: float) -> void:
        if state == 0:
            seq_t -= delta
            if seq_t <= 0.0:
                _begin()
        elif state == 1:
            hop_t -= delta
            if hop_t <= 0.0:
                _hop_next()
        else:
            hop_t -= delta
            if hop_t <= 0.0:
                _return_home()

    func _begin() -> void:
        targets = _pick_targets()
        if targets.is_empty():
            seq_t = float(p["retry_delay"])
            return
        origin = player.global_position
        hop_i = 0
        hop_t = 0.0
        player.invuln = maxf(player.invuln, float(targets.size()) * float(p["hop_interval"]) + float(p["return_delay"]) + 0.2)
        state = 1

    func _hop_next() -> void:
        while hop_i < targets.size():
            var e: EnemyManager.E = targets[hop_i] as EnemyManager.E
            if e != null and e.alive:
                break
            hop_i += 1
        if hop_i >= targets.size():
            state = 2
            hop_t = float(p["return_delay"])
            return
        var tgt: EnemyManager.E = targets[hop_i] as EnemyManager.E
        hop_i += 1
        var from: Vector2 = player.global_position
        var away: Vector2 = from - tgt.pos
        if away.length_squared() > 1.0:
            away = away.normalized()
        else:
            away = Vector2.RIGHT
        player.global_position = tgt.pos + away * float(p["land_offset"])
        var slash_dir: Vector2 = tgt.pos - from
        var ang := 0.0
        if slash_dir.length_squared() > 1.0:
            ang = slash_dir.angle()
        world().fx.slash_arc(tgt.pos, ang, SLASH_RADIUS, SLASH_ARC, def.color)
        world().fx.attack_flourish(player.global_position, tgt.pos - from)
        world().fx.ring(tgt.pos, 4.0, 26.0, 0.22, Color(0.75, 0.92, 1.0), 2.0)
        world().enemies.damage(tgt, dmg(), tgt.pos - from, float(p["knockback"]), def.color)
        Audio.sfx(def.audio_event, -4.0, randf_range(0.95, 1.1))
        hop_t = float(p["hop_interval"])

    func _return_home() -> void:
        var from: Vector2 = player.global_position
        player.global_position = origin
        var back: Vector2 = origin - from
        var ang := 0.0
        if back.length_squared() > 1.0:
            ang = back.angle()
        world().fx.slash_arc(origin, ang, SLASH_RADIUS, SLASH_ARC, def.color)
        world().fx.ring(origin, 8.0, 44.0, 0.3, def.color, 3.0)
        Audio.sfx(def.audio_event, -6.0, 0.9)
        targets.clear()
        state = 0
        seq_t = float(p["cooldown"]) * cd()

    func _pick_targets() -> Array:
        var r: float = float(p["range"])
        var r2: float = r * r
        var center: Vector2 = player.global_position
        var n: int = player.scaled_count(int(p["count"]))
        var found: Array = []
        for e in world().enemies.active:
            if not e.alive:
                continue
            if (e.pos - center).length_squared() <= r2:
                found.append(e)
        found.sort_custom(func(a, b) -> bool: return a.hp > b.hp)
        if found.size() > n:
            found.resize(n)
        return found

    func hud_line() -> String:
        if state != 0:
            return "HUNTING"
        if seq_t <= 0.0:
            return "READY"
        return "%0.1fs" % seq_t


# =============================================================================================== Legendary chest pickup: Shamir (worm_ride)
# Periodically the player bursts out astride a worm: much faster for a few
# seconds while everything touched is shredded. Normal enemies die outright;
# elites and bosses lose a % of max HP per hit. Locked behind a per-weapon
# prerequisite (see Player.is_legendary_unlocked); drawn from the chest only
# once unlocked, at a Luck-scaled capped % per slot.
class WormRide extends Ability:
    const MIN_COOLDOWN := 6.0
    const WORM_SEGS := 11
    const HEAD_R := 24.0
    const TAIL_R := 8.0
    const WORM_COL := Color(0.55, 0.42, 0.62)
    const TOOTH_COL := Color(0.95, 0.93, 0.85)
    var state := 0          # 0 idle, 1 riding
    var seq_t := 0.0        # idle: time to next ride attempt
    var ride_t := 0.0       # riding: time left in the ride
    var sfx_t := 0.0
    var hit_timers: Dictionary = {}

    func on_ready() -> void:
        seq_t = _cooldown() * 0.5

    func update(delta: float) -> void:
        if state == 0:
            seq_t -= delta
            if seq_t <= 0.0:
                if _enemy_within(float(p["trigger_range"])):
                    _begin()
                else:
                    seq_t = float(p["retry_delay"])
            return
        ride_t -= delta
        _tick_shred(delta)
        if ride_t <= 0.0:
            _finish()
            seq_t = _cooldown()

    func _cooldown() -> float:
        return maxf(MIN_COOLDOWN, float(p["cooldown"])) * cd()

    func _begin() -> void:
        state = 1
        ride_t = float(p["duration"])
        hit_timers.clear()
        sfx_t = 0.0
        player.add_buff("shamir_ride", ride_t, {}, {"move_speed": float(p["speed_mult"])})
        world().fx.attack_flourish(player.global_position, player.aim_dir())
        player.invuln = maxf(player.invuln, 0.2)
        world().fx.ring(player.global_position, 8.0, 60.0, 0.35, def.color, 3.0)
        Audio.sfx(def.audio_event, -4.0, 1.0)
        Game.shake(2.0)

    func _finish() -> void:
        player.remove_buff("shamir_ride")
        world().fx.ring(player.global_position, 8.0, 44.0, 0.3, def.color, 3.0)
        Audio.sfx(def.audio_event, -6.0, 0.9)
        hit_timers.clear()
        state = 0

    func _tick_shred(delta: float) -> void:
        for uid in hit_timers.keys():
            var left: float = float(hit_timers[uid]) - delta
            if left <= 0.0:
                hit_timers.erase(uid)
            else:
                hit_timers[uid] = left
        sfx_t -= delta
        var r: float = float(p["shred_radius"])
        var r2: float = r * r
        var center: Vector2 = player.global_position
        var hit_any := false
        for e in world().enemies.active:
            if not e.alive:
                continue
            if (e.pos - center).length_squared() > r2:
                continue
            if hit_timers.has(e.uid):
                continue
            _shred(e, center)
            hit_any = true
        if hit_any and sfx_t <= 0.0:
            Audio.sfx(def.audio_event, -8.0, randf_range(0.95, 1.1))
            sfx_t = 0.15

    func _shred(e, center: Vector2) -> void:
        var col: Color = def.color
        var dir: Vector2 = e.pos - center
        var knock: float = float(p["knockback"])
        if float(e.def.boss_time) > 0.0:
            world().enemies.damage(e, e.max_hp * float(p["boss_pct"]), dir, knock, col)
            hit_timers[e.uid] = float(p["elite_interval"])
        elif e.is_elite:
            world().enemies.damage(e, e.max_hp * float(p["elite_pct"]), dir, knock, col)
            hit_timers[e.uid] = float(p["elite_interval"])
        else:
            world().enemies.damage(e, e.hp * 2.0, dir, knock, col)
            hit_timers[e.uid] = float(p["hit_interval"])

    func _enemy_within(radius: float) -> bool:
        var r2: float = radius * radius
        var center: Vector2 = player.global_position
        for e in world().enemies.active:
            if not e.alive:
                continue
            if (e.pos - center).length_squared() <= r2:
                return true
        return false

    func draw_overlay(c: Node2D) -> void:
        if state != 1:
            return
        var origin: Vector2 = player.global_position
        var r: float = float(p["shred_radius"])
        c.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(WORM_COL.r, WORM_COL.g, WORM_COL.b, 0.30), 2.0)
        var hist: Array = player.history
        if hist.size() < 2:
            return
        var step: int = maxi(1, hist.size() / WORM_SEGS)
        var pts: Array[Vector2] = []
        var i: int = hist.size() - 1
        while i >= 0 and pts.size() < WORM_SEGS:
            var g: Vector2 = hist[i]
            pts.append(g - origin)
            i -= step
        if pts.size() < 2:
            return
        var n: int = pts.size()
        for k in range(n - 1, -1, -1):
            var t: float = float(k) / float(maxi(1, n - 1))
            var rad: float = lerpf(HEAD_R, TAIL_R, t)
            var col: Color = WORM_COL.lerp(WORM_COL.darkened(0.4), t)
            c.draw_circle(pts[k], rad, col)
            c.draw_circle(pts[k], rad * 0.6, col.lightened(0.18))
        var fwd: Vector2 = pts[0] - pts[1]
        if fwd.length_squared() < 1.0:
            fwd = Vector2.RIGHT
        fwd = fwd.normalized()
        var side: Vector2 = fwd.orthogonal()
        for m in range(-1, 2):
            var base: Vector2 = pts[0] + fwd * HEAD_R * 0.8 + side * float(m) * HEAD_R * 0.55
            c.draw_colored_polygon(PackedVector2Array([base - side * 3.0, base + side * 3.0, base + fwd * HEAD_R * 0.55]), TOOTH_COL)

    func hud_line() -> String:
        if state == 1:
            return "RIDING %0.1fs" % ride_t
        if seq_t <= 0.0:
            return "READY"
        return "%0.1fs" % seq_t
