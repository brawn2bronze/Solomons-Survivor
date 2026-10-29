class_name Player
extends Node2D
## The player character. Owns stats (base x upgrades x temporary buffs), movement, the generic dash used by
## several abilities, flight/knockdown (Harpy), armor (Minotaur roar), XP/levels, and applies level-up choices.

signal died
signal leveled_up
signal hurt

const RADIUS := 8.0
## Treasure-chest weapon pool (ported from the bare-bones-survivor export). Elites drop a chest,
## the chest offers 3 of these 9, re-picks level the weapon.
const CHEST_WEAPON_IDS: Array[String] = ["pickup_rifle", "pickup_shurikens", "pickup_blunderbuss", "pickup_aa12", "pickup_dynamite", "pickup_keg", "pickup_caltrops", "pickup_energy_food", "pickup_cloak"]
## Rare chest weapons: no unlock, drawn at a Luck-scaled capped % per slot (see World._roll_chest_tier).
const RARE_WEAPON_IDS: Array[String] = ["pickup_shamir_tooth"]
## Legendary chest weapons: silhouette-locked in the Archive behind a per-weapon prerequisite
## (see is_legendary_unlocked), drawn at an even smaller Luck-scaled cap once unlocked.
const LEGENDARY_WEAPON_IDS: Array[String] = ["pickup_shamir"]


## Late-run scaling whitelist: only these stats ride the clock on ranks 4-5.
## Defenses (max_hp, defense, regen) stay flat all run — you still dodge at 28:00.
const LATE_DAMAGE_STATS: Array[String] = ["damage", "area", "cooldown"]


## Per-weapon legendary gate. Shamir's prerequisite is TBD (stays locked);
## per-weapon custom prerequisite checks land in the match below.
static func is_legendary_unlocked(id: String) -> bool:
	match id:
		"pickup_shamir":
			return false
		_:
			return false

var world
var def: CharacterDef
var sprite: Sprite2D
var visual_scale := 1.0
var hp := 100.0
var max_hp := 100.0
var level := 1
var xp := 0
var xp_next := 8
var kills := 0
var base: Dictionary = {}
var mods: Dictionary = {}
var buffs: Array = []
var upgrade_levels: Dictionary = {}
var weapon: Ability
var passive: Ability
var chest_weapons: Array[Ability] = []
var rented_weapon_id := ""     # Black Market rental this run started with (HUD tags it)
var vel := Vector2.ZERO
var move_input := Vector2.ZERO  # player intent, excludes dash/knockback impulse
var facing_x := 1.0
var last_dir := Vector2.RIGHT
var invuln := 0.0
var stunned := 0.0
var untargetable := 0.0       # seconds; honored by contact, projectiles and enemy aim
var untargetable_t := 0.0
var dead := false
var flying := false
var can_fly := false
var grounded_t := 0.0
var armor := 0.0
var crit_chance := 0.0
var dmg_mitigation := 0.0
var proj_mults: Dictionary = {}
var reload_mult := 1.0            # reload-time divider: 2.0 = twice as fast (Jolly Roger banner)
var sources: Dictionary = {}
var aura_r := 0.0
var aura_col := Color.WHITE
var flash_r := 0.0
var flash_t := 0.0
var flash_col := Color.WHITE
var dash_t := 0.0
var dash_dir := Vector2.ZERO
var dash_speed := 0.0
var dash_opts: Dictionary = {}
var dash_hit: Dictionary = {}
var _anim := 0.0
var _dust_t := 0.0
var _ghost_t := 0.0
var _target: EnemyManager.E = null
var _target_t := 0.0
var _hurt_flash := 0.0
var _time := 0.0
var history: Array[Vector2] = []


static func xp_for(lv: int) -> int:
	return int(6.0 + lv * 4.5 + pow(float(lv), 1.6))


