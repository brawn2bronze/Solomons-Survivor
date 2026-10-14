class_name MarketItemDef
extends Resource
## One Black Market listing. Drop a .tres of this type into res://data/market/ and it appears in the shop - no code changes.
## RENTAL: buy once, start a run with that chest weapon (consumed when a run starts). Name/art come from the weapon.
## MOD: a permanent per-weapon upgrade, owned forever. It applies whenever that weapon enters a run (rental or chest).
## ops use the AbilityDef op format ({"stat": ["mul"|"add"|"set", value]}) and rewrite the weapon's numbers.
## flags are behavior switches/params the weapon behavior reads through Ability.has_mod() / mod_f() (src/abilities/).

enum Kind { RENTAL, MOD }

@export var id: String = ""
@export var kind: int = Kind.RENTAL
@export var weapon_id: String = ""         ## a WeaponDef id from Player.CHEST_WEAPON_IDS
@export var display_name: String = ""      ## MOD only (rentals show the weapon's own name)
@export_multiline var description: String = ""   ## MOD only; keep it under ~95 characters so it fits the card
@export var cost: int = 100                ## coins
@export var sort_order: int = 0
@export var ops: Dictionary = {}
@export var flags: Dictionary = {}
@export var icon: String = ""              ## optional res:// override; empty = the weapon's own icon via AbilityArt
