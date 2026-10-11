class_name Board
extends RefCounted
## Pure game logic, no Node dependencies, so the same model can drive a 2D or 3D view.
## A cell holds 0 when empty, otherwise the atom's connection mask (see Atoms).

var width: int
var height: int
var topology: Topology
## Rules that powerup cards can bend: open connections a molecule may still have
## when it clears, and the minimum number of atoms for a molecule to clear.
var max_open_ends := 0
var min_molecule := 2
## How far a bomb blast reaches.
var blast_radius := Atoms.BLAST_RADIUS
## How preplaced and stray atoms are generated (the queue uses its own, see Playfield):
## chances, the bomb threshold (-1: Atoms.BOMB_MIN_CONNECTIONS) and shape weights (empty: the topology's).
var bomb_chance := Atoms.BOMB_CHANCE
var wild_chance := Atoms.WILD_CHANCE
var min_bomb_connections := -1
var shape_weights: Array[float] = []
var _cells: Array[int] = []
## Masks of the atoms removed by the last place() call, parallel to its returned cells.
var last_cleared_masks: Array[int] = []
## How the last clear spreads, parallel to place()'s result: bonds away from the placed
## atom (blast victims count from their bomb) and the cell each atom was reached from.
var last_clear_depths: Array[int] = []
var last_clear_parents: Array[Vector2i] = []
## Cells of the bombs that exploded during the last place() call.
var last_exploded: Array[Vector2i] = []
## Number of atoms in the molecule closed by the last place() call (0 if none); blasted extras not included.
var last_molecule_size := 0


func _init(w: int, h: int, topo: Topology = null) -> void:
	topology = topo if topo != null else Topology.square()
	width = w
	height = h
	_cells.resize(w * h)
	_cells.fill(0)


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func get_atom(p: Vector2i) -> int:
	return _cells[p.y * width + p.x]


func is_empty(p: Vector2i) -> bool:
	return in_bounds(p) and get_atom(p) == 0


## Share of occupied cells, 0..1.
func fill_ratio() -> float:
	var used := 0
	for c in _cells:
		if c != 0:
			used += 1
	return float(used) / _cells.size()


func is_full() -> bool:
	for c in _cells:
		if c == 0:
			return false
	return true


func _is_valid_atom(atom: int) -> bool:
	if atom == Atoms.WILD:
		return true
	var dir_bits := (1 << topology.dir_count) - 1
	return (atom & dir_bits) != 0 and (atom & ~(dir_bits | Atoms.BOMB)) == 0


## True if the connection of the atom at p pointing in direction dir is answered
## by an atom next door pointing back, or by a wildcard.
func is_bonded(p: Vector2i, dir: int) -> bool:
	if not (get_atom(p) & (1 << dir)):
		return false
	var n := topology.neighbor(p, dir)
	if not in_bounds(n):
		return false
	var other := get_atom(n)
	return (other & (1 << topology.opposite(dir))) != 0 or Atoms.is_wild(other)


## True if p and its neighbour in direction dir belong to the same molecule.
func is_linked(p: Vector2i, dir: int) -> bool:
	if is_bonded(p, dir):
		return true
	var n := topology.neighbor(p, dir)
	return Atoms.is_wild(get_atom(p)) and in_bounds(n) and (get_atom(n) & (1 << topology.opposite(dir))) != 0


## Places an atom and returns every cell cleared by it: the closed molecule plus
## anything wiped by exploding bombs (empty if no molecule closed).
## Bombs caught in a blast explode too.
## Returns an empty array without changing anything if the cell is not free.
func place(p: Vector2i, mask: int) -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	last_cleared_masks.clear()
	last_clear_depths.clear()
	last_clear_parents.clear()
	last_exploded.clear()
	last_molecule_size = 0
	if not _is_valid_atom(mask) or not is_empty(p):
		return cleared
	_cells[p.y * width + p.x] = mask
	var group := molecule_at(p)
	if is_closed(group):
		last_molecule_size = group.size()
		var removed: Array[Vector2i] = group.duplicate()
		var tree := _link_tree(p)
		var depth_of := {}
		var bombs: Array[Vector2i] = []
		for c in group:
			var node: Dictionary = tree[c]
			depth_of[c] = node.depth
			bombs.append_array(_remove(c, removed, false, node.depth, node.parent))
		while not bombs.is_empty():
			var bomb: Vector2i = bombs.pop_back()
			last_exploded.append(bomb)
			for n in topology.cells_within(bomb, blast_radius, width, height):
				if get_atom(n) != 0:
					depth_of[n] = int(depth_of[bomb]) + topology.distance(bomb, n)
					bombs.append_array(_remove(n, removed, true, depth_of[n], bomb))
		return removed
	return cleared


