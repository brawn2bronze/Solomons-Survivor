class_name PassiveBehaviors
extends RefCounted
## One inner class per behavior key used by PassiveDef.behavior. Ground effects (webs, turds) are decals
## registered with the world so they draw under actors.
## Rule: drop-and-leave ground traps must use query_ground_circle so flying
## enemies (height == 1) are unaffected. Spider webs are the exception and use query_circle.

static func make(key: String) -> Ability:
    match key:
        "whip": return Whip.new()
        "stun_pulse": return StunPulse.new()
        "summon_allies": return SummonAllies.new()
        "astral_clone": return AstralClone.new()
        "web": return Web.new()
        "roar": return Roar.new()
        "swoop": return Swoop.new()
        "raise_dead": return RaiseDead.new()
        "turds": return Turds.new()
        "nutrient_bloom": return NutrientBloom.new()
    return null


# =============================================================================================== Cowboy whip / Paladin prayer
class Whip extends Ability:
    const TRAIL_TICK := 0.4
    var tick_t := 0.0
    var trail_pos := Vector2.INF   # dragging_chain: last trail drop position
    var roundup_t := 0.0      # roundup cadence
    var fence_t := 0.0        # barbed_fence post cadence
    var fence_hit_t := 0.0    # barbed_fence beam damage cadence
    var parry_short := 0.0    # snap_parry: current lash length loss
    var posts: Array = []     # barbed_fence posts (last three)
    var pr_consec_t := 0.0    # consecration: drop cadence
    var pr_grounds: Array = []  # consecration: live zones
    var pr_burn_t := 0.0      # consecration: burn tick
    var pr_orb_ang := 0.0     # seraph_ring: orbit angle
    var pr_orb_gate: Dictionary = {}
    var pr_sanct_cd := 0.0    # sanctuary: cooldown between zones
    var pr_sanct_life := 0.0  # sanctuary: active zone time left
    var pr_sanct_center := Vector2.ZERO
    var pr_sanct_r := 0.0
    var pr_sanct_push_t := 0.0
    var pr_sanct_decal: Dictionary = {}
    var pr_loh_t := 0.0       # lay_on_hands: cooldown
    var pr_rings: Array = []  # tolling_bell: expanding rings
    var pr_final_t := 0.0     # final_judgement: sky tell remaining
    var pr_final_decal: Dictionary = {}

    func on_ready() -> void:
        t = 0.8
        roundup_t = float(evo_param("roundup", "every", 8.0))
        fence_t = float(evo_param("barbed_fence", "every", 6.0))

    func update(delta: float) -> void:
        var mode := String(flags.get("mode", ""))
        var r := float(p["range"]) * player.stat("area")
        var origin := player.global_position + Vector2(0, -8)
        var col: Color = def.color
        var moving := EvoPrims.is_moving(player)
        if def.id == "prayer":
            _prayer_evos(delta, origin, r, col)
        if has_evo("dragging_chain") and moving:
            if trail_pos == Vector2.INF or trail_pos.distance_to(player.global_position) >= float(evo_param("dragging_chain", "spacing", 24.0)):
                trail_pos = player.global_position
                world().projectiles.spawn_trap_zone(player.global_position, 18.0, dmg() * float(evo_param("dragging_chain", "dps_mult", 0.4)) * TRAIL_TICK, float(evo_param("dragging_chain", "life", 2.0)), {"color": col, "tick_interval": TRAIL_TICK, "src": "whip_trail"})
        if has_evo("roundup"):
            roundup_t -= delta
            if roundup_t <= 0.0:
                roundup_t = float(evo_param("roundup", "every", 8.0)) * cd()
                _roundup(origin, r, col)
        if has_evo("barbed_fence"):
            fence_t -= delta
            if fence_t <= 0.0:
                fence_t = float(evo_param("barbed_fence", "every", 6.0)) * cd()
                posts.append(origin)
                while posts.size() > int(evo_param("barbed_fence", "posts", 3)):
                    posts.pop_front()
            fence_hit_t -= delta
            if fence_hit_t <= 0.0:
                fence_hit_t = 0.4
                _fence_tick(col)
        if mode == "aura":
            player.aura_r = r
            player.aura_col = col
            var tick_rate := 1.0
            if has_evo("twirling_lasso"):
                tick_rate = float(evo_param("twirling_lasso", "base_spin", 2.0)) + float(evo_param("twirling_lasso", "spin_per_speed", 0.02)) * player.vel.length()
            tick_t -= delta * tick_rate
            if tick_t <= 0.0:
                tick_t = float(p["tick"]) * cd()
                var aura_dmg := dmg() * float(evo_param("twirling_lasso", "hit_mult", 1.0))
                for e in world().enemies.query_circle(origin, r):
                    world().enemies.damage(e, aura_dmg, e.pos - origin, 18.0, col)
                if def.id == "flailing_whip":
                    world().fx.lash(origin, randf() * TAU, r, col)
                    Audio.sfx("whip_crack", -12.0, 1.0, 0.15)
            return
        t -= delta
        if t > 0.0:
            return
        if def.id == "prayer":
            t = float(p["interval"]) * cd()
            _prayer_pulse(origin, r, col)
            return
        if mode == "lash":
            var ltgt: EnemyManager.E = world().enemies.nearest(player.global_position, r, {})
            if ltgt == null:
                t = 0.05
                return
            t = float(p["interval"]) * cd()
            _lash(origin, ltgt, r, col)
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, r * 1.25, {})
        if tgt == null and mode != "pulse":
            t = 0.05
            return
        t = float(p["interval"]) * cd()
        if mode == "pulse":
            _radial(origin, r, col, true)
            for i in 6:
                world().fx.lash(origin, TAU * float(i) / 6.0 + randf() * 0.3, r, col)
        else:
            var dir: Vector2 = (tgt.pos - origin).normalized()
            var hits: Array[EnemyManager.E] = world().enemies.query_arc(origin, dir, r, deg_to_rad(float(p["arc_deg"])))
            for e in hits:
                world().enemies.damage(e, dmg(), dir, 70.0, col)
            world().fx.lash(origin, dir.angle(), r, col)
            world().fx.lash(origin, dir.angle() + 0.25, r * 0.85, col)
            Audio.sfx("whip_crack", -6.0)
            if not hits.is_empty():
                Game.shake(1.0)

    ## Cracking Lash branch: one directed, narrow, long lash at the nearest enemy.
    func _lash(origin: Vector2, tgt: EnemyManager.E, r: float, col: Color) -> void:
        var length := maxf(30.0, r - parry_short)
        parry_short = 0.0
        var dir: Vector2 = (tgt.pos - origin).normalized()
        var endp := origin + dir * length
        var far_frac := 0.0
        var far_mult := 1.0
        if has_evo("sweet_spot"):
            far_frac = float(evo_param("sweet_spot", "tip_frac", 0.2))
            far_mult = float(evo_param("sweet_spot", "tip_mult", 2.0))
        var hits: int = EvoPrims.segment_hit(world(), origin, endp, 14.0, dmg(), dir, 60.0, "whip_lash", 1.0, 0.0, far_frac, far_mult)
        world().fx.lash(origin, dir.angle(), length, col)
        world().fx.lash(origin, dir.angle() + 0.2, length * 0.85, col)
        Audio.sfx("whip_crack", -6.0)
        if hits > 0:
            Game.shake(1.0)
        if has_evo("wanted_poster"):
            _wanted(origin, endp)
        if has_evo("fast_hands") and hits >= int(evo_param("fast_hands", "hits_needed", 3)):
            var w = player.weapon
            if w != null and w.has_method("reload_now"):
                w.reload_now()
                world().fx.star(origin, 8.0, Color(1.0, 0.9, 0.5))
        if has_evo("snap_parry"):
            var n: int = EvoPrims.intercept_segment(world(), origin, endp, 22.0, "destroy")
            if n > 0:
                parry_short = minf(length * float(evo_param("snap_parry", "refund", 0.15)) * float(n), length * float(evo_param("snap_parry", "refund_cap", 0.5)))
                world().fx.star(origin + dir * length * 0.5, 10.0, Color(0.8, 0.95, 1.0))
                Audio.sfx("button_click", -8.0, 1.5)

    func _roundup(origin: Vector2, r: float, col: Color) -> void:
        world().fx.ring(origin, r * 0.4, r, 0.35, col, 3.0)
        var pull_s := float(evo_param("roundup", "pull_px", 60.0)) * 8.0
        var stun_t := float(evo_param("roundup", "stun", 0.6))
        for e in world().enemies.query_circle(origin, r):
            world().enemies.pull(e, origin, r, pull_s, 0.0)
            world().enemies.stun(e, stun_t)
        Audio.sfx("whip_crack", -3.0, 0.7)
        Game.shake(1.6)

    func _fence_tick(col: Color) -> void:
        if posts.size() < 2:
            return
        var link_mult := float(evo_param("barbed_fence", "link_mult", 0.5))
        var slow_mult := float(evo_param("barbed_fence", "slow", 0.6))
        for i in posts.size() - 1:
            var a: Vector2 = posts[i]
            var b: Vector2 = posts[i + 1]
            world().fx.beam_between(a, b, 2.0, 0.18, col)
            EvoPrims.segment_hit(world(), a, b, 10.0, dmg() * link_mult, Vector2.ZERO, 0.0, "whip_fence", slow_mult, 0.4)

    func _wanted(from: Vector2, to: Vector2) -> void:
        var seg := to - from
        var seg_len := seg.length()
        if seg_len < 0.01:
            return
        var seg_dir := seg / seg_len
        for e in world().enemies.query_circle((from + to) * 0.5, seg_len * 0.5 + 40.0):
            if not (e.is_elite or float(e.def.boss_time) > 0.0):
                continue
            var proj: float = clampf((e.pos - from).dot(seg_dir), 0.0, seg_len)
            if e.pos.distance_to(from + seg_dir * proj) <= 40.0 + e.radius:
                world().enemies.mark(e, "wanted_poster", float(evo_param("wanted_poster", "mark_time", 8.0)), "wanted", {
                    "taken": float(evo_param("wanted_poster", "taken", 1.25)),
                    "leash": float(evo_param("wanted_poster", "leash", 260.0)),
                })

    func _radial(origin: Vector2, r: float, col: Color, big: bool) -> void:
        for e in world().enemies.query_circle(origin, r):
            world().enemies.damage(e, dmg(), e.pos - origin, 90.0 if big else 40.0, col)
        world().fx.ring(origin, 6.0, r, 0.35, col, 3.0 if big else 2.0)
        player.aura_flash(r, col)
        Audio.sfx("whip_crack", -4.0, 0.7 if def.id == "prayer" else 1.0)
        if def.id == "prayer":
            for i in 14:
                world().fx.emit(origin + Vector2.from_angle(randf() * TAU) * randf_range(4.0, r), Vector2(0, -randf_range(20.0, 60.0)), 0.7, 2.0, Color(1.0, 0.95, 0.7), 1, 1.0)
        Game.shake(2.0 if big else 0.8)

    # ---------------------------------------------------------------- Prayer evolutions
    func _prayer_evos(delta: float, origin: Vector2, r: float, col: Color) -> void:
        if has_evo("consecration"):
            _consecration_update(delta, origin, r, col)
        if has_evo("seraph_ring"):
            _seraph_update(delta, origin, r, col)
        if has_evo("sanctuary"):
            _sanctuary_update(delta, origin, r, col)
        if has_evo("lay_on_hands"):
            _lay_update(delta, origin, r, col)
        _toll_update(delta)
        _final_update(delta)

    func _prayer_origins(origin: Vector2) -> Array:
        if not has_evo("twin_suns"):
            return [origin]
        var off: float = float(evo_param("twin_suns", "offset", 150.0))
        return [origin + Vector2(-off, 0.0), origin + Vector2(off, 0.0)]

    func _prayer_pulse(origin: Vector2, r: float, col: Color) -> void:
        var ctx := {"origin": origin, "radius": r, "origins": _prayer_origins(origin)}
        hook("on_flash", ctx)
        var origins: Array = ctx.get("origins", [origin])
        if has_evo("tolling_bell"):
            for o in origins:
                var op: Vector2 = o
                _toll_ring(op, r, col)
        else:
            for o in origins:
                var op2: Vector2 = o
                _radial(op2, r, col, true)
        if has_evo("verdict_mark"):
            _verdict(origin, r, col)
        if has_evo("final_judgement"):
            var every: int = maxi(1, int(evo_param("final_judgement", "every", 3)))
            if nth("prayer_final", every):
                _final_judgement(col)

    func _consecration_update(delta: float, origin: Vector2, r: float, col: Color) -> void:
        pr_consec_t -= delta
        if pr_consec_t <= 0.0:
            pr_consec_t = float(evo_param("consecration", "every", 4.0)) * cd()
            var rr: float = maxf(20.0, r * float(evo_param("consecration", "radius_mult", 0.9)))
            var life: float = float(evo_param("consecration", "life", 5.0))
            var dec := {"kind": "consecration", "pos": origin, "r": rr, "t": 0.0, "life": life, "dead": false}
            world().add_decal(dec)
            pr_grounds.append({"pos": origin, "r": rr, "t": 0.0, "life": life, "decal": dec})
            world().fx.ring(origin, 6.0, rr, 0.35, col, 2.0)
            Audio.sfx("whip_crack", -12.0, 1.3)
        var on_ground := false
        for i in range(pr_grounds.size() - 1, -1, -1):
            var g: Dictionary = pr_grounds[i]
            g["t"] = float(g["t"]) + delta
            var gdec: Dictionary = g["decal"]
            gdec["t"] = g["t"]
            var gp: Vector2 = g["pos"]
            var gr: float = float(g["r"])
            if float(g["t"]) >= float(g["life"]):
                gdec["dead"] = true
                pr_grounds.remove_at(i)
            elif player.global_position.distance_to(gp) <= gr + 4.0:
                on_ground = true
        if on_ground:
            player.heal(float(evo_param("consecration", "heal_per_sec", 2.0)) * delta)
        pr_burn_t -= delta
        if pr_burn_t <= 0.0:
            pr_burn_t = 0.25
            var burn_dps: float = dmg() * float(evo_param("consecration", "dps_mult", 0.5))
            for g2 in pr_grounds:
                var gp2: Vector2 = g2["pos"]
                for e in world().enemies.query_ground_circle(gp2, float(g2["r"])):
                    world().enemies.burn(e, burn_dps, 0.35)

    func _seraph_update(delta: float, origin: Vector2, r: float, col: Color) -> void:
        pr_orb_ang = fmod(pr_orb_ang + delta * 2.2, TAU)
        var count: int = maxi(1, int(evo_param("seraph_ring", "orbs", 3)))
        var orbit_r: float = r * 0.92
        var now: float = world().run_time
        for i in count:
            var orb_pos: Vector2 = origin + Vector2.from_angle(pr_orb_ang + TAU * float(i) / float(count)) * orbit_r
            for e in world().enemies.query_circle(orb_pos, 26.0):
                if e.pos.distance_to(orb_pos) > 14.0 + e.radius:
                    continue
                if now < float(pr_orb_gate.get(e.uid, -1.0)):
                    continue
                pr_orb_gate[e.uid] = now + 0.45
                var dir: Vector2 = e.pos - orb_pos
                if dir.length_squared() < 0.01:
                    dir = Vector2.RIGHT
                world().enemies.damage(e, dmg() * float(evo_param("seraph_ring", "touch_mult", 0.5)), dir.normalized(), float(evo_param("seraph_ring", "knockback", 80.0)), col, "seraph_ring")
                world().fx.star(orb_pos, 7.0, col, 0.2)

    func _sanctuary_update(delta: float, origin: Vector2, r: float, col: Color) -> void:
        pr_sanct_cd = maxf(0.0, pr_sanct_cd - delta)
        if pr_sanct_life <= 0.0 and pr_sanct_cd <= 0.0:
            pr_sanct_life = float(evo_param("sanctuary", "life", 5.0))
            pr_sanct_cd = float(evo_param("sanctuary", "cooldown", 20.0)) * cd()
            pr_sanct_center = origin
            pr_sanct_r = maxf(20.0, r * float(evo_param("sanctuary", "radius_mult", 1.5)))
            pr_sanct_push_t = 0.0
            var dec := {"kind": "sanctuary", "pos": origin, "r": pr_sanct_r, "t": 0.0, "life": pr_sanct_life, "dead": false}
            pr_sanct_decal = dec
            world().add_decal(dec)
            world().fx.ring(origin, pr_sanct_r * 0.9, pr_sanct_r, 0.35, col, 3.0)
            Audio.sfx("whip_crack", -5.0, 1.4)
        if pr_sanct_life <= 0.0:
            return
        pr_sanct_life -= delta
        if not pr_sanct_decal.is_empty():
            pr_sanct_decal["t"] = float(pr_sanct_decal["t"]) + delta
        pr_sanct_push_t -= delta
        if pr_sanct_push_t <= 0.0:
            pr_sanct_push_t = 0.12
            for e in world().enemies.query_circle(pr_sanct_center, pr_sanct_r):
                var off: Vector2 = e.pos - pr_sanct_center
                if off.length_squared() < 0.01:
                    continue
                e.knock += off.normalized() * 220.0 * (0.35 if e.is_elite else 1.0)
        if pr_sanct_life <= 0.0:
            pr_sanct_life = 0.0
            if not pr_sanct_decal.is_empty():
                pr_sanct_decal["dead"] = true

    func _lay_update(delta: float, origin: Vector2, r: float, col: Color) -> void:
        pr_loh_t = maxf(0.0, pr_loh_t - delta)
        if pr_loh_t > 0.0 or player.dead:
            return
        if player.max_hp <= 0.0 or player.hp > player.max_hp * float(evo_param("lay_on_hands", "hp_frac", 0.3)):
            return
        pr_loh_t = float(evo_param("lay_on_hands", "cooldown", 60.0)) * cd()
        player.heal(player.max_hp * float(evo_param("lay_on_hands", "heal_pct", 0.4)))
        var rr: float = maxf(160.0, r * 2.0)
        for e in world().enemies.query_circle(origin, rr):
            var off: Vector2 = e.pos - origin
            if off.length_squared() < 0.01:
                continue
            e.knock += off.normalized() * float(evo_param("lay_on_hands", "knockback", 260.0)) * (0.35 if e.is_elite else 1.0)
        world().fx.ring(origin, 10.0, rr, 0.4, col.lightened(0.2), 4.0)
        world().fx.star(origin, 30.0, col.lightened(0.25), 0.4)
        world().fx.float_text(origin + Vector2(0, -38), "LAY ON HANDS", Color(1.0, 0.95, 0.7), 16, 1.1, 20.0)
        Audio.sfx("whip_crack", -2.0, 0.8)
        Game.shake(2.5)

    func _toll_ring(origin: Vector2, r: float, col: Color) -> void:
        var speed: float = maxf(20.0, float(evo_param("tolling_bell", "ring_speed", 220.0)))
        var life: float = maxf(0.1, r / speed)
        pr_rings.append({"origin": origin, "r": r, "cur": 8.0, "speed": speed, "life": life, "t": 0.0, "hit": {}, "color": col})
        world().fx.ring(origin, 8.0, r, life, col, 3.0)
        player.aura_flash(r, col)
        Audio.sfx("whip_crack", -4.0, 0.7)
        Game.shake(1.0)

    func _toll_update(delta: float) -> void:
        for i in range(pr_rings.size() - 1, -1, -1):
            var ring: Dictionary = pr_rings[i]
            ring["t"] = float(ring["t"]) + delta
            var center: Vector2 = ring["origin"]
            var max_r: float = float(ring["r"])
            var cur: float = minf(max_r, 8.0 + float(ring["speed"]) * float(ring["t"]))
            ring["cur"] = cur
            var hit: Dictionary = ring["hit"]
            var col: Color = ring["color"]
            var knock: float = float(evo_param("tolling_bell", "knockback", 100.0))
            var edge_mult: float = float(evo_param("tolling_bell", "edge_mult", 1.5))
            for e in world().enemies.query_circle(center, cur + 32.0):
                if hit.has(e.uid):
                    continue
                var dist: float = e.pos.distance_to(center)
                if dist > cur + e.radius or dist < cur - e.radius - 22.0:
                    continue
                hit[e.uid] = true
                var dir: Vector2 = e.pos - center
                if dir.length_squared() < 0.01:
                    dir = Vector2.RIGHT
                var edge: float = edge_mult if dist >= max_r * 0.72 else 1.0
                world().enemies.damage(e, dmg() * edge, dir.normalized(), knock, col, "tolling_bell")
            if float(ring["t"]) >= float(ring["life"]):
                pr_rings.remove_at(i)

    func _verdict(origin: Vector2, r: float, col: Color) -> void:
        var list: Array = world().enemies.query_circle(origin, r)
        var targets: Array = []
        var count: int = mini(int(evo_param("verdict_mark", "targets", 3)), list.size())
        for k in count:
            var best = null
            var best_score := -1.0
            for e in list:
                if targets.has(e):
                    continue
                var score: float = e.hp + (100000.0 if e.is_elite else 0.0)
                if score > best_score:
                    best_score = score
                    best = e
            if best != null:
                targets.append(best)
        if targets.is_empty():
            return
        var delay: float = maxf(0.05, float(evo_param("verdict_mark", "delay", 1.0)))
        var leash: float = float(evo_param("verdict_mark", "leash", 300.0))
        var mult: float = float(evo_param("verdict_mark", "mult", 2.0))
        for e in targets:
            world().enemies.mark(e, "verdict_mark", delay, "verdict", {})
            world().fx.star(e.pos, 10.0, col, 0.25)
        after(delay, func() -> void:
            for e in targets:
                if not e.alive:
                    continue
                if e.pos.distance_to(origin) > leash:
                    continue
                var dir: Vector2 = e.pos - origin
                if dir.length_squared() < 0.01:
                    dir = Vector2.RIGHT
                world().enemies.clear_mark(e, "verdict_mark")
                world().enemies.damage(e, dmg() * mult, dir.normalized(), 140.0, col, "verdict_mark")
                world().fx.beam_between(origin, e.pos, 8.0, 0.18, col)
                world().fx.star(e.pos, 14.0, col, 0.3)
        )

    func _final_judgement(col: Color) -> void:
        var tell: float = maxf(0.1, float(evo_param("final_judgement", "tell", 1.2)))
        pr_final_t = tell
        var dec := {"kind": "judgement_tell", "pos": player.global_position, "r": 900.0, "t": 0.0, "life": tell, "dead": false}
        pr_final_decal = dec
        world().add_decal(dec)
        world().fx.ring(player.global_position, 24.0, 500.0, tell, col, 2.0)
        Audio.sfx("whip_crack", -2.0, 0.6)
        var mult: float = float(evo_param("final_judgement", "mult", 3.0))
        var pct: float = float(evo_param("final_judgement", "pct_elite", 0.08))
        after(tell, func() -> void:
            if player == null or player.dead or world() == null:
                return
            var center: Vector2 = player.global_position
            for e in world().enemies.query_circle(center, 900.0):
                var amount: float = dmg() * mult
                if e.is_elite or float(e.def.boss_time) > 0.0:
                    amount = minf(amount, e.max_hp * pct)
                var dir: Vector2 = e.pos - center
                if dir.length_squared() < 0.01:
                    dir = Vector2.RIGHT
                world().enemies.damage(e, amount, dir.normalized(), 120.0, col, "final_judgement")
            world().fx.ring(center, 16.0, 900.0, 0.45, Color(1.0, 0.95, 0.65), 5.0)
            world().fx.disc(center, 40.0, 380.0, 0.45, Color(1.0, 0.9, 0.5), 3.0)
            Audio.sfx("greatsword_swing", -3.0, 0.7)
            Game.shake(5.0)
            Game.hit_stop(0.08, 0.08)
        )

    func _final_update(delta: float) -> void:
        if pr_final_t <= 0.0:
            return
        pr_final_t = maxf(0.0, pr_final_t - delta)
        if pr_final_decal.is_empty():
            return
        pr_final_decal["t"] = float(pr_final_decal["t"]) + delta
        if pr_final_t <= 0.0:
            pr_final_decal["dead"] = true

    func incoming_damage_mult(_amount: float, _source_pos: Vector2, _source: String) -> float:
        if not has_evo("sanctuary") or pr_sanct_life <= 0.0:
            return 1.0
        if player.global_position.distance_to(pr_sanct_center) > pr_sanct_r:
            return 1.0
        return 1.0 - clampf(float(evo_param("sanctuary", "reduce", 0.5)), 0.0, 0.95)

    func draw_overlay(c: Node2D) -> void:
        if def.id != "prayer":
            return
        var col: Color = def.color
        if has_evo("seraph_ring"):
            var count: int = maxi(1, int(evo_param("seraph_ring", "orbs", 3)))
            var rr: float = float(p["range"]) * player.stat("area") * 0.92
            for i in count:
                var op: Vector2 = Vector2(0, -8) + Vector2.from_angle(pr_orb_ang + TAU * float(i) / float(count)) * rr
                c.draw_circle(op, 6.0, Color(col.r, col.g, col.b, 0.9))
                c.draw_circle(op, 10.0, Color(1.0, 0.95, 0.7, 0.18))
                c.draw_arc(op, 11.0, 0.0, TAU, 16, Color(1.0, 0.95, 0.7, 0.5), 1.0)
        if has_evo("twin_suns"):
            var off: float = float(evo_param("twin_suns", "offset", 150.0))
            var now: float = world().run_time if world() != null else 0.0
            for side in [-1.0, 1.0]:
                var sp: Vector2 = Vector2(float(side) * off, -8.0)
                var pulse: float = 0.5 + 0.5 * sin(now * 5.0)
                c.draw_circle(sp, 16.0 + pulse * 2.0, Color(1.0, 0.9, 0.5, 0.08))
                c.draw_circle(sp, 8.0, Color(1.0, 0.95, 0.7, 0.9))
                c.draw_arc(sp, 12.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.4, 0.55), 1.5)


