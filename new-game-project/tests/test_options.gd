extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_options.gd
## Every setup option really changes the game, and the defaults reproduce the old behaviour.


## A playfield with the given option values; Relaxed unless the pressure is in `values`.
func _make(values := {}, versus := false) -> Playfield:
	var pf := Playfield.new()
	pf.versus = versus
	pf.config.set_value("pressure", GameConfig.PRESSURE_NONE)
	for id in values:
		pf.config.set_value(id, str(values[id]))
	root.add_child(pf)
	await process_frame
	pf.start(4242)
	pf.progression.pick_levels.clear()
	return pf


func _empty(pf: Playfield) -> void:
	pf.board = Board.new(pf.board_w, pf.board_h, pf.topology)
	pf._apply_rules_to_board()


func _count_atoms(pf: Playfield) -> int:
	var n := 0
	for y in pf.board_h:
		for x in pf.board_w:
			if pf.board.get_atom(Vector2i(x, y)) != 0:
				n += 1
	return n


## Draws many atoms from the playfield's queue generator: {bombs, wild, crowded}.
func _sample(pf: Playfield, draws := 1500) -> Dictionary:
	var r := {"bombs": 0, "wild": 0, "crowded": 0, "bomb_conn": {}}
	for i in draws:
		var a := pf._new_atom()
		if Atoms.is_wild(a):
			r.wild += 1
			continue
		var c := pf.topology.connection_count(a)
		if c >= 4:
			r.crowded += 1
		if Atoms.is_bomb(a):
			r.bombs += 1
			r.bomb_conn[c] = true
	return r


func _init() -> void:
	await _defaults_unchanged()
	await _board_size()
	await _queue_options()
	await _board_rules()
	await _scoring_and_cards()
	await _pressure()
	await _versus()
	_finish()


func _defaults_unchanged() -> void:
	for board_id in ["square", "hex"]:
		var tag := " [%s]" % board_id
		var pf := await _make({"board": board_id, "pressure": GameConfig.PRESSURE_TURNS})
		# The old generation: constants straight into Board.preplace and Atoms.random_atom.
		var topo := Topology.for_id(board_id)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var b := Board.new(8, 8, topo)
		b.preplace(10, rng)
		_check(b.snapshot() == pf.board.snapshot(), "default preplaced atoms equal the old generation" + tag)
		var same := true
		for i in 12:
			var legacy := Atoms.random_atom(rng, Atoms.BOMB_CHANCE, Atoms.WILD_CHANCE, Modifiers.new().shape_weights(topo), Atoms.BOMB_MIN_CONNECTIONS, topo)
			var mine: int = pf._queue[i] if i < 2 else pf._new_atom() # the first two were drawn at start
			if legacy != mine:
				same = false
		_check(same, "default queue atoms equal the old generation" + tag)
		_check(pf._queue.size() == 2 and pf.board_w == 8 and pf.board_h == 8, "default queue (held + 1 preview) and 8x8 board" + tag)
		_check(pf.board.blast_radius == 1 and pf.board.max_open_ends == 0 and pf.board.min_molecule == 2, "default board rules" + tag)
		_check(pf._danger.countdown == float(Danger.interval(1) + Danger.FIRST_GRACE), "default solo schedule" + tag)
		var wide := pf.board_pixel_size().x
		_check(is_equal_approx(wide, 8.0 * 72.0), "default board is 576 px wide" + tag)
		pf.queue_free()


