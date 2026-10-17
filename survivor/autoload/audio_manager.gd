extends Node
## Central audio hub. Gameplay code only ever calls Audio.sfx("event_key") / Audio.music("track_key").
## Every placeholder file lives at the exact path below - overwrite the file, keep the name, done.

const EVENTS := {
    # weapons
    "revolver_shot": "res://audio/weapons/revolver_shot.wav",
    "katana_slash": "res://audio/weapons/katana_slash.wav",
    "hand_cannon": "res://audio/weapons/hand_cannon.wav",
    "whip_crack": "res://audio/weapons/whip_crack.wav",
    "greatsword_swing": "res://audio/weapons/greatsword_swing.wav",
    "lightning_bolt": "res://audio/weapons/lightning_bolt.wav",
    "fang_bite": "res://audio/weapons/fang_bite.wav",
    "horn_swipe": "res://audio/weapons/horn_swipe.wav",
    "screech": "res://audio/weapons/screech.wav",
    "skull_projectile": "res://audio/weapons/skull_projectile.wav",
    "goose_charge": "res://audio/weapons/goose_charge.wav",
    # enemies
    "goblin_hit": "res://audio/enemies/goblin_hit.wav",
    "skeleton_hit": "res://audio/enemies/skeleton_hit.wav",
    "dragon_hit": "res://audio/enemies/dragon_hit.wav",
    "dinosaur_hit": "res://audio/enemies/dinosaur_hit.wav",
    "enemy_death": "res://audio/enemies/enemy_death.wav",
    "elite_enemy_spawn": "res://audio/enemies/elite_enemy_spawn.wav",
    # player
    "player_hit": "res://audio/player/player_hit.wav",
    "player_death": "res://audio/player/player_death.wav",
    "xp_pickup": "res://audio/player/xp_pickup.wav",
    "level_up": "res://audio/player/level_up.wav",
    "character_select": "res://audio/player/character_select.wav",
    "coin_pickup": "res://audio/player/coin_pickup.wav",
    "frog_fart": "res://audio/player/frog-fart.wav",
    # ui
    "button_click": "res://audio/ui/button_click.wav",
    "menu_open": "res://audio/ui/menu_open.wav",
    "menu_close": "res://audio/ui/menu_close.wav",
    "upgrade_selected": "res://audio/ui/upgrade_selected.wav",
    "market_unlock": "res://audio/ui/market_unlock.wav",
    "market_purchase": "res://audio/ui/market_purchase.wav",
}
const MUSIC := {
    "ambient_loop": "res://audio/music/ambient_loop.ogg",
    "boss_music": "res://audio/music/boss_music.ogg",
    "menu_music": "res://audio/music/menu_music.ogg",
    "act1_orchestral": "res://audio/music/act1_orchestral.ogg",
    "act2_glitch": "res://audio/music/act2_glitch.ogg",
    "act3_choir": "res://audio/music/act3_choir.ogg",
    "act4_lucifer": "res://audio/music/act4_lucifer.ogg",
}
## Minimum seconds between two plays of the same event (stops 200 enemy hits per second turning into noise).
const MIN_GAP := {
    "goblin_hit": 0.045, "skeleton_hit": 0.045, "dragon_hit": 0.07, "dinosaur_hit": 0.06, "enemy_death": 0.035,
    "xp_pickup": 0.02, "coin_pickup": 0.03, "revolver_shot": 0.04, "fang_bite": 0.05, "whip_crack": 0.08,
}
const VOICES := 20
const SETTINGS_PATH := "user://settings.cfg"
const BUS_NAMES := {"master": "Master", "music": "Music", "sfx": "SFX"}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _missing_warned: Dictionary = {}
var _last_played: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_key := ""
var volume := {"master": 0.8, "music": 0.6, "sfx": 0.9}
var _xp_combo := 0
var _xp_combo_t := 0.0
var _coin_combo := 0
var _coin_combo_t := 0.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _ensure_bus("Music")
    _ensure_bus("SFX")
    for i in VOICES:
        var p := AudioStreamPlayer.new()
        p.bus = "SFX"
        add_child(p)
        _players.append(p)
    _music_a = _make_music_player()
    _music_b = _make_music_player()
    load_settings()


func _process(delta: float) -> void:
    _xp_combo_t -= delta
    if _xp_combo_t <= 0.0:
        _xp_combo = 0
    _coin_combo_t -= delta
    if _coin_combo_t <= 0.0:
        _coin_combo = 0


func _ensure_bus(bus_name: String) -> void:
    if AudioServer.get_bus_index(bus_name) == -1:
        AudioServer.add_bus()
        var idx := AudioServer.bus_count - 1
        AudioServer.set_bus_name(idx, bus_name)
        AudioServer.set_bus_send(idx, "Master")


