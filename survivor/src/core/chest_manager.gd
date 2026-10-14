class_name ChestManager
extends Node2D
## Treasure chests dropped by elite enemies. Walk over one to open a 3-of-9 weapon draft.
## Pooled sprites (no physics bodies); magnet + collect feel matches GemManager.

const MAX := 12
const DROP_CHANCE := 1.0     # 100% while testing; tune down (e.g. 0.35) for shipping

class C:
    var sprite: Sprite2D
    var pos := Vector2.ZERO
    var vel := Vector2.ZERO
    var t := 0.0
    var spawn_t := 0.0

var world
var live: Array[C] = []
var _free: Array[C] = []
var _spark_t := 0.0


func setup(world_ref) -> void:
    world = world_ref
    z_index = -1
    var tex: Texture2D = DB.texture("res://art/pickups/treasure_chest.png")
    for i in MAX:
        var c := C.new()
        var sp := Sprite2D.new()
        sp.texture = tex
        sp.offset = Vector2(0, -10)
        sp.visible = false
        add_child(sp)
        c.sprite = sp
        _free.append(c)


func drop(pos: Vector2) -> void:
    if world != null and world.no_treasures:
        return
    if randf() > DROP_CHANCE:
        return
    if live.size() >= MAX or _free.is_empty():
        return
    var c: C = _free.pop_back()
    c.pos = pos
    c.vel = Vector2.from_angle(randf() * TAU) * randf_range(20.0, 50.0)
    c.t = randf() * TAU
    c.spawn_t = 0.0
    c.sprite.visible = true
    live.append(c)


func _release(idx: int) -> void:
    var c: C = live[idx]
    c.sprite.visible = false
    live.remove_at(idx)
    _free.append(c)


func _process(delta: float) -> void:
    if world == null or not world.sim_running:
        return
    delta = minf(delta, 1.0 / 30.0)
    var pl = world.player
    var pp: Vector2 = pl.global_position
    var pick: float = pl.stat("pickup_radius")
    _spark_t -= delta
    if _spark_t <= 0.0:
        _spark_t = 0.12
        if not live.is_empty():
            var sc: C = live[randi() % live.size()]
            world.fx.emit(sc.pos + Vector2(randf_range(-8.0, 8.0), -14.0), Vector2(0, -30.0), 0.4, 2.0, Color(1.0, 0.85, 0.4), 1, 1.0)
    var i: int = live.size() - 1
    while i >= 0:
        var c: C = live[i]
        c.t += delta
        c.spawn_t += delta
        var to_p: Vector2 = pp - c.pos
        var dist: float = to_p.length()
        if dist < pick and c.spawn_t > 0.12:
            var dir: Vector2 = to_p / maxf(dist, 0.001)
            c.vel = c.vel.lerp(dir * 320.0, minf(1.0, delta * 8.0))
        else:
            c.vel *= exp(-6.0 * delta)
        c.pos += c.vel * delta
        c.sprite.position = c.pos + Vector2(0, sin(c.t * 4.0) * 1.5)
        if c.pos.distance_squared_to(pp) < 17.0 * 17.0 and c.spawn_t > 0.1:
            var at: Vector2 = c.pos
            _release(i)
            world.on_chest_opened(at)
        i -= 1
