class_name World
extends Node2D
## One run. Builds the arena, owns the managers, camera, lighting, level-up flow, pause and game over.

signal exit_requested(dest: String)     # "retry" | "select" | "menu"

const LIGHT_SHADER := """
shader_type canvas_item;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(0.0);
void fragment() {
    vec2 uv = UV - vec2(0.5);
    uv.x *= 1.7778;
    float d = length(uv);
    float vig = smoothstep(0.38, 1.0, d);
    float a = vig * 0.74 + 0.06;
    vec3 tint = mix(vec3(0.015, 0.02, 0.06), vec3(0.75, 0.04, 0.05), clamp(hurt * vig * 1.6, 0.0, 1.0));
    a = clamp(a + hurt * vig * 0.55, 0.0, 0.96);
    COLOR = vec4(tint, a);
    COLOR = mix(COLOR, vec4(flash_color.rgb, 1.0), flash_color.a);
}
"""

var player: Player
var enemies: EnemyManager
var projectiles: ProjectileManager
var gems: GemManager
var chests: ChestManager
var coins: CoinManager
var fx: FxManager
var status_icons: StatusIcons
var camera: Camera2D
var actors: Node2D
var ground: GroundLayer
var hud: Hud
var levelup: LevelUpScreen
var pause_menu: PauseMenu
var gameover: GameOverScreen
var light_mat: ShaderMaterial
var sim_running := false
var run_time := 0.0
var no_gems := false      # in-game sandbox lock: enemies drop nothing
var no_levels := false    # in-game sandbox lock: XP ignored, level picker never opens
var run_coins := 0         # coins collected this run (HUD + game over); the balance itself lives in Meta
var market_unlocked_now := false   # this run's boss kill opened the Black Market
var decals: Array = []
var cam_pos := Vector2.ZERO
var _shake := 0.0
var _pending_levels := 0
var _pending_chests := 0
var _chest_pos := Vector2.ZERO
var _picker_kind := ""   # dev skip/reroll: "level" | "chest" | "" (which draft is open)
var _rerolls := 0        # Fate stock (§29): run-local, seeded from seal level in start()
var _skips := 0
var _banishes := 0
var _banished: Array[String] = []   # choice keys ("type:id") excluded from drafts this run
var _pending_owed: Array = []  # owed bonus pairs ({kind "weapon"/"passive", tier 0 branch / 1 evo / 2 final}); shown free after the next pick
var _hurt := 0.0
var _flash := Color(0, 0, 0, 0)
var _flash_rate := 3.0      # alpha lost per second by the current screen flash
var _music_key := ""
var _music_t := 0.0
var _over := false


func start(char_id: String) -> void:
	Game.reset_time()
	Game.selected_character = char_id
	Game.shake_requested.connect(_on_shake)
	ground = GroundLayer.new()
	ground.world = self
	ground.z_index = -10
	add_child(ground)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	player = Player.new()
	actors.add_child(player)
	player.setup(self, DB.characters[char_id])
	gems = GemManager.new()
	add_child(gems)
	gems.setup(self)
	chests = ChestManager.new()
	add_child(chests)
	chests.setup(self)
	coins = CoinManager.new()
	add_child(coins)
	coins.setup(self)
	projectiles = ProjectileManager.new()
	add_child(projectiles)
	projectiles.setup(self)
	enemies = EnemyManager.new()
	add_child(enemies)
	enemies.setup(self, actors)
	fx = FxManager.new()
	fx.z_index = 8
	add_child(fx)
	fx.setup(self)
	status_icons = StatusIcons.new()
	add_child(status_icons)
	status_icons.setup(self)
	camera = Camera2D.new()
	camera.zoom = Vector2(Game.ZOOM, Game.ZOOM)
	add_child(camera)
	camera.make_current()
	cam_pos = player.global_position
	# lighting / vignette
	var lc := CanvasLayer.new()
	lc.layer = 5
	add_child(lc)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = LIGHT_SHADER
	light_mat = ShaderMaterial.new()
	light_mat.shader = sh
	rect.material = light_mat
	lc.add_child(rect)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	levelup = LevelUpScreen.new()
	add_child(levelup)
	levelup.chosen.connect(_on_choice)
	levelup.dev_reroll.connect(_on_dev_reroll)
	levelup.dev_skip.connect(_on_dev_skip)
	levelup.utility_reroll.connect(_on_utility_reroll)
	levelup.utility_skip.connect(_on_utility_skip)
	levelup.utility_banish.connect(_on_utility_banish)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.setup(self)
	pause_menu.action.connect(func(a: String) -> void: exit_requested.emit(a))
	gameover = GameOverScreen.new()
	add_child(gameover)
	gameover.action.connect(func(a: String) -> void: exit_requested.emit(a))
	player.leveled_up.connect(_on_level_up)
	player.died.connect(_on_died)
	if Game.dev_active:
		_apply_dev_config()
	else:
		sim_running = true
	# Fate stock (§29): triangular grant from seal level, run-local, dev runs included.
	var stock := Meta.get_utility_stock()
	_rerolls = stock
	_skips = stock
	_banishes = stock
	_banished.clear()
	_set_music("ambient_loop")
	var intro: String = "DEV SANDBOX" if Game.dev_active else "SURVIVE"
	var rental_msg: String = _apply_meta_loadout()
	if rental_msg != "":
		intro += "  -  " + rental_msg
	if stock > 0:
		intro += "  -  FATE: %d REROLL / %d SKIP / %d BANISH" % [stock, stock, stock]
	announce(intro, Game.dev_active)


