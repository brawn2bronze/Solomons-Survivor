class_name EnemyDef
extends Resource
## behavior: chaser | swarm | charger | ranged | boss.  height: 0 ground, 1 air.
## Elites (is_elite) are immune to Raise Dead, get a health ring, and announce themselves with a sting.

@export var id: String = ""
@export var display_name: String = ""
@export var family: String = "goblin"     ## goblin | skeleton | dragon | dinosaur (hit-sound family)
@export var max_hp: float = 10.0
@export var speed: float = 50.0
@export var contact_damage: float = 5.0
@export var xp: int = 1
@export var radius: float = 9.0
@export var sprite: String = ""            ## horizontal strip, frame = 48px
@export var frames: int = 4
@export var behavior: String = "chaser"
@export var height: int = 0
@export var is_elite: bool = false
@export var can_hit_flying: bool = false   ## contact / projectiles can knock a flying player out of the air
@export var hit_event: String = "goblin_hit"
@export var sprite_scale: float = 1.0
@export var spawn_weight: float = 1.0
@export var spawn_start: float = 0.0
@export var spawn_end: float = 9999.0
@export var elite_every: float = 0.0       ## seconds between elite spawns (0 = not an elite event)
@export var shoot_interval: float = 0.0
@export var shoot_speed: float = 0.0
@export var shoot_damage: float = 0.0
## Unique boss events (Black Market): boss_time is the run second it arrives (0 = not a boss), once per run.
## boss_unlock is the Meta unlock granted when it dies ("black_market"). coin_drop is a guaranteed coin jackpot
## (0 = elites drop a default coin shower, everything else rolls the luck-scaled chance).
@export var boss_time: float = 0.0
@export var boss_unlock: String = ""
@export var coin_drop: int = 0
## Boss attack kit (Hellfire Devil): aimed projectile fan + splash, periodic spiral burst, per-def enrage.
## Defaults preserve the stock boss (radial ring, 40% hp enrage, 0.7x cooldown). spiral_every = 0 disables the spiral.
## Spiral emission is quota-paced over spiral_cast_time; spiral_fire_interval is reserved/validated.
@export var projectile_style: String = ""
@export var projectile_count: int = 1
@export var projectile_spread_deg: float = 0.0
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0
@export var splash_falloff: bool = false
@export var spiral_every: int = 0
@export var spiral_projectile_count: int = 0
@export var spiral_turns: float = 1.0
@export var spiral_cast_time: float = 0.75
@export var spiral_fire_interval: float = 0.03
@export var spiral_alternate_direction: bool = false
@export var spiral_projectile_speed: float = 0.0
@export var spiral_projectile_range: float = 0.0
@export var spiral_splash_radius: float = 0.0
@export var spiral_splash_damage: float = 0.0
@export var enrage_hp_fraction: float = 0.4
@export var enrage_interval_mult: float = 0.7
