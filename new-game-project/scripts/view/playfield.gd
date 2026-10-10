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
signal progression_changed ## XP, level or cards changed (solo saves them)

const BOARD_W := 8
const BOARD_H := 8
const HEADER := 130
const PREPLACED := 10
const REROLL_COOLDOWN := 4 ## placements before Reroll recharges
const LIFELINE_FILL := 0.78
const LIFELINE_COOLDOWN := 4
const CLEAR_STEP := 0.07 ## seconds between neighbouring atoms of a clearing molecule
const CLEAR_MAX_TIME := 0.7 ## the whole wave never takes longer than this
const REROLL_RADIUS := 22.0 ## the round Reroll button next to the held atom
const REROLL_SLOT := 62.0 ## header width it takes, pushing the coming-up queue to the right
const WARN_SECONDS := 3.0 ## timed mode: the warning sound and red countdown start this far ahead

const HEX_BOARD_UNITS := 8.5 ## a hex board is as wide as a square one when its cells are width / 8.5

var base_cell_size := 72 ## cell width of a square board; hex cells are sized to match its width
var cell_size := 72.0
var topology: Topology = Topology.square()
var interactive := true
var title := ""
## Where the node sits when not shaking; set by whoever lays out the scene.
var home_position := Vector2.ZERO

var board: Board
var score := 0
var finished := false
## Level, XP and cards. The owner swaps this in before start(): solo keeps it between
## games, versus starts everyone fresh each match.
var progression := Progression.new()
var versus := false
## The options picked on the setup screen (pressure mode, and whatever is added later).
var config := GameConfig.new()
## Solo pressure flavour: stray atoms drop on a clock instead of every few placements.
var timed: bool:
	get:
		return config.pressure() == GameConfig.PRESSURE_TIMED
var mods: Modifiers:
	get:
		return progression.mods

var _queue_rng := RandomNumberGenerator.new() ## seeded: both players get the same atoms
var _fx_rng := RandomNumberGenerator.new() ## local only: effects and stray atom placement
var _queue: Array[int] = []
var _attack_charge := 0.0 ## versus: points not yet turned into stray atoms (Scoring.POINTS_PER_ATTACK each)
var _pending := 0## versus: queued incoming stray atoms (including the announced one)
var _hover := Vector2i(-1, -1)
var _reroll_hover := false
var _card_overlay: CardOverlay
var _stash := 0
var _reroll_cd := 0
var _lifeline_cd := 0
var _placements := 0
var _since_clear := 99 ## placements since the last clear (for Combo Chain)
var _stray := {} ## cells that received stray atoms (for Gardener)
var _overlay_title := ""
var _overlay_sub := ""
var _overlay_color := Palette.TEXT

var _fx := PlayfieldFx.new() ## particles, popups, ghosts and shake
var _danger := Danger.new() ## solo pressure: announced stray atoms that drop on a schedule
var _incoming := Danger.new() ## versus: the one announced incoming stray atom and its countdown
var _warned := false ## the timed drop warning already played this round
var _offer_wait := 0.0 ## seconds to hold back a level-up card pick so the clear animation can play


func _ready() -> void:
	_fx_rng.randomize()
	_apply_topology()
	_fx.ghost_fired.connect(_on_ghost_fired)
	if interactive:
		_card_overlay = CardOverlay.new()
		_card_overlay.board_size = board_pixel_size()
		_card_overlay.picked.connect(_on_card_picked)
		add_child(_card_overlay)
	if board == null:
		start(randi())


## Resets to a fresh game. The same seed gives the same preplaced atoms and atom sequence.
func start(seed_value: int) -> void:
	_queue_rng.seed = seed_value
	_apply_topology()
	board = Board.new(BOARD_W, BOARD_H, topology)
	if _card_overlay:
		_card_overlay.board_size = board_pixel_size()
	_apply_rules_to_board()
	board.preplace(mods.preplaced_count(PREPLACED), _queue_rng)
	_danger.ghosts.clear()
	_danger.timed = timed
	_incoming.ghosts.clear()
	_incoming.timed = true
	_incoming.count_override = 1
	_warned = false
	if _danger_active():
		_danger.start(board, progression.level, _fx_rng)
	_queue.clear()
	_fit_queue()
	score = 0
	_pending = 0
	_attack_charge = 0.0
	_stash = 0
	_reroll_cd = 0
	_lifeline_cd = 0
	_placements = 0
	_since_clear = 99
	_stray.clear()
	if _card_overlay:
		_card_overlay.hide_offer()
	finished = false
	_overlay_title = ""
	_overlay_sub = ""
	_fx.clear()
	_offer_wait = 0.0
	queue_redraw()
	if interactive:
		board_changed.emit(board.snapshot())
		_maybe_offer.call_deferred()