## Foreseen Victory placeholder pool: hardcoded stat deltas (no mod registry yet).
const FORESEEN_MODS := [
	{"label": "+15% damage", "stat": "damage", "mul": 1.15},
	{"label": "+10% area", "stat": "area", "mul": 1.10},
	{"label": "+10% attack speed", "stat": "cooldown", "mul": 0.90},
	{"label": "+8% move speed", "stat": "move_speed", "mul": 1.08},
	{"label": "+10% max HP", "stat": "max_hp", "mul": 1.10},
	{"label": "+20% magnet", "stat": "pickup_radius", "mul": 1.20},
]


## Start-of-run meta loadout: spend the unsealed Archive weapon + Temporal Loops XP head-start + Foreseen Victory mods.
func _apply_meta_loadout() -> String:
	if Game.dev_active:
		return ""
	var start_bonus := Meta.get_seal_bonus("temporal_loops")
	if start_bonus > 0.0 and player != null:
		player.xp = mini(player.xp_next - 1, maxi(0, int(float(player.xp_next) * start_bonus)))
	var parts: Array[String] = []
	var wid: String = Meta.consume_armed_rental()
	if wid != "":
		player.apply_chest_weapon(wid)
		player.rented_weapon_id = wid
		var wd: WeaponDef = DB.weapons.get(wid)
		if wd != null:
			parts.append("UNSEALED: %s" % wd.display_name.to_upper())
	var start_mod_count := int(Meta.get_total_seal_bonus("start_mod"))
	for i in range(start_mod_count):
		var mod_label := _grant_foreseen_mod()
		if mod_label != "":
			parts.append("FORESEEN VICTORY: %s" % mod_label.to_upper())
	return "  -  ".join(parts)


## Applies one random Foreseen Victory stat delta directly to player.mods.
## Placeholder until a real mod registry lands; always refreshes afterwards.
func _grant_foreseen_mod() -> String:
	if player == null or FORESEEN_MODS.is_empty():
		return ""
	var pick: Dictionary = FORESEEN_MODS[randi() % FORESEEN_MODS.size()]
	var key := String(pick.get("stat", ""))
	if key == "":
		return ""
	if not player.mods.has(key):
		player.mods[key] = {"add": 0.0, "mul": 1.0}
	player.mods[key]["mul"] = float(player.mods[key]["mul"]) * float(pick.get("mul", 1.0))
	player.refresh()
	return String(pick.get("label", key))


## Sandbox entry: apply pre-run spawn filter, start sim, attach F1 overlay.
## Pre-run config is minimal (character + allowed_enemies + elite_only).
## Godmode / director / spawn-rate / time / builds / gem+level locks
## are all controlled live from DevOverlay.
func _apply_dev_config() -> void:
	var cfg: Dictionary = Game.dev_config
	Game.godmode = false
	enemies.apply_dev_config(cfg)
	sim_running = true
	if Game.DEV_MODE_ENABLED:
		var overlay := DevOverlay.new()
		add_child(overlay)
		overlay.setup(self)


## Max out weapon + passive (with chosen branches) and all stat upgrades. Used for ability debugging.
func dev_max_build(wb: int = 0, pb: int = 0) -> void:
	_dev_max_ability(player.weapon, wb)
	_dev_max_ability(player.passive, pb)
	for up_id in DB.upgrades.keys():
		var up: UpgradeDef = DB.upgrades[up_id]
		while int(player.upgrade_levels.get(up_id, 0)) < up.max_level:
			player.apply_choice({"type": "stat", "id": up_id})
	player.hp = player.max_hp


## Dev sandbox helper: climb to 16, taking the branch at 4 and both
## evolutions (option 0) on the way up.
func _dev_max_ability(ab: Ability, branch_idx: int) -> void:
	while ab.can_level():
		ab.level_up()
		if ab.needs_branch():
			ab.pick_branch(clampi(branch_idx, 0, 1))
		if ab.needs_evo(1):
			ab.apply_evo(1, 0)
		if ab.needs_evo(2):
			ab.apply_evo(2, 0)


