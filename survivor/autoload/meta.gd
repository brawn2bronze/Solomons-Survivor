extends Node
## Persistent meta-progression: the coin balance, the Black Market unlock, one-run weapon rentals and permanent weapon mods.
## Everything saves to user://save.cfg (ConfigFile, plain text). One section per feature, so later features (the roster
## unlock plan in workbench.md section 11) can share the file: this singleton preserves sections it does not own.
## Gameplay code only talks to this singleton: Meta.add_coins(), Meta.mod_items_for(), Meta.consume_armed_rental(), ...

signal coins_changed(total: int)
signal market_unlocked_changed
signal loadout_changed
signal seal_changed
signal bestiary_updated(enemy_id: String)
signal hero_seal_changed(hero_id: String)

const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 1
const MAX_COINS := 9999999
const MAX_RENTAL_STOCK := 5            ## most rentals of one weapon you can hold at once
const AUTOSAVE_SECONDS := 12.0         ## coin pickups are batched; purchases/unlocks/run end save immediately
const UNLOCK_MARKET := "black_market" ## EnemyDef.boss_unlock key that opens the Black Market

const SEC_META := "meta"
const SEC_MARKET := "market"
const SEC_RENTALS := "rentals"
const SEC_BESTIARY := "bestiary"
const SEC_SEAL := "seal"
const SEC_HERO_SEALS := "hero_seals"

var coins := 0
var market_unlocked := false
var armed_rental := ""                  ## weapon id the next run starts with ("" = none)
var rentals: Dictionary = {}            ## weapon id -> stock held (int)
var owned_mods: Array[String] = []      ## MarketItemDef ids (unknown ids are kept so a save survives a removed listing)
var _bestiary: Dictionary = {}          ## enemy id -> lifetime kills (int)
var _seal_upgrades: Dictionary = {}     ## seal node id -> level (int)
var _hero_seals: Dictionary = {}        ## hero id -> { seal node id -> level (int) }
var _loaded_version := SAVE_VERSION
var _dirty := false
var _dirty_t := 0.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    load_save()


func _process(delta: float) -> void:
    if not _dirty:
        return
    _dirty_t -= delta
    if _dirty_t <= 0.0:
        save()


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        flush()


# ------------------------------------------------------------------ persistence
func load_save() -> void:
    _reset_state()
    var cfg := ConfigFile.new()
    var err: int = cfg.load(SAVE_PATH)
    if err == ERR_FILE_NOT_FOUND:
        return
    if err != OK:
        push_warning("Meta: %s is unreadable (error %d); keeping a .corrupt copy and starting fresh" % [SAVE_PATH, err])
        DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".corrupt")
        return
    _loaded_version = _as_int(cfg.get_value(SEC_META, "version", SAVE_VERSION), SAVE_VERSION)
    if _loaded_version > SAVE_VERSION:
        push_warning("Meta: save version %d is newer than this build (%d); known fields are read, the rest is preserved" % [_loaded_version, SAVE_VERSION])
    coins = clampi(_as_int(cfg.get_value(SEC_MARKET, "coins", 0), 0), 0, MAX_COINS)
    market_unlocked = _as_bool(cfg.get_value(SEC_MARKET, "unlocked", false))
    var armed: Variant = cfg.get_value(SEC_MARKET, "armed_rental", "")
    if typeof(armed) == TYPE_STRING:
        armed_rental = String(armed)
    var raw_mods: Variant = cfg.get_value(SEC_MARKET, "mods", [])
    if raw_mods is Array:
        for m in raw_mods as Array:
            var mid: String = String(m)
            if mid != "" and not owned_mods.has(mid):
                owned_mods.append(mid)
    if cfg.has_section(SEC_RENTALS):
        for key in cfg.get_section_keys(SEC_RENTALS):
            var n: int = clampi(_as_int(cfg.get_value(SEC_RENTALS, key, 0), 0), 0, MAX_RENTAL_STOCK)
            if n > 0:
                rentals[String(key)] = n
    if armed_rental != "" and rental_count(armed_rental) <= 0:
        armed_rental = ""
    var raw_best: Variant = cfg.get_value(SEC_BESTIARY, "kills", {})
    if raw_best is Dictionary:
        for key in (raw_best as Dictionary).keys():
            var kills: int = maxi(0, _as_int((raw_best as Dictionary)[key], 0))
            if kills > 0:
                _bestiary[String(key)] = kills
    var raw_seal: Variant = cfg.get_value(SEC_SEAL, "levels", {})
    if raw_seal is Dictionary:
        for key in (raw_seal as Dictionary).keys():
            var lvl: int = maxi(0, _as_int((raw_seal as Dictionary)[key], 0))
            if lvl > 0:
                _seal_upgrades[String(key)] = lvl
    var raw_hero: Variant = cfg.get_value(SEC_HERO_SEALS, "data", {})
    if raw_hero is Dictionary:
        for hero_id in (raw_hero as Dictionary).keys():
            var tree: Variant = (raw_hero as Dictionary)[hero_id]
            if not tree is Dictionary:
                continue
            var clean: Dictionary = {}
            for node_id in (tree as Dictionary).keys():
                var hlvl: int = maxi(0, _as_int((tree as Dictionary)[node_id], 0))
                if hlvl > 0:
                    clean[String(node_id)] = hlvl
            if not clean.is_empty():
                _hero_seals[String(hero_id)] = clean