func _make_music_player() -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.bus = "Music"
    p.volume_db = -80.0
    add_child(p)
    return p


func _load(path: String) -> AudioStream:
    if _cache.has(path):
        return _cache[path]
    if not ResourceLoader.exists(path):
        if not _missing_warned.has(path):
            _missing_warned[path] = true
            push_warning("Audio: missing file %s (drop a real one in, same name)" % path)
        _cache[path] = null
        return null
    var s: AudioStream = load(path)
    _cache[path] = s
    return s


## Play a one-shot. pitch_var randomises pitch a little so repeats don't sound machine-gunned.
func sfx(event: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_var: float = 0.06) -> void:
    if not EVENTS.has(event):
        push_warning("Audio: unknown event '%s'" % event)
        return
    var now := Time.get_ticks_msec() / 1000.0
    var gap: float = MIN_GAP.get(event, 0.0)
    if gap > 0.0 and now - float(_last_played.get(event, -9.0)) < gap:
        return
    _last_played[event] = now
    var stream := _load(EVENTS[event])
    if stream == null:
        return
    var p := _players[_next]
    _next = (_next + 1) % VOICES
    p.stream = stream
    p.volume_db = volume_db
    p.pitch_scale = maxf(0.1, pitch + randf_range(-pitch_var, pitch_var))
    p.play()


## XP pickups rise in pitch while you keep collecting - the classic "vacuum" feel.
## count lets GemManager batch one frame's pickups into a single blip (default 1 = old behavior).
func xp_pickup(count: int = 1) -> void:
    _xp_combo = mini(_xp_combo + maxi(1, count), 24)
    _xp_combo_t = 0.35
    sfx("xp_pickup", -6.0, 1.0 + _xp_combo * 0.035, 0.0)


## Coin pickups climb in pitch like XP pickups, a little brighter and quieter.
## count lets CoinManager batch one frame's pickups into a single blip (default 1 = old behavior).
func coin_pickup(count: int = 1) -> void:
    _coin_combo = mini(_coin_combo + maxi(1, count), 16)
    _coin_combo_t = 0.4
    sfx("coin_pickup", -8.0, 1.0 + _coin_combo * 0.04, 0.0)


func music(key: String, fade: float = 1.0) -> void:
    if key == _music_key:
        return
    _music_key = key
    var stream := _load(MUSIC.get(key, ""))
    var a_active := _music_a.playing and _music_a.volume_db > -60.0
    var incoming: AudioStreamPlayer = _music_b if a_active else _music_a
    var outgoing: AudioStreamPlayer = _music_a if a_active else _music_b
    if stream != null:
        if stream is AudioStreamOggVorbis:
            (stream as AudioStreamOggVorbis).loop = true
        incoming.stream = stream
        incoming.volume_db = -80.0
        incoming.play()
        var t := create_tween().set_parallel(true)
        t.tween_property(incoming, "volume_db", 0.0, fade)
        t.tween_property(outgoing, "volume_db", -80.0, fade)
        t.chain().tween_callback(outgoing.stop)
    else:
        var t2 := create_tween()
        t2.tween_property(outgoing, "volume_db", -80.0, fade)
        t2.tween_callback(outgoing.stop)


## Latency-compensated playback position (seconds) of the audible music track, or -1.0 if none is playing.
## The title screen reads this to sync its visuals to the song (see MenuMusicCurve).
func music_time() -> float:
    var p: AudioStreamPlayer = _music_a
    if not _music_a.playing or (_music_b.playing and _music_b.volume_db > _music_a.volume_db):
        p = _music_b
    if not p.playing:
        return -1.0
    return maxf(0.0, p.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())


func stop_music(fade: float = 0.6) -> void:
    _music_key = ""
    for p in [_music_a, _music_b]:
        if p.playing:
            var t := create_tween()
            t.tween_property(p, "volume_db", -80.0, fade)
            t.tween_callback(p.stop)


func set_volume(channel: String, linear: float) -> void:
    volume[channel] = clampf(linear, 0.0, 1.0)
    _apply_volume(channel)
    save_settings()


func _apply_volume(channel: String) -> void:
    var idx := AudioServer.get_bus_index(BUS_NAMES[channel])
    if idx >= 0:
        AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume[channel], 0.0001)))


func load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) == OK:
        for k in volume.keys():
            volume[k] = float(cfg.get_value("audio", k, volume[k]))
    for k in volume.keys():
        _apply_volume(k)


func save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)
    for k in volume.keys():
        cfg.set_value("audio", k, volume[k])
    cfg.save(SETTINGS_PATH)
