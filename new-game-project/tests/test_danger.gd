extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_danger.gd
## Solo danger: drop schedule per level, ghosts, relocation, double drops after level 10.


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# Schedule per level.
	_check(Danger.interval(1) == 8, "level 1 drops every 8 placements")
	_check(Danger.interval(3) == 7 and Danger.interval(5) == 6 and Danger.interval(9) == 4, "interval shrinks every 2 levels")
	_check(Danger.interval(11) == 3 and Danger.interval(50) == 3, "interval never drops below the minimum")
	var monotonic := true
	for level in range(1, 40):
		if Danger.interval(level + 1) > Danger.interval(level):
			monotonic = false
	_check(monotonic, "higher levels are never slower")
	_check(Danger.spawn_count(1) == 1 and Danger.spawn_count(10) == 1, "one atom per drop up to level 10")
	_check(Danger.spawn_count(11) == 2 and Danger.spawn_count(30) == 2, "two atoms per drop after level 10")

	# Start and announcement.
	var board := Board.new(8, 8)
	var d := Danger.new()
	d.start(board, 1, rng)
	_check(d.countdown == Danger.interval(1) + Danger.FIRST_GRACE, "first drop has a grace period")
	_check(d.ghosts.size() == 1 and board.is_empty(d.ghosts[0].cell), "one ghost on a free cell")
	var announced: Dictionary = d.ghosts[0].duplicate()

	# Counting down: nothing drops until the countdown ends, then exactly the announced atoms.
	var total := d.countdown
	var early := false
	for i in total - 1:
		if not d.tick(board, rng).is_empty():
			early = true
	_check(not early, "no drop before the countdown ends")
	_check(d.countdown == 1, "one placement left")
	var drops := d.tick(board, rng)
	_check(drops.size() == 1 and drops[0].cell == announced.cell and drops[0].mask == announced.mask, "the drop is exactly what was announced")
	_check(d.ghosts.is_empty(), "ghosts are consumed by the drop")
	board.place(drops[0].cell, drops[0].mask)
	d.schedule_next(board, 1, rng)
	_check(d.countdown == Danger.interval(1) and d.ghosts.size() == 1, "next round is scheduled without grace")
	_check(d.ghosts[0].cell != announced.cell, "the next ghost avoids the filled cell")

	# Placing on a ghost pushes it elsewhere and keeps its shape.
	var g: Dictionary = d.ghosts[0]
	var mask_before: int = g.mask
	var cell_before: Vector2i = g.cell
	board.place(cell_before, Atoms.N) # the player places there
	var moved := d.relocate_at(cell_before, board, rng)
	_check(moved.x >= 0 and moved != cell_before and board.is_empty(moved), "ghost moved to another free cell")
	_check(d.ghosts[0].mask == mask_before and d.ghosts.size() == 1, "moved ghost keeps its shape")
	var untouched_cell := Vector2i(-1, -1)
	for y in 8:
		for x in 8:
			if board.is_empty(Vector2i(x, y)) and d.ghost_index(Vector2i(x, y)) < 0 and untouched_cell.x < 0:
				untouched_cell = Vector2i(x, y)
	var before: Vector2i = d.ghosts[0].cell
	_check(d.relocate_at(untouched_cell, board, rng).x < 0 and d.ghosts[0].cell == before, "a cell without a ghost leaves ghosts alone")

	# Level 11: two distinct ghosts.
	var big := Board.new(8, 8)
	var d2 := Danger.new()
	d2.start(big, 11, rng)
	_check(d2.ghosts.size() == 2 and d2.ghosts[0].cell != d2.ghosts[1].cell, "two distinct ghosts after level 10")
	_check(d2.countdown == Danger.interval(11) + Danger.FIRST_GRACE, "level 11 interval plus grace")

	# Ghosts never sit on occupied cells, even on crowded boards.
	var always_free := true
	for round in 200:
		var b := Board.new(8, 8)
		b.preplace(rng.randi_range(0, 55), rng)
		var dd := Danger.new()
		dd.start(b, rng.randi_range(1, 15), rng)
		for gh in dd.ghosts:
			if not b.is_empty(gh.cell):
				always_free = false
		for step in 6:
			var free_cell := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
			if b.is_empty(free_cell):
				b.place(free_cell, Atoms.random_shape(rng))
				dd.relocate_at(free_cell, b, rng)
			dd.tick(b, rng)
			for gh in dd.ghosts:
				if not b.is_empty(gh.cell):
					always_free = false
	_check(always_free, "ghosts always stand on free cells (200 random boards)")

	# A ghost whose cell gets filled by something else is relocated on the next tick.
	var b3 := Board.new(8, 8)
	var d3 := Danger.new()
	d3.start(b3, 1, rng)
	var gc: Vector2i = d3.ghosts[0].cell
	b3.place(gc, Atoms.N) # filled without relocate_at
	d3.tick(b3, rng)
	_check(d3.ghosts.size() == 1 and d3.ghosts[0].cell != gc, "tick relocates a ghost whose cell was filled")

	# No room: ghosts disappear instead of failing.
	var tiny := Board.new(2, 1)
	tiny.place(Vector2i(0, 0), Atoms.N)
	var d4 := Danger.new()
	d4.start(tiny, 11, rng)
	_check(d4.ghosts.size() == 1, "only as many ghosts as there are free cells")
	tiny.place(d4.ghosts[0].cell, Atoms.N)
	_check(d4.relocate_at(d4.ghosts[0].cell, tiny, rng).x < 0 and d4.ghosts.is_empty(), "a ghost with no room left vanishes")

	# Timed flavour: seconds instead of placements.
	_check(Danger.seconds(1) == 18.0 and Danger.seconds(3) == 16.5, "timed gap starts at 18 s and shrinks 1.5 s per 2 levels")
	_check(Danger.seconds(40) == Danger.MIN_SECONDS, "timed gap has a floor")
	var timed_monotonic := true
	for level in range(1, 40):
		if Danger.seconds(level + 1) > Danger.seconds(level):
			timed_monotonic = false
	_check(timed_monotonic, "higher levels are never slower (timed)")
	var tb := Board.new(8, 8)
	var td := Danger.new()
	td.timed = true
	td.start(tb, 1, rng)
	_check(is_equal_approx(td.countdown, Danger.seconds(1) + Danger.FIRST_GRACE_SECONDS), "timed start has a grace period")
	_check(td.countdown_label() == 24, "countdown label rounds seconds up")
	var announced_t: Dictionary = td.ghosts[0].duplicate()
	_check(td.advance(10.0, tb, rng).is_empty() and is_equal_approx(td.countdown, 14.0), "ten seconds pass without a drop")
	_check(td.countdown_label() == 14, "label follows the clock")
	var early_drop := td.advance(13.9, tb, rng)
	_check(early_drop.is_empty(), "still nothing just before the end")
	var timed_drop := td.advance(0.2, tb, rng)
	_check(timed_drop.size() == 1 and timed_drop[0].cell == announced_t.cell and timed_drop[0].mask == announced_t.mask, "the timed drop is the announced atom")
	tb.place(timed_drop[0].cell, timed_drop[0].mask)
	td.schedule_next(tb, 1, rng)
	_check(is_equal_approx(td.countdown, Danger.seconds(1)) and td.ghosts.size() == 1, "next timed round has no grace")
	var td2 := Danger.new()
	td2.timed = true
	td2.start(Board.new(8, 8), 11, rng)
	_check(td2.ghosts.size() == 2, "two timed strays after level 10")

	_finish()
