extends "res://tests/test_base.gd"
## Run: godot --headless --path . --script res://tests/test_scrap.gd
## The Scrap ability: arm it (button / C), click an atom to delete it, then it recharges over
## placements. Square and hex boards, solo and versus.

var _sfx: Array = []
var _snapshots: Array = []


func _make(board_id: String, versus := false, values := {}) -> Playfield:
	var pf := Playfield.new()
	pf.versus = versus
	pf.config.set_value("board", board_id)
	pf.config.set_value("pressure", GameConfig.PRESSURE_NONE)
	for id in values:
		pf.config.set_value(id, str(values[id]))
	root.add_child(pf)
	await process_frame
	pf.start(77)
	pf.progression.pick_levels.clear()
	pf.board = Board.new(pf.board_w, pf.board_h, pf.topology) # empty, so nothing clears by accident
	pf._apply_rules_to_board()
	_sfx.clear()
	_snapshots.clear()
	pf.sfx_requested.connect(func(n: String, pitch: float) -> void: _sfx.append([n, pitch]))
	pf.board_changed.connect(func(cells: PackedInt32Array) -> void: _snapshots.append(cells))
	return pf


func _click(pf: Playfield, pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pf.get_parent_global_offset() + pf.home_position + pos
	pf._unhandled_input(e)


func _key(pf: Playfield, code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	pf._unhandled_input(e)


## A lone single-connection atom that points at a free cell, so nothing clears and nothing is dead.
func _put(pf: Playfield, p: Vector2i, mask: int) -> void:
	pf.board.place(p, mask)


func _init() -> void:
	for board_id in ["square", "hex"]:
		await _suite(board_id)
	await _options_and_guards()
	await _pressure_clock()
	_finish(true)


func _suite(board_id: String) -> void:
	var tag := " [%s]" % board_id
	var pf := await _make(board_id, true)
	var east := 1 if board_id == "square" else 0 # direction index of "east"
	var e_bit := 1 << east
	_check(pf.scrap_enabled() and not pf._scrap_armed and pf._scrap_cd == 0, "Scrap is on and ready by default" + tag)

	# Dead molecule: an atom A points east at B, whose own arm points away, so A is blocked by B.
	var a := Vector2i(2, 2)
	var b := pf.topology.neighbor(a, east)
	_put(pf, a, e_bit)
	_put(pf, b, e_bit)
	_check(pf.board.is_dead(pf.board.molecule_at(a)), "A is dead while B blocks it" + tag)

	# Arm and cancel in every way.
	pf.toggle_scrap()
	_check(pf._scrap_armed, "button / toggle arms Scrap" + tag)
	pf.toggle_scrap()
	_check(not pf._scrap_armed, "toggling again cancels" + tag)
	_key(pf, KEY_C)
	_check(pf._scrap_armed, "key C arms Scrap" + tag)
	_key(pf, KEY_ESCAPE)
	_check(not pf._scrap_armed, "Esc cancels" + tag)
	_key(pf, KEY_C)
	var queue_before := pf._queue.duplicate()
	_click(pf, pf._reroll_center(), MOUSE_BUTTON_RIGHT)
	_check(not pf._scrap_armed and pf._queue == queue_before, "right-click cancels (and does not rotate)" + tag)
	_click(pf, pf._scrap_center())
	_check(pf._scrap_armed, "clicking the Scrap button arms it" + tag)
	_click(pf, pf._scrap_center())
	_check(not pf._scrap_armed, "clicking the button again cancels" + tag)

	# Armed on an empty cell: nothing happens, stays armed.
	pf.toggle_scrap()
	var empty := Vector2i(5, 5)
	_sfx.clear()
	_snapshots.clear()
	_check(not pf.scrap_cell(empty) and pf._scrap_armed and pf._scrap_cd == 0 and _snapshots.is_empty(), "an empty cell cannot be scrapped" + tag)
	_click(pf, pf._cell_center(empty))
	_check(pf._scrap_armed and pf.board.is_empty(empty) and pf.board.get_atom(b) == e_bit, "clicking an empty cell while armed does not place an atom" + tag)

	# Scrap the blocker B by clicking it.
	var held := pf._queue[0]
	var score := pf.score
	var xp := pf.progression.xp
	_sfx.clear()
	_snapshots.clear()
	_click(pf, pf._cell_center(b))
	_check(pf.board.is_empty(b) and not pf._scrap_armed, "clicking an atom while armed removes it" + tag)
	_check(pf._scrap_cd == 6, "cooldown starts at the default of 6 placements" + tag)
	_check(pf.score == score and pf.progression.xp == xp, "no points or XP for a scrap" + tag)
	_check(pf._queue[0] == held, "the held atom is untouched" + tag)
	_check(not pf.board.is_dead(pf.board.molecule_at(a)), "removing the blocker revives the dead molecule" + tag)
	var clear_sfx := false
	for s in _sfx:
		if s[0] == "clear" and s[1] < 1.0:
			clear_sfx = true
	_check(clear_sfx, "a low-pitched clear sound is requested" + tag)
	_check(_snapshots.size() == 1 and _snapshots[0][b.y * pf.board_w + b.x] == 0 and _snapshots[0][a.y * pf.board_w + a.x] == e_bit, "versus: a board snapshot with the removal is emitted" + tag)

	# While recharging it cannot be armed or used.
	pf.toggle_scrap()
	_check(not pf._scrap_armed, "cannot arm while recharging" + tag)
	_check(not pf.scrap_cell(a) and pf.board.get_atom(a) == e_bit, "cannot scrap while recharging" + tag)
	pf.board.remove_atom(a)
	# Placements tick the cooldown down; it is ready after 6 of them.
	var spots: Array[Vector2i] = []
	for y in pf.board_h:
		for x in pf.board_w:
			spots.append(Vector2i(x, y))
	var placed := 0
	var i := 0
	while placed < 6:
		var p := spots[i]
		i += 1
		if not pf.board.is_empty(p):
			continue
		pf._queue[0] = e_bit
		var before := pf._scrap_cd
		pf.try_place(p)
		# keep the board free of clears: remove what was just placed, only the cooldown matters
		if pf.board.get_atom(p) != 0:
			pf.board.remove_atom(p)
		placed += 1
		_check(pf._scrap_cd == maxi(0, before - 1), "a placement ticks the Scrap cooldown (%d)" % placed + tag)
	_check(pf._scrap_cd == 0, "Scrap is ready again after 6 placements" + tag)
	pf.toggle_scrap()
	_check(pf._scrap_armed, "ready again: can be armed" + tag)
	pf.queue_free()


func _options_and_guards() -> void:
	# Off disables everything.
	var pf := await _make("square", false, {"scrap_cooldown": 0})
	_put(pf, Vector2i(1, 1), Atoms.E)
	_check(not pf.scrap_enabled(), "scrap_cooldown Off disables Scrap")
	pf.toggle_scrap()
	_key(pf, KEY_C)
	_check(not pf._scrap_armed and not pf.scrap_cell(Vector2i(1, 1)) and pf.board.get_atom(Vector2i(1, 1)) == Atoms.E, "Off: cannot arm or scrap")
	_check(not pf._scrap_hit(pf._scrap_center()), "Off: no button to click")
	pf.queue_free()

	# Other cooldown values.
	for cd in [4, 8, 12]:
		pf = await _make("square", false, {"scrap_cooldown": cd})
		_put(pf, Vector2i(1, 1), Atoms.E)
		pf.toggle_scrap()
		pf.scrap_cell(Vector2i(1, 1))
		_check(pf._scrap_cd == cd, "scrap_cooldown %d: recharge is %d placements" % [cd, cd])
		pf.queue_free()

	# The option is part of the setup lists and the config round trip.
	var def := GameConfig.option_def("scrap_cooldown")
	_check(not def.is_empty() and def.default == "6" and GameConfig.choice_values("scrap_cooldown") == ["0", "4", "6", "8", "12"], "option scrap_cooldown: Off / 4 / 6 / 8 / 12, default 6")
	_check(GameConfig.options_for("solo").has(def) and GameConfig.options_for("versus").has(def), "scrap_cooldown is offered in solo and versus")
	var sent := GameConfig.from_dict(GameConfig.new().to_dict())
	sent.set_value("scrap_cooldown", "12")
	_check(GameConfig.from_dict(sent.to_dict()).get_int("scrap_cooldown") == 12, "scrap_cooldown travels in the option dictionary")

	# Finished game and open card offer block it.
	pf = await _make("square")
	_put(pf, Vector2i(1, 1), Atoms.E)
	pf.toggle_scrap()
	_check(pf._scrap_armed, "armed before the game ends")
	pf.set_overlay("BOARD FULL - YOU LOSE")
	_check(not pf._scrap_armed and not pf.scrap_cell(Vector2i(1, 1)) and pf.board.get_atom(Vector2i(1, 1)) == Atoms.E, "a finished game disarms and blocks Scrap")
	pf.queue_free()
	pf = await _make("square")
	_put(pf, Vector2i(1, 1), Atoms.E)
	pf.progression.pick_levels.append(2)
	pf._offer_wait = 0.0
	pf._maybe_offer()
	_check(pf._offer_open(), "a card offer is open")
	pf.toggle_scrap()
	_check(not pf._scrap_armed and not pf.scrap_cell(Vector2i(1, 1)) and pf.board.get_atom(Vector2i(1, 1)) == Atoms.E, "an open card offer blocks Scrap")
	pf.queue_free()

	# Mirror (non-interactive) playfields never scrap.
	pf = Playfield.new()
	pf.interactive = false
	root.add_child(pf)
	await process_frame
	pf.start(5)
	pf.board.place(Vector2i(1, 1), Atoms.E)
	pf.toggle_scrap()
	_check(not pf._scrap_armed and not pf.scrap_cell(Vector2i(1, 1)), "a mirror cannot scrap")
	pf.queue_free()


func _pressure_clock() -> void:
	# Turn-based: a scrap is one tick of the pressure clock.
	var pf := await _make("square", false, {"pressure": GameConfig.PRESSURE_TURNS})
	_put(pf, Vector2i(1, 1), Atoms.E)
	var before := pf._danger.countdown
	pf.toggle_scrap()
	pf.scrap_cell(Vector2i(1, 1))
	_check(is_equal_approx(pf._danger.countdown, before - 1.0), "turn-based: a scrap counts as a placement for the pressure clock")
	pf.queue_free()

	# Timed: no extra cost, the clock decides.
	pf = await _make("square", false, {"pressure": GameConfig.PRESSURE_TIMED})
	_put(pf, Vector2i(1, 1), Atoms.E)
	before = pf._danger.countdown
	pf.toggle_scrap()
	pf.scrap_cell(Vector2i(1, 1))
	_check(is_equal_approx(pf._danger.countdown, before) and pf.board.is_empty(Vector2i(1, 1)), "timed: a scrap costs no clock time")
	pf.queue_free()

	# Relaxed: no clock at all.
	pf = await _make("hex", false, {"pressure": GameConfig.PRESSURE_NONE})
	_put(pf, Vector2i(1, 1), 1)
	pf.toggle_scrap()
	_check(pf.scrap_cell(Vector2i(1, 1)) and pf.board.is_empty(Vector2i(1, 1)), "relaxed: scrap works without pressure")
	pf.queue_free()
