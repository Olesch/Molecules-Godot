class_name SquareTopology
extends Topology
## Square grid, directions 0..3 = N, E, S, W (mask bits 1, 2, 4, 8).

const OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _init() -> void:
	id = "square"
	dir_count = 4
	max_connections = 4
	shapes = [1, 1 | 4, 1 | 2, 1 | 2 | 8, 1 | 2 | 4 | 8]
	shape_weights = [1.5, 1.5, 1.5, 1.0, 0.4]


func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	return cell + OFFSETS[dir]


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func cells_within(cell: Vector2i, radius: int, width: int, height: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := cell + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < width and p.y < height:
				result.append(p)
	return result


func cell_center(cell: Vector2i, size: float = 72.0) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * size


func cell_at(pos: Vector2, size: float = 72.0) -> Vector2i:
	return Vector2i(floori(pos.x / size), floori(pos.y / size))


func board_pixel_size(width: int, height: int, size: float = 72.0) -> Vector2:
	return Vector2(width, height) * size


func dir_vector(dir: int) -> Vector2:
	return Vector2(OFFSETS[dir])


func cell_polygon(cell: Vector2i, size: float = 72.0) -> PackedVector2Array:
	var o := Vector2(cell) * size
	return PackedVector2Array([o, o + Vector2(size, 0), o + Vector2(size, size), o + Vector2(0, size)])
