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
    var tick_t := 0.0

    func on_ready() -> void:
        t = 0.8

    func update(delta: float) -> void:
        var mode := String(flags.get("mode", ""))
        var r := float(p["range"]) * player.stat("area")
        var origin := player.global_position + Vector2(0, -8)
        var col: Color = def.color
        if mode == "aura":
            player.aura_r = r
            player.aura_col = col
            tick_t -= delta
            if tick_t <= 0.0:
                tick_t = float(p["tick"]) * cd()
                for e in world().enemies.query_circle(origin, r):
                    world().enemies.damage(e, dmg(), e.pos - origin, 18.0, col)
                if def.id == "flailing_whip":
                    world().fx.lash(origin, randf() * TAU, r, col)
                    Audio.sfx("whip_crack", -12.0, 1.0, 0.15)
            return
        t -= delta
        if t > 0.0:
            return
        if def.id == "prayer":
            t = float(p["interval"]) * cd()
            _radial(origin, r, col, mode == "pulse")
            return
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, r * 1.25)
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


# =============================================================================================== Ninja flash bombs
class StunPulse extends Ability:
    func on_ready() -> void:
        t = float(p["interval"]) * 0.5

    func update(delta: float) -> void:
        t -= delta
        if t > 0.0:
            return
        t = float(p["interval"]) * cd()
        var origin := player.global_position + Vector2(0, -8)
        var r := float(p["radius"]) * player.stat("area")
        var n := 0
        for e in world().enemies.query_circle(origin, r):
            world().enemies.stun(e, float(p["stun"]))
            n += 1
        world().fx.ring(origin, 4.0, r, 0.3, Color(1.0, 1.0, 0.8), 4.0)
        world().fx.ring(origin, 2.0, r * 0.7, 0.2, Color(1, 1, 1), 2.0)
        for i in 18:
            world().fx.emit(origin, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 220.0), 0.3, 2.0, Color(1.0, 1.0, 0.85), 2, 5.0)
        world().flash_screen(Color(1, 1, 0.9, 0.35))
        Audio.sfx("lightning_bolt", -6.0, 1.7)
        if n > 0:
            Game.shake(2.0)


# =============================================================================================== Pirate crew
class SummonAllies extends Ability:
    var allies: Array = []
    var active_t := 0.0
    var _clock := 0.0

    func on_ready() -> void:
        t = float(p["interval"]) * 0.35

    func update(delta: float) -> void:
        _clock += delta
        if active_t > 0.0:
            active_t -= delta
            var n := allies.size()
            for i in n:
                var a: Sprite2D = allies[i]
                var ang := _clock * 1.2 + TAU * float(i) / float(maxi(n, 1))
                var target := player.global_position + Vector2(cos(ang) * 40.0, sin(ang) * 16.0 + 4.0)
                a.global_position = a.global_position.lerp(target, minf(1.0, delta * 8.0))
                a.frame = 2 + int(_clock * 9.0 + i) % 4
                a.flip_h = player.facing_x < 0.0
                a.modulate.a = clampf(active_t * 3.0, 0.0, 1.0)
            if active_t <= 0.0:
                _dismiss()
            return
        t -= delta
        if t <= 0.0:
            _summon()

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
            world().fx.ring(s.global_position, 2.0, 22.0, 0.3, Color(1.0, 0.85, 0.5), 2.0)
        active_t = float(p["duration"])
        # Crew multiplier equals the ally count: 2 allies -> x2, 3 -> x3, ...
        var mult := float(n)
        player.proj_mults["crew"] = mult
        player.sources["crew"] = allies
        world().announce("ALL HANDS!  x%.2f VOLLEY" % mult, false)
        Audio.sfx("hand_cannon", -10.0, 1.5)

    func _dismiss() -> void:
        for a in allies:
            world().fx.ring(a.global_position, 2.0, 20.0, 0.25, Color(1, 1, 1), 2.0)
            a.queue_free()
        allies.clear()
        player.proj_mults.erase("crew")
        player.sources.erase("crew")
        t = float(p["interval"]) * cd()

    func hud_line() -> String:
        return "x%.2f" % float(player.proj_mults.get("crew", 1.0)) if active_t > 0.0 else "%ds" % maxi(0, ceili(t))


# =============================================================================================== Wizard astral projection
class AstralClone extends Ability:
    var clone: Sprite2D
    var active_t := 0.0

    func on_ready() -> void:
        t = float(p["interval"]) * 0.4

    func update(delta: float) -> void:
        if active_t > 0.0:
            active_t -= delta
            var lag: Vector2 = player.history[4]
            clone.global_position = lag + Vector2(-player.facing_x * 22.0, -2.0 + sin(active_t * 5.0) * 2.0)
            clone.frame = player.sprite.frame
            clone.flip_h = player.sprite.flip_h
            clone.modulate.a = clampf(active_t * 2.0, 0.0, 0.55)
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
        player.proj_mults["astral"] = float(p["projectile_mult"])
        player.sources["astral"] = [clone]
        world().fx.ring(player.global_position, 4.0, 60.0, 0.4, Color(0.6, 0.8, 1.0), 3.0)
        world().announce("ASTRAL PROJECTION  x%.2f" % float(p["projectile_mult"]), false)
        Audio.sfx("lightning_bolt", -8.0, 0.6)

    func _end() -> void:
        if clone != null:
            world().fx.ring(clone.global_position, 2.0, 40.0, 0.3, Color(0.6, 0.8, 1.0), 2.0)
            clone.queue_free()
            clone = null
        player.proj_mults.erase("astral")
        player.sources.erase("astral")
        t = float(p["interval"]) * cd()

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
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, 300.0)
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

    func on_ready() -> void:
        t = float(p["interval"]) * 0.5

    func update(delta: float) -> void:
        if active_t > 0.0:
            active_t -= delta
            if active_t <= 0.0:
                _expire()
            return
        t -= delta
        if t <= 0.0:
            _roar()

    func _roar() -> void:
        var origin := player.global_position + Vector2(0, -12)
        active_t = float(p["duration"])
        player.armor = float(p["armor_hp"])
        player.add_buff("roar", active_t, {}, {"damage": 1.0 + float(p["boost_damage"]), "move_speed": 1.0 + float(p["boost_speed"])})
        world().fx.ring(origin, 6.0, 150.0, 0.5, Color(1.0, 0.7, 0.35), 5.0)
        world().fx.ring(origin, 3.0, 90.0, 0.35, Color(1, 1, 1), 3.0)
        for e in world().enemies.query_circle(origin, 120.0):
            world().enemies.fear(e, 0.8, origin)
        world().announce("BEAST'S ROAR", false)
        Audio.sfx("horn_swipe", -2.0, 0.5)
        Game.shake(6.0)

    func _expire() -> void:
        player.armor = 0.0
        player.remove_buff("roar")
        t = float(p["interval"]) * cd()

    func on_armor_break() -> void:
        # caveat from the design: broken armor stuns the minotaur
        active_t = 0.0
        player.remove_buff("roar")
        player.stun(float(p["break_stun"]))
        world().fx.ring(player.global_position + Vector2(0, -12), 6.0, 70.0, 0.4, Color(1.0, 0.4, 0.3), 4.0)
        world().announce("ARMOR BROKEN - STUNNED", true)
        Audio.sfx("player_hit", -2.0, 0.6)
        Game.shake(5.0)
        t = float(p["interval"]) * cd()

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
        var tgt: EnemyManager.E = world().enemies.nearest(player.global_position, float(p["swoop_range"]))
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
            var tgt: EnemyManager.E = world().enemies.nearest(pos, 280.0)
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