# =============================================================================================== Ninja flash bombs
class StunPulse extends Ability:
    var _mine_pos := Vector2.INF    # trailing_mines: last mine drop position
    var _mine_ttl: Array = []      # trailing_mines: remaining life per dropped mine
    var _cascade_busy := false     # cascade_flash: one-generation guard

    func on_ready() -> void:
        t = float(p["interval"]) * 0.5

    func update(delta: float) -> void:
        if has_evo("trailing_mines"):
            _mine_flow(delta)
        t -= delta
        if t > 0.0:
            return
        t = float(p["interval"]) * cd()
        _flash(player.global_position + Vector2(0, -8), float(p["radius"]) * player.stat("area"), float(p["stun"]))

    ## One flash: stun + fx, plus the flash-bomb evolutions. `evolved` is false for
    ## chained cascade flashes so evolutions cannot re-trigger off each other.
    func _flash(origin: Vector2, r: float, stun: float, evolved: bool = true) -> void:
        var atk_ctx := {"origin": origin, "radius": r, "stun": stun, "mult": 1.0, "cancel": false}
        hook("on_attack", atk_ctx)
        if bool(atk_ctx.get("cancel", false)):
            return
        stun = float(atk_ctx.get("stun", stun))
        r = float(atk_ctx.get("radius", r))
        origin = atk_ctx.get("origin", origin)
        var n := 0
        var hit: Array = []
        for e in world().enemies.query_circle(origin, r):
            world().enemies.stun(e, stun)
            hit.append(e)
            if has_evo("killing_light"):
                world().enemies.mark(e, "killing_light", stun, "flash", {"mult": float(evo_param("killing_light", "hit_mult", 2.0))})
            if has_evo("panic_powder"):
                world().enemies.fear(e, float(evo_param("panic_powder", "fear", 1.5)), origin)
            n += 1
        world().fx.ring(origin, 4.0, r, 0.3, Color(1.0, 1.0, 0.8), 4.0)
        world().fx.ring(origin, 2.0, r * 0.7, 0.2, Color(1, 1, 1), 2.0)
        for i in 18:
            world().fx.emit(origin, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0), 0.3, 2.0, Color(1.0, 1.0, 0.85), 2, 5.0)
        world().flash_screen(Color(1, 1, 0.9, 0.35))
        Audio.sfx("lightning_bolt", -6.0, 1.7)
        if n > 0:
            Game.shake(2.0)
        if not evolved:
            return
        hook("on_flash", atk_ctx)
        if has_evo("panic_powder"):
            after(float(evo_param("panic_powder", "fear", 1.5)), _panic_followup.bind(hit))
        if has_evo("smoke_veil"):
            world().projectiles.spawn_trap_zone(origin, r * float(evo_param("smoke_veil", "radius_mult", 1.0)), 0.0, float(evo_param("smoke_veil", "life", 4.0)), {"color": Color(0.8, 0.85, 0.9), "tick_interval": 0.4, "slow_mult": float(evo_param("smoke_veil", "slow", 0.6)), "slow_time": 0.5, "contact_mult": float(evo_param("smoke_veil", "contact_mult", 0.7)), "contact_time": 0.5, "src": "smoke_veil"})
        if has_evo("vanish"):
            player.go_untargetable(float(evo_param("vanish", "untargetable", 0.8)))
            if player.weapon != null and player.weapon.has_method("set_ambush"):
                player.weapon.set_ambush(float(evo_param("vanish", "window", 2.0)), float(evo_param("vanish", "ambush_mult", 2.5)))

    ## Panic Powder follow-up: the enemies that fled are usually outside the flash
    ## radius by now, so slow the ones actually feared (not a fresh circle query).
    func _panic_followup(hit: Array) -> void:
        for e in hit:
            if e != null and e.alive:
                world().enemies.slow(e, float(evo_param("panic_powder", "slow", 0.7)), float(evo_param("panic_powder", "slow_time", 2.0)))

    ## trailing_mines (Lv8): drop up to max_mines short-lived stun mines while moving.
    func _mine_flow(delta: float) -> void:
        for i in range(_mine_ttl.size() - 1, -1, -1):
            _mine_ttl[i] = float(_mine_ttl[i]) - delta
            if _mine_ttl[i] <= 0.0:
                _mine_ttl.remove_at(i)
        if not player.is_moving() or _mine_ttl.size() >= int(evo_param("trailing_mines", "max_mines", 4)):
            return
        if _mine_pos != Vector2.INF and _mine_pos.distance_to(player.global_position) < float(evo_param("trailing_mines", "spacing", 60.0)):
            return
        _mine_pos = player.global_position
        _mine_ttl.append(1.4)
        world().projectiles.spawn_trap_zone(player.global_position, 18.0, 0.0, 1.4, {"color": Color(1.0, 1.0, 0.6), "stun": float(evo_param("trailing_mines", "stun", 1.0)), "arm": float(evo_param("trailing_mines", "arm", 0.3)), "src": "flash_mine"})

    ## cascade_flash (Lv16): a stunned enemy that dies emits one smaller flash.
    func on_kill(e) -> void:
        if _cascade_busy or not has_evo("cascade_flash"):
            return
        if e != null and float(e.stun) > 0.0:
            _cascade_busy = true
            _flash(e.pos, float(p["radius"]) * player.stat("area") * float(evo_param("cascade_flash", "radius_mult", 0.5)), float(p["stun"]) * 0.5, false)
            _cascade_busy = false


