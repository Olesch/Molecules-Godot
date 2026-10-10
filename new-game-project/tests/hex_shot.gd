extends SceneTree
## Windowed: godot --path new-game-project --resolution 1100x860 --script res://tests/hex_shot.gd
## Saves screenshots of the hex (and square) board into the scratchpad.

const OUT := "user://shots/"
const CONFIG_PATH := "user://shot_config.json"

var g


func _init() -> void:
	_run()


func _snap(file: String, wait_frames := 4) -> void:
	for i in wait_frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OUT + file)


func _hover(pf: Playfield, cell: Vector2i) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pf.home_position + pf._cell_center(cell)
	pf._unhandled_input(m)


func _start(board: String, pressure: String) -> Playfield:
	var cfg := GameConfig.new()
	cfg.set_value("board", board)
	cfg.set_value("pressure", pressure)
	g._config = cfg
	g._start_solo()
	await process_frame
	var pf: Playfield = g._local
	pf.progression.pick_levels.clear()
	return pf


func _run() -> void:
	g = load("res://main.tscn").instantiate()
	g.config_path = CONFIG_PATH
	g.solo_progress_path = "user://shot_progress.json"
	root.add_child(g)
	await process_frame
	g._solo_progression = Progression.new()

	# Setup screen with the Board row.
	g._on_menu_choose("solo", "")
	await _snap("hex_setup.png")
	g._setup.visible = false

	# Hex, turn-based: announced strays, hover preview.
	var pf := await _start("hex", GameConfig.PRESSURE_TURNS)
	pf._queue[0] = 1 | 2 | 8
	_hover(pf, Vector2i(3, 3))
	await _snap("hex_a_hover.png")

	# Bomb preview.
	pf._queue[0] = 63 | Atoms.BOMB
	_hover(pf, Vector2i(4, 3))
	await _snap("hex_b_bomb.png")

	# Wildcard held.
	pf._queue[0] = Atoms.WILD
	pf._queue[1] = 63
	if pf._queue.size() > 2:
		pf._queue[2] = 1 | 4 | 16
	_hover(pf, Vector2i(3, 4))
	await _snap("hex_c_wild.png")

	# A clear wave mid animation: a six-star with all neighbours pointing back.
	pf = await _start("hex", GameConfig.PRESSURE_NONE)
	pf.board = Board.new(8, 8, Topology.hex())
	var centre := Vector2i(3, 3)
	var t := pf.topology
	for d in 6:
		pf.board.place(t.neighbor(centre, d), 1 << t.opposite(d))
	pf.board.place(Vector2i(0, 6), 1 | 2)
	pf.board.place(Vector2i(6, 6), 3 | 8 | 16)
	pf._queue[0] = 63
	pf.try_place(centre)
	_hover(pf, Vector2i(6, 1))
	for i in 5:
		await process_frame
	await create_timer(0.12).timeout
	await _snap("hex_d_clear.png", 1)

	# Square board for comparison.
	pf = await _start("square", GameConfig.PRESSURE_TURNS)
	pf._queue[0] = 1 | 2 | 8
	_hover(pf, Vector2i(3, 3))
	await _snap("square_a.png")
	pf._queue[0] = 15 | Atoms.BOMB
	_hover(pf, Vector2i(4, 4))
	await _snap("square_b_bomb.png")
	quit()
