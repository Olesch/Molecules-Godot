class_name Playfield
extends Node2D
## One player's board: rules (via Board), drawing, effects and, if interactive, input.
## The node's origin is the board's top-left corner; the header (held atom, queue) is drawn above it.
## A non-interactive Playfield is a mirror of the opponent and only shows snapshots.

signal attack(amount: int) ## stray atoms this player sends to the opponent
signal lost
signal board_changed(cells: PackedInt32Array)
signal restart_requested
signal sfx_requested(sfx_name: String, pitch: float)

const BOARD_W := 8
const BOARD_H := 8
const HEADER := 130
const PREPLACED := 10
const QUEUE_SIZE := 4 ## the held atom plus the ones coming after it
const SHAKE_MAX := 22.0
const POP_TIME := 0.18

const COLORS: Array[Color] = [
	Color("6ab04c"), # 1 connection
	Color("4a90d9"), # 2
	Color("e0a030"), # 3
	Color("c0504d"), # 4
]
const BOMB_COLOR := Color("2b2f38")
const BLAST_COLOR := Color("ff9a3c")
const WILD_COLOR := Color("b07cff")
const GRID_COLOR := Color("353b46")
const STUB_OK := Color("e8ecf1")
const STUB_OPEN := Color("ff5d5d")
const DIM_TEXT := Color("8f98a8")

var cell_size := 72
var interactive := true
var title := ""
## Where the node sits when not shaking; set by whoever lays out the scene.
var home_position := Vector2.ZERO

var board: Board
var score := 0
var finished := false

var _queue_rng := RandomNumberGenerator.new() ## seeded: both players get the same atoms
var _fx_rng := RandomNumberGenerator.new() ## local only: effects and stray atom placement
var _queue: Array[int] = []
var _pending := 0 ## stray atoms waiting to land after this player's next plain placement
var _hover := Vector2i(-1, -1)
var _overlay_title := ""
var _overlay_sub := ""
var _overlay_color := STUB_OK

# Juice: particles and rings share one list; popups are floating score text.
var _fx: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _pop_age := {} # Vector2i -> seconds since the atom was placed
var _trauma := 0.0


func _ready() -> void:
	_fx_rng.randomize()
	if board == null:
		start(randi())


## Resets to a fresh game. The same seed gives the same preplaced atoms and atom sequence.
func start(seed_value: int) -> void:
	_queue_rng.seed = seed_value
	board = Board.new(BOARD_W, BOARD_H)
	board.preplace(PREPLACED, _queue_rng)
	_queue.clear()
	for i in QUEUE_SIZE:
		_queue.append(Atoms.random_atom(_queue_rng))
	score = 0
	_pending = 0
	finished = false
	_overlay_title = ""
	_overlay_sub = ""
	_fx.clear()
	_popups.clear()
	_pop_age.clear()
	queue_redraw()
	if interactive:
		board_changed.emit(board.snapshot())


## Overlay text for a finished game ("" clears it). Also stops local input.
func set_overlay(overlay_title: String, sub := "", color := STUB_OK) -> void:
	_overlay_title = overlay_title
	_overlay_sub = sub
	_overlay_color = color
	finished = overlay_title != ""
	queue_redraw()


## Called when the opponent attacks; the atoms land after the next plain placement.
func receive_attack(amount: int) -> void:
	if finished or amount <= 0:
		return
	_pending += amount
	sfx_requested.emit("warning", 1.0)
	queue_redraw()


## Mirror mode: show the opponent's board. Atoms that vanished get a small burst.
func apply_snapshot(cells: PackedInt32Array) -> void:
	if board == null or cells.size() != BOARD_W * BOARD_H:
		return
	for y in BOARD_H:
		for x in BOARD_W:
			var p := Vector2i(x, y)
			var old := board.get_atom(p)
			var now := cells[y * BOARD_W + x]
			if old != 0 and now == 0:
				_burst(_cell_center(p), _atom_color(old), 8, 160.0)
			elif old == 0 and now != 0:
				_pop_age[p] = 0.0
	board.load_snapshot(cells)
	queue_redraw()