# =============================================================================================== Pirate crew
class SummonAllies extends Ability:
    class Ally:
        var kind := 0        # 0 idle, 1 leaping, 2 overboard, 3 returning
        var t := 0.0
        var target := Vector2.ZERO
        var fire_t := 0.0

    var allies: Array = []
    var ally_info: Array = []
    var active_t := 0.0
    var _clock := 0.0
    # Pirate crew evolutions
    var board_t := 0.0
    var banner: Node2D = null
    var banner_pos := Vector2.ZERO
    var banner_t := 0.0
    var banner_pulse := 0.0
    var spot: Sprite2D = null
    var spot_pos := Vector2.ZERO
    var spot_t := 0.0
    var spot_wait := 4.0
    var keg: Sprite2D = null
    var keg_pos := Vector2.ZERO
    var keg_t := 3.0

    func on_ready() -> void:
        t = float(p["interval"]) * 0.35

    func update(delta: float) -> void:
        _clock += delta
        _update_banner(delta)
        _update_spot(delta)
        _update_keg(delta)
        if active_t > 0.0:
            active_t -= delta
            _update_allies(delta)
            if active_t <= 0.0:
                _dismiss()
            return
        t -= delta
        if t <= 0.0:
            _summon()

    func _update_allies(delta: float) -> void:
        var n := allies.size()
        for i in n:
            if i >= ally_info.size():
                break
            var a: Sprite2D = allies[i]
            if not is_instance_valid(a):
                continue
            var info: Ally = ally_info[i]
            if info.kind == 2:
                # man_overboard: the ally is in the water, waiting to come back
                info.t -= delta
                if info.t <= 0.0:
                    info.kind = 0
                    a.visible = true
                    a.modulate.a = 1.0
                    world().fx.ring(a.global_position, 2.0, 24.0, 0.3, Color(0.6, 0.85, 1.0), 2.0)
                continue
            var ang := _clock * 1.2 + TAU * float(i) / float(maxi(n, 1))
            var slot := player.global_position + Vector2(cos(ang) * 40.0, sin(ang) * 16.0 + 4.0)
            if info.kind == 1:
                # boarding_party: airborne, heading for the cluster
                a.global_position = a.global_position.lerp(info.target, minf(1.0, delta * 9.0))
                info.t -= delta
                if info.t <= 0.0:
                    _board_slam(info.target)
                    info.kind = 3
                    info.t = 0.7
            elif info.kind == 3:
                a.global_position = a.global_position.lerp(slot, minf(1.0, delta * 8.0))
                info.t -= delta
                if info.t <= 0.0:
                    info.kind = 0
            else:
                a.global_position = a.global_position.lerp(slot, minf(1.0, delta * 8.0))
            a.frame = 2 + int(_clock * 9.0 + i) % 4
            a.flip_h = player.facing_x < 0.0
            a.modulate.a = clampf(active_t * 3.0, 0.0, 1.0)
            if has_evo("gun_crew"):
                _ally_gun(a, info, delta)
            if has_evo("human_shield"):
                _ally_shield(a)
        if has_evo("boarding_party"):
            board_t -= delta
            if board_t <= 0.0:
                board_t = float(evo_param("boarding_party", "every", 4.0))
                _send_boarder()

    func _summon() -> void:
        var n := int(round(float(p["allies"])))
        var tex := DB.texture("res://art/characters/pirate_ally.png")
        for i in n:
            var s := Sprite2D.new()
            s.texture = tex
            s.hframes = 6
            s.offset = Vector2(0, -30)
            s.scale = Vector2(0.8, 0.8)
            s.modulate = Color(0.85, 0.95, 1.0)
            s.global_position = player.global_position + Vector2.from_angle(randf() * TAU) * 30.0
            world().actors.add_child(s)
            allies.append(s)
            var info := Ally.new()
            info.fire_t = randf() * float(evo_param("gun_crew", "interval", 1.5))
            ally_info.append(info)
            world().fx.ring(s.global_position, 2.0, 22.0, 0.3, Color(1.0, 0.85, 0.5), 2.0)
        active_t = float(p["duration"])
        # Crew multiplier equals the ally count: 2 allies -> x2, 3 -> x3, ...
        var mult := float(n)
        if has_evo("gun_crew") and bool(evo_param("gun_crew", "replaces_multiplier", true)):
            mult = 1.0
        player.proj_mults["crew"] = mult
        player.sources["crew"] = allies
        if mult > 1.0:
            world().announce("ALL HANDS!  x%.2f VOLLEY" % mult, false)
        else:
            world().announce("GUN CREW!  CANNONS READY", false)
        Audio.sfx("hand_cannon", -10.0, 1.5)
        if has_evo("jolly_roger"):
            _plant_banner()

    func _dismiss() -> void:
        if has_evo("release_the_kraken"):
            _kraken_volley()
        for a in allies:
            world().fx.ring(a.global_position, 2.0, 20.0, 0.25, Color(1, 1, 1), 2.0)
            a.queue_free()
        allies.clear()
        ally_info.clear()
        player.proj_mults.erase("crew")
        player.sources.erase("crew")
        t = float(p["interval"]) * cd()

    # ---------------------------------------------------------------- gun crew
    func _ally_gun(a: Sprite2D, info: Ally, delta: float) -> void:
        info.fire_t -= delta
        if info.fire_t > 0.0:
            return
        info.fire_t = float(evo_param("gun_crew", "interval", 1.5))
        var tgt: EnemyManager.E = world().enemies.nearest(a.global_position, 420.0, {})
        if tgt == null:
            return
        var aim: Vector2 = tgt.pos - a.global_position
        if aim.length() < 4.0:
            return
        var dir := aim.normalized()
        var amount := float(evo_param("gun_crew", "damage", 18.0)) * float(evo_param("gun_crew", "mult", 0.5)) * player.stat("damage")
        var muzzle := a.global_position + dir * 10.0
        world().projectiles.fire(ProjectileManager.Kind.CANNON, muzzle, dir, 430.0, amount, 5.0, 1, 0.8, Color(1.0, 0.7, 0.3), {"knock": 50.0})
        world().fx.muzzle(muzzle, dir, Color(1.0, 0.7, 0.3))

    # ---------------------------------------------------------------- human shield
    func _ally_shield(a: Sprite2D) -> void:
        var radius := float(evo_param("human_shield", "radius", 26.0))
        var blocked: int = world().projectiles.intercept(a.global_position, radius, "destroy")
        if blocked <= 0:
            return
        world().fx.ring(a.global_position, 8.0, radius + 12.0, 0.22, Color(0.7, 0.9, 1.0), 2.5)
        var amount := float(evo_param("human_shield", "damage", 14.0)) * float(evo_param("human_shield", "counter_mult", 0.8)) * player.stat("damage")
        var tgt: EnemyManager.E = world().enemies.nearest(a.global_position, 420.0, {})
        if tgt != null:
            var dir := (tgt.pos - a.global_position).normalized()
            var muzzle := a.global_position + dir * 10.0
            world().projectiles.fire(ProjectileManager.Kind.CANNON, muzzle, dir, 430.0, amount, 5.0, 1, 0.8, Color(0.7, 0.9, 1.0), {"knock": 70.0})
            world().fx.muzzle(muzzle, dir, Color(0.7, 0.9, 1.0))
        Audio.sfx("screech", -14.0, 1.4)

    # ---------------------------------------------------------------- boarding party
    func _send_boarder() -> void:
        var reach := float(evo_param("boarding_party", "leap_range", 240.0))
        var target := EvoPrims.densest_cluster(world(), player.global_position, reach, 60.0, [player.global_position])
        if target.distance_to(player.global_position) < 50.0:
            return
        for i in ally_info.size():
            var info: Ally = ally_info[i]
            if info.kind == 0:
                info.kind = 1
                info.t = 0.4
                info.target = target
                world().fx.ring(target, 8.0, float(evo_param("boarding_party", "radius", 60.0)), 0.4, Color(1.0, 0.75, 0.35, 0.9), 2.5)
                return

    func _board_slam(pos: Vector2) -> void:
        var radius := float(evo_param("boarding_party", "radius", 60.0))
        var amount := _crew_dmg(float(evo_param("boarding_party", "mult", 1.0)))
        world().fx.ring(pos, 10.0, radius, 0.3, Color(1.0, 0.75, 0.35), 3.0)
        world().fx.hit_sparks(pos, Vector2.UP, Color(1.0, 0.8, 0.45), 12)
        Game.shake(2.4)
        Audio.sfx("hand_cannon", -12.0, 0.7)
        for e in world().enemies.query_circle(pos, radius):
            world().enemies.damage(e, amount, (e.pos - pos).normalized(), 130.0, Color(1.0, 0.75, 0.35), "boarding_party")

    # ---------------------------------------------------------------- jolly roger
    func _plant_banner() -> void:
        if banner != null and is_instance_valid(banner):
            banner.queue_free()
        banner_pos = player.global_position + Vector2(0, 6)
        banner_t = float(evo_param("jolly_roger", "life", 8.0))
        banner_pulse = 0.0
        var holder := Node2D.new()
        holder.global_position = banner_pos
        var pole := Line2D.new()
        pole.points = PackedVector2Array([Vector2(0, 0), Vector2(0, -52)])
        pole.width = 3.0
        pole.default_color = Color(0.25, 0.18, 0.11)
        holder.add_child(pole)
        var flag := Polygon2D.new()
        flag.polygon = PackedVector2Array([Vector2(1, -52), Vector2(30, -44), Vector2(1, -34)])
        flag.color = Color(0.07, 0.07, 0.09)
        holder.add_child(flag)
        var skull := Polygon2D.new()
        skull.polygon = PackedVector2Array([Vector2(9, -46), Vector2(16, -41), Vector2(9, -36), Vector2(3, -41)])
        skull.color = Color(0.92, 0.92, 0.9)
        holder.add_child(skull)
        world().actors.add_child(holder)
        banner = holder
        world().fx.ring(banner_pos, 6.0, 40.0, 0.4, Color(0.9, 0.85, 0.6), 3.0)
        world().announce("JOLLY ROGER!", false)
        Audio.sfx("coin_pickup", -12.0, 0.8)

    func _update_banner(delta: float) -> void:
        if banner_t <= 0.0:
            if banner != null:
                if is_instance_valid(banner):
                    banner.queue_free()
                banner = null
            if player.reload_mult != 1.0:
                player.reload_mult = 1.0
                player.remove_buff("jolly_roger")
            return
        banner_t -= delta
        banner_pulse -= delta
        var radius := float(evo_param("jolly_roger", "radius", 100.0))
        if banner_pulse <= 0.0:
            banner_pulse = 0.55
            world().fx.ring(banner_pos, radius * 0.72, radius, 0.55, Color(0.85, 0.8, 0.55, 0.5), 2.0)
        if player.global_position.distance_to(banner_pos) <= radius:
            player.reload_mult = float(evo_param("jolly_roger", "reload_speed", 2.0))
            player.add_buff("jolly_roger", 0.3, {"regen": float(evo_param("jolly_roger", "regen", 2.0))}, {})
        else:
            player.reload_mult = 1.0
            player.remove_buff("jolly_roger")

    # ---------------------------------------------------------------- x marks the spot
    func _plant_spot() -> void:
        var dist := float(evo_param("x_marks_the_spot", "distance", 300.0))
        spot_pos = player.global_position + Vector2.from_angle(randf() * TAU) * dist
        var s := Sprite2D.new()
        s.texture = DB.texture("res://art/pickups/treasure_chest.png")
        s.offset = Vector2(0, -14)
        s.global_position = spot_pos
        world().actors.add_child(s)
        spot = s
        spot_t = float(evo_param("x_marks_the_spot", "window", 12.0))
        world().fx.ring(spot_pos, 6.0, 34.0, 0.45, Color(1.0, 0.85, 0.4), 2.5)
        world().announce("X MARKS THE SPOT", false)

    func _update_spot(delta: float) -> void:
        if not has_evo("x_marks_the_spot"):
            return
        if spot != null:
            if spot_t <= 0.0:
                world().fx.float_text(spot_pos + Vector2(0, -34), "THE SPOT IS LOST", Color(0.85, 0.75, 0.6), 15, 1.2, 16.0)
                if is_instance_valid(spot):
                    spot.queue_free()
                spot = null
                return
            if player.global_position.distance_to(spot_pos) <= 30.0:
                var at := spot_pos
                world().fx.ring(at, 8.0, 46.0, 0.35, Color(1.0, 0.85, 0.4), 3.0)
                world().fx.float_text(at + Vector2(0, -34), "X MARKS THE SPOT", Color(1.0, 0.85, 0.4), 15, 1.2, 16.0)
                Audio.sfx("coin_pickup", -6.0, 1.0)
                if is_instance_valid(spot):
                    spot.queue_free()
                spot = null
                world().on_chest_opened(at)
            return
        spot_wait -= delta
        if spot_wait <= 0.0:
            spot_wait = float(evo_param("x_marks_the_spot", "every", 60.0))
            _plant_spot()

    # ---------------------------------------------------------------- grog rations
    func _toss_keg() -> void:
        keg_pos = player.global_position + player.aim_dir() * 72.0
        var s := Sprite2D.new()
        s.texture = DB.texture("res://art/weapons/keg.png")
        s.offset = Vector2(0, -14)
        s.scale = Vector2(0.7, 0.7)
        s.global_position = keg_pos
        world().actors.add_child(s)
        keg = s
        world().fx.ring(keg_pos, 4.0, 26.0, 0.35, Color(1.0, 0.75, 0.35, 0.85), 2.0)

    func _update_keg(delta: float) -> void:
        if not has_evo("grog_rations"):
            return
        if keg != null:
            if player.global_position.distance_to(keg_pos) <= 24.0:
                player.heal(player.max_hp * float(evo_param("grog_rations", "heal_pct", 0.05)))
                player.add_buff("grog", float(evo_param("grog_rations", "buff_time", 5.0)), {}, {"damage": float(evo_param("grog_rations", "buff_mult", 1.25))})
                world().fx.float_text(player.global_position + Vector2(0, -44), "GROG!", Color(1.0, 0.8, 0.4), 17, 1.2, 16.0)
                world().fx.ring(player.global_position, 4.0, 30.0, 0.3, Color(1.0, 0.8, 0.4), 2.5)
                Audio.sfx("coin_pickup", -8.0, 1.2)
                if is_instance_valid(keg):
                    keg.queue_free()
                keg = null
            return
        keg_t -= delta
        if keg_t <= 0.0:
            keg_t = float(evo_param("grog_rations", "every", 6.0))
            _toss_keg()

    # ---------------------------------------------------------------- man overboard
    func absorb_hit(_amount: float) -> bool:
        if not has_evo("man_overboard"):
            return false
        for i in ally_info.size():
            var info: Ally = ally_info[i]
            if info.kind == 2:
                continue
            var a: Sprite2D = allies[i]
            info.kind = 2
            info.t = float(evo_param("man_overboard", "respawn", 8.0))
            a.visible = false
            world().fx.ring(a.global_position, 8.0, 38.0, 0.3, Color(0.6, 0.85, 1.0), 3.0)
            world().fx.float_text(a.global_position + Vector2(0, -38), "MAN OVERBOARD", Color(0.7, 0.9, 1.0), 15, 1.2, 16.0)
            Audio.sfx("screech", -8.0, 0.9)
            player.invuln = maxf(player.invuln, 0.35)
            return true
        return false

    # ---------------------------------------------------------------- release the kraken
    func _kraken_volley() -> void:
        var count := int(evo_param("release_the_kraken", "slams", 3))
        var tell := float(evo_param("release_the_kraken", "tell", 0.8))
        var radius := float(evo_param("release_the_kraken", "radius", 55.0))
        var amount := _crew_dmg(float(evo_param("release_the_kraken", "mult", 1.2)))
        var picked: Array = [player.global_position]
        for i in count:
            var slam_at := EvoPrims.densest_cluster(world(), player.global_position, 340.0, 60.0, picked)
            if slam_at.distance_to(player.global_position) < 40.0:
                continue
            picked.append(slam_at)
            world().fx.ring(slam_at, 8.0, radius, tell, Color(0.4, 0.85, 0.95, 0.9), 3.0)
            after(tell, func() -> void: _kraken_slam(slam_at, radius, amount))
        world().announce("RELEASE THE KRAKEN!", false)

    func _kraken_slam(pos: Vector2, radius: float, amount: float) -> void:
        world().fx.ring(pos, 10.0, radius, 0.3, Color(0.4, 0.85, 0.95), 4.0)
        world().fx.hit_sparks(pos, Vector2.UP, Color(0.5, 0.9, 1.0), 14)
        Game.shake(3.0)
        Audio.sfx("screech", -6.0, 0.7)
        for e in world().enemies.query_circle(pos, radius):
            world().enemies.damage(e, amount, (e.pos - pos).normalized(), 150.0, Color(0.4, 0.85, 0.95), "kraken")

    # ---------------------------------------------------------------- shared
    func _crew_dmg(mult: float) -> float:
        if player.weapon != null:
            return player.weapon.dmg(mult)
        return 30.0 * mult

    func hud_line() -> String:
        return "x%.2f" % float(player.proj_mults.get("crew", 1.0)) if active_t > 0.0 else "%ds" % maxi(0, ceili(t))