func dev_set_godmode(on: bool) -> void:
	Game.godmode = on
	if on and player != null:
		player.hp = player.max_hp


## In-game sandbox locks (DevOverlay). Clearing the field on enable keeps
## sprite-isolation tests from leveling via leftover gems.
func set_no_gems(on: bool) -> void:
	no_gems = on
	if on and gems != null:
		for g in gems.live:
			gems._free.append(g)
		gems.live.clear()
		gems.queue_redraw()
	if on and coins != null:
		coins.clear()


func set_no_levels(on: bool) -> void:
	no_levels = on
	if on:
		_pending_levels = 0
		if player != null:
			player.xp = 0


func _exit_tree() -> void:
	Meta.flush()
	Game.reset_time()
	get_tree().paused = false
	if Game.shake_requested.is_connected(_on_shake):
		Game.shake_requested.disconnect(_on_shake)


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if player == null:
		return
	if sim_running:
		run_time += minf(delta, 1.0 / 30.0)
	var target := player.global_position + Vector2(0, -8)
	cam_pos = cam_pos.lerp(target, 1.0 - exp(-9.0 * delta))
	_shake = maxf(0.0, _shake - 28.0 * delta)
	var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	camera.global_position = cam_pos.round()
	camera.offset = off.round()
	for i in range(decals.size() - 1, -1, -1):
		if decals[i]["dead"]:
			decals.remove_at(i)
	_hurt = maxf(0.0, _hurt - delta * 2.4)
	var low := 0.0
	if not player.dead and player.max_hp > 0.0 and player.hp / player.max_hp < 0.3:
		low = 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
	light_mat.set_shader_parameter("hurt", clampf(maxf(_hurt, low), 0.0, 1.0))
	_flash.a = maxf(0.0, _flash.a - delta * _flash_rate)
	light_mat.set_shader_parameter("flash_color", _flash)
	_music_t -= delta
	if _music_t <= 0.0 and sim_running:
		_music_t = 1.0
		_set_music("boss_music" if not enemies.elites.is_empty() else "ambient_loop")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and sim_running and not levelup.visible and not _over:
		pause_menu.open()
		get_viewport().set_input_as_handled()


func _set_music(key: String) -> void:
	if key != _music_key:
		_music_key = key
		Audio.music(key, 1.2)


# ------------------------------------------------------------------ hooks used by other systems
func _on_shake(amount: float) -> void:
	_shake = minf(9.0, _shake + amount * 0.7)


func announce(text: String, danger: bool = false) -> void:
	if hud != null:
		hud.announce(text, danger)


## Full-screen colour pulse (scaled by the FLASH option). A weaker flash never overrides a stronger
## one that is still fading; fade_rate is alpha lost per second.
func flash_screen(c: Color, fade_rate: float = 3.0) -> void:
	c.a *= Game.fx_flash
	if c.a <= 0.0 or c.a < _flash.a:
		return
	_flash = c
	_flash_rate = fade_rate


func hurt_flash() -> void:
	_hurt = 1.0


func add_decal(d: Dictionary) -> void:
	decals.append(d)


func on_kill(e) -> void:
	player.kills += 1
	Meta.note_kill(String(e.def.id))
	player.passive.on_kill(e)
	player.weapon.on_kill(e)
	for cw in player.chest_weapons:
		cw.on_kill(e)
	if String(e.def.boss_unlock) != "":
		_on_boss_defeated(e)


## A unique boss died: grant its meta unlock (the Forbidden Archive) and announce it. The fragment jackpot comes from CoinManager.
func _on_boss_defeated(e) -> void:
	if String(e.def.boss_unlock) == Meta.UNLOCK_MARKET and Meta.unlock_market():
		market_unlocked_now = true
		Audio.sfx("market_unlock", 0.0, 1.0, 0.0)
		flash_screen(Color(1.0, 0.85, 0.3, 0.55))
		announce("THE ARCHIVE IS UNSEALED", false)
		Game.shake(6.0)
	else:
		announce("%s SLAIN" % String(e.def.display_name).to_upper(), false)


# ------------------------------------------------------------------ level up + treasure chests
func _on_level_up() -> void:
	if no_levels:
		_pending_levels = 0
		return
	_pending_levels += 1
	_maybe_open_picker()


func on_chest_opened(at: Vector2) -> void:
	_pending_chests += 1
	_chest_pos = at
	_maybe_open_picker()


