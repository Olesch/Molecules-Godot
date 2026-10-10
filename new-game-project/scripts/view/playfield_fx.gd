class_name PlayfieldFx
extends RefCounted
## Juice for one Playfield: particles, rings, sparks, score popups, placement pop-in, screen
## shake and the ghosts of cleared atoms. It has no _process of its own: the Playfield calls
## advance(), and its _draw calls paint() so the effects sit between the atoms and the HUD.

signal ghost_fired(ghost: Dictionary) ## the clear wave reached a ghost (after its effects spawned)

enum Kind { DOT, RING, SPARK }

const SHAKE_MAX := 22.0
const POP_TIME := 0.18
const POPUP_TIME := 0.9

var cell_size := 72

var _items: Array[Dictionary] = [] # particles, rings and sparks share one list
var _popups: Array[Dictionary] = [] # floating score text
var _pop_age := {} # Vector2i -> seconds since the atom was placed
var _ghosts: Array[Dictionary] = [] # cleared atoms still shown until the clear wave reaches them
var _trauma := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	_items.clear()
	_popups.clear()
	_pop_age.clear()
	_ghosts.clear()


## True while anything still animates, so the owner keeps redrawing.
func is_busy() -> bool:
	return not (_items.is_empty() and _popups.is_empty() and _pop_age.is_empty() and _ghosts.is_empty()) or _trauma > 0.0


## True while cleared atoms are waiting for the clear wave.
func has_ghosts() -> bool:
	return not _ghosts.is_empty()


func cell_center(p: Vector2i) -> Vector2:
	return (Vector2(p) + Vector2(0.5, 0.5)) * cell_size


## Spawns count dots flying outward from pos.
func burst(pos: Vector2, color: Color, count: int, speed: float) -> void:
	var scale := cell_size / 72.0
	for i in count:
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		_items.append({
			"kind": Kind.DOT,
			"pos": pos,
			"vel": dir * speed * scale * _rng.randf_range(0.35, 1.0),
			"age": 0.0,
			"life": _rng.randf_range(0.35, 0.8),
			"size": _rng.randf_range(3.0, 6.5) * scale,
			"color": color.lightened(_rng.randf_range(0.0, 0.35)),
		})


## An expanding ring; grow scales its final radius.
func ring(pos: Vector2, color: Color, life: float, grow := 1.0) -> void:
	_items.append({"kind": Kind.RING, "pos": pos, "age": 0.0, "life": life, "color": color, "grow": grow})


## A short line that runs from one point to another.
func spark(from: Vector2, to: Vector2, color := Color.WHITE, life := 0.22) -> void:
	_items.append({"kind": Kind.SPARK, "pos": from, "to": to, "age": 0.0, "life": life, "color": color})


## Floating text; a negative age delays it.
func popup(pos: Vector2, text: String, age := 0.0) -> void:
	_popups.append({"pos": pos, "age": age, "text": text})


## An atom that stays visible until the clear wave reaches it, delay seconds from now.
func add_ghost(cell: Vector2i, mask: int, delay: float, parent: Vector2i) -> void:
	_ghosts.append({"cell": cell, "mask": mask, "delay": delay, "age": 0.0, "parent": parent})


## Starts the placement pop-in of an atom.
func pop(cell: Vector2i) -> void:
	_pop_age[cell] = 0.0


func pop_scale(cell: Vector2i) -> float:
	if not _pop_age.has(cell):
		return 1.0
	var x: float = _pop_age[cell] / POP_TIME - 1.0
	return 0.3 + 0.7 * (1.0 + 2.70158 * x * x * x + 1.70158 * x * x)


## Adds screen shake (0..1, capped).
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


## Jumps straight to the strongest shake.
func shake_max() -> void:
	_trauma = 1.0


## Random displacement for the Playfield node this frame.
func shake_offset() -> Vector2:
	if _trauma <= 0.0:
		return Vector2.ZERO
	return Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * SHAKE_MAX * (cell_size / 72.0) * _trauma * _trauma


