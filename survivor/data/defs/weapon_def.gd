class_name WeaponDef
extends AbilityDef
## Per-weapon FX skins (FX lab part swaps). Empty sprite = procedural fallback
## (today's look), so old .tres files load unchanged. Projectile skin replaces
## the projectile head (trail stays); muzzle skin replaces the muzzle flash +
## streaks (ejected casing stays).
@export var proj_fx_sprite: String = ""
@export var proj_fx_frames: int = 1
@export var proj_fx_fps: float = 8.0
@export var proj_fx_scale: float = 1.0
@export var muzzle_fx_sprite: String = ""
@export var muzzle_fx_frames: int = 1
@export var muzzle_fx_fps: float = 8.0
@export var muzzle_fx_scale: float = 1.0
@export var muzzle_fx_life: float = 0.12
