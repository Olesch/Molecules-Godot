extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_board_extra.gd


func _init() -> void:
	var N := Atoms.N
	var E := Atoms.E
	var S := Atoms.S
	var W := Atoms.W

	# rotate_cw over all masks: 4 rotations is identity, popcount preserved, 0 and 15 fixed.
	var rot_ok := true
	for m in 16:
		var r := m
		for i in 4:
			r = Atoms.rotate_cw(r)
		if r != m or Atoms.connection_count(Atoms.rotate_cw(m)) != Atoms.connection_count(m):
			rot_ok = false
	_check(rot_ok, "rotate_cw x4 identity, count preserved (all masks)")
	_check(Atoms.rotate_cw(0) == 0 and Atoms.rotate_cw(15) == 15, "rotate fixed points")
	_check(Atoms.rotate_cw(E) == S and Atoms.rotate_cw(S) == W, "rotate E->S, S->W")
	_check(Atoms.opposite(0) == 2 and Atoms.opposite(3) == 1, "opposite")

	# 1x1 board: nothing can bond, atom stays, board full.
	var b := Board.new(1, 1)
	_check(b.place(Vector2i(0, 0), N | E | S | W).is_empty(), "1x1 never clears")
	_check(b.is_full(), "1x1 full after placement")

	# Placement validation.
	b = Board.new(2, 2)
	_check(b.place(Vector2i(-1, 0), N).is_empty(), "out of bounds rejected (neg)")
	_check(b.place(Vector2i(2, 0), N).is_empty(), "out of bounds rejected (high)")
	_check(b.place(Vector2i(0, 0), 0).is_empty() and b.is_empty(Vector2i(0, 0)), "zero mask rejected")

	# Bond across the board edge does not wrap.
	b = Board.new(3, 1)
	b.place(Vector2i(0, 0), W)
	_check(b.place(Vector2i(2, 0), E).is_empty(), "no wraparound bond")
	_check(not b.is_bonded(Vector2i(0, 0), 3), "edge W not bonded")

	# Chain of 3: A(E) - B(W|E) - C(W).
	b = Board.new(5, 1)
	b.place(Vector2i(0, 0), E)
	b.place(Vector2i(2, 0), W)
	_check(b.get_atom(Vector2i(0, 0)) == E, "chain end waits")
	var c := b.place(Vector2i(1, 0), W | E)
	_check(c.size() == 3, "chain of 3 clears via middle placement")
	_check(b.is_empty(Vector2i(0, 0)) and b.is_empty(Vector2i(1, 0)) and b.is_empty(Vector2i(2, 0)), "chain removed")

	# Returned array is independent of board state / a copy-safe value.
	b = Board.new(2, 1)
	b.place(Vector2i(0, 0), E)
	var cl := b.place(Vector2i(1, 0), W)
	cl.clear()
	b.place(Vector2i(0, 0), E)
	_check(b.get_atom(Vector2i(0, 0)) == E, "mutating returned array doesn't affect board")

	# Cleared cells are reusable.
	_check(b.place(Vector2i(1, 0), W).size() == 2, "cell reusable after clear")

	# Placing next to a closed-looking neighbour that points elsewhere.
	b = Board.new(3, 1)
	b.place(Vector2i(0, 0), E)
	_check(b.place(Vector2i(1, 0), W | E).is_empty(), "open east end keeps pair")
	_check(b.molecule_at(Vector2i(1, 0)).size() == 2, "molecule_at size 2")
	_check(b.molecule_at(Vector2i(2, 0)).is_empty(), "molecule_at empty cell")
	_check(b.place(Vector2i(2, 0), W).size() == 3, "late closer clears all 3")

	# Adjacent non-bonded atoms are separate molecules (a closed one clears, neighbour stays).
	b = Board.new(3, 2)
	b.place(Vector2i(2, 0), N | S)
	b.place(Vector2i(0, 0), E)
	_check(b.place(Vector2i(1, 0), W).size() == 2, "pair clears")
	_check(b.get_atom(Vector2i(2, 0)) == (N | S), "unrelated neighbour untouched")

	# Full 4-way atom in a 3x3 plus: centre needs 4 arms each pointing back.
	b = Board.new(3, 3)
	b.place(Vector2i(1, 0), S)
	b.place(Vector2i(2, 1), W)
	b.place(Vector2i(1, 2), N)
	b.place(Vector2i(0, 1), E)
	_check(b.place(Vector2i(1, 1), N | E | S | W).size() == 5, "plus molecule clears")

	_finish()