func setup(world_ref, character: CharacterDef) -> void:
	world = world_ref
	def = character
	base = def.base_stats.duplicate()
	can_fly = bool(def.flags.get("flying", false))
	flying = can_fly
	sprite = Sprite2D.new()
	sprite.texture = DB.texture(def.sprite)
	sprite.hframes = maxi(6, int(def.frames))
	sprite.offset = Vector2(0, -30)
	sprite.frame = 0
	add_child(sprite)
	refresh()
	hp = max_hp
	xp_next = xp_for(1)
	weapon = Ability.make(DB.weapons[def.weapon_id], self)
	passive = Ability.make(DB.passives[def.passive_id], self)
	for i in 24:
		history.append(global_position)


# ------------------------------------------------------------------ stats
func stat(stat_name: String) -> float:
	var v: float = float(base.get(stat_name, 0.0))
	var add := 0.0
	var mul := 1.0
	if mods.has(stat_name):
		add = float(mods[stat_name]["add"])
		mul = float(mods[stat_name]["mul"])
	for b in buffs:
		add += float(b["add"].get(stat_name, 0.0))
		mul *= float(b["mul"].get(stat_name, 1.0))
	v = (v + add) * mul
	var low: Dictionary = def.flags.get("low_hp_scaling", {})
	if low.has(stat_name) and max_hp > 0.0:
		v *= 1.0 + float(low[stat_name]) * (1.0 - clampf(hp / max_hp, 0.0, 1.0))
	if stat_name == "damage":
		var bestiary_dmg := Meta.get_total_seal_bonus("bestiary_dmg_bonus")
		v *= 1.0 + Meta.get_seal_bonus("enhanced_bindings") + Meta.get_total_seal_bonus("damage") + Meta.get_bestiary_bonus("damage") + bestiary_dmg * Meta.catalogued_count()
	elif stat_name == "move_speed":
		var bestiary_move := Meta.get_total_seal_bonus("bestiary_move_bonus")
		v *= 1.0 + Meta.get_total_seal_bonus("move_speed") + Meta.get_bestiary_bonus("move_speed") + bestiary_move * Meta.catalogued_count()
	elif stat_name == "max_hp":
		v *= 1.0 + Meta.get_total_seal_bonus("max_hp")
	elif stat_name == "crit_chance":
		return crit_chance
	if stat_name == "cooldown":
		v = maxf(0.60, v)
	return v


func refresh() -> void:
	crit_chance = clampf(Meta.get_total_seal_bonus("crit_chance"), 0.0, 0.75)
	dmg_mitigation = clampf(Meta.get_total_seal_bonus("dmg_mitigation"), 0.0, 0.75)
	var old := max_hp
	max_hp = stat("max_hp")
	if max_hp > old and old > 0.0 and not dead:
		hp += max_hp - old


func add_buff(id: String, seconds: float, add: Dictionary, mul: Dictionary) -> void:
	remove_buff(id)
	buffs.append({"id": id, "t": seconds, "add": add, "mul": mul})


func remove_buff(id: String) -> void:
	for i in range(buffs.size() - 1, -1, -1):
		if buffs[i]["id"] == id:
			buffs.remove_at(i)


func projectile_multiplier() -> float:
	var m := 1.0
	for k in proj_mults.keys():
		m *= float(proj_mults[k])
	return minf(m, 3.0)


func scaled_count(n: int) -> int:
	var f := float(n) * projectile_multiplier()
	var c := floori(f)
	if randf() < f - float(c):
		c += 1
	return maxi(1, c)


func fire_origin(i: int, dir: Vector2) -> Vector2:
	var origin := global_position + Vector2(0, -14) + dir * 10.0
	if i == 0:
		return origin
	var list: Array = []
	for k in sources.keys():
		list.append_array(sources[k])
	if list.is_empty():
		return origin
	var src: Node2D = list[(i - 1) % list.size()]
	var o := src.global_position + Vector2(0, -14) + dir * 10.0
	world.fx.muzzle(o, dir, Color(1.0, 0.85, 0.5))
	return o


func target() -> EnemyManager.E:
	return _target


