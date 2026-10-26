class_name Danger
extends RefCounted
## Solo pressure: stray atoms drop onto the board on a schedule that speeds up with the level.
## It is fully predictable. The atoms to drop next are chosen ahead of time and shown as
## transparent "ghosts" with a countdown in placements. Placing an atom on a ghost's cell
## pushes that ghost to another free cell. Above DOUBLE_ABOVE_LEVEL two atoms drop at once.
## Two flavours: turn-based (the countdown counts placements) and timed (it counts seconds).
## The schedule numbers below are the defaults; the instance fields (set from the game options)
## replace them. Pure logic: the Playfield draws the ghosts and places the atoms.

const BASE_INTERVAL := 8 ## placements between drops at level 1
const MIN_INTERVAL := 3 ## the interval never gets shorter than this
const LEVELS_PER_STEP := 2 ## the interval shrinks by one placement every this many levels
const DOUBLE_ABOVE_LEVEL := 10 ## after this level two atoms drop each time
const FIRST_GRACE := 2 ## extra placements before the very first drop of a game

# Timed flavour: the same shape of schedule, in seconds.
const BASE_SECONDS := 18.0 ## seconds between drops at level 1
const MIN_SECONDS := 5.0
const SECONDS_PER_STEP := 1.5 ## the gap shrinks by this much every LEVELS_PER_STEP levels
const FIRST_GRACE_SECONDS := 6.0

## Versus: seconds between incoming stray atoms with no cards (Modifiers.incoming_gap_seconds adjusts it).
const INCOMING_BASE_SECONDS := 3.0

var timed := false ## true: countdown is in seconds and advance() runs it; false: placements and tick()
var countdown := 0.0 ## placements (turn-based) or seconds (timed) left until the ghosts drop
var ghosts: Array[Dictionary] = [] ## each {cell: Vector2i, mask: int}
## > 0: always plan exactly this many ghosts instead of spawn_count(level) (versus incoming: 1).
var count_override := 0
## > 0 (timed): this is the gap used by start() and schedule_next() instead of seconds(level),
## and start() adds no first-drop grace.
var seconds_override := 0.0
## The schedule of this instance; the constants above are the defaults.
var base_interval := BASE_INTERVAL
var min_interval := MIN_INTERVAL
var first_grace := FIRST_GRACE
var base_seconds := BASE_SECONDS
var min_seconds := MIN_SECONDS
var first_grace_seconds := FIRST_GRACE_SECONDS
var double_above_level := DOUBLE_ABOVE_LEVEL


## Placements between drops at the given level (level 1 = BASE_INTERVAL).
static func interval(level: int, base := BASE_INTERVAL, minimum := MIN_INTERVAL) -> int:
	var steps := floori((level - 1) / float(LEVELS_PER_STEP))
	return maxi(minimum, base - steps)


## Seconds between drops at the given level (timed flavour).
static func seconds(level: int, base := BASE_SECONDS, minimum := MIN_SECONDS) -> float:
	var steps := floori((level - 1) / float(LEVELS_PER_STEP))
	return maxf(minimum, base - steps * SECONDS_PER_STEP)


## How many atoms drop each time at the given level.
static func spawn_count(level: int, double_above := DOUBLE_ABOVE_LEVEL) -> int:
	return 2 if level > double_above else 1


## Starts a fresh game: first countdown (with grace) and the first ghosts.
func start(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	if timed and seconds_override > 0.0:
		countdown = seconds_override
	else:
		countdown = seconds(level, base_seconds, min_seconds) + first_grace_seconds if timed else float(interval(level, base_interval, min_interval) + first_grace)
	plan(board, level, rng)


## Chooses new ghosts on free cells (replacing the old ones).
func plan(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	ghosts.clear()
	for i in (count_override if count_override > 0 else spawn_count(level, double_above_level)):
		var spot := _best_spot(board, rng, _random_stray(rng, board.topology, board.shape_weights))
		if spot.is_empty():
			break
		ghosts.append(spot)


## Sets the next countdown and plans the next ghosts; call after the drops were applied.
func schedule_next(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	if timed and seconds_override > 0.0:
		countdown = seconds_override
	else:
		countdown = seconds(level, base_seconds, min_seconds) if timed else float(interval(level, base_interval, min_interval))
	plan(board, level, rng)


## What to show next to a ghost: whole placements, or whole seconds rounded up.
func countdown_label() -> int:
	return int(ceil(countdown))


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


## Counts one placement (turn-based). Returns the atoms to drop now ({cell, mask}); empty
## until the countdown runs out. After a drop, apply the atoms and call schedule_next().
func tick(board: Board, rng: RandomNumberGenerator) -> Array[Dictionary]:
	return _count(1.0, board, rng)


## Lets delta seconds pass (timed). Same result as tick().
func advance(delta: float, board: Board, rng: RandomNumberGenerator) -> Array[Dictionary]:
	return _count(delta, board, rng)


func _count(amount: float, board: Board, rng: RandomNumberGenerator) -> Array[Dictionary]:
	for i in range(ghosts.size() - 1, -1, -1):
		if not board.is_empty(ghosts[i].cell):
			_relocate(i, board, rng) # something else filled the cell
	countdown -= amount
	var drops: Array[Dictionary] = []
	if countdown <= 0.0:
		drops.assign(ghosts)
		ghosts.clear()
	return drops


func _relocate(i: int, board: Board, rng: RandomNumberGenerator) -> Vector2i:
	var old: Vector2i = ghosts[i].cell
	var spot := _best_spot(board, rng, ghosts[i].mask, old, false) # an announced stray keeps its look
	if spot.is_empty():
		ghosts.remove_at(i)
		return Vector2i(-1, -1)
	ghosts[i].cell = spot.cell
	ghosts[i].mask = spot.mask
	return spot.cell


## Where a stray atom of this shape should go (see Board.stray_spot). Returns {cell, mask},
## or {} if there is no free cell.
func _best_spot(board: Board, rng: RandomNumberGenerator, shape: int, avoid := Vector2i(-1, -1), rotate := true) -> Dictionary:
	var reserved := {}
	for g in ghosts:
		reserved[g.cell] = true
	return board.stray_spot(rng, shape, rotate, avoid, reserved)


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
func _random_stray(rng: RandomNumberGenerator, topology: Topology, weights: Array[float]) -> int:
	var mask := Atoms.random_shape(rng, weights, topology)
	for i in rng.randi_range(0, topology.dir_count - 1):
		mask = topology.rotate_cw(mask)
	return mask