# =============================================================================================== Wizard astral projection
class AstralClone extends Ability:
    var clone: Sprite2D
    var active_t := 0.0
    var _anchor_pos := Vector2.ZERO
    var _anchor_t := 0.0
    var _proj_count := 0
    var _flow_extra := 0.0
    var _wild_t := 0.0

    func on_ready() -> void:
        t = float(p["interval"]) * 0.4

    func update(delta: float) -> void:
        if active_t > 0.0:
            active_t -= delta
            var lag: Vector2 = player.history[4]
            if has_evo("mirror_image"):
                var move := player.global_position - lag
                clone.global_position = player.global_position - move + Vector2(0, -2.0 + sin(active_t * 5.0) * 2.0)
            elif has_evo("astral_anchor"):
                clone.global_position = _anchor_pos + Vector2(0, sin(active_t * 5.0) * 2.0)
                _anchor_t -= delta
                if _anchor_t <= 0.0:
                    _anchor_t = 1.4
                    _anchor_cast()
            else:
                clone.global_position = lag + Vector2(-player.facing_x * 22.0, -2.0 + sin(active_t * 5.0) * 2.0)
            clone.frame = player.sprite.frame
            clone.flip_h = player.sprite.flip_h
            clone.modulate.a = clampf(active_t * 2.0, 0.0, 0.55)
            _wild_magic_update(delta)
            if active_t <= 0.0:
                _end()
            return
        t -= delta
        if t <= 0.0:
            _begin()

    func _begin() -> void:
        clone = Sprite2D.new()
        clone.texture = player.sprite.texture
        clone.hframes = player.sprite.hframes
        clone.offset = player.sprite.offset
        clone.modulate = Color(0.6, 0.8, 1.0, 0.55)
        var m := CanvasItemMaterial.new()
        m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        clone.material = m
        clone.global_position = player.global_position
        world().actors.add_child(clone)
        active_t = float(p["duration"])
        _anchor_pos = player.global_position
        _anchor_t = 1.0
        _flow_extra = 0.0
        _wild_t = 0.6
        if not (has_evo("spell_echo") and bool(evo_param("spell_echo", "replaces_multiplier", true))):
            player.proj_mults["astral"] = float(p["projectile_mult"])
            player.sources["astral"] = [clone]
        world().fx.ring(player.global_position, 4.0, 60.0, 0.4, Color(0.6, 0.8, 1.0), 3.0)
        world().announce("ASTRAL PROJECTION  x%.2f" % float(p["projectile_mult"]), false)
        Audio.sfx("lightning_bolt", -8.0, 0.6)
        if has_evo("ethereal_walk"):
            var walk := float(evo_param("ethereal_walk", "duration", 4.0))
            player.go_untargetable(walk)
            player.add_buff("ethereal_walk", walk, {}, {"cooldown": 2.0})
        _proj_count += 1
        if has_evo("time_stop"):
            var every := int(evo_param("time_stop", "every", 4))
            if every > 0 and _proj_count % every == 0:
                _time_stop()

    func _end() -> void:
        if clone != null:
            if has_evo("astral_swap"):
                _astral_swap()
            else:
                world().fx.ring(clone.global_position, 2.0, 40.0, 0.3, Color(0.6, 0.8, 1.0), 2.0)
            clone.queue_free()
            clone = null
        player.proj_mults.erase("astral")
        player.sources.erase("astral")
        if has_evo("ethereal_walk"):
            player.remove_buff("ethereal_walk")
        t = float(p["interval"]) * cd()

    func _dmg(mult: float) -> float:
        if player.weapon != null:
            return player.weapon.dmg(mult)
        return 24.0 * mult

    func hook(name: String, ctx: Dictionary = {}) -> void:
        if name == "on_player_cast":
            _clone_weapon_cast(ctx)
        super.hook(name, ctx)

    func _clone_weapon_cast(_ctx: Dictionary) -> void:
        if active_t <= 0.0 or clone == null:
            return
        if has_evo("spell_echo"):
            _queue_spell_echo(_ctx)

    func _queue_spell_echo(_ctx: Dictionary) -> void:
        if not has_evo("spell_echo") or clone == null:
            return
        var delay := float(evo_param("spell_echo", "delay", 0.5))
        var power := float(evo_param("spell_echo", "power", 0.7))
        var origin := clone.global_position
        after(delay, func() -> void: _echo_cast(origin, power))

    func _echo_cast(origin: Vector2, power: float) -> void:
        var tgt: EnemyManager.E = world().enemies.nearest(origin, 320.0, {})
        if tgt == null:
            return
        var col := Color(0.55, 0.85, 1.0)
        world().fx.bolt(WeaponBehaviors.jagged(origin + Vector2(0, -12), tgt.pos + Vector2(0, -8)), col, 0.18)
        world().fx.strike(tgt.pos)
        world().enemies.damage(tgt, _dmg(power), Vector2.ZERO, 0.0, col, "astral_echo")

    func _anchor_cast() -> void:
        if clone == null:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(clone.global_position, 300.0, {})
        if tgt == null:
            return
        var col := Color(0.6, 0.8, 1.0)
        world().fx.bolt(WeaponBehaviors.jagged(clone.global_position + Vector2(0, -12), tgt.pos + Vector2(0, -8)), col, 0.16)
        world().enemies.damage(tgt, _dmg(0.6), Vector2.ZERO, 0.0, col, "astral_anchor")

    func _astral_swap() -> void:
        var other := clone.global_position
        var here := player.global_position
        var radius := float(evo_param("astral_swap", "ring_radius", 70.0))
        var mult := float(evo_param("astral_swap", "ring_mult", 1.0))
        var inv := float(evo_param("astral_swap", "invuln", 0.2))
        player.blink_to(other, inv)
        _detonate(here, radius, mult)
        _detonate(other, radius, mult)

    func _detonate(pos: Vector2, radius: float, mult: float) -> void:
        var col := Color(0.6, 0.8, 1.0)
        world().fx.ring(pos, 6.0, radius, 0.3, col, 3.0)
        world().fx.strike(pos)
        for e in world().enemies.query_circle(pos, radius):
            world().enemies.damage(e, _dmg(mult), (e.pos - pos).normalized(), 80.0, col, "astral_swap")

    func _time_stop() -> void:
        var freeze := float(evo_param("time_stop", "freeze", 1.5))
        for e in world().enemies.active:
            world().enemies.stun(e, freeze)
        world().fx.ring(player.global_position, 16.0, 460.0, 0.5, Color(0.7, 0.85, 1.0), 4.0)
        world().announce("TIME STOP", false)
        Audio.sfx("lightning_bolt", -6.0, 0.5)

    func _flow_state_kill() -> void:
        if not has_evo("flow_state") or active_t <= 0.0:
            return
        var cap := float(evo_param("flow_state", "cap", 4.0))
        var gain := minf(float(evo_param("flow_state", "per_kill", 0.3)), cap - _flow_extra)
        if gain <= 0.0:
            return
        _flow_extra += gain
        active_t += gain
        world().fx.float_text(player.global_position + Vector2(0, -40), "+%0.1fs" % gain, Color(0.7, 0.85, 1.0), 13, 0.7, 18.0)

    func on_kill(_e) -> void:
        _flow_state_kill()

    func _wild_magic_update(delta: float) -> void:
        if not has_evo("wild_magic"):
            return
        _wild_t -= delta
        if _wild_t > 0.0:
            return
        _wild_t = 1.2
        var pool: Array = evo_param("wild_magic", "pool", ["frost_nova", "meteor", "gravity_pull"])
        if pool.is_empty():
            return
        var kind := String(pool[randi() % pool.size()])
        var tell := float(evo_param("wild_magic", "tell", 0.5))
        var origin := clone.global_position if clone != null else player.global_position
        if kind == "frost_nova":
            world().fx.ring(origin, 6.0, 92.0, tell, Color(0.6, 0.85, 1.0), 3.0)
            after(tell, func() -> void: _wild_nova(origin))
        elif kind == "meteor":
            var spot := EvoPrims.densest_cluster(world(), origin, 240.0, 60.0, [])
            world().fx.ring(spot, 8.0, 70.0, tell, Color(1.0, 0.55, 0.3), 3.0)
            after(tell, func() -> void: _wild_meteor(spot))
        else:
            world().fx.ring(origin, 8.0, 130.0, tell, Color(0.7, 0.5, 1.0), 3.0)
            after(tell, func() -> void: _wild_pull(origin))

    func _wild_nova(pos: Vector2) -> void:
        var col := Color(0.6, 0.85, 1.0)
        world().fx.ring(pos, 10.0, 100.0, 0.3, col, 4.0)
        for e in world().enemies.query_circle(pos, 100.0):
            world().enemies.damage(e, _dmg(0.8), (e.pos - pos).normalized(), 60.0, col, "wild_magic")
            world().enemies.slow(e, 0.4, 2.0)

    func _wild_meteor(pos: Vector2) -> void:
        var col := Color(1.0, 0.65, 0.3)
        world().fx.strike(pos)
        world().fx.ring(pos, 10.0, 72.0, 0.3, col, 4.0)
        Game.shake(3.0)
        for e in world().enemies.query_circle(pos, 72.0):
            world().enemies.damage(e, _dmg(1.4), (e.pos - pos).normalized(), 90.0, col, "wild_magic")

    func _wild_pull(pos: Vector2) -> void:
        var col := Color(0.7, 0.5, 1.0)
        world().fx.ring(pos, 8.0, 130.0, 0.3, col, 4.0)
        for e in world().enemies.query_circle(pos, 130.0):
            e.pos = e.pos.lerp(pos, 0.35)
            world().enemies.damage(e, _dmg(0.4), (pos - e.pos).normalized(), 40.0, col, "wild_magic")

    func hud_line() -> String:
        return "x%.2f" % float(p["projectile_mult"]) if active_t > 0.0 else "%ds" % maxi(0, ceili(t))