func aim_dir() -> Vector2:
	if _target != null and _target.alive:
		return (_target.pos - global_position).normalized()
	return last_dir


# ------------------------------------------------------------------ frame update
func _process(delta: float) -> void:
	if world == null or not world.sim_running or dead:
		return
	delta = minf(delta, 1.0 / 30.0)
	_time += delta
	_tick_timers(delta)
	_target_t -= delta
	if _target_t <= 0.0:
		_target_t = 0.08
		_target = world.enemies.nearest(global_position, 520.0, {})
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if world.touch_controls != null:
		input = (input + world.touch_controls.move_vector).limit_length(1.0)
	if stunned > 0.0:
		input = Vector2.ZERO
	move_input = input
	if dash_t > 0.0:
		_update_dash(delta)
	else:
		var spd := stat("move_speed")
		vel = vel.move_toward(input * spd, 1500.0 * delta)
		global_position += vel * delta
	if input.length() > 0.1:
		last_dir = input.normalized()
		if absf(input.x) > 0.1:
			facing_x = signf(input.x)
	# regen
	var rg := stat("regen")
	if rg > 0.0 and hp < max_hp:
		hp = minf(max_hp, hp + rg * delta)
	if stunned <= 0.0:
		weapon.update(delta)
		weapon.update_evos(delta)
		for cw in chest_weapons:
			cw.update(delta)
			cw.tick_afters(delta)
	passive.update(delta)
	passive.update_evos(delta)
	history.push_back(global_position)
	history.pop_front()
	_animate(delta, input)
	queue_redraw()


func _tick_timers(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	stunned = maxf(0.0, stunned - delta)
	untargetable = maxf(0.0, untargetable - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	flash_t = maxf(0.0, flash_t - delta)
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i]["t"] = float(buffs[i]["t"]) - delta
		if buffs[i]["t"] <= 0.0:
			buffs.remove_at(i)
	if can_fly and not flying:
		grounded_t -= delta
		if grounded_t <= 0.0:
			flying = true
			world.fx.ring(global_position, 4.0, 40.0, 0.3, Color(0.9, 0.95, 1.0), 2.0)


func is_moving() -> bool:
	return vel.length() > 12.0 or dash_t > 0.0


## Intent-based movement: true while the player is steering or dashing, even if
## the body was just nudged by a swing impulse.
func is_walking() -> bool:
	return move_input.length() > 0.1 or dash_t > 0.0


## Fraction of top speed currently travelled (0..~1.4), for speed-scaled evolutions.
func speed_ratio() -> float:
	return clampf(vel.length() / maxf(stat("move_speed"), 1.0), 0.0, 1.4)

func _animate(delta: float, _input: Vector2) -> void:
	var moving := is_moving()
	_anim += delta
	var has_fly := sprite.hframes >= 8
	if flying and has_fly:
		# Harpy airborne: frames 6-7 flap loop for BOTH idle and move,
		# so ground (0-1 / 2-5) vs air (6-7) always reads. Faster flap when moving.
		sprite.frame = 6 + int(_anim * (9.0 if moving else 4.5)) % 2
	elif moving:
		sprite.frame = 2 + int(_anim * 11.0) % 4
		_dust_t -= delta
		if _dust_t <= 0.0 and not flying and dash_t <= 0.0:
			_dust_t = 0.16
			world.fx.dust(global_position + Vector2(-facing_x * 4.0, 0))
	else:
		sprite.frame = int(_anim * 2.5) % 2
	sprite.flip_h = facing_x < 0.0
	var bob := 0.0
	if flying:
		bob = -14.0 + sin(_time * 5.0) * 3.0
	sprite.position.y = lerpf(sprite.position.y, bob, minf(1.0, delta * 12.0))
	var sq := 1.0 + (sin(_anim * 22.0) * 0.045 if moving else sin(_anim * 5.0) * 0.02)
	sprite.scale = Vector2(1.0 / sq, sq) * visual_scale
	if _hurt_flash > 0.0:
		sprite.modulate = Color(1.0, 0.35, 0.35)
	elif invuln > 0.0 and dash_t <= 0.0:
		sprite.modulate = Color(1, 1, 1, 0.45 if int(_time * 24.0) % 2 == 0 else 0.9)
	elif stunned > 0.0:
		sprite.modulate = Color(0.7, 0.7, 0.85)
	elif armor > 0.0:
		sprite.modulate = Color(1.0, 0.92, 0.75)
	else:
		sprite.modulate = Color.WHITE


func _draw() -> void:
	if aura_r > 0.0:
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		draw_circle(Vector2(0, -8), aura_r, Color(aura_col.r, aura_col.g, aura_col.b, 0.07 + 0.03 * pulse))
		draw_arc(Vector2(0, -8), aura_r, 0.0, TAU, 48, Color(aura_col.r, aura_col.g, aura_col.b, 0.35 + 0.2 * pulse), 1.5)
	if flash_t > 0.0:
		var k := 1.0 - flash_t / 0.4
		draw_circle(Vector2(0, -8), flash_r * (0.3 + 0.7 * k), Color(flash_col.r, flash_col.g, flash_col.b, 0.35 * (1.0 - k)))
		draw_arc(Vector2(0, -8), flash_r * k, 0.0, TAU, 48, Color(1, 1, 1, 0.8 * (1.0 - k)), 2.5)
	if armor > 0.0:
		draw_arc(Vector2(0, -14), 21.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.4, 0.75), 2.0)
		draw_arc(Vector2(0, -14), 24.0, _time * 3.0, _time * 3.0 + 2.0, 12, Color(1.0, 0.95, 0.7, 0.5), 1.5)
	if passive != null:
		passive.draw_overlay(self)
	if weapon != null:
		weapon.draw_overlay(self)
	for cw in chest_weapons:
		cw.draw_overlay(self)