## One picker at a time (the LevelUpScreen is shared): chests first, then level-ups.
## Chests still open under no_levels (gear test); level cards never do.
func _maybe_open_picker() -> void:
	if levelup.visible:
		return
	if _pending_chests > 0:
		_open_chest()
	elif _pending_levels > 0 and not no_levels:
		_open_levelup()
	elif no_levels:
		_pending_levels = 0


func _open_levelup() -> void:
	sim_running = false
	get_tree().paused = true
	Audio.sfx("level_up", 0.0, 1.0, 0.0)
	fx.level_up_burst(player.global_position + Vector2(0, -10))
	gems.attract_all()
	_picker_kind = "level"
	levelup.show_choices(build_choices(), player.level - _pending_levels + 1)
	levelup.set_utility(_rerolls, _skips, _banishes)


func _open_chest() -> void:
	sim_running = false
	get_tree().paused = true
	Audio.sfx("level_up", 0.0, 1.1, 0.0)
	fx.level_up_burst(_chest_pos)
	announce("TREASURE!", false)
	_picker_kind = "chest"
	levelup.show_choices(roll_chest_choices(), player.level, "TREASURE!")
	levelup.set_utility(_rerolls, _skips, _banishes)


## Chest tier roll per draft slot: 0 common, 1 rare, 2 legendary. Legendary gate
## first (zero chance while no legendary is unlocked), then the rare roll, else
## common. Caps scale with Luck (Fortune): rare 12% base / 25% cap / +10% per
## luck, legendary 4% base / 10% cap / +5% per luck.
func _roll_chest_tier() -> int:
	var luck: float = maxf(0.0, player.stat("luck"))
	var has_legend := false
	for lid in Player.LEGENDARY_WEAPON_IDS:
		if Player.is_legendary_unlocked(String(lid)):
			has_legend = true
			break
	if has_legend:
		var leg_chance: float = minf(0.10, 0.04 + 0.05 * luck)
		if randf() < leg_chance:
			return 2
	if not Player.RARE_WEAPON_IDS.is_empty():
		var rare_chance: float = minf(0.25, 0.12 + 0.10 * luck)
		if randf() < rare_chance:
			return 1
	return 0


## 3 distinct picks; unowned first, then level-ups for owned. Each slot rolls its
## tier first (common / rare / legendary) and draws fresh-first within that tier,
## falling back to commons when the rolled tier is exhausted.
func roll_chest_choices() -> Array:
	var owned: Dictionary = {}
	for cw in player.chest_weapons:
		owned[cw.def.id] = cw
	var legends: Array = []
	for lid in Player.LEGENDARY_WEAPON_IDS:
		if Player.is_legendary_unlocked(String(lid)):
			legends.append(String(lid))
	var tiers: Array = [Player.CHEST_WEAPON_IDS, Player.RARE_WEAPON_IDS, legends]
	var picked: Array = []
	for slot in 3:
		var t: int = _roll_chest_tier()
		var fresh: Array = []
		var rest: Array = []
		for wid in tiers[t]:
			var w: String = String(wid)
			if picked.has(w):
				continue
			if _banished.has("chest:chest_" + w):
				continue
			if owned.has(w):
				rest.append(w)
			else:
				fresh.append(w)
		fresh.shuffle()
		rest.shuffle()
		var choice: String = ""
		if not fresh.is_empty():
			choice = String(fresh[0])
		elif not rest.is_empty():
			choice = String(rest[0])
		else:
			var c_fresh: Array = []
			var c_rest: Array = []
			for cid in Player.CHEST_WEAPON_IDS:
				var c: String = String(cid)
				if picked.has(c):
					continue
				if _banished.has("chest:chest_" + c):
					continue
				if owned.has(c):
					c_rest.append(c)
				else:
					c_fresh.append(c)
			c_fresh.shuffle()
			c_rest.shuffle()
			if not c_fresh.is_empty():
				choice = String(c_fresh[0])
			elif not c_rest.is_empty():
				choice = String(c_rest[0])
			else:
				choice = String(Player.CHEST_WEAPON_IDS[randi() % Player.CHEST_WEAPON_IDS.size()])
		if choice != "":
			picked.append(choice)
	if picked.is_empty():
		# Everything rolled is banished (needs 9+ banishes; stock caps at 6):
		# ignore the banish list for one common rather than opening an empty draft.
		picked.append(String(Player.CHEST_WEAPON_IDS[randi() % Player.CHEST_WEAPON_IDS.size()]))
	var cards: Array = []
	for wid in picked:
		var w: String = String(wid)
		var def = DB.weapons[w]
		var sub := "New weapon"
		var tag := "TREASURE"
		if int(def.rarity) == 2:
			tag = "TREASURE LEGENDARY"
		elif int(def.rarity) == 1:
			tag = "TREASURE RARE"
		if owned.has(w):
			var cw = owned[w]
			if cw.can_level():
				sub = "Lv %d -> %d" % [cw.level, cw.level + 1]
				tag += " UPGRADE"
			else:
				sub = "Already maxed"
		var desc: String = "%s\n\n%s" % [def.description, UI.describe_ops(def.level_scaling)]
		cards.append(_card("chest", "chest_" + w, def.display_name, tag, sub, desc, def.color, {"weapon_id": w}))
	return cards