# =============================================================================================== Spider webs
class Web extends Ability:
    var web: Dictionary = {}
    var caught: Dictionary = {}

    func on_ready() -> void:
        t = 1.5

    func update(delta: float) -> void:
        if not web.is_empty():
            web["t"] = float(web["t"]) + delta
            var pos: Vector2 = web["pos"]
            var r := float(p["radius"]) * player.stat("area")
            web["r"] = r
            # Intentional exception: webs catch flying enemies too.
            for e in world().enemies.query_circle(pos, r):
                world().enemies.slow(e, float(p["slow"]), 0.35)
                if not caught.has(e.uid):
                    caught[e.uid] = true
                    world().fx.emit(e.pos, Vector2.ZERO, 0.2, 6.0, Color(0.9, 0.9, 1.0), 1, 0.0)
            web["load"] = float(caught.size()) / maxf(1.0, float(p["capacity"]))
            if caught.size() >= int(round(float(p["capacity"]))) or float(web["t"]) >= float(p["lifetime"]):
                _break()
            return
        t -= delta
        if t > 0.0:
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, 300.0, {})
        if tgt == null:
            t = 0.2
            return
        var spot: Vector2 = player.global_position.lerp(tgt.pos, 0.6)
        web = {"kind": "web", "pos": spot, "r": float(p["radius"]), "t": 0.0, "load": 0.0, "dead": false}
        caught.clear()
        world().add_decal(web)
        world().fx.ring(spot, 4.0, float(p["radius"]), 0.3, Color(0.9, 0.9, 1.0), 2.0)
        Audio.sfx("fang_bite", -8.0, 0.6)

    func _break() -> void:
        world().fx.ring(web["pos"], 4.0, float(web["r"]) * 1.1, 0.3, Color(0.9, 0.9, 1.0), 2.0)
        for i in 12:
            world().fx.emit(web["pos"] + Vector2.from_angle(randf() * TAU) * randf_range(0.0, float(web["r"])), Vector2.from_angle(randf() * TAU) * 40.0, 0.5, 2.0, Color(0.9, 0.9, 1.0), 2, 3.0)
        web["dead"] = true
        web = {}
        caught.clear()
        t = float(p["interval"]) * cd()

    func hud_line() -> String:
        if web.is_empty():
            return "%ds" % maxi(0, ceili(t))
        return "%d/%d" % [caught.size(), int(round(float(p["capacity"])))]


