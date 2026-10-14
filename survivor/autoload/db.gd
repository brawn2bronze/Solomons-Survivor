extends Node
## Content registry. Scans res://data/<kind>/*.tres at startup, so new characters, weapons, passives,
## enemies and upgrades are added by dropping a Resource file in - no code changes.

var characters: Dictionary = {}
var weapons: Dictionary = {}
var passives: Dictionary = {}
var enemies: Dictionary = {}
var upgrades: Dictionary = {}
var market: Dictionary = {}        # Black Market listings (MarketItemDef), by id
var _tex: Dictionary = {}


func _ready() -> void:
    _scan("res://data/characters", characters)
    _scan("res://data/weapons", weapons)
    _scan("res://data/passives", passives)
    _scan("res://data/enemies", enemies)
    _scan("res://data/upgrades", upgrades)
    _scan("res://data/market", market)
    print("DB: %d characters, %d weapons, %d passives, %d enemies, %d upgrades, %d market listings" % [characters.size(), weapons.size(), passives.size(), enemies.size(), upgrades.size(), market.size()])


func _scan(dir_path: String, into: Dictionary) -> void:
    var dir := DirAccess.open(dir_path)
    if dir == null:
        push_error("DB: cannot open %s" % dir_path)
        return
    for f in dir.get_files():
        var fname := f.trim_suffix(".remap")          # exported builds rename resources to *.tres.remap
        if not (fname.ends_with(".tres") or fname.ends_with(".res")):
            continue
        var res = load(dir_path + "/" + fname)
        if res != null and "id" in res and res.id != "":
            into[res.id] = res
        else:
            push_warning("DB: skipped %s/%s" % [dir_path, fname])


func roster() -> Array:
    var arr: Array = characters.values()
    arr.sort_custom(func(a, b): return a.roster_order < b.roster_order)
    return arr


## Selectable right now (menu parade + confirmable in select).
func playable_roster() -> Array:
    var arr: Array = []
    for c in roster():
        if int(c.get("roster_status")) == CharacterDef.RosterStatus.PLAYABLE:
            arr.append(c)
    return arr


## Everything not fully hidden (playable + locked teasers). Character select
## builds its grid from this; HIDDEN ids stay loadable by id for dev/testing.
func visible_roster() -> Array:
    var arr: Array = []
    for c in roster():
        if int(c.get("roster_status")) != CharacterDef.RosterStatus.HIDDEN:
            arr.append(c)
    return arr


## Black Market listings of one MarketItemDef.Kind, in shop order.
func market_items(kind: int) -> Array:
    var arr: Array = []
    for it in market.values():
        if int(it.kind) == kind:
            arr.append(it)
    arr.sort_custom(_market_order)
    return arr


func _market_order(a, b) -> bool:
    if a.sort_order != b.sort_order:
        return a.sort_order < b.sort_order
    return a.id < b.id


func ability(id: String):
    return weapons.get(id, passives.get(id))


func texture(path: String) -> Texture2D:
    if _tex.has(path):
        return _tex[path]
    var t: Texture2D = null
    if ResourceLoader.exists(path):
        t = load(path)
    else:
        push_warning("DB: missing texture %s" % path)
    _tex[path] = t
    return t