## Takes the topology from the config and sizes the cells so a hex board is as wide as a
## square one. Must run before anything is drawn.
func _apply_topology() -> void:
	topology = Topology.for_id(config.board_id())
	var square_width := BOARD_W * float(base_cell_size)
	cell_size = square_width / HEX_BOARD_UNITS if topology.id == "hex" else float(base_cell_size)
	_fx.topology = topology
	_fx.cell_size = cell_size


func board_pixel_size() -> Vector2:
	return topology.board_pixel_size(BOARD_W, BOARD_H, cell_size)


func _apply_rules_to_board() -> void:
	board.max_open_ends = mods.max_open_ends()
	board.min_molecule = mods.min_molecule()


func _new_atom() -> int:
	return Atoms.random_atom(_queue_rng, mods.bomb_chance(), mods.wild_chance(), mods.shape_weights(topology), mods.min_bomb_connections(topology), topology)


## Grows or shrinks the queue to the size the current cards allow.
func _fit_queue() -> void:
	var target := mods.queue_size()
	while _queue.size() < target:
		_queue.append(_new_atom())
	while _queue.size() > target:
		_queue.pop_back()


## Overlay text for a finished game ("" clears it). Also stops local input.
func set_overlay(overlay_title: String, sub := "", color := Palette.TEXT) -> void:
	_overlay_title = overlay_title
	_overlay_sub = sub
	_overlay_color = color
	finished = overlay_title != ""
	queue_redraw()


## Called when the opponent attacks: the atoms are queued and land one at a time,
## each announced as a ghost with a countdown (see _advance_incoming).
func receive_attack(amount: int) -> void:
	if finished or amount <= 0:
		return
	_pending += int(ceil(amount * mods.incoming_mult()))
	sfx_requested.emit("warning", 1.0)
	_announce_incoming()
	queue_redraw()


## Versus only: the incoming stray atoms are announced and landed on a clock.
func _incoming_active() -> bool:
	return interactive and versus


## Announces the next queued atom as a ghost with a full gap, unless one is already announced.
func _announce_incoming() -> void:
	if not _incoming_active() or board == null:
		return
	if _pending <= 0:
		_incoming.ghosts.clear()
		return
	if not _incoming.ghosts.is_empty():
		return
	_incoming.seconds_override = mods.incoming_gap_seconds()
	_incoming.schedule_next(board, progression.level, _fx_rng)


## Every frame in versus: runs the incoming clock (it stops while a card pick is open).
func _advance_incoming(delta: float) -> void:
	if _pending <= 0:
		_incoming.ghosts.clear()
		return
	if _incoming.ghosts.is_empty():
		_announce_incoming()
		return
	var drops := _incoming.advance(delta, board, _fx_rng)
	if drops.is_empty():
		if _incoming.ghosts.is_empty():
			_announce_incoming() # the ghost found no room and vanished
		return
	for d in drops:
		_land_incoming(d)
	if finished:
		return
	_incoming.ghosts.clear()
	_announce_incoming()


## One incoming atom lands. One that closes a molecule clears it like any placement.
func _land_incoming(d: Dictionary) -> void:
	var cell: Vector2i = d.cell
	_pending = maxi(0, _pending - 1)
	if board.is_empty(cell):
		var cleared := board.place(cell, d.mask)
		if cleared.is_empty():
			_stray[cell] = true
			_fx.pop(cell)
			_fx.burst(_cell_center(cell), Palette.ORANGE, 8, 160.0)
			_fx.ring(_cell_center(cell), Palette.ORANGE, 0.35)
		else:
			_celebrate(cleared)
	sfx_requested.emit("garbage", 1.0)
	_fx.shake(0.35)
	if mods.has(Cards.COUNTERSTRIKE):
		attack.emit(1)
	if board.is_full():
		_lose()
	board_changed.emit(board.snapshot())
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
				_fx.burst(_cell_center(p), AtomPainter.color(old), 8, 160.0)
			elif old == 0 and now != 0:
				_fx.pop(p)
	board.load_snapshot(cells)
	queue_redraw()