func _board_size() -> void:
	for board_id in ["square", "hex"]:
		for n in [6, 8, 10]:
			var tag := " [%s %d]" % [board_id, n]
			var pf := await _make({"board": board_id, "board_size": n, "preplaced": 5})
			_check(pf.board.width == n and pf.board.height == n and pf.board.snapshot().size() == n * n, "board is %dx%d" % [n, n] + tag)
			var px := pf.board_pixel_size()
			_check(is_equal_approx(px.x, 576.0) and px.y <= 580.0, "board is as wide as a normal one and no taller (%s)" % str(px) + tag)
			# Every cell sits inside the board rectangle and maps back from its centre.
			var round_trip := true
			for y in n:
				for x in n:
					var p := Vector2i(x, y)
					var c := pf.topology.cell_center(p, pf.cell_size)
					if c.x < 0 or c.y < 0 or c.x > px.x or c.y > px.y or pf.topology.cell_at(c, pf.cell_size) != p:
						round_trip = false
			_check(round_trip, "cells map to and from screen positions" + tag)
			_check(_count_atoms(pf) == 5, "preplaced atoms fit the board" + tag)
			# Playing and the danger ghosts stay inside the board.
			pf.config.set_value("pressure", GameConfig.PRESSURE_TURNS)
			pf.start(7)
			for g in pf._danger.ghosts:
				_check(pf.board.in_bounds(g.cell), "stray ghost is on the board" + tag)
			pf.queue_free()
	# The versus mirror takes the host's size too: snapshots of that size are accepted.
	var host := await _make({"board_size": 10}, true)
	var mirror := Playfield.new()
	mirror.interactive = false
	mirror.base_cell_size = 40
	mirror.config = host.config.duplicate_config()
	root.add_child(mirror)
	await process_frame
	mirror.start(4242)
	_check(mirror.board.width == 10 and is_equal_approx(mirror.board_pixel_size().x, 320.0), "mirror board is 10x10 and still 320 px wide")
	mirror.apply_snapshot(host.board.snapshot())
	_check(mirror.board.snapshot() == host.board.snapshot(), "mirror shows a 10x10 snapshot")
	var wrong := PackedInt32Array()
	wrong.resize(64)
	var before := mirror.board.snapshot()
	mirror.apply_snapshot(wrong)
	_check(mirror.board.snapshot() == before, "a snapshot of the wrong size is ignored")
	host.queue_free()
	mirror.queue_free()


func _queue_options() -> void:
	for n in [0, 5, 16]:
		var pf := await _make({"preplaced": n})
		_check(_count_atoms(pf) == n, "preplaced %d gives %d atoms" % [n, n])
		pf.queue_free()
	for n in [1, 2, 3, 4]:
		var pf := await _make({"preview": n})
		_check(pf._queue.size() == n + 1, "preview %d: held atom plus %d shown" % [n, n])
		pf.progression.mods.add(Cards.LONG_VIEW)
		pf._fit_queue()
		_check(pf._queue.size() == n + 2, "Long View adds one to preview %d" % n)
		pf.queue_free()

	var def := await _make()
	var none := await _make({"bombs": "0"})
	var few := await _make({"bombs": "0.15"})
	var many := await _make({"bombs": "0.6"})
	var s_def := _sample(def)
	var s_none := _sample(none)
	var s_few := _sample(few)
	var s_many := _sample(many)
	_check(s_none.bombs == 0, "no bombs with Bombs: None")
	_check(s_few.bombs < s_def.bombs and s_def.bombs < s_many.bombs, "more bombs with each Bombs step (%d < %d < %d)" % [s_few.bombs, s_def.bombs, s_many.bombs])
	_check(def.board.bomb_chance == 0.35 and many.board.bomb_chance == 0.6, "preplaced atoms use the bomb option too")

	# Bomb minimum connections: the default only blesses 4-connection atoms.
	var lowest := func(s: Dictionary) -> int:
		var m := 99
		for c in s.bomb_conn:
			m = mini(m, c)
		return m
	var low := await _make({"bombs": "0.6", "bomb_min": 2})
	var high := await _make({"bombs": "0.6", "bomb_min": 5})
	_check(lowest.call(_sample(many)) == 4, "default: only 4-connection atoms are bombs")
	_check(lowest.call(_sample(low)) == 2, "bomb_min 2: 2-connection atoms can be bombs")
	_check(_sample(high).bombs == 0, "bomb_min 5: no bombs on a square board (4 connections at most)")
	var hex_high := await _make({"bombs": "0.6", "bomb_min": 5, "board": "hex"})
	_check(lowest.call(_sample(hex_high)) >= 5, "bomb_min 5: only 5- and 6-connection atoms are bombs on a hex board")

	# Wildcards.
	var wild := await _make({"wild_chance": "0.2"})
	_check(s_def.wild == 0 and _sample(wild).wild > 100, "wildcards appear only when the option is set")

	# Crowded atoms.
	var rare := await _make({"crowded": "0.5"})
	var never := await _make({"crowded": "0"})
	var common := await _make({"crowded": "4"})
	_check(_sample(never).crowded == 0, "crowded Never: no 4+ connection atoms")
	_check(_sample(rare).crowded < s_def.crowded and s_def.crowded < _sample(common).crowded, "crowded atoms get rarer / more common with the option")
	for pf in [def, none, few, many, low, high, hex_high, wild, rare, never, common]:
		pf.queue_free()


