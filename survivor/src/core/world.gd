class_name World
extends Node2D
## One run. Builds the arena, owns the managers, camera, lighting, level-up flow, pause and game over.

signal exit_requested(dest: String)     # "retry" | "select" | "menu"

const LIGHT_SHADER := """
shader_type canvas_item;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(0.0);
uniform vec4 base_tint : source_color = vec4(0.015, 0.02, 0.06, 1.0);
uniform vec4 edge_glow : source_color = vec4(0.0);
void fragment() {
    vec2 uv = UV - vec2(0.5);
    uv.x *= 1.7778;
    float d = length(uv);
    float vig = smoothstep(0.38, 1.0, d);
    float a = vig * 0.74 + 0.06;
    vec3 tint = mix(base_tint.rgb, vec3(0.75, 0.04, 0.05), clamp(hurt * vig * 1.6, 0.0, 1.0));
    tint = mix(tint, edge_glow.rgb, clamp(edge_glow.a * vig, 0.0, 1.0));
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
var critters: CritterManager
var fx: FxManager
var status_icons: StatusIcons
var camera: Camera2D
var actors: Node2D
var ground: GroundLayer
var hud: Hud
var touch_controls: TouchControls
var levelup: LevelUpScreen
var pause_menu: PauseMenu
var gameover: GameOverScreen
var light_mat: ShaderMaterial
var acts: ActManager
var act_ambient: ActAmbient
var act_banner: ActBanner
var act_clear: ActClearScreen
var sim_running := false
var run_time := 0.0
var no_gems := false      # in-game sandbox lock: enemies drop nothing
var no_levels := false    # in-game sandbox lock: XP ignored, level picker never opens
var no_treasures := false # sandbox lock: elites drop no treasure chests, field wiped on enable
var dev_time_rate := 1.0  # sandbox slow-mo baseline for FX inspection
var run_coins := 0         # escrow: Fragments collected this run (HUD + game over); banked to Meta on Withdraw
var run_lost := 0          # Fragments forfeited on death (escrow, non-dev): shown on the game-over screen
var run_banked := 0        # Fragments actually banked by bank_run(): shown on the victory screen
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
var _tint_cur := Color(0.015, 0.02, 0.06, 1.0)
var _tint_tgt := Color(0.015, 0.02, 0.06, 1.0)
var _vignette_pulse := 0.0
var _edge_col := Color(0, 0, 0, 0)
var _over := false
var _banked := false       # bank_run guard: escrow banks exactly once
var _clearing := false     # Act Cleared beat running or clear screen open: blocks pause
var rentals_stripped := false   # Withdraw drops the one-battle rental (Phase 3 reads this)


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
	acts = ActManager.new()
	add_child(acts)
	acts.setup(self)
	gems = GemManager.new()
	add_child(gems)
	gems.setup(self)
	chests = ChestManager.new()
	add_child(chests)
	chests.setup(self)
	coins = CoinManager.new()
	add_child(coins)
	coins.setup(self)
	critters = CritterManager.new()
	add_child(critters)
	critters.setup(self, actors)
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
	touch_controls = TouchControls.new()
	add_child(touch_controls)
	touch_controls.setup(self)
	act_ambient = ActAmbient.new()
	add_child(act_ambient)
	act_ambient.setup(self)
	act_banner = ActBanner.new()
	add_child(act_banner)
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
	act_clear = ActClearScreen.new()
	add_child(act_clear)
	act_clear.descend.connect(_on_clear_descend)
	act_clear.withdraw.connect(_on_clear_withdraw)
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
	# Descent checkpoint (Phase 3): consume Game.pending_descent once. A continued
	# run restores the saved build instead of the meta loadout; dev runs ignore it.
	var snap: Dictionary = Game.pending_descent
	Game.pending_descent = {}
	var continuing: bool = not Game.dev_active and not snap.is_empty() and Descent.restore(self, snap)
	_set_music("ambient_loop")
	var intro: String
	if continuing:
		intro = "CONTINUE - %s" % String(acts.act_at(int(snap.get("next_act", 0))).display_name)
	else:
		intro = "DEV SANDBOX" if Game.dev_active else "SURVIVE"
		var rental_msg: String = _apply_meta_loadout()
		if rental_msg != "":
			intro += "  -  " + rental_msg
		if stock > 0:
			intro += "  -  FATE: %d REROLL / %d SKIP / %d BANISH" % [stock, stock, stock]
	announce(intro, Game.dev_active)
	# Act director: normal runs start at act 1 with the clock reset; dev jump-ins
	# derive the act from the seeded clock and keep it; a Continue starts at the
	# saved next act. First activation is instant.
	var start_idx := 0
	var set_clock := true
	if Game.dev_active:
		start_idx = acts.act_for_time(run_time)
		set_clock = false
	elif continuing:
		start_idx = int(snap.get("next_act", 0))
	acts.begin_act(start_idx, set_clock, true)


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


## Sandbox entry: apply pre-run start state atomically before the first tick,
## then attach the F1 overlay (which mirrors the same keys live).
## Order matters: clock first, then director (pause/mult/timers seeded from the
## clock), then locks/godmode/time-rate, and only then sim_running = true.
## Paused means zero director spawns; time-skip while paused only moves the
## clock, and due events (e.g. bosses) fire once on unpause.
func _apply_dev_config() -> void:
	var cfg: Dictionary = Game.dev_config
	Game.godmode = false
	Game.dev_time_rate = 1.0
	dev_time_rate = 1.0
	run_time = maxf(0.0, float(cfg.get("start_time", 0.0)))
	enemies.apply_dev_config(cfg)
	set_no_gems(bool(cfg.get("no_gems", false)))
	set_no_levels(bool(cfg.get("no_levels", false)))
	set_no_treasures(bool(cfg.get("no_treasures", false)))
	if bool(cfg.get("godmode", false)):
		dev_set_godmode(true)
	dev_set_time_rate(clampf(float(cfg.get("time_rate", 1.0)), 0.1, 1.0))
	sim_running = true
	if Game.DEV_MODE_ENABLED:
		var overlay := DevOverlay.new()
		add_child(overlay)
		overlay.setup(self)


## Max out weapon + passive (with chosen branches) and all stat upgrades. Used for ability debugging.
func dev_max_build(wb: int = 0, pb: int = 0, we1: int = 0, we2: int = 0, pe1: int = 0, pe2: int = 0) -> void:
	_dev_max_ability(player.weapon, wb, we1, we2)
	_dev_max_ability(player.passive, pb, pe1, pe2)
	for up_id in DB.upgrades.keys():
		var up: UpgradeDef = DB.upgrades[up_id]
		while int(player.upgrade_levels.get(up_id, 0)) < up.max_level:
			player.apply_choice({"type": "stat", "id": up_id})
	player.hp = player.max_hp


## Dev sandbox helper: climb to 16, taking the branch at 4 and both
## evolutions (chosen options) on the way up.
func _dev_max_ability(ab: Ability, branch_idx: int, e1: int = 0, e2: int = 0) -> void:
	while ab.can_level():
		ab.level_up()
		if ab.needs_branch():
			ab.pick_branch(clampi(branch_idx, 0, 1))
		if ab.needs_evo(1):
			ab.apply_evo(1, clampi(e1, 0, 7))
		if ab.needs_evo(2):
			ab.apply_evo(2, clampi(e2, 0, 7))


func dev_set_kit(kind: String, level: int, branch: int, e1: int, e2: int) -> void:
	var ab: Ability = player.weapon if kind == "weapon" else player.passive
	while ab.level < level and ab.can_level():
		ab.level_up()
		if ab.needs_branch():
			ab.pick_branch(clampi(branch, 0, 1))
		if ab.needs_evo(1) and ab.evo1 < 0:
			ab.apply_evo(1, clampi(e1, 0, 7))
		if ab.needs_evo(2) and ab.evo2 < 0:
			ab.apply_evo(2, clampi(e2, 0, 7))
	refresh()


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


## Sandbox lock (DevMenu pre-run + DevOverlay live). Mirrors set_no_gems:
## elites stop dropping chests and the live field is recycled, so boss tests
## don't get interrupted by pickup drafts. Manual Grant/Draft chest still works.
func set_no_treasures(on: bool) -> void:
	no_treasures = on
	if on and chests != null:
		for c in chests.live:
			chests._free.append(c)
			c.sprite.visible = false
		chests.live.clear()


## Sandbox slow-mo baseline for small-FX inspection. Stored on Game as well so
## hit-stop completion restores to this instead of 1.0 in dev runs.
func dev_set_time_rate(v: float) -> void:
	dev_time_rate = clampf(v, 0.1, 1.0)
	Game.dev_time_rate = dev_time_rate
	if not Game._time_locked:
		Engine.time_scale = dev_time_rate


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
	_tint_cur = _tint_cur.lerp(_tint_tgt, clampf(delta * 1.5, 0.0, 1.0))
	light_mat.set_shader_parameter("base_tint", _tint_cur)
	var eg := Color(0, 0, 0, 0)
	if _vignette_pulse > 0.0:
		var s := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * _vignette_pulse)
		eg = Color(_edge_col.r, _edge_col.g, _edge_col.b, 0.10 + 0.22 * s)
	light_mat.set_shader_parameter("edge_glow", eg)
	_music_t -= delta
	if _music_t <= 0.0 and sim_running:
		_music_t = 1.0
		var mact = acts.current() if acts != null else null
		if mact != null:
			_set_music(mact.boss_music_key if enemies.boss_alive() else mact.music_key)
		else:
			_set_music("ambient_loop")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and try_pause():
		get_viewport().set_input_as_handled()


## Shared pause entry (Esc/P key path and the on-screen touch button).
func try_pause() -> bool:
	if sim_running and not levelup.visible and not _over and not _clearing:
		pause_menu.open()
		return true
	return false


func _set_music(key: String, fade := 1.2) -> void:
	if key != _music_key:
		_music_key = key
		if key == "":
			Audio.stop_music(fade)
		else:
			Audio.music(key, fade)


## Apply an act's arena theme: floor/brazier palette (instant = no floor tween),
## vignette tint tween, ambient wash, Act IV edge pulse, and a live enemy re-tint.
## Called from ActManager.begin_act on every act change.
func set_arena_theme(act: ActDef, instant: bool) -> void:
	if act == null:
		return
	if ground != null:
		ground.apply_theme(act, instant)
	_tint_tgt = act.vignette_tint
	if instant:
		_tint_cur = _tint_tgt
	_vignette_pulse = act.vignette_pulse
	_edge_col = act.flame_glow
	if act_ambient != null:
		act_ambient.set_act(act, instant)
	if enemies != null:
		enemies._on_act_changed(acts.idx if acts != null else 0)


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
	elif float(e.def.boss_time) > 0.0:
		announce("SLAIN", false)
	# Unique act boss: only the boss the director is currently holding advances
	# the act (Phase-2 shim auto-advances; dev-spawned bosses never trigger it).
	if acts != null and acts.held_boss_id == String(e.def.id):
		acts.boss_slain(e.def)


func on_ability_hit(e, amount: float) -> void:
	if player.weapon != null:
		player.weapon.on_hit(e, amount)
	if player.passive != null:
		player.passive.on_hit(e, amount)
	for cw in player.chest_weapons:
		cw.on_hit(e, amount)


func on_player_hurt(amount: float) -> void:
	if player.weapon != null:
		player.weapon.on_player_hurt(amount)
	if player.passive != null:
		player.passive.on_player_hurt(amount)
	for cw in player.chest_weapons:
		cw.on_player_hurt(amount)


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


# ------------------------------------------------------------------ act clear + fragment escrow
## Fragments picked up during a run. Dev sandbox credits Meta live (legacy
## behaviour); a normal run holds them in escrow (run_coins) until Withdraw.
func credit_fragments(n: int) -> void:
	if n <= 0:
		return
	if Game.dev_active:
		Meta.add_coins(n)
	run_coins += n


## Bank the escrowed run into the persistent balance. Guarded to run once.
func bank_run() -> void:
	if _banked:
		return
	_banked = true
	run_banked = run_coins
	if run_coins > 0:
		Meta.add_coins(run_coins)
	Meta.flush()


## True once every picker has resolved (open draft, pending levels/chests and owed pairs).
func pickers_done() -> bool:
	return not levelup.visible and _pending_levels == 0 and _pending_chests == 0 and _pending_owed.is_empty()


## Act Cleared beat (Phase 2, replaces the old auto-advance shim). Called by
## ActManager.boss_slain for the unique act boss, non-dev only: stop music,
## quiet-wipe the field, vacuum pickups, let the run breathe, wait out any
## pickers (boss chests / level-ups resolve first), then freeze and offer the choice.
func run_clear_beat(def) -> void:
	_clearing = true
	_set_music("", 1.2)
	enemies.wipe_quiet()
	gems.attract_all()
	Game.hit_stop(0.12)
	await get_tree().create_timer(2.5, true, false, true).timeout
	while not pickers_done():
		await get_tree().create_timer(0.1, true, false, true).timeout
	var next = acts.next_act()
	var forced: bool = not acts.next_is_playable()
	sim_running = false
	get_tree().paused = true
	act_clear.show_clear(acts.current(), next, run_coins, forced, String(def.display_name))


## Descend: same run continues into the next act (clock resumes from its start,
## banner + theme + music crossfade), with 8s of zero director spawns under the banner.
func _on_clear_descend() -> void:
	act_clear.hide_screen()
	_clearing = false
	get_tree().paused = false
	sim_running = true
	acts.begin_act(acts.idx + 1)
	enemies.breather(8.0)


func _on_clear_withdraw() -> void:
	withdraw()


## Withdraw at the clear beat: bank the escrow, drop the one-battle rental, show
## the victory summary. Rentals never carry out (Phase 3 excludes the rented
## weapon from the checkpoint); `rentals_stripped` records it for that step.
func withdraw() -> void:
	if _over:
		return
	_over = true
	_clearing = false
	if not Game.dev_active:
		# Phase 3 checkpoint: one per hero, written on Withdraw only. A later,
		# shallower save never overwrites a deeper one (kept until a deeper clear).
		var snap: Dictionary = Descent.capture(self)
		var prev: Dictionary = Meta.get_descent(String(player.def.id))
		if prev.is_empty() or int(snap.get("next_act", 0)) > int(prev.get("next_act", 0)):
			Meta.set_descent(String(player.def.id), snap)
	bank_run()
	rentals_stripped = true
	sim_running = false
	Audio.stop_music(1.0)
	act_clear.hide_screen()
	get_tree().paused = false
	gameover.show_victory(self, run_banked, not acts.next_is_playable())


# ------------------------------------------------------------------ death
func _on_died() -> void:
	if _over:
		return
	_over = true
	if not Game.dev_active:
		# Escrow forfeit: unbanked Fragments are lost; the Meta balance is untouched.
		run_lost = run_coins
		run_coins = 0
	Meta.flush()
	sim_running = false
	Audio.stop_music(1.0)
	Game.lock_time_scale(0.35)
	await get_tree().create_timer(1.1, true, false, true).timeout
	Engine.time_scale = 1.0
	get_tree().paused = true
	gameover.show_result(self)