func save() -> bool:
    _dirty = false
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        cfg = ConfigFile.new()          # missing or unreadable: write a clean file
    cfg.set_value(SEC_META, "version", maxi(_loaded_version, SAVE_VERSION))
    cfg.set_value(SEC_MARKET, "coins", coins)
    cfg.set_value(SEC_MARKET, "unlocked", market_unlocked)
    cfg.set_value(SEC_MARKET, "armed_rental", armed_rental)
    var mod_list: Array = []
    mod_list.append_array(owned_mods)   # plain Array: typed-array syntax in a .cfg is needlessly fragile
    cfg.set_value(SEC_MARKET, "mods", mod_list)
    if cfg.has_section(SEC_RENTALS):
        cfg.erase_section(SEC_RENTALS)
    for wid in rentals.keys():
        cfg.set_value(SEC_RENTALS, String(wid), int(rentals[wid]))
    cfg.set_value(SEC_BESTIARY, "kills", _bestiary)
    cfg.set_value(SEC_SEAL, "levels", _seal_upgrades)
    cfg.set_value(SEC_HERO_SEALS, "data", _hero_seals)
    # Write to a temp file first so a crash mid-write can never leave a half-written save.
    var tmp: String = SAVE_PATH + ".tmp"
    var err: int = cfg.save(tmp)
    if err == OK:
        err = DirAccess.rename_absolute(tmp, SAVE_PATH)
    if err != OK:
        err = cfg.save(SAVE_PATH)
    if err != OK:
        push_warning("Meta: could not write %s (error %d); will retry" % [SAVE_PATH, err])
        _mark_dirty()
        return false
    return true


## Save now if anything is pending (run end, quit, focus loss).
func flush() -> void:
    if _dirty:
        save()


func _mark_dirty() -> void:
    if not _dirty:
        _dirty = true
        _dirty_t = AUTOSAVE_SECONDS


func _reset_state() -> void:
    coins = 0
    market_unlocked = false
    armed_rental = ""
    rentals.clear()
    owned_mods.clear()
    _bestiary.clear()
    _seal_upgrades.clear()
    _hero_seals.clear()
    _loaded_version = SAVE_VERSION
    _dirty = false


func _as_int(v: Variant, fallback: int) -> int:
    if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
        return int(v)
    return fallback


func _as_bool(v: Variant) -> bool:
    if typeof(v) == TYPE_BOOL:
        return bool(v)
    if typeof(v) == TYPE_INT:
        return int(v) != 0
    return false


# ------------------------------------------------------------------ coins
func add_coins(n: int) -> void:
    if n <= 0:
        return
    coins = mini(MAX_COINS, coins + n)
    _mark_dirty()
    coins_changed.emit(coins)


func can_afford(cost: int) -> bool:
    return coins >= cost


# ------------------------------------------------------------------ unlock
func unlock_market() -> bool:
    if market_unlocked:
        return false
    market_unlocked = true
    save()
    market_unlocked_changed.emit()
    return true


## Menu hint while locked, built from whichever EnemyDef carries the unlock.
func unlock_hint() -> String:
    for def in DB.enemies.values():
        if String(def.boss_unlock) == UNLOCK_MARKET:
            var secs: int = int(def.boss_time)
            return "Slay %s (%02d:%02d) to unlock" % [def.display_name, secs / 60, secs % 60]
    return "Defeat the boss to unlock"