func _board_rules() -> void:
	# Blast radius: the preview area and the real blast.
	for board_id in [["square", 9, 25], ["hex", 7, 19]]:
		var pf1 := await _make({"board": board_id[0]})
		var pf2 := await _make({"board": board_id[0], "blast_radius": 2})
		var mid := Vector2i(4, 4)
		_check(pf1.blast_preview_cells(mid).size() == board_id[1], "radius 1 blast preview [%s]" % board_id[0])
		_check(pf2.blast_preview_cells(mid).size() == board_id[2], "radius 2 blast preview [%s]" % board_id[0])
		pf1.queue_free()
		pf2.queue_free()
	for radius in [1, 2]:
		var pf := await _make({"blast_radius": radius})
		_empty(pf)
		var near := Vector2i(2, 5) # one cell below the bomb, outside nothing; two cells for the far one
		var far := Vector2i(2, 6)
		pf.board.place(near, Atoms.N)
		pf.board.place(far, Atoms.N)
		pf.board.place(Vector2i(2, 4), Atoms.E | Atoms.BOMB)
		pf.board.place(Vector2i(3, 4), Atoms.W) # closes the pair, the bomb at (2,4) blows
		_check(pf.board.is_empty(near), "radius %d: a neighbour is wiped" % radius)
		_check(pf.board.is_empty(far) == (radius == 2), "radius %d: the atom two cells away %s" % [radius, "is wiped" if radius == 2 else "survives"])
		pf.queue_free()

	# Loose molecules and minimum size, combined with the cards.
	var pf := await _make({"open_ends": 1})
	_empty(pf)
	pf.board.place(Vector2i(0, 0), Atoms.E)
	pf.board.place(Vector2i(1, 0), Atoms.W | Atoms.E)
	var cleared := pf.board.place(Vector2i(2, 0), Atoms.W | Atoms.S) # one open end (south)
	_check(cleared.size() == 3, "open_ends 1: a molecule of 3 clears with one open end")
	pf.progression.mods.add(Cards.LOOSE_ENDS)
	_check(pf.mods.max_open_ends(2) == 2 and pf.mods.max_open_ends(0) == 1, "the Loose Ends card never lowers the option")
	pf.queue_free()

	pf = await _make({"open_ends": 0})
	_empty(pf)
	pf.board.place(Vector2i(0, 0), Atoms.E)
	pf.board.place(Vector2i(1, 0), Atoms.W | Atoms.E)
	_check(pf.board.place(Vector2i(2, 0), Atoms.W | Atoms.S).is_empty(), "default: an open end keeps the molecule")
	pf.queue_free()

	pf = await _make({"min_molecule": 3})
	_empty(pf)
	pf.board.place(Vector2i(0, 0), Atoms.E)
	_check(pf.board.place(Vector2i(1, 0), Atoms.W).is_empty(), "min_molecule 3: a pair does not clear")
	_check(pf.board.min_molecule == 3, "the board rule comes from the option")
	pf.queue_free()


func _scoring_and_cards() -> void:
	_check(Scoring.points(4, 3) == 9 and Scoring.points(5, 3) == 12 and Scoring.points(10, 8) == 52 and Scoring.points(5) == 15, "Scoring.points honours the cap")
	_check(Scoring.atom_points(9, 3) == 3 and Scoring.atom_points(2, 3) == 2, "Scoring.atom_points honours the cap")
	for cap in [3, 5, 8]:
		var pf := await _make({"max_points": cap})
		_empty(pf)
		# A straight chain of four atoms closes on the last placement.
		for step in [[Vector2i(0, 0), Atoms.E], [Vector2i(1, 0), Atoms.W | Atoms.E], [Vector2i(2, 0), Atoms.W | Atoms.E], [Vector2i(3, 0), Atoms.W]]:
			pf._queue[0] = step[1]
			pf.try_place(step[0])
		_check(pf.score == Scoring.points(4, cap), "max_points %d: a 4-atom molecule scores %d (got %d)" % [cap, Scoring.points(4, cap), pf.score])
		pf.queue_free()

	var base := Progression.new()
	_check(Progression.xp_needed(1) == 32 and Progression.xp_needed(3, 2.0) == 112 and Progression.xp_needed(1, 0.5) == 16, "xp_needed scales with the option")
	var slow := Progression.new()
	_check(base.add_xp(40) == 1 and slow.add_xp(40, 2.0) == 0, "double XP cost: 40 points no longer level up")
	var quick := Progression.new()
	_check(quick.add_xp(33, 0.5) >= 1, "half XP cost levels up sooner")

	var pf := await _make({"reroll_cooldown": 6})
	pf.progression.mods.add(Cards.REROLL)
	pf.reroll_held()
	_check(pf._reroll_cd == 6, "Reroll recharges after the chosen number of placements")
	pf.queue_free()
	pf = await _make()
	pf.progression.mods.add(Cards.REROLL)
	pf.reroll_held()
	_check(pf._reroll_cd == Playfield.REROLL_COOLDOWN, "default Reroll recharge is unchanged")
	pf.queue_free()

	var mods := Modifiers.new()
	_check(mods.queue_size() == 2 and mods.queue_size(3) == 4 and mods.bomb_chance() == Atoms.BOMB_CHANCE and is_equal_approx(mods.bomb_chance(0.6), 0.6), "Modifiers defaults and bases")
	_check(mods.min_bomb_connections(null, 3) == 3 and mods.wild_chance(0.1) == 0.1 and mods.min_molecule(3) == 3, "Modifiers bases for bombs, wildcards and size")


