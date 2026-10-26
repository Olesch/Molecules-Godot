extends Danger
## Danger with a tweakable schedule shape, for prototyping pressure curves without touching scripts/.

var levels_per_step := Danger.LEVELS_PER_STEP
var seconds_per_step := Danger.SECONDS_PER_STEP
var step_size := 1 ## placements the interval shrinks per step (turn-based)


func _iv(level: int) -> int:
	var steps := floori((level - 1) / float(levels_per_step))
	return maxi(min_interval, base_interval - steps * step_size)


func _sec(level: int) -> float:
	var steps := floori((level - 1) / float(levels_per_step))
	return maxf(min_seconds, base_seconds - steps * seconds_per_step)


func start(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	if timed and seconds_override > 0.0:
		countdown = seconds_override
	else:
		countdown = _sec(level) + first_grace_seconds if timed else float(_iv(level) + first_grace)
	plan(board, level, rng)


func schedule_next(board: Board, level: int, rng: RandomNumberGenerator) -> void:
	if timed and seconds_override > 0.0:
		countdown = seconds_override
	else:
		countdown = _sec(level) if timed else float(_iv(level))
	plan(board, level, rng)