## Breadth-first walk over the molecule from p: cell -> {depth, parent}.
## depth is the number of bonds from p; the origin's parent is (-1, -1).
func _link_tree(p: Vector2i) -> Dictionary:
	var tree := {p: {"depth": 0, "parent": Vector2i(-1, -1)}}
	var queue: Array[Vector2i] = [p]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for dir in topology.dir_count:
			if is_linked(cur, dir):
				var n: Vector2i = topology.neighbor(cur, dir)
				if not tree.has(n):
					tree[n] = {"depth": int(tree[cur].depth) + 1, "parent": cur}
					queue.append(n)
	return tree


## Empties a cell, records its mask, depth and parent, and returns it in an array if it was a bomb.
func _remove(c: Vector2i, removed: Array[Vector2i], add_to_removed: bool, depth: int, parent: Vector2i) -> Array[Vector2i]:
	var atom := get_atom(c)
	last_cleared_masks.append(atom)
	last_clear_depths.append(depth)
	last_clear_parents.append(parent)
	_cells[c.y * width + c.x] = 0
	if add_to_removed:
		removed.append(c)
	var bombs: Array[Vector2i] = []
	if Atoms.is_bomb(atom):
		bombs.append(c)
	return bombs


## All atoms linked to the one at p through mutual bonds (including p).
func molecule_at(p: Vector2i) -> Array[Vector2i]:
	var group: Array[Vector2i] = []
	if not in_bounds(p) or get_atom(p) == 0:
		return group
	var seen := {p: true}
	var stack: Array[Vector2i] = [p]
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		group.append(cur)
		for dir in topology.dir_count:
			if is_linked(cur, dir):
				var n: Vector2i = topology.neighbor(cur, dir)
				if not seen.has(n):
					seen[n] = true
					stack.append(n)
	return group


## Molecules need this many atoms before max_open_ends applies; smaller ones must be fully closed.
const LOOSE_MIN_SIZE := 3

## A group is closed when it has at least min_molecule atoms and at most
## max_open_ends unbonded connections (0 by default: every connection bonded;
## the allowance only applies to groups of LOOSE_MIN_SIZE+ atoms).
## A lone atom (e.g. a wildcard) never counts.
func is_closed(group: Array[Vector2i]) -> bool:
	if group.size() < maxi(min_molecule, 2):
		return false
	var allowed := max_open_ends if group.size() >= LOOSE_MIN_SIZE else 0
	return open_end_count(group) <= allowed


## Open ends that can never be bonded as things stand: they point off the board or at an
## occupied cell whose atom does not point back.
func blocked_end_count(group: Array[Vector2i]) -> int:
	var blocked := 0
	for c in group:
		for dir in topology.dir_count:
			if (get_atom(c) & (1 << dir)) and not is_bonded(c, dir):
				var n := topology.neighbor(c, dir)
				if not in_bounds(n) or get_atom(n) != 0:
					blocked += 1
	return blocked


## True when the group can no longer be finished: more blocked ends than it may leave open.
func is_dead(group: Array[Vector2i]) -> bool:
	if group.is_empty():
		return false
	var allowed := max_open_ends if group.size() >= LOOSE_MIN_SIZE else 0
	return blocked_end_count(group) > allowed


func open_end_count(group: Array[Vector2i]) -> int:
	var open := 0
	for c in group:
		for dir in topology.dir_count:
			if (get_atom(c) & (1 << dir)) and not is_bonded(c, dir):
				open += 1
	return open