# ------------------------------------------------------------------ dash (Goose charge, Minotaur bull rush, Harpy swoop)
func start_dash(dir: Vector2, dist: float, speed: float, opts: Dictionary = {}) -> void:
	dash_dir = dir.normalized()
	dash_speed = speed
	dash_t = dist / speed
	dash_opts = opts
	dash_hit.clear()
	if opts.get("invuln", false):
		invuln = maxf(invuln, dash_t + 0.12)
	if absf(dash_dir.x) > 0.1:
		facing_x = signf(dash_dir.x)


# ------------------------------------------------------------------ blink (primitive 8)
## Teleport to `pos` (Vanish, Kawarimi, Blink Strike, Astral Swap). Optionally
## set an invulnerability window. Leaves a ghost tell at both ends.
func blink_to(pos: Vector2, invuln_time: float = 0.0) -> void:
	if dead:
		return
	var from := global_position
	global_position = pos
	vel = Vector2.ZERO
	if invuln_time > 0.0:
		invuln = maxf(invuln, invuln_time)
	var col: Color = def.color
	world.fx.emit(from + Vector2(0, -12), Vector2.ZERO, 0.28, 9.0, Color(col.r, col.g, col.b, 0.5), 1, 0.0)
	world.fx.emit(pos + Vector2(0, -12), Vector2.ZERO, 0.28, 9.0, Color(col.r, col.g, col.b, 0.6), 1, 0.0)


## Vanish window: enemies stop firing at and cannot touch the player until `seconds` elapse.
func go_untargetable(seconds: float) -> void:
	untargetable = maxf(untargetable, seconds)


