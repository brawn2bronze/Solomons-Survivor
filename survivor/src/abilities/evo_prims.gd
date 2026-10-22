class_name EvoPrims
extends RefCounted

## Shared evolution primitives (Phase 0 + Cowboy slice).
## segment_hit: line-segment sweep from `from` to `to`, damaging enemies within `radius`.
## Returns the number of enemies hit. Used by Cowboy tier evolutions (fan arcs, whip cracks).

static func segment_hit(world, from: Vector2, to: Vector2, radius: float, damage: float, knock_dir: Vector2 = Vector2.ZERO, knock_force: float = 0.0, src: String = "") -> int:
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
            world.enemies.damage(e, damage, knock_dir if knock_dir != Vector2.ZERO else seg_dir, knock_force, Color(1.0, 0.9, 0.6), src)
            hit += 1
    return hit


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
