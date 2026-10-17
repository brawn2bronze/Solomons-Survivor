class_name ActManager
extends Node
## The act director: owns the four ActDef slices, the clock hold during boss
## fights, and the act-to-act transitions. Child of World, created in
## World.start() after the player and before enemies.setup.
## Note: boss_slain is a method (World.on_kill calls it); the boss-slain signal
## is named boss_defeated to avoid the name clash.

signal act_changed(idx: int)
signal boss_spawned(def)
signal boss_defeated(def)

var world         # World (untyped ref; never := on its members)
var acts: Array = []
var idx := 0
var clock_held := false
var held_boss_id := ""
var _dev_recheck_t := 0.0


func setup(world_ref) -> void:
    world = world_ref
    acts = DB.acts


func current():
    if idx >= 0 and idx < acts.size():
        return acts[idx]
    return null


func act_at(i: int):
    if i >= 0 and i < acts.size():
        return acts[i]
    return null


func next_act():
    return act_at(idx + 1)


func next_is_playable() -> bool:
    var nxt = next_act()
    return nxt != null and not nxt.sealed


## Which act's slice contains run second t (clamped to the last act).
func act_for_time(t: float) -> int:
    var best := 0
    for i in range(acts.size()):
        if t >= acts[i].clock_start:
            best = i
    return best


func hold_for_boss(def) -> void:
    clock_held = true
    held_boss_id = def.id
    boss_spawned.emit(def)


## Begin act i. set_clock jumps the run clock to the act's clock_start
## (false keeps a dev jump-in clock). First call at run start uses instant
## visuals (no floor tween).
func begin_act(i: int, set_clock := true, instant := false) -> void:
    var clamped := clampi(i, 0, maxi(0, acts.size() - 1))
    var changed: bool = clamped != idx
    idx = clamped
    clock_held = false
    held_boss_id = ""
    var act = current()
    if act == null:
        return
    if set_clock:
        world.run_time = act.clock_start
    world.set_arena_theme(act, instant)
    world._set_music(act.boss_music_key if world.enemies != null and world.enemies.boss_alive() else act.music_key, 3.0)
    if world.act_banner != null:
        world.act_banner.show_act(act)
    if world.act_ambient != null:
        world.act_ambient.set_act(act, instant)
    if not instant and act.intro_flash.a > 0.0:
        world.flash_screen(act.intro_flash, 1.2)
    if changed:
        act_changed.emit(idx)


## The unique act boss died (called from World.on_kill).
## PHASE-2 SHIM: stop music, clear the field, vacuum pickups, then auto-advance.
## Phase 2 replaces this with the Act Cleared screen (Descend / Withdraw).
func boss_slain(def) -> void:
    boss_defeated.emit(def)
    world._set_music("", 1.2)   # empty key resets the poll so the next act's music plays
    world.enemies.wipe_quiet()
    world.gems.attract_all()
    await world.get_tree().create_timer(2.5, true, false, true).timeout
    if next_is_playable():
        begin_act(idx + 1)
    else:
        world.announce("THE FOURTH GATE HOLDS", false)


func _process(delta: float) -> void:
    if world == null or not Game.dev_active or clock_held:
        return
    _dev_recheck_t -= delta
    if _dev_recheck_t > 0.0:
        return
    _dev_recheck_t = 1.0
    var derived := act_for_time(world.run_time)
    if derived != idx:
        begin_act(derived, false)