func advance(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	for i in range(_items.size() - 1, -1, -1):
		var f := _items[i]
		f.age += delta
		if f.age >= f.life:
			_items.remove_at(i)
			continue
		if f.kind != Kind.DOT:
			continue # rings and sparks do not fall
		var vel: Vector2 = f.vel
		vel = vel * maxf(0.0, 1.0 - 3.0 * delta) + Vector2(0.0, 380.0 * cell_size / 72.0) * delta
		f.vel = vel
		f.pos += vel * delta
	for i in range(_ghosts.size() - 1, -1, -1):
		var ghost := _ghosts[i]
		ghost.age += delta
		if ghost.age >= ghost.delay:
			_ghosts.remove_at(i)
			_fire_ghost(ghost)
	for i in range(_popups.size() - 1, -1, -1):
		_popups[i].age += delta
		if _popups[i].age >= POPUP_TIME:
			_popups.remove_at(i)
	for cell in _pop_age.keys():
		_pop_age[cell] += delta
		if _pop_age[cell] >= POP_TIME:
			_pop_age.erase(cell)


## The clear wave reaches an atom: it bursts, and a spark runs along the bond it came through.
func _fire_ghost(ghost: Dictionary) -> void:
	var mask: int = ghost.mask
	var center := cell_center(ghost.cell)
	var body := AtomPainter.color(mask)
	burst(center, body, 14, 300.0)
	ring(center, body, 0.4)
	var parent: Vector2i = ghost.parent
	if parent.x >= 0:
		spark(cell_center(parent), center)
	if Atoms.is_bomb(mask):
		burst(center, Palette.ORANGE, 36, 520.0)
		ring(center, Palette.ORANGE, 0.55, 2.4)
		shake_max()
	ghost_fired.emit(ghost)


## Draws ghosts, particles and popups onto canvas (the Playfield, in its own coordinates).
func paint(canvas: CanvasItem, board: Board) -> void:
	var font := ThemeDB.fallback_font
	var line_scale := cell_size / 72.0
	for g in _ghosts:
		var center := cell_center(g.cell)
		var lead: float = g.delay - g.age # seconds until the wave arrives
		var charge := clampf(1.0 - lead / 0.1, 0.0, 1.0)
		AtomPainter.draw(canvas, center, g.mask, 1.0, 1.0 + 0.2 * charge, cell_size, board, Vector2i(-1, -1))
		if charge > 0.0:
			canvas.draw_arc(center, cell_size * (0.3 + 0.1 * charge), 0.0, TAU, 24, Color(1, 1, 1, 0.8 * charge), 3.0 * line_scale)
	for f in _items:
		var k: float = f.age / f.life
		var col: Color = f.color
		col.a = 1.0 - k
		match f.kind:
			Kind.DOT:
				canvas.draw_circle(f.pos, f.size * (1.0 - 0.6 * k), col)
			Kind.SPARK:
				var head: Vector2 = f.pos.lerp(f.to, minf(1.0, k * 2.0))
				var tail: Vector2 = f.pos.lerp(f.to, clampf(k * 2.0 - 0.5, 0.0, 1.0))
				canvas.draw_line(tail, head, col, (7.0 - 4.0 * k) * line_scale)
			Kind.RING:
				canvas.draw_arc(f.pos, lerpf(cell_size * 0.2, cell_size * 0.95 * f.grow, k), 0.0, TAU, 32, col, (6.0 * (1.0 - k) + 1.0) * line_scale)
	for pop in _popups:
		if pop.age < 0.0:
			continue
		var k: float = pop.age / POPUP_TIME
		var col := Palette.GOLD
		col.a = 1.0 - k * k
		var at: Vector2 = pop.pos + Vector2(-40, -30 - 50 * k) * line_scale
		canvas.draw_string(font, at, pop.text, HORIZONTAL_ALIGNMENT_CENTER, 80 * line_scale, int(34 * line_scale), col)