# =============================================================================================== Minotaur roar
class Roar extends Ability:
    var active_t := 0.0
    var roar_strength := 1.0
    var roar_stomp_t := 0.0
    var roar_stand_cd := 0.0

    func on_ready() -> void:
        t = float(p["interval"]) * 0.5

    func update(delta: float) -> void:
        if roar_stand_cd > 0.0:
            roar_stand_cd -= delta
        if active_t > 0.0:
            active_t -= delta
            _roar_tick(delta)
            if active_t <= 0.0:
                _expire()
            return
        if has_evo("last_stand") and roar_stand_cd <= 0.0 and player.hp <= player.max_hp * float(evo_param("last_stand", "hp_frac", 0.3)):
            roar_stand_cd = float(evo_param("last_stand", "cooldown", 40.0))
            _roar(float(evo_param("last_stand", "strength", 1.5)))
            return
        t -= delta
        if t <= 0.0:
            _roar()

    func _roar(strength: float = 1.0) -> void:
        var origin := player.global_position + Vector2(0, -12)
        roar_strength = strength
        active_t = float(p["duration"])
        roar_stomp_t = 0.0
        player.armor = float(p["armor_hp"]) * strength
        player.add_buff("roar", active_t, {}, {"damage": 1.0 + float(p["boost_damage"]) * strength, "move_speed": 1.0 + float(p["boost_speed"]) * strength})
        world().fx.ring(origin, 6.0, 150.0, 0.5, Color(1.0, 0.7, 0.35), 5.0)
        world().fx.ring(origin, 3.0, 90.0, 0.35, Color(1, 1, 1), 3.0)
        for e in world().enemies.query_circle(origin, 120.0):
            world().enemies.fear(e, 0.8, origin)
        if has_evo("warcry_shockwave"):
            _warcry(origin)
        if has_evo("armored_charge") and player.weapon != null and player.weapon.has_method("horn_force_charge"):
            player.weapon.horn_force_charge(float(evo_param("armored_charge", "distance", 240.0)))
        if has_evo("bulldozer"):
            player.visual_scale = float(evo_param("bulldozer", "scale", 1.4))
        world().announce("BEAST'S ROAR", false)
        Audio.sfx("horn_swipe", -2.0, 0.5)
        Game.shake(6.0)

    func _roar_tick(delta: float) -> void:
        if has_evo("outnumbered"):
            var n: int = world().enemies.query_circle(player.global_position, float(evo_param("outnumbered", "radius", 120.0))).size()
            var bonus := minf(float(evo_param("outnumbered", "cap", 0.3)), float(n) * float(evo_param("outnumbered", "per_enemy", 0.03)))
            player.add_buff("roar_outnumbered", 0.12, {}, {"damage": 1.0 + bonus})
        if has_evo("thundering_hooves") and player.is_moving():
            roar_stomp_t -= delta
            if roar_stomp_t <= 0.0:
                roar_stomp_t = float(evo_param("thundering_hooves", "stomp_every", 0.5))
                _roar_stomp()
        if has_evo("bulldozer"):
            player.stunned = 0.0
            player.visual_scale = float(evo_param("bulldozer", "scale", 1.4))
            if player.is_walking():
                var radius := float(evo_param("bulldozer", "shove_radius", 30.0))
                for e in world().enemies.query_circle(player.global_position, radius):
                    var away: Vector2 = e.pos - player.global_position
                    if away.length_squared() < 0.01:
                        away = player.last_dir
                    e.knock += away.normalized() * 260.0

    func _roar_stomp() -> void:
        var origin := player.global_position + Vector2(0, -10)
        var rr := float(evo_param("thundering_hooves", "radius", 40.0)) * player.stat("area")
        var amount := _roar_dmg(float(evo_param("thundering_hooves", "mult", 0.4)))
        for e in world().enemies.query_circle(origin, rr):
            world().enemies.damage(e, amount, e.pos - origin, 80.0, def.color, "thundering_hooves")
        world().fx.ring(origin, 4.0, rr, 0.2, Color(0.95, 0.75, 0.45), 2.0)

    func _warcry(origin: Vector2) -> void:
        var radius := float(evo_param("warcry_shockwave", "radius", 140.0))
        var push := float(evo_param("warcry_shockwave", "push_px", 100.0)) * 8.0
        for e in world().enemies.query_circle(origin, radius):
            var away: Vector2 = e.pos - origin
            if away.length_squared() < 0.01:
                away = player.last_dir
            e.knock += away.normalized() * push
        if bool(evo_param("warcry_shockwave", "destroy_projectiles", true)):
            world().projectiles.intercept(origin, radius, "destroy")
        world().fx.ring(origin, 8.0, radius, 0.3, Color(1.0, 0.8, 0.5), 3.0)

    func _expire() -> void:
        player.armor = 0.0
        player.remove_buff("roar")
        player.remove_buff("roar_outnumbered")
        player.visual_scale = 1.0
        active_t = 0.0
        roar_strength = 1.0
        t = float(p["interval"]) * cd()

    func on_armor_break() -> void:
        active_t = 0.0
        player.remove_buff("roar")
        player.remove_buff("roar_outnumbered")
        player.visual_scale = 1.0
        var origin := player.global_position + Vector2(0, -12)
        if has_evo("armor_burst"):
            player.invuln = maxf(player.invuln, float(evo_param("armor_burst", "invuln", 1.0)))
            var rr := 90.0 * player.stat("area")
            var amount := _roar_dmg(float(evo_param("armor_burst", "nova_mult", 1.5)))
            for e in world().enemies.query_circle(origin, rr):
                world().enemies.damage(e, amount, e.pos - origin, 220.0, def.color, "armor_burst")
            world().fx.ring(origin, 10.0, rr, 0.35, Color(1.0, 0.85, 0.5), 5.0)
            world().fx.star(origin, rr * 0.5, Color(1.0, 0.9, 0.6), 0.3)
            world().announce("ARMOR BURST", false)
            Audio.sfx("player_hit", -2.0, 0.6)
            Game.shake(5.0)
            t = float(p["interval"]) * cd()
            return
        if not has_evo("bulldozer"):
            player.stun(float(p["break_stun"]))
        world().fx.ring(origin, 6.0, 70.0, 0.4, Color(1.0, 0.4, 0.3), 4.0)
        world().announce("ARMOR BROKEN - STUNNED" if not has_evo("bulldozer") else "ARMOR BROKEN", true)
        Audio.sfx("player_hit", -2.0, 0.6)
        Game.shake(5.0)
        t = float(p["interval"]) * cd()

    func on_armor_hit(_amount: float, source_pos: Vector2) -> void:
        if not has_evo("spiked_hide") or not source_pos.is_finite():
            return
        var attacker = world().enemies.nearest(source_pos, 70.0, {})
        if attacker == null:
            return
        var dir: Vector2 = (attacker.pos - player.global_position).normalized()
        world().enemies.damage(attacker, _roar_dmg(float(evo_param("spiked_hide", "thorns_mult", 1.0))), dir, float(evo_param("spiked_hide", "knockback", 120.0)), def.color, "spiked_hide")
        world().fx.hit_sparks(attacker.pos, -dir, def.color, 4)

    func _roar_dmg(mult: float) -> float:
        if player.weapon != null:
            return player.weapon.dmg(mult)
        return 10.0 * player.stat("damage") * mult

    func hud_line() -> String:
        if active_t > 0.0:
            return "ARMOR %d" % int(player.armor)
        return "%ds" % maxi(0, ceili(t))


