extends Node
## Global run state, input map, and the "game feel" broker (hit-stop + screen shake requests).

signal shake_requested(amount: float)

# --- DEVELOPER MODE HARD TOGGLE -------------------------------------------
# Set to false to hide DEV MODE completely for shipping builds.
# Location path (as requested): survivor/autoload/game.gd -> DEV_MODE_ENABLED
const DEV_MODE_ENABLED := true

const ZOOM := 2.0                  ## camera zoom: 1280x720 window shows 640x360 world pixels (crisp 2x pixel art)
const VIEW := Vector2(640.0, 360.0)

var selected_character := "cowboy"
var last_result: Dictionary = {}
var _hit_stop_token := 0

# --- Developer / sandbox state (only used when DEV_MODE_ENABLED) ------------
var dev_active := false
var dev_config: Dictionary = {}
var godmode := false
var dev_time_rate := 1.0   # sandbox slow-mo baseline for FX inspection; hit-stop restores to this in dev runs

# --- Game-feel settings (Options panel, persisted). 1.0 = full strength, 0.0 = off. ---
const FX_SETTINGS_PATH := "user://fx_settings.cfg"
var fx_shake := 1.0          ## scales every Game.shake() request
var fx_hitstop := 1.0        ## scales hit-stop duration (0 disables freezes)
var fx_flash := 1.0          ## scales full-screen flashes (World.flash_screen)
var _hs_end_ms := 0          ## real-time msec when the running hit-stop ends
var _time_locked := false    ## death slow-mo owns Engine.time_scale; hit-stops are ignored


## Default sandbox settings. DevMenu edits a copy of this.
## Pre-run covers time/director/locks/survival/spawn so the run starts
## in the desired state; DevOverlay mirrors the same keys live in-game.
func default_dev_config() -> Dictionary:
	return {
		"character": selected_character,
		"allowed_enemies": [],       # empty = normal director pool; else Array of enemy ids
		"elite_only": false,         # if true, only spawn entries with is_elite
		"start_time": 0.0,           # jump-in clock (s); time-triggered events fire from here
		"director_paused": false,    # true = zero director spawns; manual spawns still work
		"no_gems": false,            # block gem + coin drops, wipe field on enable
		"no_levels": false,          # freeze XP, level picker never opens
		"no_treasures": false,       # block elite treasure drops, wipe field on enable
		"godmode": false,            # infinite HP
		"spawn_mult": 1.0,           # director rate multiplier
		"time_rate": 1.0,            # slow-mo baseline for FX inspection (0.1 - 1.0)
	}


func clear_dev() -> void:
	dev_active = false
	dev_config = {}
	godmode = false
	dev_time_rate = 1.0
	Engine.time_scale = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_fx_settings()
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("pause", [KEY_ESCAPE, KEY_P])
	_add_action("ui_confirm", [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## Screen-shake request (scaled by the SHAKE option). World turns it into a decaying camera offset.
func shake(amount: float) -> void:
	if fx_shake <= 0.0:
		return
	shake_requested.emit(amount * fx_shake)


## Freeze-frame. Uses a real-time timer so it isn't slowed by the slowdown it causes.
## Scaled by the HITSTOP option; a shorter request never cuts short a longer freeze already running.
func hit_stop(seconds: float, time_scale: float = 0.04) -> void:
	if get_tree().paused or _time_locked:
		return
	seconds *= fx_hitstop
	if seconds <= 0.0:
		return
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	if end_ms <= _hs_end_ms:
		return
	_hs_end_ms = end_ms
	_hit_stop_token += 1
	var token := _hit_stop_token
	Engine.time_scale = time_scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hit_stop_token:
		Engine.time_scale = dev_time_rate if dev_active else 1.0


## Death slow-mo: takes ownership of the clock so a late hit-stop can't snap it back to 1.0.
## Released by reset_time() (World.start / World._exit_tree).
func lock_time_scale(time_scale: float) -> void:
	_hit_stop_token += 1
	_time_locked = true
	Engine.time_scale = time_scale


func reset_time() -> void:
	_hit_stop_token += 1
	_time_locked = false
	_hs_end_ms = 0
	Engine.time_scale = 1.0


func load_fx_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(FX_SETTINGS_PATH) != OK:
		return
	fx_shake = clampf(float(cf.get_value("fx", "shake", 1.0)), 0.0, 1.0)
	fx_hitstop = clampf(float(cf.get_value("fx", "hitstop", 1.0)), 0.0, 1.0)
	fx_flash = clampf(float(cf.get_value("fx", "flash", 1.0)), 0.0, 1.0)


func save_fx_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("fx", "shake", fx_shake)
	cf.set_value("fx", "hitstop", fx_hitstop)
	cf.set_value("fx", "flash", fx_flash)
	cf.save(FX_SETTINGS_PATH)