func _on_choice(ch: Dictionary) -> void:
	if String(ch.get("type", "")) == "chest":
		var wid: String = String(ch.get("weapon_id", ""))
		var msg: String = player.apply_chest_weapon(wid)
		_pending_chests = maxi(0, _pending_chests - 1)
		_picker_kind = ""
		levelup.hide_screen()
		Audio.sfx("upgrade_selected")
		announce(msg, false)
		_maybe_open_picker()
		if not levelup.visible:
			get_tree().paused = false
			sim_running = true
		return
	# Owed bonus step: branch / evolution locks in free, then the run resumes —
	# the normal pick that earned it was already applied and counted.
	if bool(ch.get("evolution", false)):
		_apply_owed_choice(ch)
		return
	player.apply_choice(ch)
	_pending_levels -= 1
	_queue_owed()
	# The owed pair rides on the back of this level-up: normal pick first,
	# bonus pair right after, still paused, nothing consumed twice.
	if not _pending_owed.is_empty():
		_open_owed()
		return
	_picker_kind = ""
	levelup.hide_screen()
	if _pending_levels > 0 or _pending_chests > 0:
		_maybe_open_picker()
	else:
		get_tree().paused = false
		sim_running = true


## After a normal pick, note newly owed pairs: branch at 4, evolution at 8,
## final evolution at 16. At most one new debt per pick per ability (only the
## just-leveled ability can cross a threshold).
func _queue_owed() -> void:
	for pair in [["weapon", player.weapon], ["passive", player.passive]]:
		var kind: String = (pair as Array)[0]
		var ab: Ability = (pair as Array)[1]
		for tier in [0, 1, 2]:
			var owed: bool = (tier == 0 and ab.needs_branch()) or (tier > 0 and ab.needs_evo(tier))
			if owed and not _owed_has(kind, tier):
				_pending_owed.append({"kind": kind, "tier": tier})


func _owed_has(kind: String, tier: int) -> bool:
	for o in _pending_owed:
		if String((o as Dictionary).get("kind", "")) == kind and int((o as Dictionary).get("tier", -1)) == tier:
			return true
	return false


## Free bonus step: branch pair at 4, evolution pair at 8, final pair at 16.
## Game stays paused. Not rerollable, skippable or banishable — owed, not drafted.
func _open_owed() -> void:
	if _pending_owed.is_empty():
		return
	var o: Dictionary = _pending_owed[0]
	var kind := String(o.get("kind", "weapon"))
	var tier := int(o.get("tier", 0))
	var ab: Ability = player.weapon if kind == "weapon" else player.passive
	_picker_kind = "evolution"
	var titles := ["CHOOSE A PATH!", "EVOLUTION!", "FINAL EVOLUTION!"]
	var subs := ["reached Lv 4  -  choose its path (free, keeps your upgrade)", "reached Lv 8  -  evolve %s (free)" % ab.branch_name(), "reached Lv 16  -  final evolution of %s (free)" % ab.branch_name()]
	levelup.show_choices(_owed_cards(ab, kind, tier), player.level, titles[tier], "%s %s" % [ab.def.display_name, subs[tier]])
	levelup.set_utility(_rerolls, _skips, _banishes)


func _apply_owed_choice(ch: Dictionary) -> void:
	var kind := String(ch.get("evo_kind", "weapon"))
	var tier := int(ch.get("tier", 0))
	var ab: Ability = player.weapon if kind == "weapon" else player.passive
	if tier == 0:
		ab.pick_branch(int(ch.get("branch", 0)))
		announce("%s PATH: %s" % [ab.def.display_name.to_upper(), ab.branch_name().to_upper()], false)
	else:
		ab.apply_evo(tier, int(ch.get("evo", 0)))
		var opt: Dictionary = ab.evo_option(tier, int(ch.get("evo", 0)))
		var word := "EVOLVED" if tier == 1 else "FINAL EVOLUTION"
		announce("%s %s: %s" % [ab.def.display_name.to_upper(), word, String(opt.get("name", "")).to_upper()], false)
	for i in _pending_owed.size():
		var o: Dictionary = _pending_owed[i]
		if String(o.get("kind", "")) == kind and int(o.get("tier", -1)) == tier:
			_pending_owed.remove_at(i)
			break
	Audio.sfx("upgrade_selected")
	if not _pending_owed.is_empty():
		_open_owed()
		return
	_picker_kind = ""
	levelup.hide_screen()
	if _pending_levels > 0 or _pending_chests > 0:
		_maybe_open_picker()
	else:
		get_tree().paused = false
		sim_running = true


