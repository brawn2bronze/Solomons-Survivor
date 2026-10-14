class_name DevOverlay
extends CanvasLayer
## In-run sandbox cheat panel. Only created when Game.dev_active.
## Toggle with F1. Mirrors the pre-run DevMenu start state live: godmode,
## director pause + spawn-rate, time jumps + slow-mo rate, force level-up /
## max build, kill all, progression locks (no gem/treasure drops, no level-ups).

var world
var _panel: PanelContainer
var _scroll: ScrollContainer
var _visible_dev := true
var _enemy_pick: OptionButton
var _mult_slider: HSlider
var _mult_label: Label
var _rate_slider: HSlider
var _rate_label: Label
var _god_check: CheckBox
var _dir_check: CheckBox
var _nogems_check: CheckBox
var _nolevels_check: CheckBox
var _notreas_check: CheckBox
var _level_pick: OptionButton
var _chest_pick: OptionButton
var _level_cards: Array = []
var _perf: Label
var _coin_field: LineEdit


func setup(world_ref) -> void:
	world = world_ref
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = UI.panel(Color(0.07, 0.06, 0.11, 0.95), UI.GOLD, 2, 10)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-330.0, 90.0)
	_panel.custom_minimum_size = Vector2(314, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	root.add_child(_panel)
	# Anchor trick: keep top-right pinned on resize.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -330.0
	_panel.offset_right = -12.0
	_panel.offset_top = 90.0
	# Scrollable content: cap height to the viewport so the panel can never
	# grow past the bottom of the screen (refit on window resize).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	_scroll.add_child(v)
	v.add_child(UI.label("DEV SANDBOX  (F1 hides)", 18, UI.GOLD))
	v.add_child(UI.label("GOD / DIRECTOR", 13, UI.PURPLE))
	_god_check = _check(v, "Godmode (infinite HP)", Game.godmode, _on_god)
	_dir_check = _check(v, "Pause director (zero spawns)", world.enemies.director_paused, _on_dir_pause)
	v.add_child(UI.label("PROGRESSION LOCKS", 13, UI.PURPLE))
	_nogems_check = _check(v, "No gem drops", world.no_gems, _on_nogems)
	_nolevels_check = _check(v, "No level-ups (freeze XP)", world.no_levels, _on_nolevels)
	_notreas_check = _check(v, "No treasure drops", world.no_treasures, _on_notreas)
	v.add_child(UI.label("SPAWN", 13, UI.PURPLE))
	v.add_child(UI.label("Spawn target sprite", 14, UI.DIM))
	_enemy_pick = OptionButton.new()
	_enemy_pick.custom_minimum_size = Vector2(280, 32)
	var ids: Array = DB.enemies.keys()
	ids.sort()
	for i in ids.size():
		var d = DB.enemies[ids[i]]
		_enemy_pick.add_item("%s (%s)" % [d.display_name, ids[i]], i)
		_enemy_pick.set_item_metadata(i, ids[i])
	var boss_idx: int = maxi(0, ids.find(_default_spawn_id(ids)))
	_enemy_pick.select(clampi(boss_idx, 0, ids.size() - 1))
	v.add_child(_enemy_pick)
	v.add_child(_row_buttons(["+1", "+10", "+50"], [_on_spawn1, _on_spawn10, _on_spawn50]))
	v.add_child(_row_buttons(["+150", "+300", "Kill all"], [_on_spawn150, _on_spawn300, _on_kill_all]))
	v.add_child(UI.label("PROGRESS", 13, UI.PURPLE))
	v.add_child(_row_buttons(["Heal", "Level+1", "Max build"], [_on_heal, _on_levelup, _on_maxbuild]))
	v.add_child(UI.label("UPGRADES (direct grant)", 13, UI.PURPLE))
	v.add_child(UI.label("Level-up catalog", 14, UI.DIM))
	_level_pick = OptionButton.new()
	_level_pick.custom_minimum_size = Vector2(280, 32)
	v.add_child(_level_pick)
	v.add_child(UI.label("Chest weapon", 14, UI.DIM))
	_chest_pick = OptionButton.new()
	_chest_pick.custom_minimum_size = Vector2(280, 32)
	v.add_child(_chest_pick)
	v.add_child(_row_buttons(["Grant lv", "Draft chest", "Grant chest"], [_on_grant_level, _on_open_chest_draft, _on_grant_chest]))
	v.add_child(UI.label("BLACK MARKET (saves to disk)", 13, UI.PURPLE))
	v.add_child(_row_buttons(["Boss", "+250c", "Unlock"], [_on_boss, _on_coins, _on_market_unlock]))
	v.add_child(_row_buttons(["Lock", "24:50", "Wipe save"], [_on_market_lock, _on_jump_boss, _on_meta_wipe]))
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 8)
	v.add_child(coin_row)
	_coin_field = LineEdit.new()
	_coin_field.text = "1000"
	_coin_field.placeholder_text = "coins"
	_coin_field.max_length = 7
	_coin_field.custom_minimum_size = Vector2(180, 36)
	_coin_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coin_field.text_changed.connect(_on_coin_field_changed)
	coin_row.add_child(_coin_field)
	var deposit_b := UI.button("Deposit", 15, Vector2(92, 36))
	deposit_b.pressed.connect(_on_deposit_custom)
	coin_row.add_child(deposit_b)
	v.add_child(UI.label("TIME / RATE", 13, UI.PURPLE))
	v.add_child(_row_buttons(["+30s", "+60s", "Spawn x0"], [_on_t30, _on_t60, _on_rate_zero]))
	_rate_label = UI.label("Time rate x%.2f (slow-mo FX)" % world.dev_time_rate, 14, UI.DIM)
	v.add_child(_rate_label)
	_rate_slider = HSlider.new()
	_rate_slider.min_value = 0.1
	_rate_slider.max_value = 1.0
	_rate_slider.step = 0.05
	_rate_slider.value = clampf(world.dev_time_rate, 0.1, 1.0)
	_rate_slider.custom_minimum_size = Vector2(280, 20)
	_rate_slider.value_changed.connect(_on_rate)
	v.add_child(_rate_slider)
	_mult_label = UI.label("Spawn rate x%.1f" % world.enemies.spawn_mult, 14, UI.DIM)
	v.add_child(_mult_label)
	_mult_slider = HSlider.new()
	_mult_slider.min_value = 0.0
	_mult_slider.max_value = 10.0
	_mult_slider.step = 0.5
	_mult_slider.value = world.enemies.spawn_mult
	_mult_slider.custom_minimum_size = Vector2(280, 20)
	_mult_slider.value_changed.connect(_on_mult)
	v.add_child(_mult_slider)
	_perf = UI.label("", 13, UI.DIM)
	v.add_child(_perf)
	_refresh_upgrade_lists()
	_fit_scroll_height()
	get_tree().root.size_changed.connect(_fit_scroll_height)


