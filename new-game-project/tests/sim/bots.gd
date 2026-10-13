extends RefCounted
## Bots that play a SimGame using only what a human sees: the board, the held atom and the preview queue.
##   kind 1: random legal placement
##   kind 2: greedy 1-ply (close a molecule > bond safely > avoid dead ends/border > random)
##   kind 3: beam search over held + preview atoms (all rotations) with a local-evaluation heuristic
##   kind 4: human-like = kind 3 with noise (suboptimal picks) and limited attention (radius around the last move)

const Geom = preload("res://tests/sim/geom.gd")

const W_DEAD := 25.0
const W_LIVE := 3.0
const W_BOND := 3.0
const W_POCKET := 1.5
var clear_base := 25.0
var clear_mol := 6.0
var kind := 3
var rng := RandomNumberGenerator.new()
var noise := 0.15 ## chance to pick a suboptimal move (kind 4)
var focus_chance := 0.5 ## chance to only look near the last placement (kind 4)
var focus_radius := 4
var beams: Array[int] = [6, 4, 3]
var max_depth := 3
var g: Geom
var game
var scratch: Board
var _cells_after := {} ## candidate key -> cells after the move (search scratch)


func setup(game_ref, kind_id: int, seed_value: int, w: Dictionary = {}) -> void:
	game = game_ref
	kind = kind_id
	rng.seed = seed_value * 104729 + kind_id
	g = game.geom
	g.w_dead = float(w.get("dead", W_DEAD))
	g.w_live = float(w.get("live", W_LIVE))
	g.w_bond = float(w.get("bond", W_BOND))
	g.w_pocket = float(w.get("pocket", W_POCKET))
	clear_base = float(w.get("clear", clear_base))
	clear_mol = float(w.get("mol", clear_mol))
	if w.has("b0"):
		beams = [int(w.b0), int(w.get("b1", 4)), int(w.get("b2", 3))]
	scratch = Board.new(g.W, g.H, g.topo)


func _sync_scratch() -> void:
	scratch.max_open_ends = game.board.max_open_ends
	scratch.min_molecule = game.board.min_molecule
	scratch.blast_radius = game.board.blast_radius


## Returns [cell, mask] for the held atom after using active cards.
func choose() -> Array:
	_sync_scratch()
	if kind == 1:
		return _choose_random()
	_use_actives()
	if kind == 2:
		return _choose_greedy()
	return _choose_search()


func _choose_random() -> Array:
	var cells: Array[int] = []
	var snap: PackedInt32Array = game.board.snapshot()
	for i in g.N:
		if snap[i] == 0:
			cells.append(i)
	var i: int = cells[rng.randi_range(0, cells.size() - 1)]
	var rots := g.rotations(game.queue[0])
	return [g.cell_of(i), rots[rng.randi_range(0, rots.size() - 1)]]


## 1-ply classification: 3 = closes a molecule, 2 = bonds without dead ends, 1 = no dead ends, 0 = anything.
func _choose_greedy() -> Array:
	var cells: PackedInt32Array = game.board.snapshot()
	var atom: int = game.queue[0]
	var wild := Atoms.is_wild(atom)
	var rots := g.rotations(atom)
	var best_class := -1
	var pool: Array = []
	var best_close := -1
	for i in g.N:
		if cells[i] != 0:
			continue
		for m in rots:
			g.local(cells, i, m)
			var cls := 0
			var closed_size := 0
			if g.r_dead == 0 and g.r_killed == 0:
				cls = 1
				if g.r_bonded > 0 or g.r_gain > 0:
					cls = 2
			if g.may_close(game.board.max_open_ends, wild):
				scratch.load_snapshot(cells)
				var cleared := scratch.place(g.cell_of(i), m)
				if not cleared.is_empty():
					cls = 3
					closed_size = cleared.size()
			if cls > best_class or (cls == 3 and best_class == 3 and closed_size > best_close):
				best_class = cls
				best_close = closed_size
				pool = [[i, m]]
			elif cls == best_class and (cls != 3 or closed_size == best_close):
				pool.append([i, m])
	var pick: Array = pool[rng.randi_range(0, pool.size() - 1)]
	return [g.cell_of(pick[0]), pick[1]]


# ------------------------------------------------------------------ search

## Candidates for putting `atom` on `cells`: [value, idx, mask, cells_after or null], best first, top `limit`.
## `allowed` (optional) restricts the cells.
func _candidates(cells: PackedInt32Array, atom: int, limit: int, allowed: PackedByteArray = PackedByteArray()) -> Array:
	var rots := g.rotations(atom)
	var wild := Atoms.is_wild(atom)
	var max_open: int = game.board.max_open_ends
	var out: Array = []
	var restricted := allowed.size() > 0
	for i in g.N:
		if cells[i] != 0 or (restricted and allowed[i] == 0):
			continue
		for m in rots:
			g.local(cells, i, m)
			var v := g.quick()
			var after = null
			if g.may_close(max_open, wild):
				scratch.load_snapshot(cells)
				var cleared := scratch.place(g.cell_of(i), m)
				if not cleared.is_empty():
					v += clear_base + clear_mol * scratch.last_molecule_size + 2.0 * (cleared.size() - scratch.last_molecule_size)
					after = scratch.snapshot()
			out.append([v, i, m, after])
	out.sort_custom(func(a, b): return a[0] > b[0])
	if out.size() > limit:
		out.resize(limit)
	return out


