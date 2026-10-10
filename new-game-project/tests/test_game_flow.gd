extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_game_flow.gd
## Menu -> Solo -> setup screen -> game, with the choices saved between sessions.

const CONFIG_PATH := "user://test_flow_config.json"
const PROGRESS_PATH := "user://test_flow_progress.json"


func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	var g = load("res://main.tscn").instantiate()
	g.config_path = CONFIG_PATH # never touch the real settings or save
	g.solo_progress_path = PROGRESS_PATH
	g.versus_config_path = "user://test_flow_versus.json"
	root.add_child(g)
	await process_frame
	g._solo_progression = Progression.new()

	_check(g._menu.visible and not g._setup.visible, "starts on the menu")
	g._on_menu_choose("solo", "")
	_check(not g._menu.visible and g._setup.visible, "Solo opens the setup screen, not the game")
	_check(g._local == null, "no game has started yet")
	_check(g._setup.current_config().pressure() == GameConfig.PRESSURE_TURNS, "setup shows the defaults the first time")

	# Back returns to the menu.
	g._setup.back_button().pressed.emit()
	_check(g._menu.visible and not g._setup.visible and g._local == null, "Back returns to the menu")

	# Pick Time pressure and start.
	g._on_menu_choose("solo", "")
	var buttons: Array = g._setup.option_buttons("pressure")
	for b in buttons:
		if b.text == "Time pressure":
			b.pressed.emit()
	g._setup.start_button().pressed.emit()
	await process_frame
	_check(not g._setup.visible and g._local != null, "Start begins the game")
	_check(g._local.config.pressure() == GameConfig.PRESSURE_TIMED and g._local.timed, "the game uses the chosen pressure mode")
	_check(GameConfig.load_from(CONFIG_PATH).pressure() == GameConfig.PRESSURE_TIMED, "the choice was saved")
	_check(g._local._danger.timed and not g._local._danger.ghosts.is_empty(), "timed strays are announced")

	# The next visit remembers the last choice.
	g._back_to_menu()
	g._on_menu_choose("solo", "")
	_check(g._setup.current_config().pressure() == GameConfig.PRESSURE_TIMED, "setup remembers the last choice")

	# Relaxed: no strays.
	for b in g._setup.option_buttons("pressure"):
		if b.text == "Relaxed":
			b.pressed.emit()
	g._setup.start_button().pressed.emit()
	await process_frame
	_check(g._local.config.pressure() == GameConfig.PRESSURE_NONE and g._local._danger.ghosts.is_empty(), "Relaxed starts without strays")

	# The Board row offers square and hexagonal; Hexagonal starts a hex playfield.
	g._back_to_menu()
	g._on_menu_choose("solo", "")
	_check(g._setup.option_buttons("board").size() == 2 and g._setup.current_config().board_id() == "square", "setup offers a Board row defaulting to square")
	for b in g._setup.option_buttons("board"):
		if b.text == "Hexagonal":
			b.pressed.emit()
	g._setup.start_button().pressed.emit()
	await process_frame
	_check(g._local.topology.id == "hex" and g._local.board.topology.id == "hex", "Start with Hexagonal gives a hex playfield")
	_check(GameConfig.load_from(CONFIG_PATH).board_id() == "hex", "the board choice was saved")

	# Keyboard: Escape goes back, Enter starts.
	g._back_to_menu()
	g._on_menu_choose("solo", "")
	_key(KEY_ESCAPE)
	await process_frame
	_check(g._menu.visible and not g._setup.visible, "Escape on the setup screen goes back")
	g._on_menu_choose("solo", "")
	_key(KEY_ENTER)
	await process_frame
	await process_frame
	_check(g._local != null and not g._setup.visible, "Enter on the setup screen starts the game")

	# Hosting: a setup screen with only the match options opens first; nothing is hosted until Start.
	g._back_to_menu()
	g._on_menu_choose("host", "")
	_check(g._host_setup.visible and not g._menu.visible and not g._setup.visible, "Host opens the host setup screen")
	_check(g._mode == g.Mode.MENU and not g._net.is_peer_connected(), "nothing is hosted before Start")
	_check(g._host_setup.section_count() == 1 and not g._host_setup.option_buttons("board").is_empty(), "host setup offers the board choice only")
	_check(g._host_setup.option_buttons("pressure").is_empty(), "solo-only options are not shown when hosting")
	g._host_setup.back_button().pressed.emit()
	_check(g._menu.visible and not g._host_setup.visible, "Back from the host setup returns to the menu")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	_finish()