# =============================================================================================== Harpy aerial strike
class Swoop extends Ability:
    func on_ready() -> void:
        t = float(p["interval"]) * 0.5

    func update(delta: float) -> void:
        t -= delta
        if t > 0.0 or player.dash_t > 0.0:
            return
        var evasive: bool = flags.get("evasive", false)
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, float(p["swoop_range"]), {})
        if tgt == null:
            t = 0.15
            return
        t = float(p["interval"]) * cd()
        var col: Color = def.color
        if evasive:
            var dir: Vector2 = (player.global_position - tgt.pos).normalized()
            player.start_dash(dir, 150.0, 460.0, {"invuln": true, "color": col})
            player.invuln = maxf(player.invuln, float(p["invuln"]))
            world().fx.ring(player.global_position, 4.0, 34.0, 0.25, Color(0.85, 0.95, 1.0), 2.0)
        else:
            var d2: Vector2 = (tgt.pos - player.global_position).normalized()
            var dist := player.global_position.distance_to(tgt.pos) + 70.0
            player.start_dash(d2, dist, 720.0, {"damage": dmg(), "hit_radius": 20.0, "invuln": true, "color": col})
            player.invuln = maxf(player.invuln, float(p["invuln"]))
        Audio.sfx("screech", -4.0, 1.4)

    func hud_line() -> String:
        return "%ds" % maxi(0, ceili(t))


