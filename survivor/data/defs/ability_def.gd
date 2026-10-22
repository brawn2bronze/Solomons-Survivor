class_name AbilityDef
extends Resource
## Shared shape for weapons and passives.
## base: numeric stats. level_scaling: ops applied (level-1) times.
## branches: exactly two dictionaries {id,name,desc,on_pick,per_level,flags}. Op format: {"stat": ["mul"|"add"|"set", value]}
## Each branch may carry optional evo1/evo2 evolution pairs (tier at 8 / tier at 16):
## two {name,desc,ops,ops2?,ops3?,flags} dicts each. Missing = generated fallback.
## rarity (weapons only, passives ignore): 0 common, 1 rare, 2 legendary. Old .tres without the key load as COMMON.

enum Rarity { COMMON = 0, RARE = 1, LEGENDARY = 2 }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var behavior: String = ""          ## key into WeaponBehaviors / PassiveBehaviors (res://src/abilities/)
@export var audio_event: String = ""       ## key in AudioManager.EVENTS
@export var base: Dictionary = {}
@export var branches: Array = []
@export var level_scaling: Dictionary = {}
@export var max_level: int = 8
@export var color: Color = Color.WHITE
## Card/HUD art. icon is a res:// path (single image or horizontal strip of icon_frames cells).
## preview_kind: "none" | "static" | "spin" | "pulse" — card use-preview motion for single-frame art.
## anims: branch/phase slot -> {"sprite": path, "frames": int, "fps": float}. Slots: "base", "wA", "wB", "pA", "pB".
@export var icon: String = ""
@export var icon_frames: int = 1
@export var icon_fps: float = 8.0
@export var preview_kind: String = "none"
@export var anims: Dictionary = {}
## Chest-weapon rarity + legendary gate. Commons ignore both. Rares ignore unlock_hint.
@export var rarity: int = 0
@export var unlock_hint: String = ""
## Post-evolution milestones for kit abilities (levels 9-16). Optional; empty =
## filler bumps only. Entries: {"level": int, "ops": {stat: ["mul"|"add"|"set", value]},
## "flags": {}}. Applied cumulatively once `level` is reached. Pickup (chest)
## weapons never read this: their evolution path is the Black Market mods.
@export var branch_milestones: Array = []
@export var caps: Dictionary = {}
