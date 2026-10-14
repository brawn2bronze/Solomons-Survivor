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