func _pressure() -> void:
	# Turn-based schedule.
	var pf := await _make({"pressure": GameConfig.PRESSURE_TURNS, "turn_start": 12, "turn_min": 5, "turn_grace": 0})
	_check(pf._danger.countdown == 12.0, "turn_start 12, no grace: first drop after 12 placements")
	pf.progression.level = 30
	pf.start(1)
	_check(pf._danger.countdown == 5.0, "turn_min 5: the interval stops at 5")
	pf.queue_free()
	pf = await _make({"pressure": GameConfig.PRESSURE_TURNS, "turn_grace": 4})
	_check(pf._danger.countdown == float(Danger.interval(1) + 4), "turn_grace 4 extends the first drop")
	pf.queue_free()

	# Timed schedule.
	pf = await _make({"pressure": GameConfig.PRESSURE_TIMED, "time_start": 25, "time_min": 8, "time_grace": 10})
	_check(is_equal_approx(pf._danger.countdown, 35.0), "timed: 25 s plus 10 s grace at level 1")
	pf.progression.level = 40
	pf.start(1)
	_check(is_equal_approx(pf._danger.countdown, 18.0), "time_min 8 plus 10 s grace at a high level")
	pf._danger.schedule_next(pf.board, 40, pf._fx_rng)
	_check(is_equal_approx(pf._danger.countdown, 8.0), "later drops are time_min apart")
	pf.queue_free()

	# Two strays at once from the chosen level.
	for combo in [[5, 2], [10, 1], [999, 1]]:
		pf = await _make({"pressure": GameConfig.PRESSURE_TURNS, "double_level": combo[0]})
		pf.progression.level = 6
		pf.start(1)
		_check(pf._danger.ghosts.size() == combo[1], "double_level %d: %d stray(s) announced at level 6" % [combo[0], combo[1]])
		pf.queue_free()

	_check(Danger.interval(1, 12, 5) == 12 and Danger.interval(99, 12, 5) == 5 and Danger.seconds(1, 25.0, 8.0) == 25.0 and Danger.seconds(99, 25.0, 8.0) == 8.0 and Danger.spawn_count(6, 5) == 2, "Danger statics take the schedule as parameters")


func _versus() -> void:
	# Seconds between incoming strays.
	for secs in [3, 12]:
		var pf := await _make({"incoming_seconds": secs}, true)
		pf.receive_attack(1)
		_check(is_equal_approx(pf._incoming.countdown, float(secs)), "incoming gap of %d s" % secs)
		pf.queue_free()

	# Points per stray atom.
	for per in [15, 25, 40]:
		var pf := await _make({"attack_points": per}, true)
		_empty(pf)
		var sent := [0]
		pf.attack.connect(func(n: int) -> void: sent[0] += n)
		pf._attack_charge = float(per) - 3.0 # the clearing pair is worth 3 points
		pf._queue[0] = Atoms.E
		pf.try_place(Vector2i(0, 0))
		pf._queue[0] = Atoms.W
		pf.try_place(Vector2i(1, 0))
		_check(sent[0] == 1 and is_equal_approx(pf._attack_charge, 0.0), "%d points per stray atom: the pair sends exactly one" % per)
		var short := await _make({"attack_points": per}, true)
		_empty(short)
		var sent2 := [0]
		short.attack.connect(func(n: int) -> void: sent2[0] += n)
		short._attack_charge = float(per) - 4.0
		short._queue[0] = Atoms.E
		short.try_place(Vector2i(0, 0))
		short._queue[0] = Atoms.W
		short.try_place(Vector2i(1, 0))
		_check(sent2[0] == 0 and is_equal_approx(short._attack_charge, float(per) - 1.0), "%d points per stray atom: one point short sends nothing and carries over" % per)
		pf.queue_free()
		short.queue_free()