# ------------------------------------------------------------------ purchases
## Buy a listing (rental or mod). Returns false when locked, unknown, unaffordable, already owned or at the stock cap.
func buy_item(item_id: String) -> bool:
    if not market_unlocked:
        return false
    var item: MarketItemDef = DB.market.get(item_id)
    if item == null or not DB.weapons.has(item.weapon_id):
        return false
    if item.kind == MarketItemDef.Kind.MOD:
        if owns_mod(item_id):
            return false
    elif rental_count(item.weapon_id) >= MAX_RENTAL_STOCK:
        return false
    var price := get_market_price(item.cost)
    if coins < price:
        return false
    coins -= price
    if item.kind == MarketItemDef.Kind.MOD:
        owned_mods.append(item_id)
    else:
        rentals[item.weapon_id] = rental_count(item.weapon_id) + 1
        armed_rental = item.weapon_id   # you bought it to use it: the newest rental is the armed one
    save()
    coins_changed.emit(coins)
    loadout_changed.emit()
    return true


func owns_mod(item_id: String) -> bool:
    return owned_mods.has(item_id)


## Owned MOD listings for one weapon, in a stable order (merged into the weapon by Ability.set_mods).
func mod_items_for(weapon_id: String) -> Array:
    var out: Array = []
    for mid in owned_mods:
        var item: MarketItemDef = DB.market.get(mid)
        if item != null and item.kind == MarketItemDef.Kind.MOD and item.weapon_id == weapon_id:
            out.append(item)
    out.sort_custom(_by_order)
    return out


## How many owned mods still exist as listings (the progress bar numerator).
func owned_mod_count() -> int:
    var n := 0
    for mid in owned_mods:
        var item: MarketItemDef = DB.market.get(mid)
        if item != null and item.kind == MarketItemDef.Kind.MOD:
            n += 1
    return n


func _by_order(a: MarketItemDef, b: MarketItemDef) -> bool:
    if a.sort_order != b.sort_order:
        return a.sort_order < b.sort_order
    return a.id < b.id


# ------------------------------------------------------------------ rentals
func rental_count(weapon_id: String) -> int:
    return int(rentals.get(weapon_id, 0))


func arm_rental(weapon_id: String) -> bool:
    if rental_count(weapon_id) <= 0:
        return false
    armed_rental = weapon_id
    save()
    loadout_changed.emit()
    return true


func disarm_rental() -> void:
    armed_rental = ""
    save()
    loadout_changed.emit()


## Called once when a run starts. Spends one rental of the armed weapon and returns its id ("" = none armed).
func consume_armed_rental() -> String:
    var wid: String = armed_rental
    if wid == "":
        return ""
    if rental_count(wid) <= 0 or not DB.weapons.has(wid):
        armed_rental = ""
        save()
        return ""
    var left: int = rental_count(wid) - 1
    if left > 0:
        rentals[wid] = left
    else:
        rentals.erase(wid)
        armed_rental = ""
    save()
    loadout_changed.emit()
    return wid


# ------------------------------------------------------------------ bestiary (Ars Goetia) + seal tree (Solomon's Seal)
const BESTIARY_CATALOGUE_KILLS := 50

func note_kill(enemy_id: String) -> void:
    if enemy_id == "":
        return
    _bestiary[enemy_id] = int(_bestiary.get(enemy_id, 0)) + 1
    _mark_dirty()
    bestiary_updated.emit(enemy_id)


func get_kills(enemy_id: String) -> int:
    return int(_bestiary.get(enemy_id, 0))


func catalogued_count() -> int:
    var req := get_catalogue_requirement()
    var n := 0
    for id in _bestiary:
        if int(_bestiary[id]) >= req:
            n += 1
    return n


## Sum of stat_value * level across all owned seal nodes sharing one stat_hook.
## Per-node values stay in get_seal_bonus(node_id); this is the per-hook aggregate
## used by gameplay (damage, max_hp, crit_chance, xp_gain, market_discount, ...).
func get_total_seal_bonus(hook_name: String) -> float:
    var total := 0.0
    for node_id in _seal_upgrades:
        var lvl := int(_seal_upgrades[node_id])
        if lvl <= 0:
            continue
        var data: Dictionary = GlobalSealData.get_node_data(node_id)
        if data.is_empty():
            continue
        if String(data.get("stat_hook", "")) == hook_name:
            total += float(data.get("stat_value", 0.0)) * lvl
    return total


## Dynamic bestiary catalogue threshold (Scholar's Focus reduces it, floor 20).
func get_catalogue_requirement() -> int:
    var reduction := int(get_total_seal_bonus("bestiary_req_reduction"))
    return maxi(20, BESTIARY_CATALOGUE_KILLS - reduction)


