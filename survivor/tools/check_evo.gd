extends SceneTree

## Headless evolution/data checker. Run:
##   godot --headless --path . --script tools/check_evo.gd
## Validates: branch evo tables (evo1/evo2) are 2-per-tier when authored (exactly 2,
## no duplicates), caps dicts are well-formed [min,max] pairs, and each shipped slice
## (six_shooter, flailing_whip, katana, flash_bombs, hand_cannon, pirate_crew, greatsword, prayer) has both
## branches fully authored (2 per tier).

const EVO_DIR := "res://data/weapons"
const PASSIVE_DIR := "res://data/passives"
const SLICE_IDS := ["six_shooter", "flailing_whip", "katana", "flash_bombs", "hand_cannon", "pirate_crew", "greatsword", "prayer"]

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
    # evo tables live per branch: each authored tier must be exactly 2 options.
    var require_full := SLICE_IDS.has(String(def.id))
    var branches = def.branches
    if branches is Array:
        var seen: Dictionary = {}
        for bi in branches.size():
            var br = branches[bi]
            if not (br is Dictionary):
                errs.append("%s: branches[%d] not a Dictionary" % [path, bi])
                continue
            var bd: Dictionary = br
            var bname := String(bd.get("name", str(bi)))
            _check_evo_table(path, "%s/evo1" % bname, bd.get("evo1", []), require_full, seen, errs)
            _check_evo_table(path, "%s/evo2" % bname, bd.get("evo2", []), require_full, seen, errs)


func _check_evo_table(path: String, label: String, table, require_full: bool, seen: Dictionary, errs: Array[String]) -> void:
    if not (table is Array):
        errs.append("%s: %s is not an Array" % [path, label])
        return
    var arr: Array = table
    if arr.is_empty():
        if require_full:
            errs.append("%s: %s has 0 entries (slice requires exactly 2)" % [path, label])
        return
    if arr.size() != 2:
        errs.append("%s: %s has %d entries, need exactly 2" % [path, label, arr.size()])
    for i in arr.size():
        var opt = arr[i]
        if not (opt is Dictionary):
            errs.append("%s: %s[%d] not a Dictionary" % [path, label, i])
            continue
        var d: Dictionary = opt
        var eid := String(d.get("id", ""))
        if eid.is_empty():
            errs.append("%s: %s[%d] missing id" % [path, label, i])
        elif seen.has(eid):
            errs.append("%s: duplicate evo id '%s'" % [path, eid])
        else:
            seen[eid] = true
        if String(d.get("name", "")).is_empty():
            errs.append("%s: %s[%d] missing name" % [path, label, i])
