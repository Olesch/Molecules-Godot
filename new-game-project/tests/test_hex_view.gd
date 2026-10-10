extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_hex_view.gd
## A solo Playfield on a hexagonal board: topology, picking, rotation, clearing, bomb preview;
## versus always stays square.

const CONFIG_PATH := "user://test_hexview_config.json"
const PROGRESS_PATH := "user://test_hexview_progress.json"


func _mouse_button(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	return e


func _init() -> void:
	_run()


func _run() -> void:
	var cfg := GameConfig.new()
	cfg.set_value("board", "hex")
	cfg.set_value("pressure", GameConfig.PRESSURE_NONE)
	cfg.save_to(CONFIG_PATH)
	var g = load("res://main.tscn").instantiate()
	g.config_path = CONFIG_PATH # never read the real settings
	g.solo_progress_path = PROGRESS_PATH
	root.add_child(g)
	await process_frame
	g._solo_progression = Progression.new()
	g._start_solo()
	await process_frame
	await process_frame
	var pf: Playfield = g._local
	pf.progression.pick_levels.clear()

	_check(pf.topology.id == "hex" and pf.board.topology.id == "hex", "solo with board=hex uses a hex topology and board")
	var size := pf.board_pixel_size()
	_check(is_equal_approx(size.x, 576.0), "hex board is as wide as the square one")
	_check(pf._fx.topology == pf.topology and is_equal_approx(pf._fx.cell_size, pf.cell_size), "fx shares topology and cell size")
	_check(pf._card_overlay.board_size.is_equal_approx(size), "card overlay follows the board size")
	var home := pf.home_position
	_check(is_equal_approx(home.x, (g.get_viewport_rect().size.x - size.x) / 2.0), "board is centred by its pixel width")

	# Picking maps every cell centre back to the cell.
	var all_ok := true
	for y in 8:
		for x in 8:
			var c := Vector2i(x, y)
			if pf._cell_at(home + pf._cell_center(c)) != c:
				all_ok = false
	_check(all_ok, "cell_at(cell_center) maps back for all 64 cells")

	# A click places an atom on the cell under the mouse; a motion event moves the hover.
	var target := Vector2i(-1, -1)
	for y in range(1, 7):
		for x in range(1, 7):
			var c := Vector2i(x, y)
			var lonely := pf.board.is_empty(c)
			for d in 6:
				lonely = lonely and pf.board.is_empty(pf.topology.neighbor(c, d))
			if lonely and target.x < 0:
				target = c
	_check(target.x >= 0, "found an isolated empty cell")
	var motion := InputEventMouseMotion.new()
	motion.position = home + pf._cell_center(target)
	pf._unhandled_input(motion)
	_check(pf._hover == target, "mouse motion hovers the cell under the pointer")
	var held := pf._queue[0]
	pf._unhandled_input(_mouse_button(home + pf._cell_center(target)))
	_check(pf.board.get_atom(target) == held, "a click places the held atom on that hex cell")

	# Rotation has six steps.
	pf._queue[0] = 1 | 2
	var start_mask: int = pf._queue[0]
	pf.rotate_held()
	_check(pf._queue[0] == pf.topology.rotate_cw(start_mask) and pf._queue[0] != start_mask, "rotating uses the hex topology")
	for i in 5:
		pf.rotate_held()
	_check(pf._queue[0] == start_mask, "six rotations return to the start")

	# A closed molecule clears and leaves ghosts with a parent chain.
	pf.board = Board.new(8, 8, Topology.hex())
	pf._queue[0] = 2 # SE
	pf.try_place(Vector2i(2, 2))
	_check(pf.board.get_atom(Vector2i(2, 2)) == 2, "first atom placed")
	pf._queue[0] = 16 # NW
	pf.try_place(Vector2i(2, 3))
	_check(pf.board.is_empty(Vector2i(2, 2)) and pf.board.is_empty(Vector2i(2, 3)), "SE/NW pair clears")
	var ghosts: Array = pf._fx._ghosts
	var with_parent := 0
	for gh in ghosts:
		if gh.parent.x >= 0:
			with_parent += 1
	_check(ghosts.size() == 2 and with_parent == 1, "wave ghosts and one parent created")
	pf._fx.clear()
	pf._queue[0] = 1 # E
	pf.try_place(Vector2i(4, 4))
	pf._queue[0] = 8 # W
	pf.try_place(Vector2i(5, 4))
	_check(pf.board.is_empty(Vector2i(4, 4)) and pf.board.is_empty(Vector2i(5, 4)), "E/W pair clears")

	# Bomb blast preview: a flower of 7 inside, fewer at the corner.
	_check(pf.blast_preview_cells(Vector2i(3, 3)).size() == 7, "interior blast preview covers 7 cells")
	_check(pf.blast_preview_cells(Vector2i(3, 4)).size() == 7, "odd row blast preview covers 7 cells")
	_check(pf.blast_preview_cells(Vector2i(0, 0)).size() < 7, "corner blast preview is clipped")

	# Versus is always square, whatever the saved config says.
	g._make_local(Progression.new(), true)
	await process_frame
	var vs: Playfield = g._local
	_check(vs.topology.id == "square" and vs.board.topology.id == "square" and vs.config.board_id() == "square", "versus forces a square board")
	_check(vs.board_pixel_size().is_equal_approx(Vector2(576, 576)), "versus square board keeps its size")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	_finish()
