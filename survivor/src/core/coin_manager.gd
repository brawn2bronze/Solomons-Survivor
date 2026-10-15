class_name CoinManager
extends Node2D
## Pooled coin pickups (the Seal Fragment currency; code name Coin* frozen until A6). Drop rules live here: every kill rolls a luck-scaled chance for one
## coin; elites always shower coins and a boss (EnemyDef.coin_drop) drops a jackpot. Pickup feel clones GemManager:
## bob, magnet, sparkle, pitch-climbing audio, and overflow merges into a nearby coin. Collected coins go straight to
## the persistent balance (Meta) and the per-run tally (world.run_coins, shown on the HUD and game over).

const MAX := 120
const MERGE_R := 72.0        # widened to match stride-sampled scan: overflow values still find a nearby merge target instead of fizzling
const BASE_CHANCE := 0.04       ## per-kill chance of a coin at 0 luck
const LUCK_CHANCE := 0.16       ## extra chance per point of luck (Fortune is +0.1 luck per level -> +1.6% per level)
const LUCK_BONUS := 0.30        ## luck x this = chance the dropped coin is worth 2
const ELITE_PIECES := 6         ## coins in an elite's shower when its def sets no coin_drop
const ELITE_VALUE := 2          ## value of each elite-shower coin
const JACKPOT_PIECES := 16      ## a def.coin_drop total is split across this many coins
const COLLECT_R := 17.0
const SPARK_COLOR := Color(0.7, 0.4, 1.0)

class C:
    var pos := Vector2.ZERO
    var vel := Vector2.ZERO
    var value := 1
    var state := 0            # 0 idle, 1 magnetised
    var t := 0.0
    var spawn_t := 0.0

var world
var _seal_tex: Texture2D
var live: Array[C] = []
var _free: Array[C] = []
var _had_live := false        # tracks redraw state so empty frames skip queue_redraw


func setup(world_ref) -> void:
    world = world_ref
    z_index = -1
    _seal_tex = DB.texture(CoinIcon.STRIP)
    for i in MAX:
        _free.append(C.new())


## Called from EnemyManager._kill for every death.
func on_enemy_killed(e) -> void:
    if world == null or world.no_gems:
        return
    var def: EnemyDef = e.def
    if def.coin_drop > 0:
        var each: int = maxi(1, ceili(float(def.coin_drop) / float(JACKPOT_PIECES)))
        _shower(e.pos, JACKPOT_PIECES, each)
        attract_all()
        return
    if def.is_elite:
        _shower(e.pos, ELITE_PIECES, ELITE_VALUE)
        attract_all()
        return
    var luck: float = maxf(0.0, world.player.stat("luck"))
    var drop_chance: float = BASE_CHANCE + luck * LUCK_CHANCE + Meta.get_seal_bonus("demons_folly")
    if randf() >= drop_chance:
        return
    var value := 1
    if randf() < luck * LUCK_BONUS:
        value = 2
    _spawn(e.pos, value, Vector2.from_angle(randf() * TAU) * randf_range(20.0, 50.0))


func _shower(pos: Vector2, pieces: int, value: int) -> void:
    for i in pieces:
        var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(4.0, 28.0)
        _spawn(pos + offset, value, Vector2.from_angle(randf() * TAU) * randf_range(60.0, 140.0))


func _spawn(pos: Vector2, value: int, kick: Vector2) -> void:
    if _free.is_empty():
        # Phase-2 perf: stride-sample the live list (<=64 checks) instead of a full
        # scan per overflow spawn. Merge-target choice is cosmetic - the value lands
        # in a nearby coin either way, totals unchanged.
        var best: C = null
        var bd: float = MERGE_R * MERGE_R * 9.0
        var step: int = maxi(1, live.size() / 64)
        var idx := 0
        while idx < live.size():
            var oc: C = live[idx]
            var d: float = oc.pos.distance_squared_to(pos)
            if d < bd:
                bd = d
                best = oc
            idx += step
        if best != null:
            best.value += value
        return
    var c: C = _free.pop_back()
    c.pos = pos
    c.vel = kick
    c.value = value
    c.state = 0
    c.t = randf() * TAU
    c.spawn_t = 0.0
    live.append(c)


func attract_all() -> void:
    for c in live:
        c.state = 1


