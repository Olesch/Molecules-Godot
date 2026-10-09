extends Node2D
## 2D view and input for the molecule game. All rules live in Board.

const BOARD_W := 8
const BOARD_H := 8
const CELL := 72
const HEADER := 130

const COLORS: Array[Color] = [
	Color("6ab04c"), # 1 connection
	Color("4a90d9"), # 2
	Color("e0a030"), # 3
	Color("c0504d"), # 4
]
const BG_COLOR := Color("1e2229")
const GRID_COLOR := Color("353b46")
const STUB_OK := Color("e8ecf1")
const STUB_OPEN := Color("ff5d5d")

var _board: Board
var _rng := RandomNumberGenerator.new()
var _next_mask := 0
var _score := 0
var _game_over := false
var _hover := Vector2i(-1, -1)


func _ready() -> void:
	_rng.randomize()
	_new_game()


func _new_game() -> void:
	_board = Board.new(BOARD_W, BOARD_H)
	_score = 0
	_game_over = false
	_next_mask = Atoms.random_shape(_rng)
	queue_redraw()


func _origin() -> Vector2:
	var size := get_viewport_rect().size
	return Vector2((size.x - BOARD_W * CELL) / 2.0, HEADER)


func _cell_at(pos: Vector2) -> Vector2i:
	var rel := pos - _origin()
	return Vector2i(floori(rel.x / CELL), floori(rel.y / CELL))


func _cell_center(p: Vector2i) -> Vector2:
	return _origin() + (Vector2(p) + Vector2(0.5, 0.5)) * CELL


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_hover = _cell_at(event.position)
				_try_place(_hover)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
				_rotate_next()
			MOUSE_BUTTON_WHEEL_UP:
				_rotate_next(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R, KEY_SPACE:
				_rotate_next()
			KEY_ENTER:
				if _game_over:
					_new_game()


func _rotate_next(clockwise := true) -> void:
	if _game_over:
		return
	var times := 1 if clockwise else 3
	for i in times:
		_next_mask = Atoms.rotate_cw(_next_mask)
	queue_redraw()


func _try_place(p: Vector2i) -> void:
	if _game_over:
		_new_game()
		return
	if not _board.is_empty(p):
		return
	var cleared := _board.place(p, _next_mask)
	_score += cleared.size()
	_next_mask = Atoms.random_shape(_rng)
	if cleared.is_empty() and _board.is_full():
		_game_over = true
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	var font := ThemeDB.fallback_font

	# Grid and atoms.
	var origin := _origin()
	for y in BOARD_H:
		for x in BOARD_W:
			var p := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(p) * CELL, Vector2(CELL, CELL))
			draw_rect(rect, GRID_COLOR, false, 1.0)
			var mask := _board.get_atom(p)
			if mask != 0:
				_draw_atom(_cell_center(p), mask, 1.0, p)

	# Hover preview.
	if not _game_over and _board.is_empty(_hover):
		_draw_atom(_cell_center(_hover), _next_mask, 0.45, Vector2i(-1, -1))

	# Header: next atom and score.
	draw_string(font, Vector2(origin.x, 40), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, STUB_OK)
	_draw_atom(Vector2(origin.x + 150, 55), _next_mask, 1.0, Vector2i(-1, -1))
	draw_string(font, Vector2(origin.x + 300, 40), "ATOMS CLEARED: %d" % _score, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, STUB_OK)
	draw_string(font, Vector2(origin.x, size.y - 20), "Click: place   R / right-click / wheel: rotate", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GRID_COLOR.lightened(0.5))

	if _game_over:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y / 2.0 - 10), "BOARD FULL - YOU LOSE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, STUB_OPEN)
		draw_string(font, Vector2(0, size.y / 2.0 + 30), "Click or press Enter to restart", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, STUB_OK)


## cell is the board cell used to tell open from bonded stubs; pass (-1,-1) to draw all stubs neutral.
func _draw_atom(center: Vector2, mask: int, alpha: float, cell: Vector2i) -> void:
	var on_board := _board.in_bounds(cell)
	for dir in 4:
		if mask & (1 << dir):
			var open := on_board and not _board.is_bonded(cell, dir)
			var col := STUB_OPEN if open else STUB_OK
			col.a = alpha
			var tip := center + Vector2(Atoms.OFFSETS[dir]) * (CELL * 0.5)
			draw_line(center, tip, col, 8.0)
	var body := COLORS[Atoms.connection_count(mask) - 1]
	body.a = alpha
	draw_circle(center, CELL * 0.27, body)
