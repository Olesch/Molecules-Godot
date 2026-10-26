extends "res://tests/test_base.gd"
## Run: godot --headless --path . --script res://tests/test_board_hex.gd
## Gameplay on the hexagonal board: bonds along all three axes, rings, wildcards, bombs,
## rule knobs, snapshots, scatter safety and the solo danger.

const BOMB := Atoms.BOMB
const WILD := Atoms.WILD

var hx := Topology.hex()


func _bit(d: int) -> int:
	return 1 << d


func _board(w := 7, h := 7) -> Board:
	return Board.new(w, h, hx)


func _init() -> void:
	_pairs()
	_trio_and_ring()
	_wildcards()
	_bombs()
	_knobs()
	_snapshot_and_scatter()
	_danger()
	_finish(true)


func _pairs() -> void:
	_check(_board().topology == hx and Board.new(3, 3).topology == Topology.square(), "board topology defaults to square")
	var all_ok := true
	for y in [2, 3]:
		for d in 3:
			var b := _board()
			var c := Vector2i(3, y)
			var other := hx.neighbor(c, d)
			var first := b.place(c, _bit(d))
			var second := b.place(other, _bit(hx.opposite(d)))
			if not first.is_empty() or second.size() != 2 or not b.is_empty(c) or not b.is_empty(other):
				all_ok = false
	_check(all_ok, "two atoms facing each other clear along E-W, SE-NW and SW-NE on even and odd rows")
	var b := _board()
	b.place(Vector2i(3, 3), _bit(0))
	_check(b.place(Vector2i(3, 4), _bit(3)).is_empty() and b.place(Vector2i(4, 3), _bit(3)).size() == 2, "a non-facing neighbour does not bond")
	var sq := Board.new(4, 4)
	_check(sq.place(Vector2i(1, 1), 16).is_empty() and sq.get_atom(Vector2i(1, 1)) == 0, "square board rejects hex-only connection bits")
	var hb := _board()
	hb.place(Vector2i(1, 1), _bit(5))
	_check(hb.get_atom(Vector2i(1, 1)) == 32, "hex board accepts all six connection bits")


func _trio_and_ring() -> void:
	for y in [2, 3]:
		var b := _board()
		var m := Vector2i(3, y)
		var east := hx.neighbor(m, 0)
		var sw := hx.neighbor(m, 2)
		b.place(east, _bit(3))
		b.place(sw, _bit(5))
		var cleared := b.place(m, _bit(0) | _bit(2))
		_check(cleared.size() == 3 and b.last_molecule_size == 3, "bent trio clears (row %d)" % y)
	# Ring of six around an empty centre.
	var b := _board()
	var centre := Vector2i(3, 3)
	var ring: Array[Vector2i] = []
	for k in 6:
		ring.append(hx.neighbor(centre, k))
	var geometry_ok := true
	for k in 6:
		if hx.neighbor(ring[k], (k + 2) % 6) != ring[(k + 1) % 6]:
			geometry_ok = false
	_check(geometry_ok, "ring cells are chained by direction k+2")
	var last: Array[Vector2i] = []
	for k in 6:
		last = b.place(ring[k], _bit((k + 2) % 6) | _bit((k + 4) % 6))
		if k < 5:
			_check(last.is_empty(), "open ring stays while building (%d)" % k)
	_check(last.size() == 6 and b.is_empty(centre), "closed ring of six clears")


func _wildcards() -> void:
	var b := _board()
	var c := Vector2i(2, 3)
	var w := hx.neighbor(c, 0)
	var far := hx.neighbor(w, 0)
	b.place(c, _bit(0))
	b.place(far, _bit(3))
	_check(b.place(w, WILD).size() == 3, "wildcard bridges two hex atoms")
	b = _board()
	b.place(c, _bit(1))
	_check(b.place(w, WILD).is_empty(), "atom pointing elsewhere does not link to the wildcard")
	# Sockets: a wildcard links by direction from every side.
	var ok := true
	for d in 6:
		var bb := _board()
		var centre := Vector2i(3, 3)
		bb.place(hx.neighbor(centre, d), _bit(hx.opposite(d)))
		var res := bb.place(centre, WILD)
		if res.size() != 2:
			ok = false
	_check(ok, "a wildcard closes a dangling end from each of the six directions")
	b = _board()
	b.place(hx.neighbor(Vector2i(3, 3), 1), _bit(4))
	b.place(hx.neighbor(Vector2i(3, 3), 4), _bit(1))
	_check(b.place(Vector2i(3, 3), WILD).size() == 3, "wildcard links atoms on opposite sockets (SE and NW)")