## Dev sandbox: re-draft the open picker without consuming pending levels/chests.
func _on_dev_reroll() -> void:
	if not levelup.visible:
		return
	if _picker_kind == "evolution":
		return
	if _picker_kind == "chest":
		levelup.show_choices(roll_chest_choices(), player.level, "TREASURE!")
	elif _picker_kind == "level":
		levelup.show_choices(build_choices(), player.level - _pending_levels + 1)
	levelup.set_utility(_rerolls, _skips, _banishes)


## Dev sandbox: discard the open draft unapplied, then continue with next pending (if any).
func _on_dev_skip() -> void:
	if not levelup.visible:
		return
	if _picker_kind == "evolution":
		return
	if _picker_kind == "chest":
		_pending_chests = maxi(0, _pending_chests - 1)
	elif _picker_kind == "level":
		_pending_levels = maxi(0, _pending_levels - 1)
	else:
		return
	_picker_kind = ""
	levelup.hide_screen()
	_maybe_open_picker()
	if not levelup.visible:
		get_tree().paused = false
		sim_running = true


## Draft-utility key shared with LevelUpScreen (§30): "type:id" for level and
## chest cards, plus ":b<branch>" for branch-pair cards so banishing one branch
## does not seal the other away with it.
func _choice_key(ch: Dictionary) -> String:
	var key := "%s:%s" % [String(ch.get("type", "")), String(ch.get("id", ""))]
	if int(ch.get("branch", -1)) >= 0:
		key += ":b%d" % int(ch.get("branch", 0))
	if ch.has("evo"):
		key += ":e%dt%d" % [int(ch.get("evo", 0)), int(ch.get("tier", 1))]
	return key


## Fate reroll (§29): redraft the open picker without consuming pending, spends 1 stock.
func _on_utility_reroll() -> void:
	if not levelup.visible or _rerolls <= 0:
		return
	if _picker_kind == "evolution":
		return
	if _picker_kind == "chest":
		_rerolls -= 1
		levelup.show_choices(roll_chest_choices(), player.level, "TREASURE!")
	elif _picker_kind == "level":
		_rerolls -= 1
		levelup.show_choices(build_choices(), player.level - _pending_levels + 1)
	else:
		return
	levelup.set_utility(_rerolls, _skips, _banishes)
	Audio.sfx("button_click", -6.0, 1.2)


## Fate skip (§29): discard the open draft unapplied, spends 1 stock.
func _on_utility_skip() -> void:
	if not levelup.visible or _skips <= 0:
		return
	if _picker_kind == "evolution":
		return
	_skips -= 1
	_on_dev_skip()
	levelup.set_utility(_rerolls, _skips, _banishes)
	Audio.sfx("button_click", -6.0, 1.0)


## Fate banish (§29): seal one choice away for the run, then redraft, spends 1 stock.
func _on_utility_banish(choice_id: String) -> void:
	if not levelup.visible or _banishes <= 0 or choice_id == "":
		return
	if _picker_kind == "evolution":
		return
	if _banished.has(choice_id):
		return
	_banished.append(choice_id)
	_banishes -= 1
	if _picker_kind == "chest":
		levelup.show_choices(roll_chest_choices(), player.level, "TREASURE!")
	elif _picker_kind == "level":
		levelup.show_choices(build_choices(), player.level - _pending_levels + 1)
	else:
		_banished.pop_back()
		_banishes += 1
		return
	levelup.set_utility(_rerolls, _skips, _banishes)
	announce("FATE SEALS IT AWAY", false)
	Audio.sfx("button_click", -6.0, 0.8)


## Dev sandbox: every legal level-up move right now (no draft cap, no shuffle).
## Reuses _ability_cards legality (can_level) + owed branch/evolution pairs + the non-maxed stat pool.
func dev_all_level_choices() -> Array:
	var cards: Array = []
	cards.append_array(_ability_cards(player.weapon, "weapon"))
	cards.append_array(_ability_cards(player.passive, "passive"))
	for pair in [["weapon", player.weapon], ["passive", player.passive]]:
		var kind: String = (pair as Array)[0]
		var ab: Ability = (pair as Array)[1]
		if ab.needs_branch():
			cards.append_array(_owed_cards(ab, kind, 0))
		if ab.needs_evo(1):
			cards.append_array(_owed_cards(ab, kind, 1))
		if ab.needs_evo(2):
			cards.append_array(_owed_cards(ab, kind, 2))
	for up in DB.upgrades.values():
		var lv := int(player.upgrade_levels.get(up.id, 0))
		if lv < up.max_level:
			cards.append(_stat_card(up, lv))
	if cards.is_empty():
		cards.append(_card("heal", "heal", "Recovery", "BONUS", "Everything is maxed", "Restore 35% of your maximum health.", UI.GREEN))
	return cards


