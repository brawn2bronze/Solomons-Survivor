class_name WeaponDef
extends AbilityDef
## Per-weapon FX skins (FX lab part swaps). Empty sprite = procedural fallback
## (today's look), so old .tres files load unchanged. Projectile skin replaces
## the projectile head (trail stays); muzzle skin replaces the muzzle flash +
## streaks (ejected casing stays); arc skin replaces the melee slash-arc bands
## (spark emits stay). Swing life drives the stamp, so arc skins need no life.
## Calibration: fwd/up nudge the skin in aim space (fwd = along aim/travel,
## up = screen-up of aim; px, pre-scale), so art centers on truth without
## re-exporting canvases. proj_fx_trail hides the hardcoded trail when custom
## art carries its own motion read (default true = today's look).
@export var proj_fx_sprite: String = ""
@export var proj_fx_frames: int = 1
@export var proj_fx_fps: float = 8.0
@export var proj_fx_scale: float = 1.0
@export var proj_fx_fwd: float = 0.0
@export var proj_fx_up: float = 0.0
@export var proj_fx_trail: bool = true
@export var muzzle_fx_sprite: String = ""
@export var muzzle_fx_frames: int = 1
@export var muzzle_fx_fps: float = 8.0
@export var muzzle_fx_scale: float = 1.0
@export var muzzle_fx_life: float = 0.12
@export var muzzle_fx_fwd: float = 0.0
@export var muzzle_fx_up: float = 0.0
@export var arc_fx_sprite: String = ""
@export var arc_fx_frames: int = 1
@export var arc_fx_fps: float = 8.0
@export var arc_fx_scale: float = 1.0
