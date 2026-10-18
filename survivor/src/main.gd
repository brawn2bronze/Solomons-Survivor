extends Node
## Top-level state machine: MainMenu -> CharacterSelect -> World (run) -> back. Screen changes fade through black.

var _screen: Node
var _world: World
var _fade: ColorRect
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().min_size = Vector2i(640, 360)
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fade)
	_go(_show_menu)


func _go(target: Callable) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.16)
	await tw.finished
	_clear()
	target.call()
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.22)
	await tw2.finished
	_busy = false


func _clear() -> void:
	if _screen != null:
		_screen.queue_free()
		_screen = null
	if _world != null:
		_world.queue_free()
		_world = null
	Game.reset_time()
	# NOTE: dev state is NOT cleared here so "Restart Run" keeps sandbox settings.
	get_tree().paused = false


func _show_menu() -> void:
	Game.clear_dev()
	Game.run_from_descent = false
	Game.pending_descent = {}
	Audio.music("menu_music", 1.0)
	var m := MainMenu.new()
	add_child(m)
	m.play.connect(func() -> void: _go(_show_select))
	m.dev.connect(func() -> void: _go(_show_dev))
	m.market.connect(func() -> void: _go(_show_market))
	m.seal.connect(func() -> void: _go(_show_seal))
	m.quit.connect(func() -> void: get_tree().quit())
	_screen = m


func _show_market() -> void:
	Game.clear_dev()
	Audio.music("menu_music", 1.0)
	var b := BlackMarketScreen.new()
	add_child(b)
	b.back.connect(func() -> void: _go(_show_menu))
	_screen = b


func _show_seal() -> void:
	Game.clear_dev()
	Audio.music("menu_music", 1.0)
	var s := SealScreen.new()
	add_child(s)
	s.back.connect(func() -> void: _go(_show_menu))
	_screen = s


func _show_dev() -> void:
	Game.clear_dev()
	Audio.music("menu_music", 1.0)
	var d := DevMenu.new()
	add_child(d)
	d.start_requested.connect(func(_cfg: Dictionary) -> void: _go(_start_run.bind(Game.selected_character)))
	d.back.connect(func() -> void: _go(_show_menu))
	_screen = d


func _show_select() -> void:
	Game.clear_dev()
	Game.run_from_descent = false
	Game.pending_descent = {}
	Audio.music("menu_music", 1.0)
	var s := CharacterSelect.new()
	add_child(s)
	s.confirmed.connect(func(id: String) -> void: _go(_start_run.bind(id)))
	s.continued.connect(func(id: String) -> void: _go(_start_run.bind(id, true)))
	s.back.connect(func() -> void: _go(_show_menu))
	_screen = s


func _start_run(id: String, use_descent := false) -> void:
	Game.pending_descent = Meta.get_descent(id).duplicate(true) if use_descent else {}
	Game.run_from_descent = use_descent
	var w := World.new()
	add_child(w)
	w.start(id)
	w.exit_requested.connect(_on_exit)
	_world = w


func _on_exit(dest: String) -> void:
	match dest:
		"retry":
			_go(_start_run.bind(Game.selected_character, Game.run_from_descent))
		"select":
			_go(_show_select)
		_:
			_go(_show_menu)