func _check(parent: Control, text: String, pressed: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = pressed
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


func _row_buttons(labels: Array, cbs: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	for i in labels.size():
		var b := UI.button(String(labels[i]), 15, Vector2(90, 36))
		b.pressed.connect(cbs[i])
		h.add_child(b)
	return h


## Default spawn target: single isolated sprite if the pre-run filter
## picked exactly one, else the brute, else the first id.
func _default_spawn_id(ids: Array) -> String:
	var allowed: Array = Game.dev_config.get("allowed_enemies", [])
	if allowed.size() == 1 and ids.has(allowed[0]):
		return String(allowed[0])
	if ids.has("goblin_brute"):
		return "goblin_brute"
	return String(ids[0]) if not ids.is_empty() else ""


func _picked_id() -> String:
	return String(_enemy_pick.get_item_metadata(_enemy_pick.selected))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F1:
			_visible_dev = not _visible_dev
			_panel.visible = _visible_dev
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if world == null or world.enemies == null:
		return
	var flags := ""
	if world.no_gems:
		flags += " NG"
	if world.no_treasures:
		flags += " NT"
	if world.no_levels:
		flags += " NL"
	if world.enemies.director_paused:
		flags += " PAUSED"
	_perf.text = "%d FPS  enemies %d/%d  proj %d  gems %d  t %ds  rate x%.2f%s" % [Engine.get_frames_per_second(), world.enemies.alive_count(), EnemyManager.MAX_POOL, world.projectiles.live.size(), world.gems.live.size(), int(world.run_time), world.dev_time_rate, flags]


## Cap the scroll area to the viewport so the panel can never overflow
## the bottom of the screen. Called once at setup and on window resize.
func _fit_scroll_height() -> void:
	if _scroll == null:
		return
	var h: float = maxf(320.0, get_viewport().get_visible_rect().size.y - 130.0)
	_scroll.custom_minimum_size = Vector2(280, h)


func _on_god(on: bool) -> void:
	world.dev_set_godmode(on)


func _on_dir_pause(on: bool) -> void:
	world.enemies.director_paused = on


func _on_mult(v: float) -> void:
	world.enemies.spawn_mult = v
	_mult_label.text = "Spawn rate x%.1f" % v


func _on_nogems(on: bool) -> void:
	world.set_no_gems(on)


func _on_nolevels(on: bool) -> void:
	world.set_no_levels(on)
	if on:
		world.announce("LEVELS FROZEN", false)


func _on_notreas(on: bool) -> void:
	world.set_no_treasures(on)
	if on:
		world.announce("TREASURES OFF", false)


func _on_rate(v: float) -> void:
	world.dev_set_time_rate(v)
	_rate_label.text = "Time rate x%.2f (slow-mo FX)" % world.dev_time_rate


func _on_spawn1() -> void:
	world.enemies.spawn_around_id(_picked_id(), 1)


func _on_spawn10() -> void:
	world.enemies.spawn_around_id(_picked_id(), 10)


func _on_spawn50() -> void:
	world.enemies.spawn_around_id(_picked_id(), 50)


func _on_spawn150() -> void:
	world.enemies.spawn_around_id(_picked_id(), 150)


func _on_spawn300() -> void:
	world.enemies.spawn_around_id(_picked_id(), 300)


func _on_kill_all() -> void:
	world.enemies.kill_all()


func _on_heal() -> void:
	world.player.hp = world.player.max_hp


func _on_levelup() -> void:
	if world.no_levels:
		world.announce("LEVELS FROZEN", false)
		return
	world.player.add_xp(world.player.xp_next)


func _on_maxbuild() -> void:
	world.dev_max_build(0, 0)


## Rebuild both grant dropdowns from live state (legality/subs change after every grant).
func _refresh_upgrade_lists() -> void:
	_level_cards = world.dev_all_level_choices()
	_level_pick.clear()
	for i in _level_cards.size():
		var ch: Dictionary = _level_cards[i]
		_level_pick.add_item("%s | %s (%s)" % [String(ch.get("tag", "")), String(ch.get("title", "")), String(ch.get("sub", ""))], i)
		_level_pick.set_item_metadata(i, i)
	var owned: Dictionary = {}
	for cw in world.player.chest_weapons:
		owned[cw.def.id] = cw
	_chest_pick.clear()
	var pool: Array = []
	pool.append_array(Player.CHEST_WEAPON_IDS)
	pool.append_array(Player.RARE_WEAPON_IDS)
	pool.append_array(Player.LEGENDARY_WEAPON_IDS)
	for i in pool.size():
		var wid: String = String(pool[i])
		var def = DB.weapons[wid]
		var sub := "New weapon"
		if owned.has(wid):
			var cw = owned[wid]
			if cw.can_level():
				sub = "Lv %d -> %d" % [cw.level, cw.level + 1]
			else:
				sub = "Already maxed"
		_chest_pick.add_item("%s (%s)" % [def.display_name, sub], i)
		_chest_pick.set_item_metadata(i, i)
	if _level_pick.item_count > 0:
		_level_pick.select(0)
	if _chest_pick.item_count > 0:
		_chest_pick.select(0)


func _on_grant_level() -> void:
	if _level_pick.item_count == 0 or _level_pick.selected < 0:
		return
	var idx: int = int(_level_pick.get_item_metadata(_level_pick.selected))
	if idx < 0 or idx >= _level_cards.size():
		return
	var ch: Dictionary = _level_cards[idx]
	world.player.apply_choice(ch)
	world.announce("DEV: " + String(ch.get("title", "upgrade")) + " applied", false)
	_refresh_upgrade_lists()


func _on_open_chest_draft() -> void:
	world.dev_open_chest_draft()


func _on_grant_chest() -> void:
	if _chest_pick.item_count == 0 or _chest_pick.selected < 0:
		return
	var idx: int = int(_chest_pick.get_item_metadata(_chest_pick.selected))
	var pool: Array = []
	pool.append_array(Player.CHEST_WEAPON_IDS)
	pool.append_array(Player.RARE_WEAPON_IDS)
	pool.append_array(Player.LEGENDARY_WEAPON_IDS)
	var wid: String = String(pool[clampi(idx, 0, pool.size() - 1)])
	var msg: String = world.player.apply_chest_weapon(wid)
	world.announce("DEV: " + msg, false)
	_refresh_upgrade_lists()


func _on_boss() -> void:
	world.enemies.spawn_around_id("bone_broker", 1)


func _on_coins() -> void:
	Meta.dev_add_coins(250)
	world.announce("DEV: +250 coins (balance %d)" % Meta.coins, false)


## Numeric-only filter for the custom deposit field (typed digits only; pasted text is stripped).
func _on_coin_field_changed(new_text: String) -> void:
	var filtered := ""
	for ch in new_text:
		if ch >= "0" and ch <= "9":
			filtered += ch
	if filtered != new_text:
		_coin_field.text = filtered
		_coin_field.caret_column = filtered.length()


## Custom currency deposit for Black Market testing. Reuses Meta.dev_add_coins
## (clamps to Meta.MAX_COINS, saves to disk immediately like +250c).
func _on_deposit_custom() -> void:
	if _coin_field == null or _coin_field.text == "":
		world.announce("DEV: type an amount first", false)
		return
	var n: int = int(_coin_field.text)
	if n <= 0:
		world.announce("DEV: type an amount first", false)
		return
	n = mini(n, Meta.MAX_COINS)
	Meta.dev_add_coins(n)
	world.announce("DEV: +%d coins (balance %d)" % [n, Meta.coins], false)


func _on_market_unlock() -> void:
	Meta.dev_set_unlocked(true)
	world.announce("DEV: Black Market unlocked", false)


func _on_market_lock() -> void:
	Meta.dev_set_unlocked(false)
	world.announce("DEV: Black Market locked", false)


func _on_jump_boss() -> void:
	var boss: EnemyDef = DB.enemies.get("bone_broker")
	if boss != null:
		world.run_time = maxf(world.run_time, boss.boss_time - 10.0)


func _on_meta_wipe() -> void:
	Meta.dev_wipe()
	world.announce("DEV: Black Market save wiped", true)


func _on_t30() -> void:
	world.run_time += 30.0


func _on_t60() -> void:
	world.run_time += 60.0


func _on_rate_zero() -> void:
	_mult_slider.value = 0.0
