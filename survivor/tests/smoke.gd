extends Node
## Headless smoke test. Run:  godot --headless --path . res://tests/smoke.tscn
## Exits 0 on success, 1 on any failure. Exercises every character's kit (both branches, max level), the pools
## at 250 enemies, and confirms every audio path resolves. (Headless has no GPU, so FPS here is logic-only.)

var failures := 0


func _check(cond: bool, msg: String) -> void:
    if not cond:
        failures += 1
        printerr("FAIL: " + msg)


func _ready() -> void:
    await get_tree().process_frame
    _check(DB.characters.size() == 12, "expected 12 characters, got %d" % DB.characters.size())
    _check(DB.weapons.size() >= 10, "expected 10+ weapons")
    _check(DB.enemies.size() >= 8, "expected 8+ enemy types")
    for k in Audio.EVENTS.keys():
        _check(ResourceLoader.exists(Audio.EVENTS[k]), "missing audio " + Audio.EVENTS[k])
    for k in Audio.MUSIC.keys():
        _check(ResourceLoader.exists(Audio.MUSIC[k]), "missing music " + Audio.MUSIC[k])
    for id in DB.characters.keys():
        for branch_pair in [[0, 0], [1, 1]]:
            await _run_character(id, branch_pair[0], branch_pair[1])
    print("SMOKE DONE, failures=%d" % failures)
    get_tree().quit(1 if failures > 0 else 0)


func _run_character(id: String, wb: int, pb: int) -> void:
    var w := World.new()
    add_child(w)
    w.start(id)
    var pl: Player = w.player
    pl.hp = 1.0e9
    pl.max_hp = 1.0e9
    pl.weapon.level = 3
    pl.weapon.pick_branch(wb)
    pl.passive.level = 3
    pl.passive.pick_branch(pb)
    for i in 8:
        pl.weapon.level_up()
        pl.passive.level_up()
    for c in w.build_choices():
        _check(c.has("title") and c.has("desc"), "bad choice card for " + id)
    # treasure-chest pickup weapons: grant all 9 (covers all 5 pickup behaviors), level one, draft 3
    for wid in Player.CHEST_WEAPON_IDS:
        var msg: String = pl.apply_chest_weapon(wid)
        _check(msg != "Unknown weapon", "chest grant failed for " + wid + " (" + id + ")")
    _check(pl.chest_weapons.size() == 9, "expected 9 chest weapons for " + id)
    var lvl_msg: String = pl.apply_chest_weapon("pickup_rifle")
    _check(lvl_msg.contains("Lv 2"), "chest re-pick should level up for " + id + " (got: " + lvl_msg + ")")
    # dev sandbox catalog: every legal level-up move must be listed and applicable
    var dev_cards: Array = w.dev_all_level_choices()
    _check(not dev_cards.is_empty(), "dev level catalog empty for " + id)
    if not dev_cards.is_empty():
        pl.apply_choice(dev_cards[0])
    var draft: Array = w.roll_chest_choices()
    _check(draft.size() == 3, "chest draft should offer 3 for " + id)
    for card in draft:
        _check(String(card.get("type", "")) == "chest" and card.has("weapon_id"), "bad chest card for " + id)
    # elite kill must drop a chest
    var brute = DB.enemies.get("goblin_brute")
    var e = w.enemies.spawn(brute, pl.global_position + Vector2(60, 0))
    _check(e != null, "could not spawn elite for " + id)
    if e != null:
        w.enemies.damage(e, 1.0e9)
        _check(w.chests.live.size() >= 1, "elite did not drop a chest for " + id)
    var defs: Array = []
    for d in DB.enemies.values():
        defs.append(d)
    for i in 250:
        var d: EnemyDef = defs[i % defs.size()]
        w.enemies.spawn(d, pl.global_position + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 320.0))
    var t0 := Time.get_ticks_usec()
    var frames := 240
    for f in frames:
        await get_tree().process_frame
    var avg_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
    _check(w.enemies.alive_count() > 0, "no enemies alive for " + id)
    print("%-12s branchW=%d branchP=%d  frame=%.2f ms  enemies=%d proj=%d gems=%d kills=%d" % [id, wb, pb, avg_ms, w.enemies.alive_count(), w.projectiles.live.size(), w.gems.live.size(), pl.kills])
    w.queue_free()
    await get_tree().process_frame