func _bombs() -> void:
	for y in [2, 3]:
		var b := _board()
		var c := Vector2i(3, y)
		b.place(c, _bit(0) | BOMB)
		for d in range(1, 6):
			b.load_snapshot(_with(b, hx.neighbor(c, d), _bit(d)))
		var ring2 := hx.neighbor(hx.neighbor(c, 3), 3)
		b.load_snapshot(_with(b, ring2, _bit(0)))
		var cleared := b.place(hx.neighbor(c, 0), _bit(3))
		var flower := hx.cells_within(c, 1, 7, 7)
		var set_ok := cleared.size() == 7
		for f in flower:
			if cleared.find(f) < 0 or not b.is_empty(f):
				set_ok = false
		_check(set_ok and flower.size() == 7, "bomb blasts exactly its 7-cell flower (row %d)" % y)
		_check(b.get_atom(ring2) != 0 and b.last_exploded.size() == 1, "atoms outside the flower survive (row %d)" % y)
	# Chain reaction: a bomb inside the flower blasts its own flower.
	var b2 := _board()
	var c2 := Vector2i(3, 3)
	var west := hx.neighbor(c2, 3)
	var beyond := hx.neighbor(west, 3)
	var untouched := hx.neighbor(hx.neighbor(west, 3), 3)
	b2.place(c2, _bit(0) | BOMB)
	b2.load_snapshot(_with(b2, west, _bit(3) | BOMB))
	b2.load_snapshot(_with(b2, beyond, _bit(0)))
	b2.load_snapshot(_with(b2, untouched, _bit(0)))
	var cleared2 := b2.place(hx.neighbor(c2, 0), _bit(3))
	_check(b2.last_exploded.size() == 2, "the second bomb exploded in a chain")
	_check(cleared2.find(beyond) >= 0 and b2.get_atom(untouched) != 0, "chain reaction reaches one more ring but no further")
	var depth_ok := true
	for i in cleared2.size():
		if cleared2[i] == beyond and b2.last_clear_depths[i] != 2 + 1:
			depth_ok = false
	_check(depth_ok, "blast victim depth = bomb depth + hex distance")


func _knobs() -> void:
	var b := _board()
	b.max_open_ends = 1
	var m := Vector2i(3, 3)
	var east := hx.neighbor(m, 0)
	var sw := hx.neighbor(m, 2)
	b.place(east, _bit(3))
	b.place(sw, _bit(5) | _bit(3))
	_check(b.place(m, _bit(0) | _bit(2)).size() == 3, "loose ends: a 3-atom molecule clears with one open connection")
	b = _board()
	b.place(east, _bit(3))
	b.place(sw, _bit(5) | _bit(3))
	_check(b.place(m, _bit(0) | _bit(2)).is_empty(), "no loose ends: the open connection blocks the clear")
	b = _board()
	b.min_molecule = 3
	b.place(Vector2i(2, 2), _bit(0))
	_check(b.place(Vector2i(3, 2), _bit(3)).is_empty(), "min_molecule 3: a pair does not clear")
	b = _board()
	b.min_molecule = 3
	b.place(Vector2i(2, 2), _bit(0))
	b.place(Vector2i(4, 2), _bit(3))
	_check(b.place(Vector2i(3, 2), _bit(3) | _bit(0)).size() == 3, "min_molecule 3: a chain of three clears")


func _with(b: Board, p: Vector2i, mask: int) -> PackedInt32Array:
	var snap := b.snapshot()
	snap[p.y * b.width + p.x] = mask
	return snap


func _snapshot_and_scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var b := _board(8, 8)
	b.preplace(14, rng)
	var snap := b.snapshot()
	var copy := _board(8, 8)
	copy.load_snapshot(snap)
	_check(copy.snapshot() == snap, "snapshot round trip")
	var other := _board(5, 5)
	other.load_snapshot(snap)
	_check(other.fill_ratio() == 0.0, "snapshot of another size is ignored")
	var safe := true
	var valid := true
	for seed_value in 12:
		rng.seed = seed_value
		var board := _board(8, 8)
		board.preplace(20, rng)
		board.add_garbage(12, rng)
		for y in 8:
			for x in 8:
				var p := Vector2i(x, y)
				var atom := board.get_atom(p)
				if atom != 0:
					if board.is_closed(board.molecule_at(p)):
						safe = false
					if atom != WILD and ((atom & 63) == 0 or (atom & ~(63 | BOMB)) != 0):
						valid = false
	_check(safe, "preplace and add_garbage never leave a closed molecule on a hex board")
	_check(valid, "scattered hex atoms are valid masks")


func _danger() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var b := _board(6, 6)
	var d := Danger.new()
	d.start(b, 1, rng)
	_check(d.ghosts.size() == 1 and b.in_bounds(d.ghosts[0].cell) and b.is_empty(d.ghosts[0].cell), "hex danger: ghost on a free in-bounds cell")
	var mask_ok := true
	for i in 200:
		d.plan(b, 11, rng)
		if d.ghosts.size() != 2 or d.ghosts[0].cell == d.ghosts[1].cell:
			mask_ok = false
		for g in d.ghosts:
			var m: int = g.mask
			if m == 0 or (m & ~63) != 0 or not b.in_bounds(g.cell):
				mask_ok = false
	_check(mask_ok, "hex danger: two distinct ghosts with valid hex masks")
	d.plan(b, 1, rng)
	var cell: Vector2i = d.ghosts[0].cell
	b.place(cell, _bit(0))
	var moved := d.relocate_at(cell, b, rng)
	_check(moved.x >= 0 and moved != cell and b.in_bounds(moved) and b.is_empty(moved), "hex danger: relocate moves the ghost to another free cell")
	var drops: Array[Dictionary] = []
	var guard := 0
	while drops.is_empty() and guard < 50:
		drops = d.tick(b, rng)
		guard += 1
	_check(drops.size() == 1 and b.is_empty(drops[0].cell), "hex danger: countdown ends with the announced drop")
