class_name GemManager
extends Node2D
## Pooled XP gems. Idle gems bob; inside pickup radius they accelerate toward the player (magnet feel),
## and pitch-climbing pickup audio + sparkle plays on collection. Overflow merges into a nearby gem.

const MAX := 260
const MERGE_R := 70.0        # widened to match stride-sampled scan: overflow values still find a nearby merge target instead of fizzling

class G:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var value := 1
	var state := 0            # 0 idle, 1 magnetised
	var t := 0.0
	var spawn_t := 0.0

var world
var live: Array[G] = []
var _free: Array[G] = []
var _had_live := false        # tracks redraw state so empty frames skip queue_redraw


func setup(world_ref) -> void:
	world = world_ref
	z_index = -1
	for i in MAX:
		_free.append(G.new())


func drop(pos: Vector2, value: int, elite: bool) -> void:
	if world != null and world.no_gems:
		return
	if elite:
		# elites shower gems
		for i in 8:
			_spawn(pos + Vector2.from_angle(randf() * TAU) * randf_range(4.0, 26.0), maxi(1, int(value / 8.0)), Vector2.from_angle(randf() * TAU) * 120.0)
		attract_all()
		return
	_spawn(pos, value, Vector2.from_angle(randf() * TAU) * randf_range(20.0, 50.0))


func _spawn(pos: Vector2, value: int, kick: Vector2) -> void:
	if _free.is_empty():
		# Phase-2 perf: stride-sample the live list (<=64 checks) instead of a full
		# scan per overflow spawn. Merge-target choice is cosmetic - the value lands
		# in a nearby gem either way, totals unchanged.
		var best: G = null
		var bd := MERGE_R * MERGE_R * 9.0
		var step := maxi(1, live.size() / 64)
		var idx := 0
		while idx < live.size():
			var og: G = live[idx]
			var d := og.pos.distance_squared_to(pos)
			if d < bd:
				bd = d
				best = og
			idx += step
		if best != null:
			best.value += value
		return
	var g: G = _free.pop_back()
	g.pos = pos
	g.vel = kick
	g.value = value
	g.state = 0
	g.t = randf() * TAU
	g.spawn_t = 0.0
	live.append(g)


func attract_all() -> void:
	for g in live:
		g.state = 1


func _process(delta: float) -> void:
	if world == null or not world.sim_running:
		return
	delta = minf(delta, 1.0 / 30.0)
	var pl = world.player
	var pp: Vector2 = pl.global_position
	var pick: float = pl.stat("pickup_radius")
	var i := live.size() - 1
	var xp_sum := 0           # Phase-2 perf: batch one frame's pickups below
	var xp_n := 0
	var xp_pos := Vector2.ZERO
	var xp_top := 0
	while i >= 0:
		var g: G = live[i]
		g.t += delta
		g.spawn_t += delta
		var to_p := pp - g.pos
		var dist := to_p.length()
		var d2 := to_p.length_squared()
		if g.state == 0 and d2 < pick * pick and g.spawn_t > 0.12:
			g.state = 1
		if g.state == 1:
			var dir := to_p / maxf(dist, 0.001)
			# Steer velocity toward the player instead of pure add: kills orbital momentum.
			var pull := 900.0 + 700.0 * clampf(1.0 - dist / 300.0, 0.0, 1.0)
			var desired := dir * minf(560.0, 140.0 + pull * 0.28 + (300.0 - minf(dist, 300.0)) * 1.2)
			g.vel = g.vel.lerp(desired, minf(1.0, delta * 10.0))
			g.vel += dir * pull * delta
			# Arrival braking so gems don't whip past the player at close range.
			g.vel = g.vel.limit_length(clampf(dist * 9.0, 130.0, 560.0))
		else:
			g.vel *= exp(-6.0 * delta)
		g.pos += g.vel * delta
		var nd2 := g.pos.distance_squared_to(pp)
		if nd2 < 17.0 * 17.0 and g.spawn_t > 0.1:
			# Batched: totals and level-crossing order are identical to per-gem
			# collection (add_xp's while loop still emits once per level crossed).
			xp_sum += g.value
			xp_n += 1
			xp_pos = g.pos
			xp_top = maxi(xp_top, g.value)
			live.remove_at(i)
			_free.append(g)
		i -= 1
	if xp_n > 0:
		pl.add_xp(xp_sum)
		Audio.xp_pickup(xp_n)
		world.fx.emit(xp_pos, Vector2.ZERO, 0.14, 8.0, _color(xp_top), 1, 0.0)
	# Perf: an empty canvas is already clean after the final clear, so skip the
	# full redraw on frames with nothing live. Pixels are identical either way.
	if live.is_empty():
		if _had_live:
			_had_live = false
			queue_redraw()
	else:
		_had_live = true
		queue_redraw()


func _color(v: int) -> Color:
	if v >= 25:
		return Color(1.0, 0.45, 0.85)
	if v >= 10:
		return Color(1.0, 0.6, 0.25)
	if v >= 5:
		return Color(1.0, 0.9, 0.35)
	if v >= 2:
		return Color(0.4, 1.0, 0.55)
	return Color(0.4, 0.75, 1.0)


## Camera view in world space (+96px margin) so off-screen gems cost zero draw
## calls. Simulation, magnet and collection are untouched - culled gems still
## fly and collect exactly as before.
func _view_rect() -> Rect2:
	var cam = world.camera if world != null else null
	if cam == null or not (cam is Camera2D):
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var center: Vector2 = (cam as Camera2D).get_screen_center_position()
	var half: Vector2 = get_viewport_rect().size * 0.5 / (cam as Camera2D).zoom + Vector2(96, 96)
	return Rect2(center - half, half * 2.0)


func _draw() -> void:
	var view := _view_rect()
	for g in live:
		if not view.has_point(g.pos):
			continue
		var c := _color(g.value)
		var s: float = 3.4 + minf(4.0, log(float(g.value) + 1.0) * 1.3)
		var bob := sin(g.t * 4.0) * 1.2 if g.state == 0 else 0.0
		var p: Vector2 = g.pos + Vector2(0, bob)
		var pop := clampf(g.spawn_t * 8.0, 0.2, 1.0)
		s *= pop
		# Phase-3 perf: the alpha halo is the priciest primitive per gem (fill-rate).
		# Small gems keep diamond + highlight + outline; halo stays on value >= 5
		# where it is actually visible.
		if g.value >= 5:
			draw_circle(p, s * 1.9, Color(c.r, c.g, c.b, 0.16))
		var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.75, 0), p + Vector2(0, s), p + Vector2(-s * 0.75, 0)])
		draw_colored_polygon(pts, c)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.75, 0), p + Vector2(0, -s * 0.1)]), c.lightened(0.5))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), c.darkened(0.45), 1.0)