func _after(cells: PackedInt32Array, cand: Array) -> PackedInt32Array:
	if cand[3] != null:
		return cand[3]
	var c := cells.duplicate()
	c[cand[1]] = cand[2]
	return c


## Best total value of playing atoms[ply..] on cells (beam search).
func _rollout(cells: PackedInt32Array, atoms: Array, ply: int, depth: int) -> float:
	if ply >= depth:
		return 0.0
	var cands := _candidates(cells, atoms[ply], beams[mini(ply, beams.size() - 1)])
	if cands.is_empty():
		return -50.0
	var best := -1.0e9
	for c in cands:
		var v: float = c[0] + _rollout(_after(cells, c), atoms, ply + 1, depth)
		best = maxf(best, v)
	return best


func _choose_search() -> Array:
	var cells: PackedInt32Array = game.board.snapshot()
	var atoms: Array = game.queue
	var depth := mini(atoms.size(), max_depth)
	var allowed := PackedByteArray()
	if kind == 4 and game.last_cell.x >= 0 and rng.randf() < focus_chance:
		allowed.resize(g.N)
		var any := false
		for i in g.N:
			if cells[i] == 0 and g.topo.distance(g.cell_of(i), game.last_cell) <= focus_radius:
				allowed[i] = 1
				any = true
		if not any:
			allowed = PackedByteArray()
	var first := _candidates(cells, atoms[0], beams[0] if kind == 3 else maxi(beams[0], 6), allowed)
	var scored: Array = []
	for c in first:
		scored.append([c[0] + _rollout(_after(cells, c), atoms, 1, depth), c[1], c[2]])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var pick: Array = scored[0]
	if kind == 4 and scored.size() > 1 and rng.randf() < noise:
		pick = scored[rng.randi_range(1, mini(scored.size() - 1, 3))]
	return [g.cell_of(pick[1]), pick[2]]


## Best 1-ply value of an atom on the current board (for deciding to stash, swap or reroll).
func _best_value(cells: PackedInt32Array, atom: int) -> float:
	var c := _candidates(cells, atom, 1)
	return c[0][0] if not c.is_empty() else -100.0


func _use_actives() -> void:
	var mods: Modifiers = game.mods
	if not (mods.has(Cards.TWO_HAND) or mods.has(Cards.STASH) or mods.has(Cards.REROLL)):
		return
	var cells: PackedInt32Array = game.board.snapshot()
	var cur := _best_value(cells, game.queue[0])
	if mods.has(Cards.TWO_HAND) and game.queue.size() >= 2:
		var alt := _best_value(cells, game.queue[1])
		if alt > cur + 0.5:
			game.swap_next()
			cur = alt
	if mods.has(Cards.STASH):
		if game.stash == 0:
			if cur < 2.0:
				game.stash_swap()
				cur = _best_value(cells, game.queue[0])
		else:
			var st := _best_value(cells, game.stash)
			if st > cur + 2.0:
				game.stash_swap()
				cur = st
	if mods.has(Cards.REROLL) and game.reroll_cd == 0 and cur < 1.0:
		game.reroll_held()


## Scrap prototype: delete the atom that causes the most dead ends in a permanently dead molecule.
func scrap_if_useful() -> void:
	if not game.scrap_ready():
		return
	var cl := g.classify(game.board)
	var groups: Array = cl[3]
	if groups.is_empty():
		return
	var cells: PackedInt32Array = game.board.snapshot()
	var best := -1
	var best_v := -1
	for grp in groups:
		for i in grp:
			var v := 0
			for d in g.D:
				var n := g.nb[i * g.D + d]
				if n < 0:
					if cells[i] & (1 << d):
						v += 2
				elif cells[n] != 0 and (cells[n] & (1 << g.back[d])) == 0 and (cells[i] & (1 << d)):
					v += 2
				elif cells[n] != 0 and (cells[n] & (1 << g.back[d])) != 0 and (cells[i] & (1 << d)) == 0:
					v += 1
			if v > best_v:
				best_v = v
				best = i
	if best >= 0:
		game.scrap(g.cell_of(best))


## Is there a clear within `depth` placements using the atoms that will really come? (hopeless-board test)
## Global beam: only the `width` best boards survive each ply.
func can_clear_within(depth: int, width: int) -> bool:
	_sync_scratch()
	var atoms: Array[int] = game.peek_atoms(depth)
	var states: Array = [[0.0, game.board.snapshot()]]
	for ply in depth:
		var next: Array = []
		for st in states:
			var cells: PackedInt32Array = st[1]
			var cands := _candidates(cells, atoms[ply], width)
			for c in cands:
				if c[3] != null:
					return true
				next.append([st[0] + c[0], _after(cells, c)])
		if next.is_empty():
			return false
		next.sort_custom(func(a, b): return a[0] > b[0])
		if next.size() > width:
			next.resize(width)
		states = next
	return false


