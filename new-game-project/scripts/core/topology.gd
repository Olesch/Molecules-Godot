class_name Topology
extends RefCounted
## Grid topology: which cells are neighbours, how connection masks rotate and where cells sit
## on screen. Square (4 directions) and hex (6 directions) implement it; the Board and the
## generators only talk to this interface. Connection bits are the low 6 bits of an atom.

const ALL_CONNECTION_BITS := 63

var id := ""
var dir_count := 0
var max_connections := 0
## Base atom shapes as connection masks; the LAST one is the most-connected shape.
var shapes: Array[int] = []
var shape_weights: Array[float] = []

static var _square: Topology
static var _hex: Topology


static func square() -> Topology:
	if _square == null:
		_square = SquareTopology.new()
	return _square


static func hex() -> Topology:
	if _hex == null:
		_hex = HexTopology.new()
	return _hex


static func for_id(topology_id: String) -> Topology:
	return hex() if topology_id == "hex" else square()


func neighbor(_cell: Vector2i, _dir: int) -> Vector2i:
	return Vector2i.ZERO


func opposite(dir: int) -> int:
	return (dir + dir_count / 2) % dir_count


## Rotates the connection bits one step clockwise; flag bits are kept.
func rotate_cw(mask: int) -> int:
	var result := mask & ~ALL_CONNECTION_BITS
	for i in dir_count:
		if mask & (1 << i):
			result |= 1 << ((i + 1) % dir_count)
	return result


func connection_count(mask: int) -> int:
	var count := 0
	for i in dir_count:
		if mask & (1 << i):
			count += 1
	return count


## Grid steps between two cells.
func distance(_a: Vector2i, _b: Vector2i) -> int:
	return 0


## All in-bounds cells with distance <= radius from cell (including cell).
func cells_within(cell: Vector2i, radius: int, width: int, height: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(maxi(0, cell.y - radius), mini(height, cell.y + radius + 1)):
		for x in range(maxi(0, cell.x - radius - 1), mini(width, cell.x + radius + 2)):
			var p := Vector2i(x, y)
			if distance(cell, p) <= radius:
				result.append(p)
	return result


# --- Geometry (screen coordinates, y down; size = pixel width of one cell) ---

func cell_center(_cell: Vector2i, _size: float = 72.0) -> Vector2:
	return Vector2.ZERO


## Nearest cell to a point (may be out of bounds).
func cell_at(_pos: Vector2, _size: float = 72.0) -> Vector2i:
	return Vector2i.ZERO


func board_pixel_size(_width: int, _height: int, _size: float = 72.0) -> Vector2:
	return Vector2.ZERO


## Unit vector from a cell centre towards the neighbouring centre in that direction.
func dir_vector(_dir: int) -> Vector2:
	return Vector2.ZERO


## Closed outline of the cell: 4 corners (square) or 6 (hex).
func cell_polygon(_cell: Vector2i, _size: float = 72.0) -> PackedVector2Array:
	return PackedVector2Array()