## Dev sandbox: force a natural chest draft (for testing drafts + Skip/Reroll live).
func dev_open_chest_draft() -> void:
	_pending_chests += 1
	_maybe_open_picker()


func _card(type: String, id: String, title: String, tag: String, sub: String, desc: String, col: Color, extra: Dictionary = {}) -> Dictionary:
	var mono := ""
	for w in title.split(" "):
		if w.length() > 0 and mono.length() < 2:
			mono += w.substr(0, 1).to_upper()
	var d := {"type": type, "id": id, "title": title, "tag": tag, "sub": sub, "desc": desc, "color": col, "mono": mono}
	d.merge(extra)
	d["art"] = _card_art(d)
	return d


## Resolved card art (path/frames/fps/preview/fallback) via AbilityArt.
## Branch cards preview their branch strip when present, otherwise the base icon.
func _card_art(ch: Dictionary) -> Dictionary:
	var t := String(ch.get("type", ""))
	var branch := int(ch.get("branch", -1))
	if t == "weapon" or t == "passive":
		var def = DB.ability(String(ch.get("id", "")))
		if def != null:
			return AbilityArt.icon_for_ability(def, branch)
	elif t == "chest":
		var wdef = DB.weapons.get(String(ch.get("weapon_id", "")))
		if wdef != null:
			return AbilityArt.icon_for_ability(wdef, -1)
	elif t == "stat":
		var up = DB.upgrades.get(String(ch.get("id", "")))
		if up != null:
			return AbilityArt.icon_for_upgrade(up)
	return {"path": AbilityArt.UPGRADE_FALLBACK, "frames": 1, "fps": 8.0, "preview": "static", "fallback": true}


## Single next-level card for a kit ability. Branch/evolution-ready abilities
## still level here (no gates) — their pairs are owed as bonus cards after
## the next pick (see _owed_cards), never forced into the draft.
func _ability_cards(ab: Ability, kind: String) -> Array:
	var out: Array = []
	if ab.can_level():
		var desc2 := UI.describe_ops(ab.def.level_scaling)
		if ab.branch >= 0:
			desc2 += "\n" + UI.describe_ops(ab.def.branches[ab.branch]["per_level"])
		out.append(_card(kind, ab.def.id, ab.def.display_name, "POWER", "Lv %d -> %d" % [ab.level, ab.level + 1], desc2, ab.def.color, {"branch": -1}))
	return out


## Owed bonus pair, free alongside the normal pick. Tier 0 = the two branch
## paths; tiers 1-2 = the two evolution options for the picked branch
## (hand-authored data when present, generated branch-flavored fallback otherwise).
func _owed_cards(ab: Ability, kind: String, tier: int) -> Array:
	var out: Array = []
	if tier == 0:
		for b in 2:
			var br: Dictionary = ab.def.branches[b]
			var desc: String = "%s\n\n%s" % [br["desc"], UI.describe_ops(br["on_pick"])]
			out.append(_card(kind, ab.def.id, br["name"], "PATH", "%s  Lv %d (free)" % [ab.def.display_name, ab.level], desc, ab.def.color, {"branch": b, "evolution": true, "evo_kind": kind, "tier": 0}))
		return out
	var tag := "EVOLUTION" if tier == 1 else "FINAL"
	for e in 2:
		var opt: Dictionary = ab.evo_option(tier, e)
		var ops: Dictionary = (opt.get("ops", {}) as Dictionary).duplicate()
		for k2 in (opt.get("ops2", {}) as Dictionary).keys():
			ops[k2] = (opt.get("ops2", {}) as Dictionary)[k2]
		for k3 in (opt.get("ops3", {}) as Dictionary).keys():
			ops[k3] = (opt.get("ops3", {}) as Dictionary)[k3]
		var desc2: String = "%s\n\n%s" % [String(opt.get("desc", "")), UI.describe_ops(ops)]
		out.append(_card(kind, ab.def.id, String(opt.get("name", "Evolve")), tag, "%s  %s Lv %d (free)" % [ab.def.display_name, ab.branch_name(), ab.level], desc2, ab.def.color, {"branch": ab.branch, "evolution": true, "evo_kind": kind, "tier": tier, "evo": e}))
	return out


func _stat_card(up: UpgradeDef, lv: int, tag: String = "STAT") -> Dictionary:
	return _card("stat", up.id, up.display_name, tag, "Lv %d -> %d" % [lv, lv + 1], up.description, up.color)


