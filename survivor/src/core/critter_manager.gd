class_name CritterManager
extends Node
## In-world friendly critters (currently: frogs). A frog hops around the arena; touching
## it makes the player eat it - a comic fart plus a flat heal - then it despawns. Spawns
## are rare and capped so the arena never floods. Sprites live on the y-sorted Actors node.

const SPRITE := "res://art/pickups/frog.png"
const FRAMES := 8
const FPS := 8.0
const MAX_ALIVE := 3
const HEAL := 15.0
const SPAWN_EVERY_MIN := 25.0
const SPAWN_EVERY_MAX := 50.0
const SPAWN_R_MIN := 350.0
const SPAWN_R_MAX := 560.0
const FIRST_SPAWN_MIN := 6.0
const FIRST_SPAWN_MAX := 14.0
const EAT_RADIUS := 15.0
const CULL_DIST := 1000.0


class Frog:
	var sprite: Sprite2D
	var pos := Vector2.ZERO
	var t := 0.0
	var anim := 0.0
	var hop_t := 0.0
	var hop_dir := Vector2.RIGHT
	var hop_z := 0.0
	var alive := false


var world
var player
var actors: Node2D
var live: Array[Frog] = []
var _free: Array[Frog] = []
var _spawn_t := 0.0


func setup(world_ref, actors_node: Node2D) -> void:
	world = world_ref
	player = world.player
	actors = actors_node
	_spawn_t = randf_range(FIRST_SPAWN_MIN, FIRST_SPAWN_MAX)
	for i in MAX_ALIVE:
		var f := Frog.new()
		var sp := Sprite2D.new()
		sp.texture = DB.texture(SPRITE)
		sp.hframes = FRAMES
		sp.offset = Vector2(0, -6)
		sp.visible = false
		actors.add_child(sp)
		f.sprite = sp
		_free.append(f)


func _process(delta: float) -> void:
	if world == null or not world.sim_running:
		return
	delta = minf(delta, 1.0 / 30.0)
	var pp: Vector2 = player.global_position
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(SPAWN_EVERY_MIN, SPAWN_EVERY_MAX)
		if live.size() < MAX_ALIVE:
			_spawn_around(pp)
	var i := live.size() - 1
	while i >= 0:
		var f: Frog = live[i]
		_update(f, delta, pp)
		if not f.alive:
			live.remove_at(i)
		i -= 1


func _spawn_around(pp: Vector2) -> void:
	if _free.is_empty():
		return
	var ang := randf() * TAU
	var pos: Vector2 = pp + Vector2.from_angle(ang) * randf_range(SPAWN_R_MIN, SPAWN_R_MAX)
	var f: Frog = _free.pop_back()
	f.pos = pos
	f.t = randf() * TAU
	f.anim = randf() * float(FRAMES)
	f.hop_t = randf_range(0.2, 0.9)
	f.hop_dir = Vector2.from_angle(randf() * TAU)
	f.hop_z = 0.0
	f.alive = true
	var sp := f.sprite
	sp.position = pos
	sp.frame = int(f.anim) % FRAMES
	sp.flip_h = f.hop_dir.x > 0.0
	sp.visible = true
	live.append(f)


func _update(f: Frog, delta: float, pp: Vector2) -> void:
	f.t += delta
	if f.pos.distance_squared_to(pp) > CULL_DIST * CULL_DIST:
		_despawn(f)
		return
	if f.pos.distance_squared_to(pp) < EAT_RADIUS * EAT_RADIUS:
		_eat(f)
		return
	# hop cycle: sit for a beat, then arc forward and land.
	f.hop_t -= delta
	if f.hop_t <= 0.0:
		f.hop_dir = Vector2.from_angle(randf() * TAU)
		f.hop_t = randf_range(0.5, 1.3)
		f.hop_z = 1.0
	var lift := 0.0
	if f.hop_z > 0.0:
		f.hop_z = maxf(0.0, f.hop_z - delta * 1.8)
		f.pos += f.hop_dir * 62.0 * delta
		lift = sin((1.0 - f.hop_z) * PI) * 5.0
	var sp := f.sprite
	sp.position = f.pos + Vector2(0, -lift)
	f.anim += delta * FPS
	sp.frame = int(f.anim) % FRAMES
	if absf(f.hop_dir.x) > 0.05:
		sp.flip_h = f.hop_dir.x > 0.0


func _despawn(f: Frog) -> void:
	f.alive = false
	f.sprite.visible = false
	_free.append(f)


## Eaten: comic fart, flat heal, a puff of green, gone.
func _eat(f: Frog) -> void:
	_despawn(f)
	Audio.sfx("frog_fart", -4.0, randf_range(0.94, 1.08), 0.0)
	if player != null and not player.dead:
		player.heal(HEAL)
	if world != null and world.fx != null:
		world.fx.emit(f.pos + Vector2(0, -4), Vector2.ZERO, 0.16, 10.0, Color(0.6, 0.95, 0.4, 0.85), 1, 0.0)
		for i in 6:
			world.fx.emit(f.pos + Vector2(0, -4), Vector2.from_angle(randf() * TAU) * randf_range(30.0, 90.0), randf_range(0.25, 0.45), randf_range(1.5, 2.6), Color(0.55, 0.85, 0.35), 0, 3.0, 0.0, false)