## Read-only view of owned seal levels (screens use this; never touch _seal_upgrades directly).
func get_seal_levels() -> Dictionary:
    return _seal_upgrades.duplicate()


func are_seal_prereqs_met(node_id: String) -> bool:
    return GlobalSealData.are_prereqs_met(node_id, _seal_upgrades)


## Discounted market price (Asmodeus's Bargain). Always compute from base at call
## time; never mutate item.cost in place. Floor of 1 fragment.
func get_market_price(base_price: int) -> int:
    var discount := get_total_seal_bonus("market_discount")
    var final_price := int(float(base_price) * (1.0 - discount))
    return maxi(1, final_price)


func get_bestiary_bonus(stat: String) -> float:
    var catalogued := catalogued_count()
    if stat == "move_speed":
        return catalogued * 0.005
    if stat == "damage":
        return catalogued * 0.01
    return 0.0


func get_seal_level(node_id: String) -> int:
    return int(_seal_upgrades.get(node_id, 0))


func get_seal_bonus(node_id: String) -> float:
    var lvl := get_seal_level(node_id)
    if lvl <= 0:
        return 0.0
    match node_id:
        "reinforced_walls":
            return -0.05 * lvl
        "enhanced_bindings":
            return 0.02 * lvl
        "temporal_loops":
            return 0.10 * lvl
        "demons_folly":
            return 0.05 * lvl
    var data: Dictionary = GlobalSealData.get_node_data(node_id)
    if not data.is_empty():
        return float(data.get("stat_value", 0.0)) * lvl
    return 0.0


## Draft-utility stock (Fate branch, §30): +1 per level on EACH Fate node, so a
## full clear (root 3 + mid 2 + tip 1) starts the run with 6 rerolls, skips and
## banishes each. Run-local spending lives in World; nothing here is mutated.
func get_utility_stock() -> int:
    var stock := 0
    for node_id in ["fates_intercession", "threads_of_fortune", "moirais_shears"]:
        stock += get_seal_level(node_id)
    return stock


func purchase_seal(node_id: String) -> bool:
    if node_id == "":
        return false
    if GlobalSealData.get_node_data(node_id).is_empty():
        return false
    var current_lvl := get_seal_level(node_id)
    var cost := GlobalSealData.get_cost(node_id, current_lvl)
    if cost < 0:
        return false
    if coins < cost:
        return false
    if not GlobalSealData.are_prereqs_met(node_id, _seal_upgrades):
        return false
    coins -= cost
    _seal_upgrades[node_id] = current_lvl + 1
    save()
    coins_changed.emit(coins)
    seal_changed.emit()
    return true


func get_hero_seal_level(hero_id: String, node_id: String) -> int:
    if not _hero_seals.has(hero_id):
        return 0
    return int((_hero_seals[hero_id] as Dictionary).get(node_id, 0))


func get_hero_seals(hero_id: String) -> Dictionary:
    return _hero_seals.get(hero_id, {})


func purchase_hero_seal(hero_id: String, node_id: String) -> bool:
    if hero_id == "" or node_id == "":
        return false
    var current_lvl := get_hero_seal_level(hero_id, node_id)
    var cost := HeroSealData.get_hero_cost(hero_id, node_id, current_lvl)
    if cost < 0:
        return false
    if HeroSealData.get_hero_node_data(hero_id, node_id).is_empty():
        return false
    if coins < cost:
        return false
    var hero_levels: Dictionary = _hero_seals.get(hero_id, {})
    var node_data: Dictionary = HeroSealData.get_hero_node_data(hero_id, node_id)
    for prereq in node_data.get("prerequisites", []):
        if int(hero_levels.get(prereq, 0)) <= 0:
            return false
    coins -= cost
    if not _hero_seals.has(hero_id):
        _hero_seals[hero_id] = {}
    (_hero_seals[hero_id] as Dictionary)[node_id] = current_lvl + 1
    save()
    coins_changed.emit(coins)
    hero_seal_changed.emit(hero_id)
    return true


# ------------------------------------------------------------------ dev sandbox (DevOverlay)
func dev_add_coins(n: int) -> void:
    add_coins(n)
    flush()


func dev_set_unlocked(on: bool) -> void:
    market_unlocked = on
    save()
    market_unlocked_changed.emit()


func dev_wipe() -> void:
    _reset_state()
    save()
    coins_changed.emit(coins)
    market_unlocked_changed.emit()
    loadout_changed.emit()
    seal_changed.emit()
    hero_seal_changed.emit("")
