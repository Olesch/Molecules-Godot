extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_cards_integration.gd
## Drives the real Game/Playfield with cards: level-up offer, pick, stash, reroll, strays, gardener.


func _init() -> void:
	var g = load("res://main.tscn").instantiate()
	g.config_path = "user://test_cards_config.json" # never read the real settings
	root.add_child(g)
	await process_frame
	g.solo_progress_path = "user://test_solo_progress.json" # never touch the real save
	g._solo_progression = Progression.new()
	g._start_solo()
	await process_frame
	await process_frame
	var pf: Playfield = g._local
	_check(pf != null and not pf.versus, "solo playfield created")

	# Level up -> offer appears.
	var gained := pf.progression.add_xp(500)
	_check(gained > 0, "xp gives levels (%d)" % gained)
	pf._maybe_offer()
	_check(pf._card_overlay.is_open(), "offer overlay opens on level-up")
	var free_cell := Vector2i(-1, -1)
	for y in 8:
		for x in 8:
			if free_cell.x < 0 and pf.board.is_empty(Vector2i(x, y)):
				free_cell = Vector2i(x, y)
	pf.try_place(free_cell)
	_check(pf.board.is_empty(free_cell), "board is locked while the offer is open")
	var pending_before := pf.progression.pick_levels.size()
	pf._on_card_picked("stash")
	_check(pf.mods.has("stash"), "picked card is owned")
	_check(pf.progression.pick_levels.size() == pending_before - 1, "pick consumes a pending level")

	# Hold slot.
	pf.progression.pick_levels.clear()
	pf._card_overlay.hide_offer()
	var held := pf._queue[0]
	var size_before := pf._queue.size()
	pf.stash_swap()
	_check(pf._stash == held and pf._queue.size() == size_before, "stash stores the held atom and refills the queue")
	var next_held := pf._queue[0]
	pf.stash_swap()
	_check(pf._queue[0] == held and pf._stash == next_held, "second stash swaps back")

	# Queue size follows cards.
	pf.progression.mods.add("long_view")
	pf._fit_queue()
	_check(pf._queue.size() == Modifiers.new().queue_size() + 1, "long view grows the queue")

	# Reroll cooldown.
	pf.progression.mods.add("reroll")
	pf.reroll_held()
	_check(pf._reroll_cd == Playfield.REROLL_COOLDOWN, "reroll starts its cooldown")
	var after_reroll := pf._queue[0]
	pf.reroll_held()
	_check(pf._queue[0] == after_reroll, "reroll is blocked while recharging")

	# The Reroll button next to the held atom can be clicked (once recharged).
	pf._reroll_cd = 0
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pf.get_parent_global_offset() + pf.home_position + pf._reroll_center()
	var held_before := pf._queue[0]
	var tries := 0
	while pf._queue[0] == held_before and tries < 40: # a reroll can hand back the same atom
		pf._reroll_cd = 0
		pf._unhandled_input(click)
		tries += 1
	_check(pf._queue[0] != held_before and pf._reroll_cd == Playfield.REROLL_COOLDOWN, "clicking the Reroll button rerolls and starts the cooldown")
	var empty_cell := Vector2i(-1, -1)
	for y in 8:
		for x in 8:
			if empty_cell.x < 0 and pf.board.is_empty(Vector2i(x, y)):
				empty_cell = Vector2i(x, y)
	click.position = pf.get_parent_global_offset() + pf.home_position + pf._cell_center(empty_cell)
	var cd_now := pf._reroll_cd
	pf._unhandled_input(click)
	_check(pf._reroll_cd == maxi(0, cd_now - 1), "a click elsewhere only places an atom (the cooldown just ticks down)")
	pf._reroll_cd = 0

	# A real clear: score, XP and combo flag.
	pf.board = Board.new(8, 8)
	pf._queue[0] = Atoms.E
	pf.try_place(Vector2i(0, 0))
	pf._queue[0] = Atoms.W
	var score_before := pf.score
	var xp_before := pf.progression.xp + pf.progression.level * 1000
	pf.try_place(Vector2i(1, 0))
	_check(pf.board.is_empty(Vector2i(0, 0)) and pf.board.is_empty(Vector2i(1, 0)), "pair clears through the playfield")
	_check(pf.score - score_before == pf.mods.scaled_points(2, 0, false), "score uses the card modifiers (+%d)" % (pf.score - score_before))
	_check(pf.progression.xp + pf.progression.level * 1000 > xp_before, "clear awards xp")
	pf.progression.pick_levels.clear()
	pf._card_overlay.hide_offer()

	# Stray atoms and Gardener (versus rules).
	pf.versus = true
	pf.progression.mods.add("gardener")
	pf.progression.mods.add("thick_skin")
	pf.board = Board.new(8, 8)
	pf._fx_rng.seed = 7 # fixed stray landing spots, so they never block the gardener pair below
	pf.receive_attack(3)
	_check(pf._pending == 3, "attack queues stray atoms")
	_check(pf._incoming.ghosts.size() == 1, "exactly one incoming stray is announced")
	var gap: float = pf.mods.incoming_gap_seconds()
	_check(is_equal_approx(gap, 3.5), "thick skin lengthens the gap (%.1f s)" % gap)
	pf._queue[0] = Atoms.N
	pf.try_place(Vector2i(7, 7))
	var filled := int(round(pf.board.fill_ratio() * 64.0))
	_check(filled == 1 and pf._pending == 3, "a plain placement lands nothing any more")
	for i in 3:
		pf._process(gap / 3.0 + 0.01) # a bit more than the gap in total
	filled = int(round(pf.board.fill_ratio() * 64.0))
	_check(filled == 2 and pf._pending == 2, "one stray lands after the gap (%d atoms)" % filled)
	_check(pf._stray.size() == 1, "stray cell is tracked")
	var stray_before := pf._stray.size()
	pf._queue[0] = Atoms.E
	pf.try_place(Vector2i(2, 0))
	pf._queue[0] = Atoms.W
	pf.try_place(Vector2i(3, 0))
	var stray_live := 0
	for c in pf._stray.keys():
		if pf.board.get_atom(c) != 0:
			stray_live += 1
	_check(stray_live <= maxi(0, stray_before - 1), "gardener removed a stray atom (live %d of %d)" % [stray_live, stray_before])

	# Rule cards reach the board.
	pf.progression.mods.add("loose_ends")
	pf._apply_rules_to_board()
	_check(pf.board.max_open_ends == 1, "loose ends propagates to the board")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_solo_progress.json"))
	_finish()
