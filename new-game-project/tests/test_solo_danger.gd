extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_solo_danger.gd
## Drives a real solo Playfield: announced stray atoms, relocation, drops, versus has none.


func _free_cell(pf: Playfield, avoid: Array) -> Vector2i:
	for y in 8:
		for x in 8:
			var p := Vector2i(x, y)
			if pf.board.is_empty(p) and not avoid.has(p):
				return p
	return Vector2i(-1, -1)


func _ghost_cells(pf: Playfield) -> Array:
	var cells := []
	for g in pf._danger.ghosts:
		cells.append(g.cell)
	return cells


func _filled(pf: Playfield) -> int:
	return int(round(pf.board.fill_ratio() * 64.0))


func _init() -> void:
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	g.solo_progress_path = "user://test_danger_progress.json" # never touch the real save
	g._solo_progression = Progression.new()
	g._on_menu_choose("solo", "")
	await process_frame
	await process_frame
	var pf: Playfield = g._local
	pf.progression.pick_levels.clear()

	# Fresh game: one ghost is announced on a free cell, with a countdown.
	_check(pf._danger_active(), "solo has danger")
	_check(pf._danger.ghosts.size() == 1 and pf.board.is_empty(pf._danger.ghosts[0].cell), "one announced stray on a free cell")
	var start_count: int = pf._danger.countdown
	_check(start_count == Danger.interval(1) + Danger.FIRST_GRACE, "countdown starts with grace")

	# Placing onto the ghost's cell moves the ghost (the placement itself is not blocked).
	pf.board = Board.new(8, 8)
	pf._danger.start(pf.board, 1, pf._fx_rng)
	var announced: Vector2i = pf._danger.ghosts[0].cell
	var shape: int = pf._danger.ghosts[0].mask
	pf._queue[0] = Atoms.N
	pf.try_place(announced)
	_check(pf.board.get_atom(announced) != 0, "the player can place on an announced cell")
	_check(pf._danger.ghosts.size() == 1 and pf._danger.ghosts[0].cell != announced and pf.board.is_empty(pf._danger.ghosts[0].cell), "the stray moved to another free cell")
	_check(pf._danger.ghosts[0].mask == shape, "the stray keeps its announced shape")
	_check(pf._danger.countdown == start_count - 1, "that placement counted down")

	# Count down to the drop: exactly the announced atom lands, then the next one is announced.
	var target: Vector2i = pf._danger.ghosts[0].cell
	var target_mask: int = pf._danger.ghosts[0].mask
	var guard := 0
	while pf._danger.countdown > 1 and guard < 40:
		guard += 1
		var cell := _free_cell(pf, _ghost_cells(pf))
		pf._queue[0] = Atoms.N # one lonely connection: never clears
		pf.try_place(cell)
		if pf._danger.ghosts.is_empty() or pf._danger.ghosts[0].cell != target:
			target = pf._danger.ghosts[0].cell if not pf._danger.ghosts.is_empty() else target
	var filled_before := _filled(pf)
	target = pf._danger.ghosts[0].cell
	target_mask = pf._danger.ghosts[0].mask
	var final_cell := _free_cell(pf, _ghost_cells(pf))
	pf._queue[0] = Atoms.N
	pf.try_place(final_cell)
	_check(pf.board.get_atom(target) == target_mask or pf.board.is_empty(target), "the announced stray landed (or closed a molecule)")
	_check(_filled(pf) >= filled_before, "the board is fuller after the drop")
	_check(pf._danger.countdown == Danger.interval(1) and pf._danger.ghosts.size() == 1, "the next stray is announced right away")

	# After level 10 two strays drop each time.
	pf.progression.level = 11
	pf.board = Board.new(8, 8)
	pf._danger.start(pf.board, pf.progression.level, pf._fx_rng)
	_check(pf._danger.ghosts.size() == 2, "two announced strays after level 10")
	var last_delta := 0
	var rounds := Danger.interval(11) + Danger.FIRST_GRACE
	for i in rounds:
		var c := _free_cell(pf, _ghost_cells(pf))
		pf._queue[0] = Atoms.N # one lonely connection: never clears
		var before := _filled(pf)
		pf.try_place(c)
		last_delta = _filled(pf) - before
		if i < rounds - 1:
			_check(last_delta == 1, "no drop before the countdown ends (placement %d)" % (i + 1))
	_check(last_delta == 3, "the final placement adds the player's atom plus two strays (got %d)" % last_delta)

	# Timed flavour on a real playfield: the clock runs the drop, a card pick pauses it.
	pf.versus = false
	pf.timed = true
	pf.progression.level = 1
	pf.board = Board.new(8, 8)
	pf._danger.timed = true
	pf._danger.start(pf.board, 1, pf._fx_rng)
	pf._queue[0] = Atoms.N
	pf.try_place(_free_cell(pf, _ghost_cells(pf)))
	var seconds_left: float = pf._danger.countdown
	_check(is_equal_approx(seconds_left, Danger.seconds(1) + Danger.FIRST_GRACE_SECONDS), "placing does not move the timed clock")
	pf._process(5.0)
	_check(is_equal_approx(pf._danger.countdown, seconds_left - 5.0), "the clock runs with _process")
	pf.progression.add_xp(500)
	pf._maybe_offer()
	_check(pf._offer_open(), "level-up offer opens in timed mode")
	var frozen: float = pf._danger.countdown
	pf._process(100.0)
	_check(is_equal_approx(pf._danger.countdown, frozen), "the clock stops while a card pick is open")
	pf._card_overlay.hide_offer()
	pf.progression.pick_levels.clear()
	var announced_cell: Vector2i = pf._danger.ghosts[0].cell
	var announced_mask: int = pf._danger.ghosts[0].mask
	var fill_before := _filled(pf)
	pf._process(frozen + 0.1)
	_check(pf.board.get_atom(announced_cell) == announced_mask and _filled(pf) == fill_before + 1, "the announced stray lands when the time is up")
	var level_now: int = pf.progression.level # the XP above leveled the player up
	_check(pf._danger.ghosts.size() == Danger.spawn_count(level_now) and is_equal_approx(pf._danger.countdown, Danger.seconds(level_now)), "the next timed stray is announced with the new level's gap")
	pf.timed = false

	# Versus has no solo danger.
	pf.versus = true
	_check(not pf._danger_active(), "versus has no solo danger")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_danger_progress.json"))
	_finish()
