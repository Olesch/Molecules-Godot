class_name Atoms
extends RefCounted
## An atom is an int: the low 4 bits are connections (bit index runs clockwise:
## 0=N, 1=E, 2=S, 3=W), higher bits are special flags such as BOMB.

const N := 1
const E := 2
const S := 4
const W := 8
const CONNECTION_BITS := 15

## Special flags.
const BOMB := 16 ## When its molecule clears, also wipes the surrounding atoms.
const BLAST_RADIUS := 1
const BOMB_CHANCE := 0.12
## A wildcard has no connections of its own: it links to every neighbour that points
## at it and never leaves an open end. It cannot clear on its own (a molecule needs 2+ atoms).
const WILD := 32
const WILD_CHANCE := 0.08

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

## Relative odds for SHAPES (tuned with tests/balance_sim.gd: fewer crosses lengthens solo games).
const SHAPE_WEIGHTS: Array[float] = [1.5, 1.5, 1.5, 1.0, 0.4]


static func rotate_cw(mask: int) -> int:
	var result := mask & ~CONNECTION_BITS
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


static func is_bomb(atom: int) -> bool:
	return (atom & BOMB) != 0


static func is_wild(atom: int) -> bool:
	return (atom & WILD) != 0


## Chances and shape weights can be overridden (powerup cards change them).
static func random_atom(rng: RandomNumberGenerator, bomb_chance := BOMB_CHANCE, wild_chance := WILD_CHANCE, weights := SHAPE_WEIGHTS) -> int:
	if rng.randf() < wild_chance:
		return WILD
	var atom := random_shape(rng, weights)
	if rng.randf() < bomb_chance:
		atom |= BOMB
	return atom


static func random_shape(rng: RandomNumberGenerator, weights := SHAPE_WEIGHTS) -> int:
	return SHAPES[rng.rand_weighted(weights)]