func _update_dash(delta: float) -> void:
	dash_t -= delta
	global_position += dash_dir * dash_speed * delta
	vel = dash_dir * dash_speed * 0.4
	var col: Color = dash_opts.get("color", def.color)
	_ghost_t -= delta
	if _ghost_t <= 0.0:
		_ghost_t = 0.02
		world.fx.emit(global_position + Vector2(0, -12), Vector2.ZERO, 0.28, 9.0, Color(col.r, col.g, col.b, 0.5), 1, 0.0)
	var fr: float = float(dash_opts.get("fear_radius", 0.0))
	if fr > 0.0:
		for e in world.enemies.query_circle(global_position, fr):
			if not dash_hit.has(-e.uid):
				dash_hit[-e.uid] = true
				world.enemies.fear(e, float(dash_opts.get("fear_time", 2.0)), global_position)
	var dmg_amt: float = float(dash_opts.get("damage", 0.0))
	if dmg_amt > 0.0:
		for e in world.enemies.query_circle(global_position, float(dash_opts.get("hit_radius", 18.0))):
			if not dash_hit.has(e.uid):
				dash_hit[e.uid] = true
				world.enemies.damage(e, dmg_amt, dash_dir, 160.0, col)
				if dash_opts.get("impale", false):
					world.enemies.stun(e, 0.7)
				var hit_cb: Callable = dash_opts.get("hit_cb", Callable())
				if hit_cb.is_valid():
					hit_cb.call(e)
				Game.shake(3.0)
				Game.hit_stop(0.04, 0.05)
	if dash_t <= 0.0:
		vel = dash_dir * 90.0
		var end_cb: Callable = dash_opts.get("end_cb", Callable())
		if end_cb.is_valid():
			dash_opts.erase("end_cb")
			end_cb.call()


func impulse(v: Vector2) -> void:
	vel += v


func aura_flash(radius: float, color: Color) -> void:
	flash_r = radius
	flash_col = color
	flash_t = 0.4


# ------------------------------------------------------------------ damage / death
func take_damage(amount: float, hits_air: bool = false, source: String = "", source_pos: Vector2 = Vector2.INF) -> void:
	if dead or invuln > 0.0 or untargetable > 0.0:
		return
	if Game.godmode:
		return
	if flying:
		if not hits_air:
			return
		_knock_from_flight()
	amount = maxf(1.0, amount - stat("defense"))
	var taken_mult := 1.0
	if weapon != null:
		taken_mult *= weapon.incoming_damage_mult(amount, source_pos, source)
	if passive != null:
		taken_mult *= passive.incoming_damage_mult(amount, source_pos, source)
	for cw in chest_weapons:
		taken_mult *= cw.incoming_damage_mult(amount, source_pos, source)
	amount = maxf(1.0, amount * (1.0 - dmg_mitigation) * taken_mult)
	if armor > 0.0:
		armor -= amount
		if passive != null:
			passive.on_armor_hit(amount, source_pos)
		world.fx.hit_sparks(global_position + Vector2(0, -12), Vector2.ZERO, Color(1.0, 0.85, 0.4), 6)
		Audio.sfx("horn_swipe", -8.0, 1.6)
		invuln = 0.18
		if armor <= 0.0:
			armor = 0.0
			passive.on_armor_break()
		weapon.hook("on_hurt", {"amount": amount})
		passive.hook("on_hurt", {"amount": amount})
		return
	if passive != null and passive.absorb_hit(amount):
		return
	if weapon != null and weapon.absorb_hit(amount):
		return
	hp -= amount
	invuln = 0.55
	_hurt_flash = 0.12
	hurt.emit()
	if world != null:
		world.on_player_hurt(amount)
	weapon.hook("on_hurt", {"amount": amount})
	passive.hook("on_hurt", {"amount": amount})
	Audio.sfx("player_hit", -2.0)
	Game.shake(4.5)
	Game.hit_stop(0.05, 0.05)
	world.fx.hit_sparks(global_position + Vector2(0, -12), Vector2.ZERO, Color(1.0, 0.3, 0.3), 8)
	world.hurt_flash()
	if hp <= 0.0:
		hp = 0.0
		_die()


func _knock_from_flight() -> void:
	flying = false
	grounded_t = float(def.flags.get("knockdown_seconds", 5.0))
	world.fx.ring(global_position, 4.0, 46.0, 0.35, Color(1.0, 0.6, 0.4), 3.0, FxManager.PRIO_IMPORTANT)
	world.announce("KNOCKED FROM FLIGHT", true)