## Empties a cell and returns the atom that was there (0 if it was empty).
func remove_atom(p: Vector2i) -> int:
	if not in_bounds(p):
		return 0
	var old := get_atom(p)
	_cells[p.y * width + p.x] = 0
	return old


## Scatters up to count random atoms with random rotation, skipping any that would
## complete a molecule (those would never clear, since nothing can attach to them).
func preplace(count: int, rng: RandomNumberGenerator) -> void:
	_scatter(count, rng, true)


## Drops stray atoms (no specials) onto random empty cells. Returns the cells used,
## which may be fewer than count if the board is nearly full.
func add_garbage(count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	return _scatter(count, rng, false)


func _scatter(count: int, rng: RandomNumberGenerator, allow_specials: bool) -> Array[Vector2i]:
	var placed: Array[Vector2i] = []
	for n in count:
		var atom := Atoms.random_atom(rng, bomb_chance, wild_chance, shape_weights, min_bomb_connections, topology) if allow_specials else Atoms.random_shape(rng, shape_weights, topology)
		# Never complete a molecule: nothing could attach to it, so it would just vanish.
		var spot := stray_spot(rng, atom, true, Vector2i(-1, -1), {}, true)
		if spot.is_empty():
			break
		_cells[spot.cell.y * width + spot.cell.x] = spot.mask
		placed.append(spot.cell)
	return placed


## Where a loose atom of this shape should go. Every free cell and rotation is scored and the
## best one picked (ties at random). In order of importance an arm should not point at
## 1) the board border, 2) a closed side of a molecule that can no longer be finished,
## 3) a closed side of a molecule that can still be finished, 4) an open side of a dead
## molecule, 5) an open side of a live one, 6) anything goes.
## A neighbour's side is open when it has a connection (or is a wildcard) facing the new atom.
## `reserved` cells and `avoid` are skipped, `rotate` false keeps the given orientation, and
## `skip_closing` rejects spots where the atom would complete a molecule.
## Returns {cell, mask}, or {} if nothing fits.
func stray_spot(rng: RandomNumberGenerator, shape: int, rotate := true, avoid := Vector2i(-1, -1), reserved := {}, skip_closing := false) -> Dictionary:
	var dead := {} # occupied cell -> true if its molecule can no longer be finished
	for y in height:
		for x in width:
			var start := Vector2i(x, y)
			if dead.has(start) or get_atom(start) == 0:
				continue
			var group := molecule_at(start)
			var is_dead_group := is_dead(group)
			for c in group:
				dead[c] = is_dead_group
	var rotations: Array[int] = []
	var mask := shape
	for i in (topology.dir_count if rotate else 1):
		if not rotations.has(mask):
			rotations.append(mask)
		mask = topology.rotate_cw(mask)
	var candidates: Array[Dictionary] = []
	for y in height:
		for x in width:
			var p := Vector2i(x, y)
			if p == avoid or get_atom(p) != 0 or reserved.has(p):
				continue
			for m in rotations:
				var border := 0
				var facing_dead := 0
				var facing_live := 0
				for dir in topology.dir_count:
					if not (m & (1 << dir)):
						continue
					var n := topology.neighbor(p, dir)
					if not in_bounds(n):
						border += 1
					elif get_atom(n) != 0:
						if dead[n]:
							facing_dead += 1
						else:
							facing_live += 1
				candidates.append({"cell": p, "mask": m, "score": border * 1000000 + facing_dead * 1000 + facing_live, "r": rng.randf()})
	candidates.sort_custom(func(a, b): return a.score < b.score or (a.score == b.score and a.r < b.r))
	for cand in candidates:
		if not skip_closing:
			return cand
		var p: Vector2i = cand.cell
		_cells[p.y * width + p.x] = cand.mask
		var closes := is_closed(molecule_at(p))
		_cells[p.y * width + p.x] = 0
		if not closes:
			return cand
	return {}


## Flat copy of the cells (row by row) for sending to the opponent.
func snapshot() -> PackedInt32Array:
	return PackedInt32Array(_cells)


## Replaces the board with a snapshot of the same size; ignores bad data.
func load_snapshot(cells: PackedInt32Array) -> void:
	if cells.size() != width * height:
		return
	for i in cells.size():
		_cells[i] = cells[i]
