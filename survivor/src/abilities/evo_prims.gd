class_name EvoPrims
extends RefCounted

## Shared evolution primitives (Phase 0 + Cowboy slice).
## segment_hit: line-segment sweep from `from` to `to`, damaging enemies within `radius`.
## Returns the number of enemies hit. Used by Cowboy tier evolutions (fan arcs, whip cracks).

static func segment_hit(world, from: Vector2, to: Vector2, radius: float, damage: float, knock_dir: Vector2 = Vector2.ZERO, knock_force: float = 0.0, src: String = "", slow_mult: float = 1.0, slow_time: float = 0.0, far_frac: float = 0.0, far_mult: float = 1.0) -> int:
    if world == null or world.enemies == null:
        return 0
    var seg := to - from
    var seg_len := seg.length()
    if seg_len < 0.01:
        return 0
    var seg_dir := seg / seg_len
    var hit := 0
    # Broad-phase: circle centered on segment midpoint with radius = seg_len/2 + radius.
    var mid := (from + to) * 0.5
    var broad_r := seg_len * 0.5 + radius + 24.0
    for e in world.enemies.query_circle(mid, broad_r):
        if not e.alive:
            continue
        # Project enemy center onto segment, clamp to [0, seg_len].
        var to_e: Vector2 = e.pos - from
        var t := clampf(to_e.dot(seg_dir), 0.0, seg_len)
        var closest := from + seg_dir * t
        if e.pos.distance_to(closest) <= radius + e.radius:
            var dmg := damage
            if far_frac > 0.0 and t >= seg_len * (1.0 - far_frac):
                dmg *= far_mult
            world.enemies.damage(e, dmg, knock_dir if knock_dir != Vector2.ZERO else seg_dir, knock_force, Color(1.0, 0.9, 0.6), src)
            if slow_time > 0.0:
                world.enemies.slow(e, slow_mult, slow_time)
            hit += 1
    return hit


## Same sweep as segment_hit, but each enemy can only be hit once per `cd` seconds.
## `gate` maps enemy uid -> next allowed hit time (absolute clock) and is mutated in place.
## Used by multi-hit evolutions (chain sweep, phantom lane) where the 0.10s per-src gate is too fast.
static func gated_segment_hit(world, from: Vector2, to: Vector2, radius: float, damage: float, gate: Dictionary, now: float, cd: float, knock_dir: Vector2 = Vector2.ZERO, knock_force: float = 0.0, src: String = "") -> int:
    if world == null or world.enemies == null:
        return 0
    var seg := to - from
    var seg_len := seg.length()
    if seg_len < 0.01:
        return 0
    var seg_dir := seg / seg_len
    var hit := 0
    var mid := (from + to) * 0.5
    var broad_r := seg_len * 0.5 + radius + 24.0
    for e in world.enemies.query_circle(mid, broad_r):
        if not e.alive:
            continue
        var next_ok := float(gate.get(e.uid, -1.0))
        if now < next_ok:
            continue
        var to_e: Vector2 = e.pos - from
        var t := clampf(to_e.dot(seg_dir), 0.0, seg_len)
        var closest := from + seg_dir * t
        if e.pos.distance_to(closest) <= radius + e.radius:
            gate[e.uid] = now + cd
            world.enemies.damage(e, damage, knock_dir if knock_dir != Vector2.ZERO else seg_dir, knock_force, Color(1.0, 0.9, 0.6), src)
            hit += 1
    return hit


## Densest enemy cluster near `origin`: returns the enemy position with the most
## neighbours within `sample_r` (searched within `max_r` of the origin).
## `avoid` is a list of Vector2 points that must not be chosen as the cluster center.
static func densest_cluster(world, origin: Vector2, max_r: float, sample_r: float, avoid: Array = []) -> Vector2:
    if world == null or world.enemies == null:
        return origin
    var list: Array = world.enemies.query_circle(origin, max_r)
    var best := origin
    var best_count := -1
    for e in list:
        if not e.alive:
            continue
        var cand: Vector2 = e.pos
        var skip := false
        for a in avoid:
            var av: Vector2 = a
            if cand.distance_to(av) < 48.0:
                skip = true
                break
        if skip:
            continue
        var count := 0
        for o in list:
            if o.alive and o.pos.distance_to(cand) <= sample_r:
                count += 1
        if count > best_count:
            best_count = count
            best = cand
    return best


## Ground-zone helper: returns enemies currently inside a circle, ground-only (no flyers).
static func zone_enemies(world, center: Vector2, radius: float) -> Array:
    if world == null or world.enemies == null:
        return []
    return world.enemies.query_ground_circle(center, radius)


## True if the player is currently moving (used by meter-based evolutions).
static func is_moving(player) -> bool:
    if player == null:
        return false
    if player.has_method("is_moving"):
        return player.is_moving()
    return false


## Primitive 6b: intercept hostiles along a line segment (snap_parry). Samples the
## segment and defers to ProjectileManager.intercept; removed shots can't be double-counted.
static func intercept_segment(world, from: Vector2, to: Vector2, radius: float, mode: String = "destroy") -> int:
    if world == null or world.projectiles == null:
        return 0
    var seg := to - from
    var seg_len := seg.length()
    if seg_len < 0.01:
        return world.projectiles.intercept(from, radius, mode)
    var steps := maxi(2, int(seg_len / maxf(radius * 0.5, 8.0)))
    var total := 0
    for i in steps + 1:
        var pos := from + seg * (float(i) / float(steps))
        total += world.projectiles.intercept(pos, radius, mode)
    return total
