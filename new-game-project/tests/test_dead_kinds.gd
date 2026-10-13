extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_dead_kinds.gd
## Dead molecules split into permanent (an open end faces the border or an atom of the same
## molecule) and fixable (it faces an atom of another molecule), on both boards.


func _init() -> void:
	_square()
	_hex()
	_finish(true)


func _put(b: Board, cells: Dictionary) -> void:
	var snap := b.snapshot()
	for p in cells:
		snap[p.y * b.width + p.x] = cells[p]
	b.load_snapshot(snap)


func _square() -> void:
	var tag := " [square]"
	var b := Board.new(6, 6)
	# A lone atom pointing off the board: permanent.
	_put(b, {Vector2i(0, 2): Atoms.W})
	var g := b.molecule_at(Vector2i(0, 2))
	var k := b.blocked_end_kinds(g)
	_check(k.permanent == 1 and k.fixable == 0 and b.is_dead(g) and b.is_permanently_dead(g), "border end is permanent" + tag)

	# An end facing an atom of another molecule: fixable, and removing that atom revives it.
	b = Board.new(6, 6)
	_put(b, {Vector2i(2, 2): Atoms.E, Vector2i(3, 2): Atoms.E})
	g = b.molecule_at(Vector2i(2, 2))
	k = b.blocked_end_kinds(g)
	_check(k.permanent == 0 and k.fixable == 1 and b.is_dead(g) and not b.is_permanently_dead(g), "end facing another molecule is fixable" + tag)
	_check(b.blocked_end_count(g) == int(k.permanent) + int(k.fixable), "kinds add up to blocked_end_count" + tag)
	b.remove_atom(Vector2i(3, 2))
	g = b.molecule_at(Vector2i(2, 2))
	_check(not b.is_dead(g) and not b.is_permanently_dead(g) and b.blocked_end_kinds(g).fixable == 0, "removing the blocker revives it" + tag)

	# An end facing an atom of its own molecule: permanent.
	b = Board.new(6, 6)
	_put(b, {Vector2i(2, 2): Atoms.E | Atoms.S, Vector2i(3, 2): Atoms.S, Vector2i(2, 3): Atoms.N | Atoms.E, Vector2i(3, 3): Atoms.N | Atoms.W})
	g = b.molecule_at(Vector2i(2, 2))
	k = b.blocked_end_kinds(g)
	_check(g.size() == 4 and k.permanent == 1 and k.fixable == 0 and b.is_permanently_dead(g), "end facing its own molecule is permanent" + tag)
	b.max_open_ends = 1
	_check(not b.is_dead(g) and not b.is_permanently_dead(g), "one open end allowed: not dead" + tag)

	# Allowance with mixed ends: 1 permanent + 1 fixable and one open end allowed: dead, but fixable.
	b = Board.new(6, 6)
	b.max_open_ends = 1
	_put(b, {Vector2i(1, 0): Atoms.N | Atoms.E, Vector2i(2, 0): Atoms.W | Atoms.E | Atoms.S, Vector2i(3, 0): Atoms.W, Vector2i(2, 1): Atoms.S})
	g = b.molecule_at(Vector2i(1, 0))
	k = b.blocked_end_kinds(g)
	_check(g.size() == 3 and k.permanent == 1 and k.fixable == 1 and b.is_dead(g) and not b.is_permanently_dead(g), "allowance 1: permanent+fixable is dead but not permanently" + tag)
	b.remove_atom(Vector2i(2, 1))
	_check(not b.is_dead(b.molecule_at(Vector2i(1, 0))), "allowance 1: clearing the blocker revives it" + tag)

	# Two permanent ends exceed an allowance of 1 but not of 2.
	b = Board.new(6, 6)
	_put(b, {Vector2i(1, 0): Atoms.N | Atoms.E, Vector2i(2, 0): Atoms.W | Atoms.E, Vector2i(3, 0): Atoms.W | Atoms.N})
	g = b.molecule_at(Vector2i(1, 0))
	b.max_open_ends = 1
	_check(b.is_permanently_dead(g), "2 permanent ends, allowance 1: permanently dead" + tag)
	b.max_open_ends = 2
	_check(not b.is_dead(g) and not b.is_permanently_dead(g), "2 permanent ends, allowance 2: alive" + tag)
	_check(not b.is_dead([] as Array[Vector2i]) and not b.is_permanently_dead([] as Array[Vector2i]), "empty group is neither" + tag)


func _hex() -> void:
	var tag := " [hex]"
	var hx := Topology.hex()
	var b := Board.new(7, 7, hx)
	# Lone atom pointing west at the left border (dir 3).
	_put(b, {Vector2i(0, 2): 1 << 3})
	var g := b.molecule_at(Vector2i(0, 2))
	var k := b.blocked_end_kinds(g)
	_check(k.permanent == 1 and k.fixable == 0 and b.is_permanently_dead(g), "border end is permanent" + tag)

	# Fixable: an end facing another molecule's atom.
	b = Board.new(7, 7, hx)
	_put(b, {Vector2i(3, 3): 1 << 0, Vector2i(4, 3): 1 << 0})
	g = b.molecule_at(Vector2i(3, 3))
	k = b.blocked_end_kinds(g)
	_check(k.permanent == 0 and k.fixable == 1 and b.is_dead(g) and not b.is_permanently_dead(g), "end facing another molecule is fixable" + tag)
	b.remove_atom(Vector2i(4, 3))
	_check(not b.is_dead(b.molecule_at(Vector2i(3, 3))), "removing the blocker revives it" + tag)

	# Triangle A(2,2) B(3,2) C(2,3): everything bonded except A's east end, which faces B.
	b = Board.new(7, 7, hx)
	_put(b, {Vector2i(2, 2): (1 << 0) | (1 << 1), Vector2i(3, 2): 1 << 2, Vector2i(2, 3): (1 << 4) | (1 << 5)})
	g = b.molecule_at(Vector2i(2, 2))
	k = b.blocked_end_kinds(g)
	_check(g.size() == 3 and k.permanent == 1 and k.fixable == 0 and b.is_permanently_dead(g), "end facing its own molecule is permanent" + tag)
	b.max_open_ends = 1
	_check(not b.is_dead(g) and not b.is_permanently_dead(g) and b.is_closed(g), "one open end allowed: closed, not dead" + tag)
