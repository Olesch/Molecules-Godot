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

const SFX_NAMES: Array[String] = ["place", "rotate", "clear", "lose", "invalid"]
const SHAKE_MAX := 22.0
const POP_TIME := 0.18

var _board: Board
var _rng := RandomNumberGenerator.new()
var _next_mask := 0
var _score := 0
var _game_over := false
var _hover := Vector2i(-1, -1)

# Juice: particles and rings share one list; popups are floating score text.
var _fx: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _pop_age := {} # Vector2i -> seconds since the atom was placed
var _trauma := 0.0
var _sfx := {}


func _ready() -> void:
	_rng.randomize()
	for sfx_name in SFX_NAMES:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if ResourceLoader.exists(path):
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			add_child(player)
			_sfx[sfx_name] = player
	_new_game()


func _new_game() -> void:
	_board = Board.new(BOARD_W, BOARD_H)
	_score = 0
	_game_over = false
	_next_mask = Atoms.random_shape(_rng)
	_fx.clear()
	_popups.clear()
	_pop_age.clear()
	queue_redraw()


func _play(sfx_name: String, pitch := 1.0, jitter := 0.0) -> void:
	if _sfx.has(sfx_name):
		var player: AudioStreamPlayer = _sfx[sfx_name]
		player.pitch_scale = pitch + _rng.randf_range(-jitter, jitter)
		player.play()


func _origin() -> Vector2:
	var size := get_viewport_rect().size
	return Vector2((size.x - BOARD_W * CELL) / 2.0, HEADER)


func _cell_at(pos: Vector2) -> Vector2i:
	var rel := pos - position - _origin()
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
	_play("rotate", 1.0, 0.04)
	queue_redraw()


func _try_place(p: Vector2i) -> void:
	if _game_over:
		_new_game()
		return
	if not _board.in_bounds(p):
		return
	if not _board.is_empty(p):
		_play("invalid")
		_trauma = minf(1.0, _trauma + 0.12)
		return
	var cleared := _board.place(p, _next_mask)
	_score += cleared.size()
	_next_mask = Atoms.random_shape(_rng)
	if cleared.is_empty():
		_pop_age[p] = 0.0
		_play("place", 1.0, 0.05)
		_trauma = minf(1.0, _trauma + 0.08)
		_burst(_cell_center(p), STUB_OK.darkened(0.4), 6, 90.0)
		if _board.is_full():
			_lose()
	else:
		_celebrate(cleared)
	queue_redraw()


func _celebrate(cleared: Array[Vector2i]) -> void:
	var sum := Vector2.ZERO
	for i in cleared.size():
		var center := _cell_center(cleared[i])
		sum += center
		var body := COLORS[Atoms.connection_count(_board.last_cleared_masks[i]) - 1]
		_burst(center, body, 14, 300.0)
		_fx.append({"kind": 1, "pos": center, "age": 0.0, "life": 0.4, "color": body, "size": 0.0, "vel": Vector2.ZERO})
	_popups.append({"pos": sum / cleared.size(), "age": 0.0, "text": "+%d" % cleared.size()})
	_play("clear", clampf(0.9 + 0.06 * (cleared.size() - 2), 0.8, 1.5))
	_trauma = minf(1.0, _trauma + 0.25 + 0.06 * cleared.size())


func _lose() -> void:
	_game_over = true
	_play("lose")
	_trauma = 1.0
	for i in 40:
		var cell := Vector2i(_rng.randi_range(0, BOARD_W - 1), _rng.randi_range(0, BOARD_H - 1))
		_burst(_cell_center(cell), STUB_OPEN, 2, 260.0)


## Spawns count dots flying outward from pos.
func _burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_fx.append({
			"kind": 0,
			"pos": pos,
			"vel": dir * speed * _rng.randf_range(0.35, 1.0),
			"age": 0.0,
			"life": _rng.randf_range(0.35, 0.8),
			"size": _rng.randf_range(3.0, 6.5),
			"color": color.lightened(_rng.randf_range(0.0, 0.35)),
		})