func _cell_at(global_pos: Vector2) -> Vector2i:
	var rel := global_pos - get_parent_global_offset() - home_position
	return Vector2i(floori(rel.x / cell_size), floori(rel.y / cell_size))


func get_parent_global_offset() -> Vector2:
	var parent := get_parent()
	return parent.global_position if parent is Node2D else Vector2.ZERO


func _cell_center(p: Vector2i) -> Vector2:
	return (Vector2(p) + Vector2(0.5, 0.5)) * cell_size


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseMotion:
		_hover = _cell_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if finished:
					restart_requested.emit()
				else:
					_hover = _cell_at(event.position)
					try_place(_hover)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
				rotate_held()
			MOUSE_BUTTON_WHEEL_UP:
				rotate_held(false)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R, KEY_SPACE:
				rotate_held()
			KEY_ENTER:
				if finished:
					restart_requested.emit()


func rotate_held(clockwise := true) -> void:
	if finished or Atoms.is_wild(_queue[0]):
		return
	var times := 1 if clockwise else 3
	for i in times:
		_queue[0] = Atoms.rotate_cw(_queue[0])
	sfx_requested.emit("rotate", 1.0)
	queue_redraw()


func try_place(p: Vector2i) -> void:
	if finished or not board.in_bounds(p):
		return
	if not board.is_empty(p):
		sfx_requested.emit("invalid", 1.0)
		_trauma = minf(1.0, _trauma + 0.12)
		return
	var cleared := board.place(p, _queue[0])
	_queue.pop_front()
	_queue.append(Atoms.random_atom(_queue_rng))
	if cleared.is_empty():
		_pop_age[p] = 0.0
		sfx_requested.emit("place", 1.0)
		_trauma = minf(1.0, _trauma + 0.08)
		_burst(_cell_center(p), STUB_OK.darkened(0.4), 6, 90.0)
		_land_stray_atoms()
		if board.is_full():
			_lose()
	else:
		_celebrate(cleared)
	if not finished:
		board_changed.emit(board.snapshot())
	queue_redraw()


func _land_stray_atoms() -> void:
	if _pending <= 0:
		return
	var landing := mini(_pending, Scoring.GARBAGE_PER_TURN)
	_pending -= landing
	var cells := board.add_garbage(landing, _fx_rng)
	for c in cells:
		_pop_age[c] = 0.0
		_burst(_cell_center(c), WILD_COLOR.darkened(0.2), 6, 140.0)
	sfx_requested.emit("garbage", 1.0)
	_trauma = minf(1.0, _trauma + 0.45)


func _celebrate(cleared: Array[Vector2i]) -> void:
	var molecule := board.last_molecule_size
	var blasted := cleared.size() - molecule
	var points := Scoring.points(molecule, blasted)
	score += points
	var sum := Vector2.ZERO
	for i in cleared.size():
		var center := _cell_center(cleared[i])
		sum += center
		var body := _atom_color(board.last_cleared_masks[i])
		_burst(center, body, 14, 300.0)
		_fx.append({"kind": 1, "pos": center, "age": 0.0, "life": 0.4, "color": body, "size": 0.0, "vel": Vector2.ZERO})
	for bomb in board.last_exploded:
		var at := _cell_center(bomb)
		_burst(at, BLAST_COLOR, 36, 520.0)
		_fx.append({"kind": 1, "pos": at, "age": 0.0, "life": 0.55, "color": BLAST_COLOR, "size": 0.0, "vel": Vector2.ZERO, "grow": 2.4})
	if not board.last_exploded.is_empty():
		sfx_requested.emit("explode", 1.0)
		_trauma = 1.0
	_popups.append({"pos": sum / cleared.size(), "age": 0.0, "text": "+%d" % points})
	sfx_requested.emit("clear", clampf(0.9 + 0.06 * (cleared.size() - 2), 0.8, 1.5))
	_trauma = minf(1.0, _trauma + 0.25 + 0.06 * cleared.size())

	# Incoming stray atoms are cancelled first; whatever is left goes to the opponent.
	var outgoing := Scoring.attack(molecule, blasted)
	var cancelled := mini(outgoing, _pending)
	_pending -= cancelled
	outgoing -= cancelled
	if outgoing > 0:
		sfx_requested.emit("attack", 1.0)
		attack.emit(outgoing)


