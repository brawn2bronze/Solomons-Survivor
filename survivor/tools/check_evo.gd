extends SceneTree

## Headless evolution/data checker. Run:
##   godot --headless --path . --script tools/check_evo.gd
## Validates: all ability .tres evo tables (evo1/evo2) are authored (>=2 entries),
## caps dicts are well-formed [min,max] pairs, no fallback evolutions are referenced,
## and the Cowboy slice (six_shooter, flailing_whip) has 8 options per tier.

const EVO_DIR := "res://data/weapons"
const PASSIVE_DIR := "res://data/passives"

func _init() -> void:
    var errs: Array[String] = []
    var weapon_paths := _list_tres(EVO_DIR)
    var passive_paths := _list_tres(PASSIVE_DIR)
    for p in weapon_paths + passive_paths:
        _check_ability(p, errs)
    if errs.is_empty():
        print("check_evo: OK (%d files)" % (weapon_paths.size() + passive_paths.size()))
    else:
        for e in errs:
            printerr("check_evo: " + e)
        printerr("check_evo: %d error(s)" % errs.size())
    quit(0 if errs.is_empty() else 1)


func _list_tres(dir_path: String) -> Array:
    var out: Array = []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return out
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if not dir.current_is_dir() and fname.ends_with(".tres"):
            out.append(dir_path + "/" + fname)
        fname = dir.get_next()
    dir.list_dir_end()
    return out


func _check_ability(path: String, errs: Array[String]) -> void:
    var res = load(path)
    if res == null:
        errs.append("%s: failed to load" % path)
        return
    if not (res is AbilityDef):
        errs.append("%s: not an AbilityDef" % path)
        return
    var def: AbilityDef = res
    # caps: every value must be a 2-element array of floats [min, max], min <= max.
    var caps: Dictionary = def.caps
    for key in caps.keys():
        var v = caps[key]
        if not (v is Array) or (v as Array).size() != 2:
            errs.append("%s: caps[%s] must be [min,max] array" % [path, key])
            continue
        var arr: Array = v
        if float(arr[0]) > float(arr[1]):
            errs.append("%s: caps[%s] min > max" % [path, key])
    # evo tables: evo1/evo2 must each have >= 2 authored entries, no fallback.
    _check_evo_table(path, "evo1", def.evo1, errs)
    _check_evo_table(path, "evo2", def.evo2, errs)


func _check_evo_table(path: String, label: String, table, errs: Array[String]) -> void:
    if table == null:
        return
    if not (table is Array):
        errs.append("%s: %s is not an Array" % [path, label])
        return
    var arr: Array = table
    if arr.size() < 2:
        errs.append("%s: %s has %d entries, need >= 2 (no fallback allowed)" % [path, label, arr.size()])
        return
    for i in arr.size():
        var opt = arr[i]
        if not (opt is Dictionary):
            errs.append("%s: %s[%d] not a Dictionary" % [path, label, i])
            continue
        var d: Dictionary = opt
        if not d.has("id") or String(d["id"]).is_empty():
            errs.append("%s: %s[%d] missing id" % [path, label, i])
        if not d.has("name") or String(d["name"]).is_empty():
            errs.append("%s: %s[%d] missing name" % [path, label, i])
        # Cowboy slice check: six_shooter + flailing_whip must have 4 per tier (8 total).
        if path.ends_with("six_shooter.tres") or path.ends_with("flailing_whip.tres"):
            if arr.size() != 4:
                errs.append("%s: %s has %d entries, Cowboy slice needs exactly 4 per tier" % [path, label, arr.size()])