func _process(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	if _trauma > 0.0:
		position = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * SHAKE_MAX * _trauma * _trauma
	else:
		position = Vector2.ZERO

	for i in range(_fx.size() - 1, -1, -1):
		var f := _fx[i]
		f.age += delta
		if f.age >= f.life:
			_fx.remove_at(i)
			continue
		var vel: Vector2 = f.vel
		vel = vel * maxf(0.0, 1.0 - 3.0 * delta) + Vector2(0.0, 380.0) * delta
		f.vel = vel
		f.pos += vel * delta
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].age += delta
		if _popups[i].age >= 0.9:
			_popups.remove_at(i)
	for cell in _pop_age.keys():
		_pop_age[cell] += delta
		if _pop_age[cell] >= POP_TIME:
			_pop_age.erase(cell)

	if not (_fx.is_empty() and _popups.is_empty() and _pop_age.is_empty()) or _trauma > 0.0 or position != Vector2.ZERO:
		queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2(-40, -40), size + Vector2(80, 80)), BG_COLOR)
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
				_draw_atom(_cell_center(p), mask, 1.0, p, _pop_scale(p))

	# Hover preview.
	if not _game_over and _board.is_empty(_hover):
		_draw_atom(_cell_center(_hover), _next_mask, 0.45, Vector2i(-1, -1))

	_draw_fx(font)

	# Header: next atom and score.
	draw_string(font, Vector2(origin.x, 40), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, STUB_OK)
	_draw_atom(Vector2(origin.x + 150, 55), _next_mask, 1.0, Vector2i(-1, -1))
	draw_string(font, Vector2(origin.x + 300, 40), "ATOMS CLEARED: %d" % _score, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, STUB_OK)
	draw_string(font, Vector2(origin.x, size.y - 20), "Click: place   R / right-click / wheel: rotate", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GRID_COLOR.lightened(0.5))

	if _game_over:
		draw_rect(Rect2(Vector2(-40, -40), size + Vector2(80, 80)), Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y / 2.0 - 10), "BOARD FULL - YOU LOSE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, STUB_OPEN)
		draw_string(font, Vector2(0, size.y / 2.0 + 30), "Click or press Enter to restart", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, STUB_OK)


## cell is the board cell used to tell open from bonded stubs; pass (-1,-1) to draw all stubs neutral.
func _pop_scale(p: Vector2i) -> float:
	if not _pop_age.has(p):
		return 1.0
	var x: float = _pop_age[p] / POP_TIME - 1.0
	return 0.3 + 0.7 * (1.0 + 2.70158 * x * x * x + 1.70158 * x * x)


func _draw_fx(font: Font) -> void:
	for f in _fx:
		var k: float = f.age / f.life
		var col: Color = f.color
		col.a = 1.0 - k
		if f.kind == 0:
			draw_circle(f.pos, f.size * (1.0 - 0.6 * k), col)
		else:
			draw_arc(f.pos, lerpf(CELL * 0.2, CELL * 0.95, k), 0.0, TAU, 32, col, 6.0 * (1.0 - k) + 1.0)
	for pop in _popups:
		var k: float = pop.age / 0.9
		var col := Color("ffe27a")
		col.a = 1.0 - k * k
		var at: Vector2 = pop.pos + Vector2(-40, -30 - 50 * k)
		draw_string(font, at, pop.text, HORIZONTAL_ALIGNMENT_CENTER, 80, 34, col)


func _draw_atom(center: Vector2, mask: int, alpha: float, cell: Vector2i, scale := 1.0) -> void:
	var on_board := _board.in_bounds(cell)
	for dir in 4:
		if mask & (1 << dir):
			var open := on_board and not _board.is_bonded(cell, dir)
			var col := STUB_OPEN if open else STUB_OK
			col.a = alpha
			var tip := center + Vector2(Atoms.OFFSETS[dir]) * (CELL * 0.5 * scale)
			draw_line(center, tip, col, 8.0 * scale)
	var body := COLORS[Atoms.connection_count(mask) - 1]
	body.a = alpha
	draw_circle(center, CELL * 0.27 * scale, body)