func _cell_at(global_pos: Vector2) -> Vector2i:
	var rel := global_pos - get_parent_global_offset() - home_position
	return topology.cell_at(rel, cell_size)


func get_parent_global_offset() -> Vector2:
	var parent := get_parent()
	return parent.global_position if parent is Node2D else Vector2.ZERO


func _cell_center(p: Vector2i) -> Vector2:
	return _fx.cell_center(p)


func _unhandled_input(event: InputEvent) -> void:
	if not interactive:
		return
	if _offer_open():
		if _card_overlay.handle_input(event, _card_overlay.get_local_mouse_position()):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_hover = _cell_at(event.position)
		_reroll_hover = _reroll_hit(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if finished:
					restart_requested.emit()
				elif _reroll_hit(event.position):
					reroll_held()
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
			KEY_H:
				stash_swap()
			KEY_X:
				reroll_held()
			KEY_TAB:
				swap_next()
				get_viewport().set_input_as_handled()
			KEY_ENTER:
				if finished:
					restart_requested.emit()


func rotate_held(clockwise := true) -> void:
	if finished or _offer_open() or Atoms.is_wild(_queue[0]):
		return
	# Counter-clockwise is dir_count - 1 clockwise steps (3 only works on a square board).
	var times := 1 if clockwise else board.topology.dir_count - 1
	for i in times:
		_queue[0] = board.topology.rotate_cw(_queue[0])
	sfx_requested.emit("rotate", 1.0)
	queue_redraw()


## Stash card: store the held atom, or swap it with the stored one.
func stash_swap() -> void:
	if finished or _offer_open() or not mods.has(Cards.STASH):
		return
	if _stash == 0:
		_stash = _queue[0]
		_queue.pop_front()
		_fit_queue()
	else:
		var held := _queue[0]
		_queue[0] = _stash
		_stash = held
	sfx_requested.emit("rotate", 0.8)
	queue_redraw()


## Reroll card: throw away the held atom for a new random one (recharges over placements).
func reroll_held() -> void:
	if finished or _offer_open() or not mods.has(Cards.REROLL) or _reroll_cd > 0:
		return
	_queue[0] = _new_atom()
	_reroll_cd = REROLL_COOLDOWN
	sfx_requested.emit("rotate", 1.4)
	queue_redraw()


## Two-Hand card: swap the held atom with the next one.
func swap_next() -> void:
	if finished or _offer_open() or not mods.has(Cards.TWO_HAND) or _queue.size() < 2:
		return
	var held := _queue[0]
	_queue[0] = _queue[1]
	_queue[1] = held
	sfx_requested.emit("rotate", 0.9)
	queue_redraw()


func try_place(p: Vector2i) -> void:
	if finished or _offer_open() or not board.in_bounds(p):
		return
	if not board.is_empty(p):
		sfx_requested.emit("invalid", 1.0)
		_fx.shake(0.12)
		return
	var cleared := board.place(p, _queue[0])
	_queue.pop_front()
	_queue.append(_new_atom())
	_placements += 1
	_since_clear += 1
	_reroll_cd = maxi(0, _reroll_cd - 1)
	_lifeline_cd = maxi(0, _lifeline_cd - 1)
	if cleared.is_empty():
		_fx.pop(p)
		sfx_requested.emit("place", 1.0)
		_fx.shake(0.08)
		_fx.burst(_cell_center(p), Palette.TEXT.darkened(0.4), 6, 90.0)
		if board.is_full():
			_lose()
	else:
		_celebrate(cleared)
	if _danger_active() and not finished:
		_danger_step(p)
	if _incoming_active() and not finished:
		var moved := _incoming.relocate_at(p, board, _fx_rng)
		if moved.x >= 0:
			var from := _cell_center(p)
			_fx.spark(from, _cell_center(moved), Palette.ORANGE, 0.3)
			_fx.ring(from, Palette.ORANGE, 0.35)
		elif _incoming.ghosts.is_empty():
			_announce_incoming() # the ghost had no room left
	_apply_lifeline()
	board_changed.emit(board.snapshot()) # also after losing, so the opponent sees the final board
	queue_redraw()
	_maybe_offer()


## Solo only (versus has the opponent for pressure), and not in Relaxed mode.
func _danger_active() -> bool:
	return interactive and not versus and config.pressure() != GameConfig.PRESSURE_NONE


## One placement passed: move a ghost you built over, then drop what is due.
func _danger_step(placed: Vector2i) -> void:
	var from := _cell_center(placed)
	var moved := _danger.relocate_at(placed, board, _fx_rng)
	if moved.x >= 0:
		_fx.spark(from, _cell_center(moved), Palette.ORANGE, 0.3)
		_fx.ring(from, Palette.ORANGE, 0.35)
	if timed:
		return # the clock decides when they drop
	var drops := _danger.tick(board, _fx_rng)
	if drops.is_empty():
		if _danger.countdown == 1 and not _danger.ghosts.is_empty():
			sfx_requested.emit("warning", 1.0)
		return
	_drop_strays(drops)
	if not finished:
		_danger.schedule_next(board, progression.level, _fx_rng)


## Timed flavour, every frame: runs the clock (it stops while a card pick is open).
func _advance_danger(delta: float) -> void:
	var drops := _danger.advance(delta, board, _fx_rng)
	if drops.is_empty():
		if not _warned and not _danger.ghosts.is_empty() and _danger.countdown <= WARN_SECONDS:
			_warned = true
			sfx_requested.emit("warning", 1.0)
		return
	_drop_strays(drops)
	if not finished:
		_danger.schedule_next(board, progression.level, _fx_rng)
		_warned = false


## The announced stray atoms land. One that closes a molecule clears it like any placement.
func _drop_strays(drops: Array[Dictionary]) -> void:
	for d in drops:
		var cell: Vector2i = d.cell
		if not board.is_empty(cell):
			continue
		var cleared := board.place(cell, d.mask)
		if cleared.is_empty():
			_fx.pop(cell)
			_fx.burst(_cell_center(cell), Palette.ORANGE, 8, 160.0)
			_fx.ring(_cell_center(cell), Palette.ORANGE, 0.35)
		else:
			_celebrate(cleared)
	sfx_requested.emit("garbage", 1.0)
	_fx.shake(0.35)
	if board.is_full():
		_lose()


## Lifeline card: a nearly full board gets a wildcard as the next atom.
func _apply_lifeline() -> void:
	if finished or not mods.has(Cards.LIFELINE) or _lifeline_cd > 0:
		return
	if board.fill_ratio() >= LIFELINE_FILL and not Atoms.is_wild(_queue[0]):
		_queue[0] = Atoms.WILD
		_lifeline_cd = LIFELINE_COOLDOWN
		sfx_requested.emit("clear", 1.5)


func _celebrate(cleared: Array[Vector2i]) -> void:
	var molecule := board.last_molecule_size
	var blasted := cleared.size() - molecule
	var combo := _since_clear <= 3 # placements since the previous clear
	var points := mods.scaled_points(molecule, blasted, combo)
	score += points
	# The clear spreads from the placed atom through the molecule: every atom stays visible
	# as a ghost until the wave reaches it (see _fire_ghost).
	var sum := Vector2.ZERO
	var depths := board.last_clear_depths
	var max_depth := 0
	for d in depths:
		max_depth = maxi(max_depth, d)
	var step := minf(CLEAR_STEP, CLEAR_MAX_TIME / maxf(1.0, max_depth))
	for i in cleared.size():
		sum += _cell_center(cleared[i])
		_fx.add_ghost(cleared[i], board.last_cleared_masks[i], depths[i] * step, board.last_clear_parents[i])
	var popup_text := "+%d" % points
	if combo and mods.has(Cards.COMBO_CHAIN):
		popup_text += " COMBO!"
	_fx.popup(sum / cleared.size(), popup_text, -max_depth * step)
	sfx_requested.emit("clear", clampf(0.9 + 0.06 * (cleared.size() - 2), 0.8, 1.5))
	_fx.shake(0.25 + 0.06 * cleared.size())

	# Incoming stray atoms are cancelled first; whatever is left goes to the opponent.
	# Every Scoring.POINTS_PER_ATTACK points scored send one stray atom; the remainder carries over.
	_attack_charge += mods.attack_charge(points)
	var outgoing := int(floor(_attack_charge / Scoring.POINTS_PER_ATTACK + 0.000001))
	_attack_charge -= outgoing * Scoring.POINTS_PER_ATTACK
	_attack_charge = maxf(_attack_charge, 0.0)
	var cancel_mult := mods.cancel_mult()
	var cancelled := mini(int(ceil(outgoing * cancel_mult)), _pending)
	_pending -= cancelled
	if _pending <= 0:
		_incoming.ghosts.clear()
	outgoing -= mini(outgoing, int(ceil(cancelled / cancel_mult)))
	if outgoing > 0:
		sfx_requested.emit("attack", 1.0)
		attack.emit(outgoing)

	_since_clear = 0
	if mods.has(Cards.GARDENER):
		_remove_random_stray()
	if mods.has(Cards.OVERCHARGE) and molecule >= 4:
		_queue.insert(0, Atoms.random_shape(_queue_rng, mods.shape_weights(topology), topology) | Atoms.BOMB)
		_fit_queue()
		sfx_requested.emit("clear", 1.3)
	if progression.add_xp(points) > 0:
		sfx_requested.emit("clear", 1.5)
		_offer_wait = max_depth * step + 0.6
	progression_changed.emit()


## Gardener card: removes one random stray atom that is still on the board.
func _remove_random_stray() -> void:
	var live: Array[Vector2i] = []
	for c in _stray.keys():
		if board.get_atom(c) != 0:
			live.append(c)
	_stray.clear()
	for c in live:
		_stray[c] = true
	if live.is_empty():
		return
	var victim := live[_fx_rng.randi_range(0, live.size() - 1)]
	board.remove_atom(victim)
	_stray.erase(victim)
	_fx.burst(_cell_center(victim), Palette.PURPLE, 12, 220.0)
	_fx.ring(_cell_center(victim), Palette.PURPLE, 0.4)


func _offer_open() -> bool:
	return _card_overlay != null and _card_overlay.is_open()


## Shows the next pending level-up card pick, if any.
func _maybe_offer() -> void:
	if _card_overlay == null or _card_overlay.is_open() or finished or not progression.has_pending_pick():
		return
	if _offer_wait > 0.0 or _fx.has_ghosts():
		return # _process tries again once the clear animation is done
	var cards: Array[Dictionary] = []
	for id in progression.roll_offer(_fx_rng, versus):
		cards.append(Cards.describe(id, progression.mods.count(id)))
	if cards.is_empty():
		progression.pick_levels.pop_front() # nothing left to offer at this level
		return
	_card_overlay.show_offer(cards, progression.pick_levels[0])
	sfx_requested.emit("clear", 1.2)


func _on_card_picked(card_id: String) -> void:
	if progression.pick(card_id):
		_apply_rules_to_board()
		_fit_queue()
		var def := Cards.get_def(card_id)
		_fx.popup(Vector2(board_pixel_size().x / 2.0, cell_size * 2.0), String(def.get("name", card_id)))
		sfx_requested.emit("win", 1.0)
		progression_changed.emit()
		queue_redraw()
	_maybe_offer()


## The clear wave reached a ghost; bombs also go off with a bang.
func _on_ghost_fired(ghost: Dictionary) -> void:
	if Atoms.is_bomb(ghost.mask):
		sfx_requested.emit("explode", 1.0)


func _lose() -> void:
	set_overlay("BOARD FULL - YOU LOSE", "", Palette.BAD)
	sfx_requested.emit("lose", 1.0)
	_fx.shake_max()
	for i in 40:
		var cell := Vector2i(_fx_rng.randi_range(0, BOARD_W - 1), _fx_rng.randi_range(0, BOARD_H - 1))
		_fx.burst(_cell_center(cell), Palette.BAD, 2, 260.0)
	lost.emit()


func _process(delta: float) -> void:
	_offer_wait = maxf(0.0, _offer_wait - delta)
	if _offer_wait == 0.0 and not _fx.has_ghosts() and progression.has_pending_pick():
		_maybe_offer()
	_fx.advance(delta)
	if timed and _danger_active() and not finished and not _offer_open():
		_advance_danger(delta)
	if _incoming_active() and not finished and not _offer_open():
		_advance_incoming(delta)
	position = home_position + _fx.shake_offset()
	if _fx.is_busy() or position != home_position or (_danger_active() and not _danger.ghosts.is_empty()) or not _incoming.ghosts.is_empty():
		queue_redraw()


func _draw() -> void:
	if board == null:
		return
	var font := ThemeDB.fallback_font
	var board_px := board_pixel_size()

	# Molecules that can never be finished (an end is blocked) get a subtle red background.
	var seen := {}
	for y in BOARD_H:
		for x in BOARD_W:
			var start := Vector2i(x, y)
			if seen.has(start) or board.get_atom(start) == 0:
				continue
			var group := board.molecule_at(start)
			for c in group:
				seen[c] = true
			if board.is_dead(group):
				for c in group:
					draw_colored_polygon(_cell_poly(c), Color(Palette.BAD, 0.12))

	# Hovering an atom lights up its molecule: cells with an open connection red, fully bonded blue.
	if interactive and not finished and board.in_bounds(_hover) and board.get_atom(_hover) != 0:
		for c in board.molecule_at(_hover):
			var is_open := false
			for dir in topology.dir_count:
				if (board.get_atom(c) & (1 << dir)) and not board.is_bonded(c, dir):
					is_open = true
					break
			var tint := Palette.BAD if is_open else Palette.BLUE
			draw_colored_polygon(_cell_poly(c), Color(tint, 0.28))

	for y in BOARD_H:
		for x in BOARD_W:
			var p := Vector2i(x, y)
			_draw_cell_outline(p)
			var mask := board.get_atom(p)
			if mask != 0:
				_draw_atom(_cell_center(p), mask, 1.0, p, _fx.pop_scale(p))

	# Hover preview (a bomb also shows its blast area).
	if interactive and not finished and board.is_empty(_hover):
		if Atoms.is_bomb(_queue[0]):
			for c in blast_preview_cells(_hover):
				var poly := _cell_poly(c)
				draw_colored_polygon(poly, Color(Palette.ORANGE, 0.12))
				_draw_closed(poly, Color(Palette.ORANGE, 0.5), 2.0)
		_draw_atom(_cell_center(_hover), _queue[0], 0.45, Vector2i(-1, -1))

	if _danger_active() and not finished:
		_draw_danger_ghosts(font, _danger, timed)
	if _incoming_active() and not finished:
		_draw_danger_ghosts(font, _incoming, true)

	_fx.paint(self, board)

	# Incoming stray atoms waiting to land: red blocks along the left edge.
	for i in mini(_pending, 16):
		draw_rect(Rect2(-14, board_px.y - 14 - i * 14, 8, 11), Palette.BAD)

	if interactive:
		_draw_header(font, board_px)
	elif title != "":
		draw_string(font, Vector2(0, -10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.DIM)

	if _overlay_title != "":
		draw_rect(Rect2(Vector2.ZERO, board_px), Color(0, 0, 0, 0.6))
		var mid := board_px.y / 2.0
		var big := 32 if interactive else 16
		draw_string(font, Vector2(0, mid - 10), _overlay_title, HORIZONTAL_ALIGNMENT_CENTER, board_px.x, big, _overlay_color)
		if _overlay_sub != "":
			draw_string(font, Vector2(0, mid + 28), _overlay_sub, HORIZONTAL_ALIGNMENT_CENTER, board_px.x, 20 if interactive else 12, Palette.TEXT)


## The cells a bomb placed at p would wipe (for the hover preview).
func blast_preview_cells(p: Vector2i) -> Array[Vector2i]:
	return board.topology.cells_within(p, Atoms.BLAST_RADIUS, BOARD_W, BOARD_H)


func _cell_poly(p: Vector2i) -> PackedVector2Array:
	return topology.cell_polygon(p, cell_size)


func _draw_closed(poly: PackedVector2Array, color: Color, width: float) -> void:
	var pts := poly.duplicate()
	pts.append(poly[0])
	draw_polyline(pts, color, width)


## Grid line of one cell. Shared edges are drawn by two cells; the thin dim colour keeps
## that unnoticeable.
func _draw_cell_outline(p: Vector2i) -> void:
	_draw_closed(_cell_poly(p), Palette.GRID, 1.0)


## True when the next drop is imminent (red countdown).
func _danger_urgent(d: Danger, is_timed: bool) -> bool:
	if d == _incoming:
		return d.countdown <= 1.0 # the 3 s gap would be red the whole time
	return d.countdown <= (WARN_SECONDS if is_timed else 1.0)


## The stray atoms that will drop soon: transparent, pulsing, with the placements left.
func _draw_danger_ghosts(font: Font, d: Danger, is_timed: bool) -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
	var urgent := _danger_urgent(d, is_timed)
	if urgent and is_timed:
		pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 80.0) # faster flicker as time runs out
	var tint := Palette.BAD if urgent else Palette.ORANGE
	var line_scale := cell_size / 72.0
	for g in d.ghosts:
		var center := _cell_center(g.cell)
		_draw_atom(center, g.mask, 0.34 + 0.16 * pulse, Vector2i(-1, -1))
		draw_arc(center, cell_size * 0.36, 0.0, TAU, 28, Color(tint, 0.35 + 0.4 * pulse), 2.5 * line_scale)
		draw_string(font, center + Vector2(cell_size * 0.16, cell_size * 0.44), str(d.countdown_label()), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * line_scale), tint)


