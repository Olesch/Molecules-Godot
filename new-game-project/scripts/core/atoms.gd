class_name Atoms
extends RefCounted
## An atom is an int: the low 6 bits are connections (bit index runs clockwise; square:
## 0=N, 1=E, 2=S, 3=W; hex: see HexTopology), higher bits are special flags such as BOMB.

const N := 1
const E := 2
const S := 4
const W := 8
const CONNECTION_BITS := 63

## Special flags.
const BOMB := 64 ## When its molecule clears, also wipes the surrounding atoms.
const BLAST_RADIUS := 1
## Chance that an eligible atom is a bomb. Only atoms with at least BOMB_MIN_CONNECTIONS
## connections are eligible; the Mini Bombs card lowers that threshold.
const BOMB_CHANCE := 0.35
const BOMB_MIN_CONNECTIONS := 4
## A wildcard has no connections of its own: it links to every neighbour that points
## at it and never leaves an open end. It cannot clear on its own (a molecule needs 2+ atoms).
const WILD := 128
const WILD_CHANCE := 0.0 ## no wildcards until the Joker Supply card is leveled

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


## Square-board conveniences (the view code uses these until it is topology-aware).
static func rotate_cw(mask: int) -> int:
	return Topology.square().rotate_cw(mask)


static func opposite(dir: int) -> int:
	return (dir + 2) % 4


static func connection_count(mask: int) -> int:
	return Topology.square().connection_count(mask)


static func is_bomb(atom: int) -> bool:
	return (atom & BOMB) != 0


static func is_wild(atom: int) -> bool:
	return (atom & WILD) != 0


## Chances and shape weights can be overridden (powerup cards change them); empty weights
## mean the topology's own. min_bomb_connections < 0 means the default, BOMB_MIN_CONNECTIONS (4 on every board).
## The rolls are always drawn, so the random sequence does not depend on the chances.
static func random_atom(rng: RandomNumberGenerator, bomb_chance := BOMB_CHANCE, wild_chance := WILD_CHANCE, weights: Array[float] = [], min_bomb_connections := -1, topology: Topology = null) -> int:
	var topo := topology if topology != null else Topology.square()
	var wild_roll := rng.randf()
	var atom := random_shape(rng, weights, topo)
	var bomb_roll := rng.randf()
	if wild_roll < wild_chance:
		return WILD
	var min_conn := min_bomb_connections if min_bomb_connections >= 0 else BOMB_MIN_CONNECTIONS
	if topo.connection_count(atom) >= min_conn and bomb_roll < bomb_chance:
		atom |= BOMB
	return atom


static func random_shape(rng: RandomNumberGenerator, weights: Array[float] = [], topology: Topology = null) -> int:
	var topo := topology if topology != null else Topology.square()
	var w: Array[float] = weights if not weights.is_empty() else topo.shape_weights
	return topo.shapes[rng.rand_weighted(w)]
