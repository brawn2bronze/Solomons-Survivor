extends Node
## Engine-side parse sweep: loads every GDScript in the project so the engine analyses
## all of them, including the ones no scene references. A script with a parse error makes
## load() return null and the engine prints the diagnostic with file:line.
## Runs as a SCENE (not --script) so the autoload singletons resolve.
## Run: godot --headless --path . res://tests/script_sweep.tscn

const SKIP_DIRS := ["res://tools/", "res://addons/"]


func _ready() -> void:
    var files := _collect("res://")
    files.sort()
    var failed := 0
    for path in files:
        var res = load(path)
        if res == null or not res.can_instantiate():
            failed += 1
            print("SWEEP FAILED ", path)
    print("SWEEP DONE files=%d failed=%d" % [files.size(), failed])
    get_tree().quit(0)


func _collect(dir_path: String) -> Array:
    var out := []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        return out
    dir.list_dir_begin()
    var entry := dir.get_next()
    while entry != "":
        if not entry.begins_with("."):
            var full := dir_path + entry
            if dir.current_is_dir():
                if not SKIP_DIRS.has(full + "/"):
                    out.append_array(_collect(full + "/"))
            elif entry.ends_with(".gd"):
                out.append(full)
        entry = dir.get_next()
    dir.list_dir_end()
    return out
