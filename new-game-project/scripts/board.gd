class_name Board
extends RefCounted
## Pure game logic, no Node dependencies, so the same model can drive a 2D or 3D view.
## A cell holds 0 when empty, otherwise the atom's connection mask (see Atoms).

var width: int
var height: int
var _cells: Array[int] = []


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


## Places an atom and returns the cells cleared by it (empty if no molecule closed).
## Returns an empty array without changing anything if the cell is not free.
func place(p: Vector2i, mask: int) -> Array[Vector2i]:
	var cleared: Array[Vector2i] = []
	if mask == 0 or not is_empty(p):
		return cleared
	_cells[p.y * width + p.x] = mask
	var group := molecule_at(p)
	if is_closed(group):
		for c in group:
			_cells[c.y * width + c.x] = 0
		return group
	return cleared


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
