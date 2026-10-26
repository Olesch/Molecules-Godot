class_name HexTopology
extends Topology
## Pointy-top hex grid in odd-r offset coordinates (odd rows shifted half a cell right).
## Directions clockwise from east: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE (bit i = 1 << i).

const EVEN_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
const ODD_OFFSETS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
const SQRT3 := 1.7320508075688772


func _init() -> void:
	id = "hex"
	dir_count = 6
	max_connections = 6
	# single, straight, wide bend, sharp bend, Y, fan, T, two 4-arm shapes, 5 arms, star.
	shapes = [1, 1 | 8, 1 | 4, 1 | 2, 1 | 4 | 16, 1 | 2 | 4, 1 | 2 | 8, 1 | 2 | 8 | 16, 1 | 2 | 4 | 16, 31, 63]
	# Hand-tuned by difficulty (total 6.61): 1 connection 23%, 2 connections 56%, 3 connections 15%,
	# 4, 5 and 6 together 6% (about the square board's 4-connection cross). The bends are common
	# because they are easy to close; Y splits a molecule into branches, so it is rarer than Fan.
	shape_weights = [1.5, 1.0, 1.2, 1.5, 0.3, 0.4, 0.3, 0.14, 0.14, 0.08, 0.05]


func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	return cell + (ODD_OFFSETS[dir] if (cell.y & 1) == 1 else EVEN_OFFSETS[dir])


func _cube_q(c: Vector2i) -> int:
	return c.x - (c.y - (c.y & 1)) / 2


func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := _cube_q(a) - _cube_q(b)
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


func cell_center(cell: Vector2i, size: float = 72.0) -> Vector2:
	var shift := 0.5 if (cell.y & 1) == 1 else 0.0
	return Vector2((cell.x + 0.5 + shift) * size, size / SQRT3 + cell.y * size * SQRT3 / 2.0)


func cell_at(pos: Vector2, size: float = 72.0) -> Vector2i:
	var row_h := size * SQRT3 / 2.0
	var row := roundi((pos.y - size / SQRT3) / row_h)
	var best := Vector2i(0, row)
	var best_d := INF
	for y in range(row - 1, row + 2):
		var shift := 0.5 if (y & 1) == 1 else 0.0
		var cx := floori(pos.x / size - 0.5 - shift)
		for x in range(cx, cx + 2):
			var d := cell_center(Vector2i(x, y), size).distance_squared_to(pos)
			if d < best_d - 1e-9:
				best_d = d
				best = Vector2i(x, y)
	return best


func board_pixel_size(width: int, height: int, size: float = 72.0) -> Vector2:
	return Vector2((width + 0.5) * size, size * 2.0 / SQRT3 + (height - 1) * size * SQRT3 / 2.0)


func dir_vector(dir: int) -> Vector2:
	var a := deg_to_rad(dir * 60.0)
	return Vector2(cos(a), sin(a))


func cell_polygon(cell: Vector2i, size: float = 72.0) -> PackedVector2Array:
	var c := cell_center(cell, size)
	var r := size / SQRT3
	var pts := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(-90.0 + 60.0 * k)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
