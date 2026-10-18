class_name Descent
extends RefCounted
## Loadout checkpoint (Phase 3). Written on Withdraw only, one per hero, and
## consumed by World.start on a Continue run: it restores the saved build at the
## next act's clock start with full HP and fresh Fragment escrow. Rentals are
## excluded (they strip at Withdraw); HP, buffs and run_coins are not stored.
## `world` is untyped throughout (never `:=` on its members).

const SNAP_VERSION := 1
## Snapshot keys (single source; check_project verifies the shape statically).
const KEYS := ["v", "hero", "next_act", "acts_cleared", "level", "xp",
    "weapon", "passive", "chest", "upgrades", "mods",
    "banished", "rerolls", "skips", "banishes", "stock_at_snapshot"]


## Snapshot the live run at the Act Cleared screen. The rented weapon is skipped
## so a one-battle rental never becomes a permanent chest weapon.
static func capture(world) -> Dictionary:
    var pl = world.player
    var chest: Array = []
    for cw in pl.chest_weapons:
        if String(cw.def.id) == String(pl.rented_weapon_id):
            continue
        chest.append(cw.to_dict())
    return {
        "v": SNAP_VERSION,
        "hero": String(pl.def.id),
        "next_act": world.acts.idx + 1,
        "acts_cleared": world.acts.idx,
        "level": pl.level,
        "xp": pl.xp,
        "weapon": pl.weapon.to_dict(),
        "passive": pl.passive.to_dict(),
        "chest": chest,
        "upgrades": pl.upgrade_levels.duplicate(true),
        "mods": pl.mods.duplicate(true),
        "banished": _to_array(world._banished),
        "rerolls": world._rerolls,
        "skips": world._skips,
        "banishes": world._banishes,
        "stock_at_snapshot": Meta.get_utility_stock(),
    }


## Restore a snapshot into a freshly set-up run. Returns false (and the caller
## starts a normal run instead) when the snapshot is unknown or references
## content that no longer exists.
static func restore(world, snap: Dictionary) -> bool:
    if int(snap.get("v", 0)) != SNAP_VERSION:
        push_warning("Descent: unknown checkpoint version; discarding")
        return false
    var pl = world.player
    if String(snap.get("hero", "")) != String(pl.def.id):
        push_warning("Descent: checkpoint hero mismatch; discarding")
        return false
    var nidx: int = int(snap.get("next_act", -1))
    if nidx < 0 or nidx >= DB.acts.size():
        push_warning("Descent: checkpoint act index out of range; discarding")
        return false
    if not (snap.get("weapon") is Dictionary) or not (snap.get("passive") is Dictionary):
        push_warning("Descent: checkpoint kit missing; discarding")
        return false
    var wd: Dictionary = snap.get("weapon")
    var pd: Dictionary = snap.get("passive")
    if String(wd.get("id", "")) != String(pl.weapon.def.id) or String(pd.get("id", "")) != String(pl.passive.def.id):
        push_warning("Descent: checkpoint kit does not match the hero; discarding")
        return false
    var chest_v = snap.get("chest")
    var chest: Array = chest_v if chest_v is Array else []
    for cd in chest:
        if not (cd is Dictionary) or not DB.weapons.has(String((cd as Dictionary).get("id", ""))):
            push_warning("Descent: checkpoint references a missing weapon; discarding")
            return false
    # Kit
    pl.weapon.from_dict(wd)
    pl.passive.from_dict(pd)
    # Stats + draft ranks
    var mods_v = snap.get("mods")
    pl.mods = (mods_v as Dictionary).duplicate(true) if mods_v is Dictionary else {}
    var ups_v = snap.get("upgrades")
    pl.upgrade_levels = (ups_v as Dictionary).duplicate(true) if ups_v is Dictionary else {}
    # Level / XP
    pl.level = maxi(1, int(snap.get("level", 1)))
    pl.xp = maxi(0, int(snap.get("xp", 0)))
    pl.xp_next = Player.xp_for(pl.level)
    # Chest weapons (the rental was excluded at capture)
    for cd in chest:
        var cdict: Dictionary = cd
        pl.apply_chest_weapon(String(cdict.get("id", "")))
        for cw in pl.chest_weapons:
            if String(cw.def.id) == String(cdict.get("id", "")):
                cw.from_dict(cdict)
                break
    pl.refresh()
    pl.hp = pl.max_hp
    # Draft state + Fate top-up from any seal levels bought since the snapshot.
    var gained: int = maxi(0, Meta.get_utility_stock() - int(snap.get("stock_at_snapshot", 0)))
    world._rerolls = int(snap.get("rerolls", 0)) + gained
    world._skips = int(snap.get("skips", 0)) + gained
    world._banishes = int(snap.get("banishes", 0)) + gained
    world._banished.clear()
    var ban_v = snap.get("banished")
    var ban: Array = ban_v if ban_v is Array else []
    for key in ban:
        world._banished.append(String(key))
    return true


static func _to_array(typed: Array) -> Array:
    var out: Array = []
    out.append_array(typed)
    return out
