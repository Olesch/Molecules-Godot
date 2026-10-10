extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_topology.gd
## Square and hex topologies: neighbours, rotation, shapes, distance, blast area, geometry.

const SIZE := 72.0
const EPS := 0.001


func _init() -> void:
	var sq := Topology.square()
	var hx := Topology.hex()
	_check(Topology.for_id("hex") == hx and Topology.for_id("square") == sq and Topology.for_id("nope") == sq, "for_id returns the shared instances")
	_check(sq.id == "square" and sq.dir_count == 4 and sq.max_connections == 4, "square basics")
	_check(hx.id == "hex" and hx.dir_count == 6 and hx.max_connections == 6, "hex basics")
	_check(Atoms.CONNECTION_BITS == 63 and Atoms.BOMB == 64 and Atoms.WILD == 128, "flag values")
	for t in [sq, hx]:
		_basic_checks(t)
		_geometry_checks(t)
	_hex_parity()
	_hex_distance_and_area()


func _basic_checks(t: Topology) -> void:
	var n := t.id + ": "
	var ok := true
	for y in 8:
		for x in 8:
			var c := Vector2i(x, y)
			for d in t.dir_count:
				var nb := t.neighbor(c, d)
				if t.distance(c, nb) != 1:
					ok = false
				if nb.x >= 0 and nb.y >= 0 and nb.x < 8 and nb.y < 8 and t.neighbor(nb, t.opposite(d)) != c:
					ok = false
	_check(ok, n + "neighbour/opposite round trip, neighbours at distance 1")

	# Rotation.
	var rot_ok := true
	var flags_ok := true
	for shape in t.shapes:
		for flags in [0, Atoms.BOMB]:
			var m: int = shape | flags
			var r := m
			for i in t.dir_count:
				r = t.rotate_cw(r)
			if r != m:
				rot_ok = false
			if (t.rotate_cw(m) & Atoms.BOMB) != flags or t.connection_count(t.rotate_cw(m)) != t.connection_count(m):
				flags_ok = false
	_check(rot_ok, n + "rotating dir_count times is the identity")
	_check(flags_ok, n + "rotation keeps flags and connection count")
	_check(t.rotate_cw(1) == 2 and t.rotate_cw(1 << (t.dir_count - 1)) == 1, n + "rotate wraps around")

	# Shapes.
	_check(t.shapes.size() == t.shape_weights.size() and not t.shapes.is_empty(), n + "shapes and weights are parallel")
	var valid := true
	var seen := {}
	var unique := true
	var allowed := (1 << t.dir_count) - 1
	for s in t.shapes:
		if s == 0 or (s & ~allowed) != 0:
			valid = false
		var best := s
		var r: int = s
		for i in t.dir_count:
			r = t.rotate_cw(r)
			best = mini(best, r)
		if seen.has(best):
			unique = false
		seen[best] = true
	_check(valid, n + "shapes are nonzero connection masks")
	_check(unique, n + "no two shapes are rotations of each other")
	_check(t.connection_count(t.shapes[t.shapes.size() - 1]) == t.max_connections, n + "last shape has every connection")
	var weights_ok := true
	for w in t.shape_weights:
		if w <= 0.0:
			weights_ok = false
	_check(weights_ok, n + "weights positive")

	# Distance and cells_within.
	var sym := true
	var tri := true
	var cells: Array[Vector2i] = []
	for y in 5:
		for x in 5:
			cells.append(Vector2i(x, y))
	for a in cells:
		for b in cells:
			var dab := t.distance(a, b)
			if dab != t.distance(b, a) or (dab == 0) != (a == b):
				sym = false
			for c in [Vector2i(2, 2), Vector2i(0, 4)]:
				if t.distance(a, b) > t.distance(a, c) + t.distance(c, b):
					tri = false
	_check(sym, n + "distance is symmetric, zero only for equal cells")
	_check(tri, n + "triangle inequality")
	var area_ok := true
	for y in 7:
		for x in 7:
			for radius in 3:
				var got := t.cells_within(Vector2i(x, y), radius, 7, 7)
				var expect := 0
				for yy in 7:
					for xx in 7:
						if t.distance(Vector2i(x, y), Vector2i(xx, yy)) <= radius:
							expect += 1
				var uniq := {}
				for g in got:
					uniq[g] = true
				if got.size() != expect or uniq.size() != expect:
					area_ok = false
	_check(area_ok, n + "cells_within matches distance <= radius")
	var one := t.cells_within(Vector2i(3, 3), 0, 7, 7)
	_check(one.size() == 1 and one[0] == Vector2i(3, 3), n + "radius 0 is the cell itself")