## Dev sandbox: drop every coin on the field (World.set_no_gems).
func clear() -> void:
    for c in live:
        _free.append(c)
    live.clear()
    queue_redraw()


func _process(delta: float) -> void:
    if world == null or not world.sim_running:
        return
    delta = minf(delta, 1.0 / 30.0)
    var pl: Player = world.player
    var pp: Vector2 = pl.global_position
    var pick: float = pl.stat("pickup_radius")
    var i: int = live.size() - 1
    var coin_sum := 0         # Phase-2 perf: batch one frame's pickups below
    var coin_n := 0
    var coin_pos := Vector2.ZERO
    while i >= 0:
        var c: C = live[i]
        c.t += delta
        c.spawn_t += delta
        var to_p: Vector2 = pp - c.pos
        var dist: float = to_p.length()
        if c.state == 0 and to_p.length_squared() < pick * pick and c.spawn_t > 0.12:
            c.state = 1
        if c.state == 1:
            var dir: Vector2 = to_p / maxf(dist, 0.001)
            var pull: float = 900.0 + 700.0 * clampf(1.0 - dist / 300.0, 0.0, 1.0)
            var desired: Vector2 = dir * minf(560.0, 140.0 + pull * 0.28 + (300.0 - minf(dist, 300.0)) * 1.2)
            c.vel = c.vel.lerp(desired, minf(1.0, delta * 10.0))
            c.vel += dir * pull * delta
            c.vel = c.vel.limit_length(clampf(dist * 9.0, 130.0, 560.0))
        else:
            c.vel *= exp(-6.0 * delta)
        c.pos += c.vel * delta
        if c.pos.distance_squared_to(pp) < COLLECT_R * COLLECT_R and c.spawn_t > 0.1:
            # Batched: Meta balance, run tally and signal fire once with the same total.
            coin_sum += c.value
            coin_n += 1
            coin_pos = c.pos
            live.remove_at(i)
            _free.append(c)
        i -= 1
    if coin_n > 0:
        Meta.add_coins(coin_sum)
        world.run_coins += coin_sum
        Audio.coin_pickup(coin_n)
        world.fx.emit(coin_pos, Vector2(0, -26.0), 0.22, 3.0, SPARK_COLOR, 1, 2.0)
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
    if v >= 10:
        return Color(1.0, 0.3, 0.55)
    if v >= 4:
        return Color(0.85, 0.3, 1.0)
    if v >= 2:
        return Color(0.65, 0.35, 0.95)
    return Color(0.5, 0.3, 0.8)


## Camera view in world space (+96px margin) so off-screen coins cost zero draw
## calls. Simulation, magnet and collection are untouched - culled coins still
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
    for c in live:
        if not view.has_point(c.pos):
            continue
        var ess: Color = _color(c.value)
        var r: float = 3.2 + minf(3.6, float(c.value) * 0.45)
        var bob: float = sin(c.t * 4.0) * 1.2 if c.state == 0 else 0.0
        var p: Vector2 = c.pos + Vector2(0, bob)
        r *= clampf(c.spawn_t * 8.0, 0.2, 1.0)
        var turn: float = maxf(0.28, absf(cos(c.t * 5.0 + c.pos.x * 0.05)))     # the shard spins edge-on
        # Phase-3 perf: the alpha halo is the priciest primitive per coin (fill-rate).
        # Plain shards keep body + shine; halo stays on value >= 2 where it reads.
        if c.value >= 2:
            draw_circle(p, r * 2.0, Color(ess.r, ess.g, ess.b, 0.14))
        draw_set_transform(p, 0.0, Vector2(turn, 1.0))
        if _seal_tex != null:
            # Seal strip, static frame 0 in-world (animated only in UI CoinIcon).
            var cw: float = _seal_tex.get_size().x / float(CoinIcon.FRAMES)
            var ch: float = _seal_tex.get_size().y
            var hh: float = r * ch / cw
            draw_texture_rect_region(_seal_tex, Rect2(Vector2(-r, -hh), Vector2(r * 2.0, hh * 2.0)), Rect2(Vector2.ZERO, Vector2(cw, ch)), ess)
        else:
            draw_circle(Vector2.ZERO, r, ess.darkened(0.4))
            draw_circle(Vector2.ZERO, r * 0.78, ess)
            draw_circle(Vector2(-r * 0.22, -r * 0.22), r * 0.3, ess.lightened(0.55))
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
