class_name AbilityArt
extends RefCounted
## Single place for the "what art does this card/HUD slot use" rule.
## Real art comes from AbilityDef.icon (+ branch anims slots); anything missing
## falls back to the grey silhouettes so unfinished weapons/passives/upgrades
## still render. Weapon strips use square cells (64px, or 32px for shuriken/caltrops);
## status icons are 32px. Cell width is always derived from the loaded texture.

const WEAPON_FALLBACK := "res://art/placeholders/silhouette_weapon.png"
const PASSIVE_FALLBACK := "res://art/placeholders/silhouette_passive.png"
const UPGRADE_FALLBACK := "res://art/placeholders/silhouette_upgrade.png"

const STATUS_STUN := "res://art/status/stun.png"
const STATUS_POISON := "res://art/status/poison.png"
const STATUS_BURN := "res://art/status/burn.png"
const STATUS_FEAR := "res://art/status/fear.png"
const STATUS_RAGE := "res://art/status/rage.png"
const STATUS_INFECTED := "res://art/status/infected.png"
const STATUS_NUTRIENT := "res://art/status/nutrient.png"


## Resolved card art for an ability def (+ optional branch index).
## Returns {"path": String, "frames": int, "fps": float, "preview": String, "fallback": bool}.
static func icon_for_ability(def, branch: int = -1) -> Dictionary:
    # NOTE: direct property access (not def.get with a default): Object.get()
    # takes no default arg, and every def carries these exports since Loop 2.
    var path := String(def.icon)
    var frames := maxi(1, int(def.icon_frames))
    var fps := float(def.icon_fps)
    var preview := String(def.preview_kind)
    var is_weapon := def is WeaponDef
    # Branch-specific ability-use strip overrides the base icon once picked.
    if branch >= 0:
        var slot := _branch_slot(def, branch)
        var anims: Dictionary = def.anims
        if anims.has(slot):
            var a: Dictionary = anims[slot]
            path = String(a.get("sprite", path))
            frames = maxi(1, int(a.get("frames", frames)))
            fps = float(a.get("fps", fps))
            preview = "static"
    var fallback := false
    if path == "":
        fallback = true
        preview = "static"
        if is_weapon:
            path = WEAPON_FALLBACK
        else:
            path = PASSIVE_FALLBACK
    return {"path": path, "frames": frames, "fps": fps, "preview": preview, "fallback": fallback}


static func icon_for_upgrade(up) -> Dictionary:
    var path := String(up.icon)
    var fallback := false
    if path == "":
        fallback = true
        path = UPGRADE_FALLBACK
    return {"path": path, "frames": 1, "fps": 8.0, "preview": "static", "fallback": fallback}


## Per-character sprite overrides, read off <prefix>_sprite/frames/fps/life/scale/
## offset/tint/loops fields of the def. Empty sprite = fallback/no-op for the
## caller (kill keeps its procedural flourish, attack draws nothing extra).
## Returns {"path", "frames", "fps", "life", "scale", "offset", "tint", "loops", "fallback"}.
static func _for_fx(def, prefix: String) -> Dictionary:
    var path: String = String(def.get(prefix + "_sprite"))
    var frames: int = maxi(1, int(def.get(prefix + "_frames")))
    var fps: float = maxf(1.0, float(def.get(prefix + "_fps")))
    var life: float = maxf(0.05, float(def.get(prefix + "_life")))
    var scale: float = maxf(0.1, float(def.get(prefix + "_scale")))
    var offset: Vector2 = def.get(prefix + "_offset")
    var tint: Color = def.get(prefix + "_tint")
    var loops: int = maxi(0, int(def.get(prefix + "_loops")))
    var fallback: bool = path == ""
    return {"path": path, "frames": frames, "fps": fps, "life": life, "scale": scale, "offset": offset, "tint": tint, "loops": loops, "fallback": fallback}


## Kill-signature sprite override for a character def. Empty kill_fx_sprite = procedural fallback.
static func for_kill(def) -> Dictionary:
    return _for_fx(def, "kill_fx")


## Attack-flourish sprite override for a character def. Empty atk_fx_sprite = no flourish.
static func for_attack(def) -> Dictionary:
    return _for_fx(def, "atk_fx")


## Projectile skin for a weapon def. Empty proj_fx_sprite = procedural fallback
## (today's per-kind head). Shape matches _for_fx; "life"/"loops" unused.
static func weapon_proj_skin(wdef) -> Dictionary:
    return _weapon_fx(wdef, "proj_fx", 0.28)


## Muzzle-flash skin for a weapon def. Empty muzzle_fx_sprite = procedural
## fallback (flash disc + streaks + casing). Played via kill_sprite.
static func weapon_muzzle_skin(wdef) -> Dictionary:
    return _weapon_fx(wdef, "muzzle_fx", 0.12)


## Melee arc skin for a weapon def. Empty arc_fx_sprite = procedural fallback
## (the three slash-arc bands). Stamp geometry (offset/rotation/scale/life)
## is fitted to the swing by fx.slash_arc; "life"/"loops" unused here.
static func weapon_arc_skin(wdef) -> Dictionary:
    return _weapon_fx(wdef, "arc_fx", 0.2)


static func _weapon_fx(wdef, prefix: String, default_life: float) -> Dictionary:
    if wdef == null:
        return {"path": "", "frames": 1, "fps": 8.0, "life": default_life, "scale": 1.0, "offset": Vector2.ZERO, "fwd": 0.0, "up": 0.0, "trail": true, "tint": Color.WHITE, "loops": 1, "fallback": true}
    var path: String = String(wdef.get(prefix + "_sprite"))
    var fwd := 0.0
    var up := 0.0
    var trail := true
    if prefix == "proj_fx" or prefix == "muzzle_fx":
        fwd = float(wdef.get(prefix + "_fwd"))
        up = float(wdef.get(prefix + "_up"))
    if prefix == "proj_fx":
        trail = bool(wdef.get("proj_fx_trail"))
    return {
        "path": path,
        "frames": maxi(1, int(wdef.get(prefix + "_frames"))),
        "fps": maxf(1.0, float(wdef.get(prefix + "_fps"))),
        "life": maxf(0.05, float(wdef.get(prefix + "_life")) if prefix == "muzzle_fx" else default_life),
        "scale": maxf(0.1, float(wdef.get(prefix + "_scale"))),
        "offset": Vector2.ZERO,
        "fwd": fwd,
        "up": up,
        "trail": trail,
        "tint": Color.WHITE,
        "loops": 1,
        "fallback": path == "",
    }


static func _branch_slot(def, branch: int) -> String:
    var suffix := "A" if branch == 0 else "B"
    if def is WeaponDef:
        return "w" + suffix
    return "p" + suffix


## Frame region for cell `idx` of a horizontal strip. Cell width is derived
## from the loaded texture so 64px weapons and 32px icons share one path.
static func frame_region(tex: Texture2D, frames: int, idx: int) -> Rect2:
    if tex == null or frames <= 1:
        var s := tex.get_size() if tex != null else Vector2(64, 64)
        return Rect2(Vector2.ZERO, s)
    var cell := tex.get_size().x / float(frames)
    var h := tex.get_size().y
    return Rect2(Vector2(cell * float(idx % frames), 0), Vector2(cell, h))
