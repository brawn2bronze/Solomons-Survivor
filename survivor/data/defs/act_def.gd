class_name ActDef
extends Resource
## One slice of the 30-minute run. The act boss spawns at the end of the slice;
## the clock and director freeze until the next act begins.
## ambient: ash | glitch | embers | gold (ActAmbient particle preset).

@export var id: String = ""
@export var index: int = 0
@export var display_name: String = "ACT I"
@export var title: String = ""
@export var subtitle: String = ""
@export var clock_start: float = 0.0
@export var boss_id: String = ""
@export var sealed: bool = false           ## authored as data, never playable in the demo
@export var music_key: String = ""
@export var boss_music_key: String = "boss_music"
## Director multipliers ON TOP of the existing time ramp (hp 1+t/240, dmg 1+t/600).
@export var hp_mult: float = 1.0
@export var dmg_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var spawn_rate_mult: float = 1.0
@export var reward_mult: float = 1.0       ## Fragment drop multiplier (min 1, int)
@export var elite_cooldown: float = 60.0   ## min seconds between elite spawns in this act
## Arena palette.
@export var floor_a: Color = Color(0.14, 0.10, 0.20)
@export var floor_b: Color = Color(0.18, 0.12, 0.26)
@export var crack_col: Color = Color(0.05, 0.03, 0.09)
@export var flame_core: Color = Color(0.6, 0.25, 1.0)
@export var flame_glow: Color = Color(0.55, 0.25, 1.0)
@export var glow_col: Color = Color(0.55, 0.25, 1.0)
@export var brazier_bonus: float = 0.0    ## 0..1 extra brazier density
@export var vignette_tint: Color = Color(0.015, 0.02, 0.06)
@export var vignette_pulse: float = 0.0   ## Hz, 0 = off (Act IV gold border pulse)
@export var enemy_tint: Color = Color.WHITE
@export var ambient: String = "ash"       ## ash | glitch | embers | gold
@export var intro_flash: Color = Color(0, 0, 0, 0)
