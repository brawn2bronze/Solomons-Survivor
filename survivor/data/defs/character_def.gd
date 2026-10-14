class_name CharacterDef
extends Resource
## One playable character. Drop a new .tres of this type into res://data/characters/ and it appears in character select,
## unless roster_status is HIDDEN (dev/test only) or LOCKED_TEASER (silhouette teaser tile).

@export var id: String = ""
@export var display_name: String = ""
@export var title: String = ""
@export var roster_order: int = 99
@export_multiline var blurb: String = ""
@export var sprite: String = ""            ## horizontal strip, 64px cells.
## Standard 6-frame layout: 0-1 ground idle, 2-5 ground run.
## Harpy (frames=8) appends 6-7 fly loop used whenever `flying` is true.
@export var frames: int = 6
@export var frame_size: int = 64
@export var weapon_id: String = ""
@export var passive_id: String = ""
## keys: max_hp, move_speed, damage, defense, regen, area, cooldown, pickup_radius, luck
@export var base_stats: Dictionary = {}
## optional: flying (bool), knockdown_seconds (float), low_hp_scaling ({stat: bonus at 0 HP})
@export var flags: Dictionary = {}
## Roster availability. PLAYABLE = selectable now. LOCKED_TEASER = visible as a
## real-sprite silhouette "???" tile, not selectable (future unlocks flip it to
## PLAYABLE). HIDDEN = excluded from menu parade + character select entirely.
enum RosterStatus { PLAYABLE, LOCKED_TEASER, HIDDEN }
@export var roster_status: int = RosterStatus.PLAYABLE
## Shown on locked-teaser tiles/details instead of the real kit. Later this pairs
## with an unlock condition id (e.g. "survive 25:00 as Cowboy").
@export var unlock_hint: String = ""
@export var color: Color = Color.WHITE
@export var playstyles: Array = []
## Ability-use showcase strips, 5 per character: "base" (pre-branch, used on character
## select + Lv 1-3 cards) + "wA", "wB" (weapon branches) + "pA", "pB" (passive branches).
## Each slot: {"sprite": res:// path, "frames": int, "fps": float}. Empty = silhouette fallback.
## Convention: art/characters/<id>_base.png, <id>_wA.png, <id>_wB.png, <id>_pA.png, <id>_pB.png (64px cells).
@export var ability_anims: Dictionary = {}
