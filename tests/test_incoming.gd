extends "res://tests/test_base.gd"
## Run: godot --headless --path . --script res://tests/test_incoming.gd
## Versus incoming stray atoms: queued by receive_attack, then announced as one ghost with a
## countdown and landed one at a time (at most one per gap). Square and hex boards.

const STEP := 0.05
const GAP := Danger.INCOMING_BASE_SECONDS

var _attacks := 0


func _make(board_id: String) -> Playfield:
	var pf := Playfield.new()
	pf.versus = true
	pf.interactive = true
	pf.config.set_value("board", board_id)
	root.add_child(pf)
	await process_frame
	pf.start(1234)
	pf.progression.pick_levels.clear()
	pf.board = Board.new(Playfield.BOARD_W, Playfield.BOARD_H, pf.topology) # empty, so nothing clears by accident
	pf.attack.connect(func(_n): _attacks += 1)
	return pf


## Lets seconds pass in small steps. keep_plain: ghosts are forced to a lone connection so a landing never clears.
func _run(pf: Playfield, seconds: float, keep_plain := false) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		if keep_plain:
			for g in pf._incoming.ghosts:
				g.mask = 1
		pf._process(STEP)
		t += STEP


func _filled(pf: Playfield) -> int:
	return int(round(pf.board.fill_ratio() * 64.0))


