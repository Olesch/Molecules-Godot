class_name Board
extends RefCounted
## Pure game logic, no Node dependencies, so the same model can drive a 2D or 3D view.
## A cell holds 0 when empty, otherwise the atom's connection mask (see Atoms).

var width: int
var height: int
var _cells: Array[int] = []
## Masks of the atoms removed by the last place() call, parallel to its returned cells.
var last_cleared_masks: Array[int] = []
## Cells of the bombs that exploded during the last place() call.
var last_exploded: Array[Vector2i] = []


func _init(w: int, h: int) -> void:
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


func is_full() -> bool:
	for c in _cells:
		if c == 0:
			return false
	return true


## True if the connection of the atom at p pointing in direction dir is answered
## by an atom next door pointing back.
func is_bonded(p: Vector2i, dir: int) -> bool:
	if not (get_atom(p) & (1 << dir)):
		return false
	var n := p + Atoms.OFFSETS[dir]
	return in_bounds(n) and (get_atom(n) & (1 << Atoms.opposite(dir))) != 0


## Places an atom and returns every cell cleared by it: the closed molecule plus
## anything wiped by exploding bombs (empty if no molecule closed).
## Bombs caught in a blast explode too.
## Returns an empty array without changing anything if the cell is not free.
func place(p: Vector2i, mask: int) -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	last_cleared_masks.clear()
	last_exploded.clear()
	if (mask & Atoms.CONNECTION_BITS) == 0 or (mask & ~(Atoms.CONNECTION_BITS | Atoms.BOMB)) != 0 or not is_empty(p):
		return cleared
	_cells[p.y * width + p.x] = mask
	var group := molecule_at(p)
	if is_closed(group):
		var removed: Array[Vector2i] = group.duplicate()
		var bombs: Array[Vector2i] = []
		for c in group:
			bombs.append_array(_remove(c, removed, false))
		while not bombs.is_empty():
			var bomb: Vector2i = bombs.pop_back()
			last_exploded.append(bomb)
			for dy in range(-Atoms.BLAST_RADIUS, Atoms.BLAST_RADIUS + 1):
				for dx in range(-Atoms.BLAST_RADIUS, Atoms.BLAST_RADIUS + 1):
					var n := bomb + Vector2i(dx, dy)
					if in_bounds(n) and get_atom(n) != 0:
						bombs.append_array(_remove(n, removed, true))
		return removed
	return cleared


## Empties a cell, records its mask, and returns it in an array if it was a bomb.
func _remove(c: Vector2i, removed: Array[Vector2i], add_to_removed: bool) -> Array[Vector2i]:
	var atom := get_atom(c)
	last_cleared_masks.append(atom)
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
		for dir in 4:
			if is_bonded(cur, dir):
				var n: Vector2i = cur + Atoms.OFFSETS[dir]
				if not seen.has(n):
					seen[n] = true
					stack.append(n)
	return group


## A group is closed when every connection of every member is bonded.
func is_closed(group: Array[Vector2i]) -> bool:
	if group.is_empty():
		return false
	for c in group:
		for dir in 4:
			if (get_atom(c) & (1 << dir)) and not is_bonded(c, dir):
				return false
	return true