func _geometry_checks(t: Topology) -> void:
	var n := t.id + ": "
	var round_trip := true
	var off_centre := true
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var spacing := true
	for y in 8:
		for x in 8:
			var c := Vector2i(x, y)
			var ctr := t.cell_center(c, SIZE)
			if t.cell_at(ctr, SIZE) != c:
				round_trip = false
			for off in [Vector2(0.25, 0.2), Vector2(-0.25, 0.2), Vector2(0.25, -0.2), Vector2(-0.25, -0.2), Vector2(0.0, 0.3), Vector2(0.3, 0.0)]:
				if t.cell_at(ctr + off * SIZE, SIZE) != c:
					off_centre = false
			var poly := t.cell_polygon(c, SIZE)
			if poly.size() != (4 if t.id == "square" else 6):
				round_trip = false
			for p in poly:
				min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
				max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
			for d in t.dir_count:
				var delta := t.cell_center(t.neighbor(c, d), SIZE) - ctr
				if not delta.is_equal_approx(t.dir_vector(d) * SIZE):
					spacing = false
	_check(round_trip, n + "cell_at(cell_center(c)) == c, polygon corner count")
	_check(off_centre, n + "points near the centre map to the cell")
	var bs := t.board_pixel_size(8, 8, SIZE)
	_check(absf(min_p.x) < EPS and absf(min_p.y) < EPS and absf(max_p.x - bs.x) < EPS and absf(max_p.y - bs.y) < EPS, n + "board_pixel_size is the polygon bounding box")
	_check(spacing, n + "neighbour centres lie one dir_vector * size away")
	var unit := true
	for d in t.dir_count:
		if absf(t.dir_vector(d).length() - 1.0) > EPS:
			unit = false
	_check(unit, n + "dir_vector has length 1")
	_check(t.cell_at(Vector2(-500, -500), SIZE).x < 0, n + "cell_at outside is out of bounds")


func _hex_parity() -> void:
	var h := Topology.hex()
	# even row y=2
	var e := Vector2i(3, 2)
	var even_expect: Array[Vector2i] = [Vector2i(4, 2), Vector2i(3, 3), Vector2i(2, 3), Vector2i(2, 2), Vector2i(2, 1), Vector2i(3, 1)]
	var odd := Vector2i(3, 3)
	var odd_expect: Array[Vector2i] = [Vector2i(4, 3), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 3), Vector2i(3, 2), Vector2i(4, 2)]
	var ok := true
	for d in 6:
		if h.neighbor(e, d) != even_expect[d] or h.neighbor(odd, d) != odd_expect[d]:
			ok = false
	_check(ok, "hex: odd-r neighbour examples (even and odd rows)")
	_check(h.opposite(0) == 3 and h.opposite(1) == 4 and h.opposite(5) == 2, "hex: opposite")
	_check(h.rotate_cw(1 << 5) == 1 and h.rotate_cw(1 | 2) == (2 | 4), "hex: rotate_cw")
	_check(h.cell_center(Vector2i(1, 1), SIZE).is_equal_approx(Vector2(2.0 * SIZE, SIZE / sqrt(3.0) + SIZE * sqrt(3.0) / 2.0)), "hex: odd rows shift half a cell right")


func _hex_distance_and_area() -> void:
	var h := Topology.hex()
	var s := Topology.square()
	_check(h.cells_within(Vector2i(3, 3), 1, 8, 8).size() == 7, "hex radius 1 interior is 7 cells (odd row)")
	_check(h.cells_within(Vector2i(3, 2), 1, 8, 8).size() == 7, "hex radius 1 interior is 7 cells (even row)")
	_check(h.cells_within(Vector2i(4, 4), 2, 9, 9).size() == 19, "hex radius 2 interior is 19 cells")
	_check(h.cells_within(Vector2i(0, 0), 1, 8, 8).size() == 3, "hex radius 1 is clipped at the corner")
	_check(s.cells_within(Vector2i(3, 3), 1, 8, 8).size() == 9, "square radius 1 is 3x3")
	_check(s.cells_within(Vector2i(0, 0), 1, 8, 8).size() == 4, "square radius 1 is clipped at the corner")
	_check(h.distance(Vector2i(0, 0), Vector2i(3, 0)) == 3 and h.distance(Vector2i(0, 0), Vector2i(0, 2)) == 2 and h.distance(Vector2i(0, 0), Vector2i(1, 2)) == 2, "hex distance examples")
	_check(s.distance(Vector2i(0, 0), Vector2i(2, 3)) == 3, "square distance is Chebyshev")
	_finish(true)