func _suite(board_id: String) -> void:
	var tag := " [%s]" % board_id
	var pf := await _make(board_id)

	# One ghost, a full countdown, nothing before one gap, then exactly one atom.
	pf.receive_attack(3)
	_check(pf._pending == 3, "attack queues 3" + tag)
	_check(pf._incoming.ghosts.size() == 1 and pf.board.is_empty(pf._incoming.ghosts[0].cell), "exactly one ghost on a free cell" + tag)
	_check(is_equal_approx(pf._incoming.countdown, GAP) and pf._incoming.countdown_label() == ceili(GAP), "countdown starts at one full gap" + tag)
	pf.receive_attack(1)
	_check(pf._pending == 4 and pf._incoming.ghosts.size() == 1 and is_equal_approx(pf._incoming.countdown, GAP), "a second attack queues without restarting the clock" + tag)
	pf._pending = 3
	_run(pf, GAP - 0.1, true)
	_check(pf._pending == 3 and _filled(pf) == 0, "nothing lands before the gap is over" + tag)
	_check(pf._incoming.countdown_label() == 1, "label counts down" + tag)

	# Record the landing times of all three atoms.
	var times: Array[float] = []
	var t := GAP - 0.1
	var pending := pf._pending
	var multi := false
	for i in int(GAP * 3.0 / STEP) + 100:
		for g in pf._incoming.ghosts:
			g.mask = 1
		pf._process(STEP)
		t += STEP
		if pf._pending < pending:
			if pending - pf._pending > 1:
				multi = true
			times.append(t)
			pending = pf._pending
			_check(pf._incoming.ghosts.is_empty() == (pf._pending == 0), "next ghost is announced right after a landing" + tag)
			if pf._pending > 0:
				_check(is_equal_approx(pf._incoming.countdown, GAP), "the next ghost gets a fresh full gap" + tag)
		if pending == 0 and t > GAP * 3.0 + 1.0:
			break
	_check(times.size() == 3 and not multi, "three landings, never two at once (%s)" % str(times) + tag)
	if times.size() == 3:
		_check(absf(times[0] - GAP) < 0.12, "first lands after ~one gap" + tag)
		_check(times[1] - times[0] >= GAP - 0.06 and times[2] - times[1] >= GAP - 0.06, "landings are at least one gap apart" + tag)
		_check(absf(times[2] - GAP * 3.0) < 0.3, "three atoms take ~three gaps" + tag)
	_check(_filled(pf) == 3 and pf._stray.size() == 3, "three strays on the board and tracked" + tag)
	_check(pf._incoming.ghosts.is_empty(), "no ghost once the queue is empty" + tag)

	# Placing on the announced cell relocates the ghost without landing it.
	pf = await _make(board_id)
	pf.receive_attack(2)
	var cell: Vector2i = pf._incoming.ghosts[0].cell
	var mask: int = pf._incoming.ghosts[0].mask
	pf._queue[0] = 1
	pf.try_place(cell)
	_check(pf.board.get_atom(cell) != 0, "the player can place on the announced cell" + tag)
	_check(pf._incoming.ghosts.size() == 1 and pf._incoming.ghosts[0].cell != cell and pf.board.is_empty(pf._incoming.ghosts[0].cell), "the ghost jumped to another free cell" + tag)
	_check(pf._incoming.ghosts[0].mask == mask and pf._pending == 2, "same shape, nothing landed" + tag)

	# The clock stops while a card pick is open.
	pf = await _make(board_id)
	pf.receive_attack(1)
	_run(pf, 1.0, true)
	var left: float = pf._incoming.countdown
	var cards: Array[Dictionary] = [Cards.describe(Cards.LONG_VIEW, 0)]
	pf._card_overlay.show_offer(cards, 2)
	_run(pf, 5.0, true)
	_check(pf._pending == 1 and is_equal_approx(pf._incoming.countdown, left), "countdown pauses during a card pick" + tag)
	pf._card_overlay.hide_offer()
	_run(pf, left + 0.1, true)
	_check(pf._pending == 0, "and resumes afterwards" + tag)

	# Clearing a molecule cancels the queue and removes the ghost.
	var e := 2 if board_id == "square" else 1
	var w := 8
	pf = await _make(board_id)
	pf.receive_attack(1)
	pf._attack_charge = 24.0 # the 3-point pair tips it over 25 points: one attack
	pf._queue[0] = e
	pf.try_place(Vector2i(0, 0))
	pf._queue[0] = w
	pf.try_place(Vector2i(1, 0))
	_check(pf.board.is_empty(Vector2i(0, 0)), "pair cleared" + tag)
	_check(pf._pending == 0 and pf._incoming.ghosts.is_empty(), "cancelling everything removes the ghost" + tag)
	pf.receive_attack(40)
	pf._attack_charge = 24.0
	pf._queue[0] = e
	pf.try_place(Vector2i(0, 0))
	pf._queue[0] = w
	pf.try_place(Vector2i(1, 0))
	_check(pf._pending > 0 and pf._pending < 40 and pf._incoming.ghosts.size() == 1, "a partial cancel keeps the ghost" + tag)

	# A landing that closes a molecule clears it.
	pf = await _make(board_id)
	pf.receive_attack(1)
	pf._queue[0] = e
	pf.try_place(Vector2i(0, 0))
	var left_before := pf._pending
	pf._incoming.ghosts.clear()
	pf._incoming.ghosts.append({"cell": Vector2i(1, 0), "mask": w})
	pf._incoming.countdown = 0.1
	pf._pending = 1
	var score_before := pf.score
	pf._process(0.2)
	_check(pf.board.is_empty(Vector2i(0, 0)) and pf.board.is_empty(Vector2i(1, 0)) and pf.score > score_before and pf._pending == 0, "a landing that closes a molecule clears and scores" + tag)
	_check(left_before == 1, "setup sanity" + tag)

	# Cards: gap length, Glass Cannon, Counterstrike, Gardener.
	for combo in [[{}, GAP], [{"thick_skin": 1}, GAP + 0.5], [{"thick_skin": 2}, GAP + 1.0], [{"shield": 1}, GAP * 1.5], [{"thick_skin": 2, "shield": 1}, (GAP + 1.0) * 1.5]]:
		pf = await _make(board_id)
		for id in combo[0]:
			for i in int(combo[0][id]):
				pf.progression.mods.add(id)
		pf.receive_attack(1)
		_check(is_equal_approx(pf._incoming.countdown, combo[1]), "gap %.2f s for %s" % [combo[1], str(combo[0])] + tag)
		_run(pf, combo[1] - 0.1, true)
		_check(pf._pending == 1, "not yet landed with %s" % str(combo[0]) + tag)
		_run(pf, 0.2, true)
		_check(pf._pending == 0, "landed after the gap with %s" % str(combo[0]) + tag)

	pf = await _make(board_id)
	pf.progression.mods.add(Cards.GLASS_CANNON)
	pf.receive_attack(4)
	_check(pf._pending == 5, "Glass Cannon: +25% incoming atoms (rounded up)" + tag)

	pf = await _make(board_id)
	pf.progression.mods.add(Cards.COUNTERSTRIKE)
	pf.receive_attack(2)
	_attacks = 0
	_run(pf, GAP + 0.2, true)
	_check(_attacks == 1, "Counterstrike sends 1 back per landing" + tag)
	_run(pf, GAP + 0.2, true)
	_check(_attacks == 2 and pf._pending == 0, "...and again for the second" + tag)

	pf = await _make(board_id)
	pf.progression.mods.add(Cards.GARDENER)
	pf.receive_attack(1)
	pf._incoming.ghosts[0].cell = Vector2i(7, 7) # out of the way of the clearing pair
	_run(pf, GAP + 0.2, true)
	_check(pf._stray.size() == 1 and _filled(pf) == 1, "a stray landed" + tag)
	pf._queue[0] = e
	pf.try_place(Vector2i(0, 6))
	pf._queue[0] = w
	pf.try_place(Vector2i(1, 6))
	_check(_filled(pf) == 0, "Gardener removes the landed stray after a clear" + tag)


func _init() -> void:
	await _suite("square")
	await _suite("hex")
	_finish()
