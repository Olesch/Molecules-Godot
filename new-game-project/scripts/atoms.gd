class_name Atoms
extends RefCounted
## Atom shapes are 4-bit masks. Bit index runs clockwise: 0=N, 1=E, 2=S, 3=W.

const N := 1
const E := 2
const S := 4
const W := 8

## Grid step for each bit index.
const OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]

## Base shapes the generator can hand out (rotation is up to the player).
const SHAPES: Array[int] = [
	N,
	N | S,
	N | E,
	N | E | W,
	N | E | S | W,
]


static func rotate_cw(mask: int) -> int:
	var result := 0
	for i in 4:
		if mask & (1 << i):
			result |= 1 << ((i + 1) % 4)
	return result


static func opposite(dir: int) -> int:
	return (dir + 2) % 4


static func connection_count(mask: int) -> int:
	var count := 0
	for i in 4:
		if mask & (1 << i):
			count += 1
	return count


static func random_shape(rng: RandomNumberGenerator) -> int:
	return SHAPES[rng.randi_range(0, SHAPES.size() - 1)]