# =============================================================================================== Necromancer raise dead
class RaiseDead extends Ability:
    var minions: Array = []

    func on_kill(e) -> void:
        if e.is_elite or minions.size() >= int(round(float(p["max_minions"]))):
            return
        var chance := float(p["chance_base"]) + float(p["chance_per_level"]) * float(player.level)
        if randf() > chance:
            return
        var s := Sprite2D.new()
        var d: EnemyDef = e.def
        s.texture = DB.texture(d.sprite)
        s.hframes = d.frames
        s.offset = Vector2(0, -22)
        s.scale = Vector2.ONE * d.sprite_scale
        s.modulate = Color(0.45, 1.0, 0.85, 0.75)
        var m := CanvasItemMaterial.new()
        m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        s.material = m
        s.global_position = e.pos
        world().actors.add_child(s)
        var mult := float(p["stat_mult"])
        minions.append({"sp": s, "pos": e.pos, "life": float(p["duration"]), "speed": d.speed * 1.2 * mult, "dmg": d.contact_damage * mult * 1.5, "cd": 0.0, "rad": d.radius, "frames": d.frames, "anim": randf() * 4.0})
        world().fx.ring(e.pos, 2.0, 22.0, 0.35, Color(0.4, 1.0, 0.8), 2.0)
        for i in 8:
            world().fx.emit(e.pos, Vector2(randf_range(-20.0, 20.0), -randf_range(30.0, 90.0)), 0.6, 2.0, Color(0.4, 1.0, 0.8), 1, 2.0)
        Audio.sfx("skull_projectile", -8.0, 1.4)

    func update(delta: float) -> void:
        for i in range(minions.size() - 1, -1, -1):
            var m: Dictionary = minions[i]
            m["life"] = float(m["life"]) - delta
            m["cd"] = float(m["cd"]) - delta
            m["anim"] = float(m["anim"]) + delta * 8.0
            var pos: Vector2 = m["pos"]
            var tgt: EnemyManager.E = world().enemies.nearest(pos, 280.0, {})
            var dest := player.global_position + Vector2(cos(float(m["anim"]) * 0.2) * 50.0, sin(float(m["anim"]) * 0.2) * 30.0)
            if tgt != null:
                dest = tgt.pos
            var to := dest - pos
            if to.length() > 3.0:
                pos += to.normalized() * float(m["speed"]) * delta
            m["pos"] = pos
            if tgt != null and float(m["cd"]) <= 0.0 and pos.distance_to(tgt.pos) < float(m["rad"]) + tgt.radius + 4.0:
                m["cd"] = 0.5
                world().enemies.damage(tgt, float(m["dmg"]), tgt.pos - pos, 60.0, Color(0.4, 1.0, 0.8))
            var sp: Sprite2D = m["sp"]
            sp.global_position = pos
            sp.frame = int(m["anim"]) % int(m["frames"])
            sp.flip_h = to.x > 0.0
            sp.modulate.a = clampf(float(m["life"]) * 1.5, 0.0, 0.75)
            if float(m["life"]) <= 0.0:
                world().fx.ring(pos, 2.0, 18.0, 0.25, Color(0.4, 1.0, 0.8), 2.0)
                sp.queue_free()
                minions.remove_at(i)

    func hud_line() -> String:
        return "%d/%d" % [minions.size(), int(round(float(p["max_minions"])))]


# =============================================================================================== Goose turds
class Turds extends Ability:
    var turds: Array = []
    var scan_t := 0.0

    func on_ready() -> void:
        t = 1.0

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
        for i in range(turds.size() - 1, -1, -1):
            var d: Dictionary = turds[i]
            d["t"] = float(d["t"]) + delta
            if bool(d["dead"]) or float(d["t"]) >= float(p["lifetime"]):
                d["dead"] = true
                turds.remove_at(i)
                continue
            if not check:
                continue
            var poison := float(p["poison_dps"]) > 0.0
            d["poison"] = poison
            # Ground trap: skip flying enemies (height == 1).
            for e in world().enemies.query_ground_circle(d["pos"], float(p["radius"]) * player.stat("area")):
                var slot: Dictionary = d["seen"]
                if float(slot.get(e.uid, -9.0)) > now:
                    continue
                slot[e.uid] = now + 2.5
                world().enemies.stun(e, float(p["stun"]))
                world().fx.emit(e.pos + Vector2(0, -10), Vector2(0, -30), 0.4, 5.0, Color(1.0, 0.95, 0.5), 1, 2.0)
                if poison:
                    world().enemies.poison(e, float(p["poison_dps"]) * player.stat("damage"), float(p["poison_time"]))

    func _drop() -> void:
        var pos := player.global_position + Vector2(-player.facing_x * 6.0, 2.0)
        while turds.size() >= int(round(float(p["max_turds"]))):
            var old: Dictionary = turds.pop_front()
            old["dead"] = true
        var d := {"kind": "turd", "pos": pos, "t": 0.0, "dead": false, "poison": false, "seen": {}, "r": float(p["radius"])}
        turds.append(d)
        world().add_decal(d)
        world().fx.emit(pos, Vector2(0, -20), 0.3, 4.0, Color(0.6, 0.4, 0.2), 0, 2.0, 80.0, false)
        Audio.sfx("goblin_hit", -12.0, 0.6)

    func hud_line() -> String:
        return "%d/%d" % [turds.size(), int(round(float(p["max_turds"])))]


# =============================================================================================== Fun-Guy
class NutrientBloom extends Ability:
    const PULL_SPEED := 260.0
    const SFX_GAP := 0.06

    var blooms: Array = []
    var stacks := 0
    var hold := 0.0
    var decay := 0.0
    var aura_t := 0.0
    var last_sfx := -1.0
    var buff_t := 0.0

    func stack_count() -> int:
        return stacks

    func aura_radius() -> float:
        return (float(p["aura_radius"]) + float(p["aura_radius_per_stack"]) * float(stacks)) * player.stat("area")

    func on_kill(e) -> void:
        if blooms.size() >= int(round(float(p["max_blooms"]))) or randf() > float(p["bloom_chance"]):
            return
        var life: float = maxf(1.0, float(p["bloom_life"]))
        var d := {"kind": "bloom", "pos": e.pos, "t": 0.0, "dead": false, "r": float(p["absorb_radius"]), "life": life}
        blooms.append(d)
        world().add_decal(d)

    func update(delta: float) -> void:
        _step_blooms(delta)
        _step_stacks(delta)
        if float(p["aura_radius"]) > 0.0:
            _step_aura(delta)
            player.aura_r = aura_radius()
            player.aura_col = def.color
        else:
            player.aura_r = 0.0
        buff_t -= delta
        if buff_t <= 0.0:
            buff_t = 0.25
            var spd: float = maxf(float(p["speed_per_stack"]), 0.0) * float(stacks)
            player.add_buff("saprotroph", 0.6, {"damage": float(p["dmg_per_stack"]) * float(stacks)}, {"move_speed": 1.0 + spd})

    func _step_blooms(delta: float) -> void:
        var touch: float = float(p["absorb_radius"])
        var reach: float = float(p["auto_absorb_radius"])
        for i in range(blooms.size() - 1, -1, -1):
            var b: Dictionary = blooms[i]
            b["t"] = float(b["t"]) + delta
            if float(b["t"]) >= float(b["life"]):
                b["dead"] = true
                blooms.remove_at(i)
                continue
            var bpos: Vector2 = b["pos"]
            var d: float = bpos.distance_to(player.global_position)
            if d > touch and reach > 0.0 and d <= reach:
                bpos = bpos.move_toward(player.global_position, PULL_SPEED * delta)
                b["pos"] = bpos
                d = bpos.distance_to(player.global_position)
            if d <= touch:
                _absorb()
                b["dead"] = true
                blooms.remove_at(i)

    func _absorb() -> void:
        player.heal(float(p["heal_per_bloom"]))
        hold = float(p["stack_hold"])
        decay = float(p["stack_decay"])
        if stacks < int(round(float(p["max_stacks"]))):
            stacks += 1
        elif float(p["shield_per_overflow"]) > 0.0:
            var cap: float = player.stat("max_hp") * float(p["shield_cap_pct"])
            player.armor = minf(cap, player.armor + float(p["shield_per_overflow"]))
        if world().run_time - last_sfx >= SFX_GAP:
            last_sfx = world().run_time
            Audio.sfx(def.audio_event, -10.0, 1.2)

    func _step_stacks(delta: float) -> void:
        if stacks <= 0:
            return
        if hold > 0.0:
            hold -= delta
            return
        decay -= delta
        if decay <= 0.0:
            stacks -= 1
            decay = float(p["stack_decay"])

    func _step_aura(delta: float) -> void:
        aura_t -= delta
        if aura_t > 0.0:
            return
        aura_t = maxf(0.1, float(p["aura_tick"]))
        var r: float = aura_radius()
        var dmg: float = (float(p["aura_dmg"]) + float(p["aura_dmg_per_stack"]) * float(stacks)) * player.stat("damage")
        var played := false
        for e in world().enemies.query_ground_circle(player.global_position, r):
            if not e.alive:
                continue
            world().enemies.damage(e, dmg, e.pos - player.global_position, 10.0, def.color)
            played = true
        if played:
            Audio.sfx(def.audio_event, -12.0, 0.7)

    func hud_line() -> String:
        return "BLM %d STK %d" % [blooms.size(), stacks]