func _draw_header(font: Font, board_px: Vector2) -> void:
	draw_string(font, Vector2(0, -HEADER + 28), "NOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.DIM)
	_draw_atom(Vector2(40, -HEADER + 78), _queue[0], 1.0, Vector2i(-1, -1), 1.0, 72)
	var queue_x := 150.0
	if mods.has(Cards.REROLL):
		queue_x += REROLL_SLOT
		_draw_reroll_button(font)
	draw_string(font, Vector2(queue_x - 30.0, -HEADER + 28), "COMING UP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.DIM)
	var spacing := minf(62.0, (board_px.x - 14.0 - queue_x) / maxf(1.0, _queue.size() - 2.0))
	for i in range(1, _queue.size()):
		_draw_atom(Vector2(queue_x + (i - 1) * spacing, -HEADER + 83), _queue[i], 0.85, Vector2i(-1, -1), 0.6, 72)
	draw_string(font, Vector2(0, -HEADER + 40), "SCORE: %d" % score, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 22, Palette.TEXT)
	var need := Progression.xp_needed(progression.level)
	draw_string(font, Vector2(board_px.x - 207, -HEADER + 57), "LV %d" % progression.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.DIM)
	var bar := Rect2(board_px.x - 160, -HEADER + 49, 160, 6)
	draw_rect(bar, Palette.GRID)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progression.xp / float(need), 0.0, 1.0), bar.size.y)), Palette.GOLD)
	if _pending > 0:
		draw_string(font, Vector2(0, -HEADER + 120), "INCOMING: %d" % _pending, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 18, Palette.BAD)
		if not _incoming.ghosts.is_empty():
			var secs := "STRAY IN %ds" % _incoming.countdown_label()
			draw_string(font, Vector2(0, -HEADER + 100), secs, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 18, Palette.BAD if _danger_urgent(_incoming, true) else Palette.ORANGE)
	elif _danger_active() and not _danger.ghosts.is_empty():
		var count := _danger.ghosts.size()
		var left := "%ds" % _danger.countdown_label() if timed else str(_danger.countdown_label())
		var text := "STRAY IN %s" % left if count == 1 else "%d STRAYS IN %s" % [count, left]
		draw_string(font, Vector2(0, -HEADER + 120), text, HORIZONTAL_ALIGNMENT_RIGHT, board_px.x, 18, Palette.BAD if _danger_urgent(_danger, timed) else Palette.ORANGE)
	_draw_card_rows(font, board_px)