func _lose() -> void:
	set_overlay("BOARD FULL - YOU LOSE", "", STUB_OPEN)
	sfx_requested.emit("lose", 1.0)
	_trauma = 1.0
	for i in 40:
		var cell := Vector2i(_fx_rng.randi_range(0, BOARD_W - 1), _fx_rng.randi_range(0, BOARD_H - 1))
		_burst(_cell_center(cell), STUB_OPEN, 2, 260.0)
	lost.emit()


## Spawns count dots flying outward from pos.
func _burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	var scale := cell_size / 72.0
	for i in count:
		var dir := Vector2.from_angle(_fx_rng.randf() * TAU)
		_fx.append({
			"kind": 0,
			"pos": pos,
			"vel": dir * speed * scale * _fx_rng.randf_range(0.35, 1.0),
			"age": 0.0,
			"life": _fx_rng.randf_range(0.35, 0.8),
			"size": _fx_rng.randf_range(3.0, 6.5) * scale,
			"color": color.lightened(_fx_rng.randf_range(0.0, 0.35)),
		})


func _process(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	if _trauma > 0.0:
		position = home_position + Vector2(_fx_rng.randf_range(-1.0, 1.0), _fx_rng.randf_range(-1.0, 1.0)) * SHAKE_MAX * (cell_size / 72.0) * _trauma * _trauma
	else:
		position = home_position

	for i in range(_fx.size() - 1, -1, -1):
		var f := _fx[i]
		f.age += delta
		if f.age >= f.life:
			_fx.remove_at(i)
			continue
		var vel: Vector2 = f.vel
		vel = vel * maxf(0.0, 1.0 - 3.0 * delta) + Vector2(0.0, 380.0 * cell_size / 72.0) * delta
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

	if not (_fx.is_empty() and _popups.is_empty() and _pop_age.is_empty()) or _trauma > 0.0 or position != home_position:
		queue_redraw()


func _draw() -> void:
	if board == null:
		return
	var font := ThemeDB.fallback_font
	var board_px := Vector2(BOARD_W, BOARD_H) * cell_size

	for y in BOARD_H:
		for x in BOARD_W:
			var p := Vector2i(x, y)
			draw_rect(Rect2(Vector2(p) * cell_size, Vector2(cell_size, cell_size)), GRID_COLOR, false, 1.0)
			var mask := board.get_atom(p)
			if mask != 0:
				_draw_atom(_cell_center(p), mask, 1.0, p, _pop_scale(p))

	# Hover preview (a bomb also shows its blast area).
	if interactive and not finished and board.is_empty(_hover):
		if Atoms.is_bomb(_queue[0]):
			var r := Atoms.BLAST_RADIUS
			var area := Rect2(Vector2(_hover - Vector2i(r, r)) * cell_size, Vector2.ONE * cell_size * (2 * r + 1))
			draw_rect(area, Color(BLAST_COLOR, 0.12))
			draw_rect(area, Color(BLAST_COLOR, 0.5), false, 2.0)
		_draw_atom(_cell_center(_hover), _queue[0], 0.45, Vector2i(-1, -1))

	_draw_fx(font)

	# Incoming stray atoms waiting to land: red blocks along the left edge.
	for i in mini(_pending, 16):
		draw_rect(Rect2(-14, board_px.y - 14 - i * 14, 8, 11), STUB_OPEN)

	if interactive:
		_draw_header(font, board_px)
	elif title != "":
		draw_string(font, Vector2(0, -10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM_TEXT)

	if _overlay_title != "":
		draw_rect(Rect2(Vector2.ZERO, board_px), Color(0, 0, 0, 0.6))
		var mid := board_px.y / 2.0
		var big := 32 if interactive else 16
		draw_string(font, Vector2(0, mid - 10), _overlay_title, HORIZONTAL_ALIGNMENT_CENTER, board_px.x, big, _overlay_color)
		if _overlay_sub != "":
			draw_string(font, Vector2(0, mid + 28), _overlay_sub, HORIZONTAL_ALIGNMENT_CENTER, board_px.x, 20 if interactive else 12, STUB_OK)


func _draw_header(font: Font, board_px: Vector2) -> void:
	draw_string(font, Vector2(0, -HEADER + 28), "NOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM_TEXT)
	_draw_atom(Vector2(40, -HEADER + 78), _queue[0], 1.0, Vector2i(-1, -1), 1.0, 72)
	draw_string(font, Vector2(120, -HEADER + 28), "COMING UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM_TEXT)
	for i in range(1, _queue.size()):
		_draw_atom(Vector2(150 + (i - 1) * 62, -HEADER + 78), _queue[i], 0.85, Vector2i(-1, -1), 0.6, 72)
	draw_string(font, Vector2(0, -HEADER + 40), "SCORE: %d" % score, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 22, STUB_OK)
	if _pending > 0:
		draw_string(font, Vector2(0, -HEADER + 70), "INCOMING: %d" % _pending, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 18, STUB_OPEN)


func _atom_color(atom: int) -> Color:
	if Atoms.is_wild(atom):
		return WILD_COLOR
	if Atoms.is_bomb(atom):
		return BOMB_COLOR
	return COLORS[Atoms.connection_count(atom) - 1]


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
			draw_arc(f.pos, lerpf(cell_size * 0.2, cell_size * 0.95 * f.get("grow", 1.0), k), 0.0, TAU, 32, col, (6.0 * (1.0 - k) + 1.0) * cell_size / 72.0)
	for pop in _popups:
		var k: float = pop.age / 0.9
		var col := Color("ffe27a")
		col.a = 1.0 - k * k
		var at: Vector2 = pop.pos + Vector2(-40, -30 - 50 * k) * cell_size / 72.0
		draw_string(font, at, pop.text, HORIZONTAL_ALIGNMENT_CENTER, 80 * cell_size / 72.0, int(34 * cell_size / 72.0), col)


## cell is the board cell used to tell open from bonded stubs; pass (-1,-1) to draw all stubs neutral.
func _draw_atom(center: Vector2, mask: int, alpha: float, cell: Vector2i, scale := 1.0, unit_px := -1) -> void:
	var unit := cell_size if unit_px < 0 else unit_px
	var on_board := board.in_bounds(cell)
	for dir in 4:
		if mask & (1 << dir):
			var open := on_board and not board.is_bonded(cell, dir)
			var col := STUB_OPEN if open else STUB_OK
			col.a = alpha
			var tip := center + Vector2(Atoms.OFFSETS[dir]) * (unit * 0.5 * scale)
			draw_line(center, tip, col, 8.0 * scale * unit / 72.0)
	var body := _atom_color(mask)
	body.a = alpha
	draw_circle(center, unit * 0.27 * scale, body)
	if Atoms.is_wild(mask):
		# Four sockets: lit when a neighbour's connection is plugged into the wildcard.
		for dir in 4:
			var lit := on_board and board.is_linked(cell, dir)
			var dot := STUB_OK if lit else WILD_COLOR.darkened(0.45)
			dot.a = alpha
			draw_circle(center + Vector2(Atoms.OFFSETS[dir]) * unit * 0.4 * scale, unit * 0.07 * scale, dot)
		var core := Color.WHITE
		core.a = alpha
		draw_arc(center, unit * 0.16 * scale, 0.0, TAU, 20, core, 3.0 * scale * unit / 72.0)
	if Atoms.is_bomb(mask):
		var ring := BLAST_COLOR
		ring.a = alpha
		draw_arc(center, unit * 0.27 * scale, 0.0, TAU, 24, ring, 4.0 * scale * unit / 72.0)
		draw_circle(center, unit * 0.09 * scale, ring)
		draw_line(center + Vector2(0, -unit * 0.27) * scale, center + Vector2(unit * 0.1, -unit * 0.4) * scale, ring, 3.0 * scale * unit / 72.0)