func stun(seconds: float) -> void:
	if stunned <= 0.0 and not dead and world != null:
		world.fx.float_text(global_position + Vector2(0, -38), "STUNNED", Color(0.75, 0.85, 1.0), 16, 1.0, 14.0)
	stunned = maxf(stunned, seconds)
	vel = Vector2.ZERO


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func _die() -> void:
	dead = true
	sprite.visible = false
	Audio.sfx("player_death")
	world.fx.death_burst(global_position, DB.enemies["goblin"], true)
	died.emit()


# ------------------------------------------------------------------ progression
func add_xp(v: int) -> void:
	if world != null and world.no_levels:
		return
	var xp_gain_bonus := Meta.get_total_seal_bonus("xp_gain")
	if xp_gain_bonus != 0.0:
		v = maxi(1, int(float(v) * (1.0 + xp_gain_bonus)))
	xp += v
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_for(level)
		leveled_up.emit()


## Rank-4+ scaling for damage-side stats: ranks 1-3 are flat, ranks 4-5 grow up
## to +60% by 30:00 so late picks stay meaningful next to Lv-12+ kit weapons.
func _late_scaled_value(up: UpgradeDef) -> float:
	var v := up.value
	if not LATE_DAMAGE_STATS.has(up.stat):
		return v
	if int(upgrade_levels.get(up.id, 0)) < 3:
		return v
	var t := 0.0
	if world != null:
		t = float(world.run_time)
	var f := 1.0 + minf(t, 1800.0) / 1800.0 * 0.15
	if up.op == "mul":
		if v >= 1.0:
			return 1.0 + (v - 1.0) * f
		return 1.0 - (1.0 - v) * f
	return v * f


func apply_chest_weapon(id: String) -> String:
	for cw in chest_weapons:
		if cw.def.id == id:
			if cw.can_level():
				cw.level_up()
				return "%s up!  Lv %d" % [cw.def.display_name, cw.level]
			return "%s already maxed" % cw.def.display_name
	var res = DB.weapons.get(id)
	if res == null:
		return "Unknown weapon"
	var ab: Ability = Ability.make(res, self)
	if ab == null:
		return "Unknown weapon"
	ab.set_mods(Meta.mod_items_for(id))   # owned Black Market upgrades for this weapon
	chest_weapons.append(ab)
	refresh()
	return "Found %s!" % res.display_name


## Cross-ability evo event: whenever a weapon or passive fires its main action,
## call this to run hook("on_player_cast", ctx) on the other ability.
func broadcast_cast(src: String, ctx: Dictionary) -> void:
	var other: Ability = weapon if src == "passive" else passive
	if other != null:
		other.hook("on_player_cast", ctx)

func apply_choice(ch: Dictionary) -> void:
	match String(ch["type"]):
		"weapon":
			if ch.has("evo"):
				weapon.apply_evo(int(ch.get("tier", 1)), int(ch.get("evo", 0)))
			elif int(ch.get("branch", -1)) >= 0:
				weapon.pick_branch(int(ch["branch"]))
			else:
				weapon.level_up()
		"passive":
			if ch.has("evo"):
				passive.apply_evo(int(ch.get("tier", 1)), int(ch.get("evo", 0)))
			elif int(ch.get("branch", -1)) >= 0:
				passive.pick_branch(int(ch["branch"]))
			else:
				passive.level_up()
		"stat":
			var up: UpgradeDef = DB.upgrades[String(ch["id"])]
			var v := _late_scaled_value(up)
			upgrade_levels[up.id] = int(upgrade_levels.get(up.id, 0)) + 1
			if not mods.has(up.stat):
				mods[up.stat] = {"add": 0.0, "mul": 1.0}
			if up.op == "mul":
				mods[up.stat]["mul"] = float(mods[up.stat]["mul"]) * v
			else:
				mods[up.stat]["add"] = float(mods[up.stat]["add"]) + v
		"heal":
			heal(max_hp * 0.35)
	refresh()
	Audio.sfx("upgrade_selected")
