extends SceneTree
## Run: godot --headless --path new-game-project --script res://tests/test_board.gd

var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		print("ok   ", name)
	else:
		print("FAIL ", name)
		_failed += 1


func _init() -> void:
	var N := Atoms.N
	var E := Atoms.E
	var S := Atoms.S
	var W := Atoms.W

	_check(Atoms.rotate_cw(N) == E, "rotate N -> E")
	_check(Atoms.rotate_cw(W) == N, "rotate W -> N")
	_check(Atoms.rotate_cw(N | S) == (E | W), "rotate straight")
	_check(Atoms.connection_count(N | E | W) == 3, "connection count")

	# Two single-connection atoms facing each other form a molecule.
	var b := Board.new(4, 4)
	_check(b.place(Vector2i(0, 0), E).is_empty(), "first half stays open")
	var cleared := b.place(Vector2i(1, 0), W)
	_check(cleared.size() == 2, "pair clears")
	_check(b.is_empty(Vector2i(0, 0)) and b.is_empty(Vector2i(1, 0)), "pair removed from board")

	# One-sided pointing is not a bond.
	b = Board.new(4, 4)
	b.place(Vector2i(0, 0), E)
	_check(b.place(Vector2i(1, 0), S).is_empty(), "no mutual bond, no clear")
	_check(not b.is_bonded(Vector2i(0, 0), 1), "not bonded")

	# Pointing off the board is an open end.
	b = Board.new(3, 3)
	_check(b.place(Vector2i(0, 0), N).is_empty(), "edge-pointing atom stays")

	# 2x2 ring closes only when the last corner arrives.
	b = Board.new(4, 4)
	b.place(Vector2i(0, 0), E | S)
	b.place(Vector2i(1, 0), W | S)
	b.place(Vector2i(0, 1), N | E)
	_check(b.get_atom(Vector2i(0, 0)) != 0, "ring open before last corner")
	_check(b.place(Vector2i(1, 1), N | W).size() == 4, "ring of 4 clears")

	# A closed pair touching an open chain: the whole group must be closed.
	b = Board.new(4, 4)
	b.place(Vector2i(0, 0), E | S)
	b.place(Vector2i(0, 1), N | E)
	b.place(Vector2i(1, 0), W | S | E) # has a dangling east end
	b.place(Vector2i(1, 1), N | W)
	_check(b.get_atom(Vector2i(1, 1)) != 0, "group with open end does not clear")

	# Occupied cells reject placement.
	b = Board.new(2, 2)
	b.place(Vector2i(0, 0), N)
	_check(b.place(Vector2i(0, 0), E).is_empty() and b.get_atom(Vector2i(0, 0)) == N, "occupied cell rejected")

	# Full board detection.
	b = Board.new(2, 1)
	_check(not b.is_full(), "empty board not full")
	b.place(Vector2i(0, 0), N)
	b.place(Vector2i(1, 0), N)
	_check(b.is_full(), "full board")

	# Bombs: rotation keeps the flag, and a cleared bomb wipes its 3x3 neighbourhood.
	_check(Atoms.rotate_cw(E | Atoms.BOMB) == (S | Atoms.BOMB), "rotate keeps bomb flag")
	_check(Atoms.connection_count(E | Atoms.BOMB) == 1, "bomb flag is not a connection")
	b = Board.new(5, 5)
	b.place(Vector2i(2, 1), N)
	b.place(Vector2i(1, 2), N)
	b.place(Vector2i(4, 4), N) # outside the blast
	b.place(Vector2i(2, 2), E | Atoms.BOMB)
	var boom := b.place(Vector2i(3, 2), W)
	_check(boom.size() == 4, "bomb pair + 2 neighbours wiped (got %d)" % boom.size())
	_check(b.last_exploded == [Vector2i(2, 2)], "one explosion recorded")
	_check(b.is_empty(Vector2i(2, 1)) and b.is_empty(Vector2i(1, 2)), "neighbours wiped")
	_check(b.get_atom(Vector2i(4, 4)) == N, "far atom survives")

	# Chain reaction: a bomb caught in a blast explodes as well.
	b = Board.new(7, 3)
	b.place(Vector2i(0, 0), E | Atoms.BOMB)
	b.place(Vector2i(3, 1), N | Atoms.BOMB) # chained: caught by blast of (1,0)
	b.place(Vector2i(2, 1), N | Atoms.BOMB) # inside blast of the bomb at (1,0)
	b.place(Vector2i(6, 1), N)              # reachable only through the chain
	b.place(Vector2i(4, 1), S)              # next to second chained bomb (3,1)
	var chain := b.place(Vector2i(1, 0), W | Atoms.BOMB)
	_check(b.last_exploded.size() >= 2, "chain explodes (got %d)" % b.last_exploded.size())
	_check(b.is_empty(Vector2i(4, 1)), "chain reached atom next to second bomb")
	_check(b.get_atom(Vector2i(6, 1)) == N, "chain stops at radius")
	_check(chain.size() == 5, "chain removed count (got %d)" % chain.size())

	# A bomb whose molecule is still open does nothing.
	b = Board.new(3, 3)
	b.place(Vector2i(1, 1), N)
	_check(b.place(Vector2i(0, 1), E | S | Atoms.BOMB).is_empty(), "open bomb molecule keeps everything")
	_check(b.get_atom(Vector2i(1, 1)) == N, "neighbour intact")

	# Wildcards: link to every neighbour pointing at them, never leave an open end.
	_check(Atoms.rotate_cw(Atoms.WILD) == Atoms.WILD, "wildcard rotation is a no-op")
	b = Board.new(5, 3)
	_check(b.place(Vector2i(2, 1), Atoms.WILD).is_empty(), "lone wildcard does not clear")
	b = Board.new(5, 3)
	b.place(Vector2i(0, 0), E)
	_check(b.place(Vector2i(1, 0), Atoms.WILD).size() == 2, "wildcard closes a single dangling end")
	b = Board.new(5, 3)
	b.place(Vector2i(0, 0), E)
	b.place(Vector2i(2, 0), W)
	_check(b.place(Vector2i(1, 0), Atoms.WILD).size() == 3, "wildcard bridges two atoms")
	b = Board.new(5, 3)
	b.place(Vector2i(0, 0), S)
	_check(b.place(Vector2i(1, 0), Atoms.WILD).is_empty(), "atom not pointing at wildcard is unlinked")
	b = Board.new(5, 3)
	b.place(Vector2i(0, 0), E | S)
	_check(b.place(Vector2i(1, 0), Atoms.WILD).is_empty(), "other open end still blocks the clear")
	b = Board.new(5, 3)
	b.place(Vector2i(1, 1), Atoms.WILD)
	_check(b.place(Vector2i(2, 1), Atoms.WILD).is_empty(), "two wildcards do not link")
	b = Board.new(5, 3)
	b.place(Vector2i(0, 0), E)
	b.place(Vector2i(1, 0), Atoms.WILD)
	_check(b.get_atom(Vector2i(0, 0)) == 0, "wildcard placed second still cleared the first")

	# Wildcard + bomb: wildcard is wiped by a blast like any other atom.
	b = Board.new(5, 5)
	b.place(Vector2i(2, 1), Atoms.WILD)
	b.place(Vector2i(2, 2), E | Atoms.BOMB)
	b.place(Vector2i(3, 2), W)
	_check(b.is_empty(Vector2i(2, 1)), "blast wipes wildcard")

	# Preplacement never leaves a closed (uncleareable) molecule.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for round in 20:
		b = Board.new(8, 8)
		b.preplace(10, rng)
		var filled := 0
		var stuck := false
		for y in 8:
			for x in 8:
				var p := Vector2i(x, y)
				if b.get_atom(p) != 0:
					filled += 1
					if b.is_closed(b.molecule_at(p)):
						stuck = true
		if filled == 0 or filled > 10 or stuck:
			_check(false, "preplace round %d: filled=%d stuck=%s" % [round, filled, stuck])
	_check(true, "preplace rounds done")

	print("failures: ", _failed)
	quit(1 if _failed > 0 else 0)