func _reroll_center() -> Vector2:
	return Vector2(106.0, -HEADER + 78.0)


## True if a click at this viewport position lands on the Reroll button.
func _reroll_hit(viewport_pos: Vector2) -> bool:
	if not mods.has(Cards.REROLL) or not interactive:
		return false
	var local := viewport_pos - get_parent_global_offset() - home_position
	return local.distance_to(_reroll_center()) <= REROLL_RADIUS + 4.0


## The Reroll card as a round button beside the held atom: two circling arrows, the key,
## and a ring that fills while it recharges. Clicking it (or pressing X) rerolls.
func _draw_reroll_button(font: Font) -> void:
	var center := _reroll_center()
	var ready := _reroll_cd == 0
	var accent := Palette.PURPLE if ready else Palette.DIM
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	if ready:
		draw_circle(center, REROLL_RADIUS + 3.0 + 2.0 * pulse, Color(accent, 0.12 + 0.10 * pulse))
	draw_circle(center, REROLL_RADIUS, Palette.PANEL.lightened(0.12) if _reroll_hover and ready else Palette.PANEL)
	draw_arc(center, REROLL_RADIUS, 0.0, TAU, 40, Color(accent, 0.45), 2.0)
	if not ready:
		var progress := 1.0 - float(_reroll_cd) / REROLL_COOLDOWN
		draw_arc(center, REROLL_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * progress, 40, Palette.PURPLE, 4.0)
	var icon := Palette.TEXT if ready else Palette.DIM
	var r := 10.0
	draw_arc(center, r, deg_to_rad(215.0), deg_to_rad(335.0), 14, icon, 3.0)
	_draw_arrow_head(center, r, deg_to_rad(335.0), icon)
	draw_arc(center, r, deg_to_rad(35.0), deg_to_rad(155.0), 14, icon, 3.0)
	_draw_arrow_head(center, r, deg_to_rad(155.0), icon)
	var caption := "X" if ready else "in %d" % _reroll_cd
	draw_string(font, center + Vector2(-30.0, REROLL_RADIUS + 15.0), caption, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 13, Palette.TEXT if ready else Palette.DIM)