## Weighted single draw from [card, weight] pairs. Returns {} when empty.
func _lane_draw(cands: Array) -> Dictionary:
	var total := 0.0
	for cw in cands:
		total += float((cw as Array)[1])
	if total <= 0.0 or cands.is_empty():
		return {}
	var r := randf() * total
	for cw in cands:
		r -= float((cw as Array)[1])
		if r <= 0.0:
			return (cw as Array)[0]
	return (cands[cands.size() - 1] as Array)[0]


## Lane-based draft. Power = owned kit upgrades. Stat = base stats with mild
## high-rank decay. Wildcard = upgrades for carried chest weapons (rarity
## weighted, Fortune-scaled) — never a fresh weapon; those stay chest-only.
## Empty lanes substitute from the other lanes' leftovers. Owed branch/evolution
## pairs are NOT part of this draft; they follow as free steps (see _on_choice).
func build_choices() -> Array:
	var want := 3 + (1 if player.stat("luck") >= 0.3 else 0)
	var luck: float = maxf(0.0, player.stat("luck"))
	# Power lane: one owned kit upgrade.
	var power: Array = []
	var kit: Array = [[player.weapon as Ability, "weapon"], [player.passive as Ability, "passive"]]
	for pair in kit:
		var ab: Ability = (pair as Array)[0]
		for c in _ability_cards(ab, String((pair as Array)[1])):
			if not _banished.has(_choice_key(c)):
				power.append([c, 1.0])
	# Stat lane: mild high-rank decay so stats persist without flooding.
	var stats: Array = []
	for up in DB.upgrades.values():
		var lv := int(player.upgrade_levels.get(up.id, 0))
		if lv < up.max_level:
			var sc := _stat_card(up, lv)
			if not _banished.has(_choice_key(sc)):
				stats.append([sc, 1.0 / (1.0 + 0.45 * float(lv))])
	# Wildcard lane: carried chest-weapon upgrades, rarity weighted. Rare and
	# legendary upgrades weigh less; Fortune (luck) lifts them back up.
	var wild: Array = []
	for cw in player.chest_weapons:
		if not cw.can_level():
			continue
		var wdef = DB.weapons.get(cw.def.id)
		if wdef == null:
			continue
		var key := "chest:chest_" + String(cw.def.id)
		if _banished.has(key):
			continue
		var w := 1.0
		if int(wdef.rarity) == 2:
			w = 0.25 * (1.0 + 0.5 * luck)
		elif int(wdef.rarity) == 1:
			w = 0.5 * (1.0 + luck)
		var sub := "Lv %d -> %d" % [cw.level, cw.level + 1]
		var desc: String = "%s\n\n%s" % [wdef.description, UI.describe_ops(wdef.level_scaling)]
		wild.append([_card("chest", "chest_" + String(cw.def.id), wdef.display_name, "WILD", sub, desc, wdef.color, {"weapon_id": String(cw.def.id)}), w])
	var cards: Array = []
	var taken: Array[String] = []
	var leftovers: Array = []
	var _take := func(cands: Array, tag: String) -> void:
		var pick: Dictionary = _lane_draw(cands)
		if pick.is_empty():
			return
		pick["tag"] = tag
		cards.append(pick)
		taken.append(_choice_key(pick))
	for cands in [power, stats, wild]:
		for cw in cands:
			leftovers.append(cw)
	_take.call(power, "POWER")
	_take.call(stats, "STAT")
	_take.call(wild, "WILD")
	# Substitution + Luck bonus: fill from anything left over, in lane order.
	var rest: Array = []
	for cw in leftovers:
		if not taken.has(_choice_key((cw as Array)[0])):
			rest.append(cw)
	rest.shuffle()
	while cards.size() < want and not rest.is_empty():
		var pick: Dictionary = (rest.pop_back() as Array)[0]
		pick["tag"] = "LUCK BONUS" if cards.size() >= 3 else pick.get("tag", "WILD")
		cards.append(pick)
	if cards.is_empty():
		# Safety net only: capacity (~70 picks vs ~45 expected) should make
		# this unreachable in a real run. Never coins or tickets — no farm loop.
		cards.append(_card("heal", "heal", "Recovery", "BONUS", "Everything is maxed", "Restore 35% of your maximum health.", UI.GREEN))
	return cards


# ------------------------------------------------------------------ death
func _on_died() -> void:
	if _over:
		return
	_over = true
	Meta.flush()
	sim_running = false
	Audio.stop_music(1.0)
	Game.lock_time_scale(0.35)
	await get_tree().create_timer(1.1, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().paused = true
	gameover.show_result(self)
