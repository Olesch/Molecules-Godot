class_name Danger
extends RefCounted
## Solo pressure: stray atoms drop onto the board on a schedule that speeds up with the level.
## It is fully predictable. The atoms to drop next are chosen ahead of time and shown as
## transparent "ghosts" with a countdown in placements. Placing an atom on a ghost's cell
## pushes that ghost to another free cell. Above DOUBLE_ABOVE_LEVEL two atoms drop at once.
## Pure logic: the Playfield draws the ghosts and places the atoms.

const BASE_INTERVAL := 8 ## placements between drops at level 1
const MIN_INTERVAL := 3 ## the interval never gets shorter than this
const LEVELS_PER_STEP := 2 ## the interval shrinks by one placement every this many levels
const DOUBLE_ABOVE_LEVEL := 10 ## after this level two atoms drop each time
const FIRST_GRACE := 2 ## extra placements before the very first drop of a game

var countdown := 0 ## placements left until the ghosts drop
var ghosts: Array[Dictionary] = [] ## each {cell: Vector2i, mask: int}


## Placements between drops at the given level (level 1 = BASE_INTERVAL).
static func interval(level: int) -> int:
	var steps := floori((level - 1) / float(LEVELS_PER_STEP))
	return maxi(MIN_INTERVAL, BASE_INTERVAL - steps)


## How many atoms drop each time at the given level.
static func spawn_count(level: int) -> int:
	return 2 if level > DOUBLE_ABOVE_LEVEL else 1


## Starts a fresh game: first countdown (with grace) and the first ghosts.
func start(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	countdown = interval(level) + FIRST_GRACE
	plan(board, level, rng)


## Chooses new ghosts on free cells (replacing the old ones).
func plan(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	ghosts.clear()
	for i in spawn_count(level):
		var cell := _random_free_cell(board, rng)
		if cell.x < 0:
			break
		ghosts.append({"cell": cell, "mask": _random_stray(rng)})


## Sets the next countdown and plans the next ghosts; call after the drops were applied.
func schedule_next(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	countdown = interval(level)
	plan(board, level, rng)


## Index of the ghost standing on cell, or -1.
func ghost_index(cell: Vector2i) -> int:
	for i in ghosts.size():
		if ghosts[i].cell == cell:
			return i
	return -1


## A placement took cell: a ghost standing there moves to another free cell.
## Returns the new cell, or (-1, -1) if nothing moved (or the ghost found no room and vanished).
func relocate_at(cell: Vector2i, board: Board, rng: RandomNumberGenerator) -> Vector2i:
	var i := ghost_index(cell)
	if i < 0:
		return Vector2i(-1, -1)
	return _relocate(i, board, rng)


## Counts one placement. Returns the atoms to drop now ({cell, mask}); empty until the
## countdown runs out. After a drop, apply the atoms and call schedule_next().
func tick(board: Board, rng: RandomNumberGenerator) -> Array[Dictionary]:
	for i in range(ghosts.size() - 1, -1, -1):
		if not board.is_empty(ghosts[i].cell):
			_relocate(i, board, rng) # something else filled the cell
	countdown -= 1
	var drops: Array[Dictionary] = []
	if countdown <= 0:
		drops.assign(ghosts)
		ghosts.clear()
	return drops


func _relocate(i: int, board: Board, rng: RandomNumberGenerator) -> Vector2i:
	var old: Vector2i = ghosts[i].cell
	var cell := _random_free_cell(board, rng, old)
	if cell.x < 0:
		ghosts.remove_at(i)
		return Vector2i(-1, -1)
	ghosts[i].cell = cell
	return cell


## A random empty cell that holds no ghost and is not `avoid`; (-1, -1) if there is none.
func _random_free_cell(board: Board, rng: RandomNumberGenerator, avoid := Vector2i(-1, -1)) -> Vector2i:
	var free: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			var p := Vector2i(x, y)
			if p != avoid and board.is_empty(p) and ghost_index(p) < 0:
				free.append(p)
	if free.is_empty():
		return Vector2i(-1, -1)
	return free[rng.randi_range(0, free.size() - 1)]


## A plain atom (no bomb or wildcard) in a random orientation.
func _random_stray(rng: RandomNumberGenerator) -> int:
	var mask := Atoms.random_shape(rng)
	for i in rng.randi_range(0, 3):
		mask = Atoms.rotate_cw(mask)
	return mask