## A small triangle at the end of a circular arc, pointing the way the arc runs (clockwise).
func _draw_arrow_head(center: Vector2, radius: float, angle: float, color: Color) -> void:
	var at := center + Vector2.from_angle(angle) * radius
	var outward := Vector2.from_angle(angle)
	var forward := Vector2.from_angle(angle + PI / 2.0)
	draw_colored_polygon(PackedVector2Array([at + forward * 7.0, at + outward * 5.0, at - outward * 5.0]), color)


## Under the board: key hints for active cards and a chip for every owned card.
func _draw_card_rows(font: Font, board_px: Vector2) -> void:
	var y := board_px.y + 24.0
	var x := 0.0
	var hint_color := Palette.DIM
	if mods.has(Cards.STASH):
		var text := "[H] Stash:"
		draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hint_color)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 6.0
		if _stash == 0:
			draw_string(font, Vector2(x, y), "empty", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, hint_color)
			x += 44.0
		else:
			_draw_atom(Vector2(x + 14.0, y - 5.0), _stash, 1.0, Vector2i(-1, -1), 0.4, 72)
			x += 34.0
		x += 14.0
	if mods.has(Cards.TWO_HAND):
		draw_string(font, Vector2(x, y), "[Tab] Swap next", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.TEXT)

	# Chips for the owned cards, coloured by rarity.
	y += 24.0
	x = 0.0
	for id in mods.stacks.keys():
		var def := Cards.get_def(id)
		if def.is_empty() or int(mods.stacks[id]) <= 0:
			continue
		var label := String(def.name)
		if int(def.max) > 1:
			label += " x%d" % int(mods.stacks[id])
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
		if x + width > board_px.x:
			x = 0.0
			y += 22.0
		var tint := Palette.RARITY[int(def.rarity)]
		if bool(def.get("risky", false)):
			tint = Palette.BAD
		draw_rect(Rect2(x, y - 13.0, width, 19.0), Color(tint, 0.22))
		draw_rect(Rect2(x, y - 13.0, width, 19.0), Color(tint, 0.8), false, 1.0)
		draw_string(font, Vector2(x + 7.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)
		x += width + 6.0


func _draw_atom(center: Vector2, mask: int, alpha: float, cell: Vector2i, scale := 1.0, unit_px := -1) -> void:
	AtomPainter.draw(self, center, mask, alpha, scale, cell_size if unit_px < 0 else unit_px, board, cell, topology)
