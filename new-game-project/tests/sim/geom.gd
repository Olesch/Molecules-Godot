extends RefCounted
## Flat-array board geometry and cheap local evaluation, shared by the sim game and the bots.
## Cells are indexed y * width + x; nb[i * D + d] is the neighbour index or -1 (off board).

var topo: Topology
var D := 4
var W := 8
var H := 8
var N := 64
var nb := PackedInt32Array()
var back := PackedInt32Array()
var _rot_cache := {}

# Results of local() (members instead of a Dictionary: this runs hundreds of thousands of times).
var r_live := 0
var r_dead := 0
var r_bonded := 0
var r_gain := 0
var r_killed := 0
var r_pocket := 0

# Weights of quick(); the bots' heuristic.
var w_bond := 3.0
var w_dead := 8.0
var w_live := 1.5
var w_pocket := 0.35


func _init(t: Topology, w: int, h: int) -> void:
	topo = t
	D = t.dir_count
	W = w
	H = h
	N = w * h
	nb.resize(N * D)
	for y in H:
		for x in W:
			var i := y * W + x
			for d in D:
				var n := t.neighbor(Vector2i(x, y), d)
				nb[i * D + d] = (n.y * W + n.x) if (n.x >= 0 and n.y >= 0 and n.x < W and n.y < H) else -1
	back.resize(D)
	for d in D:
		back[d] = t.opposite(d)


func cell_of(i: int) -> Vector2i:
	return Vector2i(i % W, i / W)


func idx_of(p: Vector2i) -> int:
	return p.y * W + p.x


## Distinct rotations of an atom (a wildcard has one).
func rotations(atom: int) -> Array[int]:
	if _rot_cache.has(atom):
		return _rot_cache[atom]
	var out: Array[int] = [atom]
	if not Atoms.is_wild(atom):
		var a := atom
		for i in D - 1:
			a = topo.rotate_cw(a)
			if not out.has(a):
				out.append(a)
	_rot_cache[atom] = out
	return out


## Looks at putting `mask` into the empty cell i. Fills r_*:
## live = arms into free cells, dead = arms at the border or at an atom that does not point back,
## bonded = arms answered by a neighbour, gain = neighbour ends answered by this atom,
## killed = neighbour ends this atom blocks (it does not point back), pocket = walls around the free cells its arms point to.
func local(cells: PackedInt32Array, i: int, mask: int) -> void:
	var live := 0
	var dead := 0
	var bonded := 0
	var gain := 0
	var killed := 0
	var pocket := 0
	var wild := (mask & 128) != 0
	var base := i * D
	for d in D:
		var n := nb[base + d]
		var arm := (not wild) and (mask & (1 << d)) != 0
		if n < 0:
			if arm:
				dead += 1
			continue
		var other := cells[n]
		if other == 0:
			if arm:
				live += 1
				var nbase := n * D
				for e in D:
					var m := nb[nbase + e]
					if m != i and (m < 0 or cells[m] != 0):
						pocket += 1
			continue
		var opp := 1 << back[d]
		if arm:
			if (other & opp) != 0 or (other & 128) != 0:
				bonded += 1
			else:
				dead += 1
		if (other & 128) == 0 and (other & opp) != 0:
			if arm or wild:
				gain += 1
			else:
				killed += 1
	r_live = live
	r_dead = dead
	r_bonded = bonded
	r_gain = gain
	r_killed = killed
	r_pocket = pocket


## Heuristic value of the placement from the last local() call.
func quick() -> float:
	return (r_bonded + r_gain) * w_bond - (r_dead + r_killed) * w_dead - r_live * w_live - r_pocket * w_pocket


## True if the last local() call could close a molecule (every own arm answered).
func may_close(max_open: int, wild: bool) -> bool:
	return r_live + r_dead <= max_open and (r_bonded > 0 or (wild and r_gain > 0))


## Counts [good, productive, good_cells] placements of this atom: good = no dead end and no blocked neighbour,
## productive = good and bonds to something.
func options(cells: PackedInt32Array, atom: int) -> Array[int]:
	var good := 0
	var prod := 0
	var rots := rotations(atom)
	for i in N:
		if cells[i] != 0:
			continue
		for m in rots:
			local(cells, i, m)
			if r_dead == 0 and r_killed == 0:
				good += 1
				if r_bonded > 0 or r_gain > 0:
					prod += 1
	return [good, prod]


## True if the atom can be attached to a live molecule's open end without creating a dead end.
## `live` flags the cells of molecules that can still be finished.
func can_extend(cells: PackedInt32Array, live: PackedByteArray, atom: int) -> bool:
	var rots := rotations(atom)
	var wild := Atoms.is_wild(atom)
	for i in N:
		if cells[i] != 0:
			continue
		var attach_dirs := 0
		for d in D:
			var n := nb[i * D + d]
			if n >= 0 and live[n] == 1 and (cells[n] & 128) == 0 and (cells[n] & (1 << back[d])) != 0:
				attach_dirs |= 1 << d
		if attach_dirs == 0:
			continue
		for m in rots:
			if not wild and (m & attach_dirs) == 0:
				continue
			local(cells, i, m)
			if r_dead == 0 and r_killed == 0:
				return true
	return false


## Number of arms pointing at free cells that belong to live molecules.
func live_ends(cells: PackedInt32Array, live: PackedByteArray) -> int:
	var count := 0
	for i in N:
		if cells[i] == 0 or live[i] == 0 or (cells[i] & 128) != 0:
			continue
		for d in D:
			if (cells[i] & (1 << d)) != 0:
				var n := nb[i * D + d]
				if n >= 0 and cells[n] == 0:
					count += 1
	return count


## Molecule classification of a Board: [perm_atoms, fix_atoms, live flags, perm groups (arrays of cell indices)].
## Permanent dead: more ends facing the border or an atom of the same molecule than it may leave open.
## Fixable dead: dead only because ends face another molecule's atoms (clearing that one frees them).
func classify(board: Board) -> Array:
	var seen := PackedByteArray()
	seen.resize(N)
	var live := PackedByteArray()
	live.resize(N)
	var perm_atoms := 0
	var fix_atoms := 0
	var perm_groups: Array = []
	for i in N:
		if seen[i] == 1:
			continue
		var p := cell_of(i)
		if board.get_atom(p) == 0:
			continue
		var grp := board.molecule_at(p)
		var gset := {}
		for c in grp:
			seen[idx_of(c)] = 1
			gset[c] = true
		var allowed := board.max_open_ends if grp.size() >= Board.LOOSE_MIN_SIZE else 0
		var perm := 0
		var fix := 0
		for c in grp:
			var atom := board.get_atom(c)
			for d in D:
				if (atom & (1 << d)) != 0 and not board.is_bonded(c, d):
					var n := topo.neighbor(c, d)
					if not board.in_bounds(n):
						perm += 1
					elif board.get_atom(n) != 0:
						if gset.has(n):
							perm += 1
						else:
							fix += 1
		if perm > allowed:
			perm_atoms += grp.size()
			var idxs: Array[int] = []
			for c in grp:
				idxs.append(idx_of(c))
			perm_groups.append(idxs)
		elif perm + fix > allowed:
			fix_atoms += grp.size()
		else:
			for c in grp:
				live[idx_of(c)] = 1
	return [perm_atoms, fix_atoms, live, perm_groups]
