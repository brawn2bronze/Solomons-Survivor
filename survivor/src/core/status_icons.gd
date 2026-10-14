class_name StatusIcons
extends Node2D
## Overhead status icons (32px) for enemies + player. Pure view layer:
## source of truth stays E.stun/fear/infect_t/poison_t + Player.stunned/buffs + Saprotroph stacks.
## Priority per enemy: Stun > Fear > Infected > Poison. Slow has no icon yet (Webbed.png
## was reclaimed for the webs passive card). Nutrient shows on the player with its stack
## count while Saprotroph has stacks; rage shows while a damage buff is active.
## Pooled Sprite2Ds (no per-enemy UI nodes) to hold 60 FPS at 200+ enemies.

const POOL := 128

var world
var _pool: Array[Sprite2D] = []
var _tex_stun: Texture2D
var _tex_poison: Texture2D
var _tex_burn: Texture2D
var _tex_fear: Texture2D
var _tex_rage: Texture2D
var _tex_infected: Texture2D
var _tex_nutrient: Texture2D
var _count: Label
var _t := 0.0


func setup(world_ref) -> void:
	world = world_ref
	z_index = 20
	_tex_stun = DB.texture(AbilityArt.STATUS_STUN)
	_tex_poison = DB.texture(AbilityArt.STATUS_POISON)
	_tex_burn = DB.texture(AbilityArt.STATUS_BURN)
	_tex_fear = DB.texture(AbilityArt.STATUS_FEAR)
	_tex_rage = DB.texture(AbilityArt.STATUS_RAGE)
	_tex_infected = DB.texture(AbilityArt.STATUS_INFECTED)
	_tex_nutrient = DB.texture(AbilityArt.STATUS_NUTRIENT)
	for i in POOL:
		var sp := Sprite2D.new()
		sp.visible = false
		sp.centered = true
		add_child(sp)
		_pool.append(sp)
	_count = Label.new()
	_count.visible = false
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_count.add_theme_constant_override("outline_size", 4)
	add_child(_count)


func _process(delta: float) -> void:
	if world == null or world.player == null or world.enemies == null:
		return
	if not world.sim_running:
		return
	_t += delta
	var n := 0
	for e in world.enemies.active:
		var tex := _enemy_tex(e)
		if tex == null:
			continue
		if n >= POOL - 4:
			break
		var sp: Sprite2D = _pool[n]
		n += 1
		sp.texture = tex
		var lift: float = 26.0 + e.radius
		if e.is_elite:
			lift += 8.0
		if e.def.height == 1:
			lift += 9.0
		sp.position = e.pos + Vector2(0, -lift + sin(_t * 5.0 + float(e.uid)) * 2.0)
		var s := 1.0
		if e.is_elite:
			s = 1.25
		if e.stun > 0.0:
			s *= 1.0 + 0.12 * sin(_t * 10.0 + float(e.uid))
		sp.scale = Vector2(s, s)
		sp.modulate = Color.WHITE
		sp.visible = true
	# Player: stunned shows stun, else nutrient stacks, else damage-buff shows rage.
	var pl: Player = world.player
	if not pl.dead and n < POOL:
		var ptex := _player_tex(pl)
		if ptex != null:
			var psp: Sprite2D = _pool[n]
			n += 1
			psp.texture = ptex
			var plift := 58.0
			if pl.flying:
				plift += 14.0
			psp.position = pl.global_position + Vector2(0, -plift + sin(_t * 5.0) * 2.0)
			var pulse := 1.0 + 0.1 * sin(_t * 8.0)
			psp.scale = Vector2(pulse, pulse)
			psp.modulate = Color.WHITE
			psp.visible = true
			var stacks: int = _nutrient_stacks(pl)
			if stacks > 0 and ptex == _tex_nutrient:
				_count.visible = true
				_count.text = str(stacks)
				_count.position = psp.position + Vector2(10.0, -12.0)
			else:
				_count.visible = false
		else:
			_count.visible = false
	else:
		_count.visible = false
	for i in range(n, POOL):
		_pool[i].visible = false


func _enemy_tex(e) -> Texture2D:
	if e.stun > 0.0:
		return _tex_stun
	if e.fear > 0.0:
		return _tex_fear
	if e.infect_t > 0.0:
		return _tex_infected
	if e.burn_t > 0.0:
		return _tex_burn
	if e.poison_t > 0.0:
		return _tex_poison
	return null


func _player_tex(pl: Player) -> Texture2D:
	if pl.stunned > 0.0:
		return _tex_stun
	if _nutrient_stacks(pl) > 0:
		return _tex_nutrient
	if _has_damage_buff(pl):
		return _tex_rage
	return null


func _nutrient_stacks(pl: Player) -> int:
	if pl.passive != null and pl.passive.has_method("stack_count"):
		return int(pl.passive.stack_count())
	return 0


func _has_damage_buff(pl: Player) -> bool:
	for b in pl.buffs:
		var mul: Dictionary = b.get("mul", {})
		if float(mul.get("damage", 1.0)) > 1.01:
			return true
	var low: Dictionary = pl.def.flags.get("low_hp_scaling", {})
	if low.has("damage") and pl.max_hp > 0.0 and pl.hp / pl.max_hp < 0.5:
		return true
	return false
