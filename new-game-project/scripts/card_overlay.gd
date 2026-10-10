class_name CardOverlay
extends Node2D
## Pick-a-card overlay drawn over the board (local coords: origin = board top-left).

signal picked(card_id: String)

const BG := Color("1e2229")
const PANEL := Color("272c35")
const GRID := Color("353b46")
const TEXT := Color("e8ecf1")
const DIM := Color("8f98a8")
const RED := Color("ff5d5d")
const RARITY_COLORS: Array[Color] = [Color("4a90d9"), Color("b07cff"), Color("ff9a3c")]
const RARITY_NAMES: Array[String] = ["BASIC", "RARE", "SUPER"]
const ANIM_TIME := 0.25
const RAISE := 6.0
const CARD_H := 320.0
const GAP := 14.0

var board_size := Vector2(576, 576)

var _cards: Array[Dictionary] = []
var _level := 1
var _open := false
var _age := 0.0
var _hover := -1
var _focus := 0


func show_offer(cards: Array[Dictionary], level: int) -> void:
	_cards = cards.duplicate()
	_level = level
	_open = true
	_age = 0.0
	_hover = -1
	_focus = 0
	visible = true
	set_process(true)
	queue_redraw()


func hide_offer() -> void:
	_open = false
	_cards = []
	_hover = -1
	visible = false
	set_process(false)
	queue_redraw()


func is_open() -> bool:
	return _open


func _ready() -> void:
	visible = _open
	set_process(_open)


func _process(delta: float) -> void:
	if _age < ANIM_TIME + 0.2:
		_age += delta
	queue_redraw()


func _card_width() -> float:
	var n := maxi(_cards.size(), 1)
	return minf(170.0, (board_size.x - 32.0 - GAP * (n - 1)) / n)


## Resting rect of card i (no animation, no hover raise).
func card_rect(i: int) -> Rect2:
	var n := _cards.size()
	var w := _card_width()
	var total := w * n + GAP * (n - 1)
	var x := (board_size.x - total) * 0.5 + i * (w + GAP)
	var y := (board_size.y - CARD_H) * 0.5 + 18.0
	return Rect2(x, y, w, CARD_H)


func _card_at(p: Vector2) -> int:
	for i in _cards.size():
		var r := card_rect(i)
		r.position.y -= RAISE
		r.size.y += RAISE
		if r.has_point(p):
			return i
	return -1


func _pick(i: int) -> void:
	if i < 0 or i >= _cards.size():
		return
	var id: String = _cards[i].get("id", "")
	hide_offer()
	picked.emit(id)


func handle_input(event: InputEvent, local_mouse: Vector2) -> bool:
	if not _open:
		return false
	if event is InputEventMouseMotion:
		var h := _card_at(local_mouse)
		if h != _hover:
			_hover = h
			if h >= 0:
				_focus = h
			queue_redraw()
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_pick(_card_at(local_mouse))
		return true
	if event is InputEventKey:
		if event.pressed and not event.echo:
			var k: int = event.keycode
			if k >= KEY_1 and k <= KEY_9:
				_pick(k - KEY_1)
			elif k >= KEY_KP_1 and k <= KEY_KP_9:
				_pick(k - KEY_KP_1)
			elif k == KEY_LEFT:
				_focus = maxi(_focus - 1, 0)
				_hover = -1
				queue_redraw()
			elif k == KEY_RIGHT:
				_focus = mini(_focus + 1, _cards.size() - 1)
				_hover = -1
				queue_redraw()
			elif k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
				_pick(_focus)
		return true
	return false


func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


func _draw() -> void:
	if not _open:
		return
	var font := ThemeDB.fallback_font
	var fade := _ease(_age / ANIM_TIME)
	draw_rect(Rect2(Vector2.ZERO, board_size), Color(0.05, 0.06, 0.08, 0.82 * fade))
	var top := card_rect(0).position.y if _cards.size() > 0 else board_size.y * 0.5
	draw_string(font, Vector2(0, top - 50), "LEVEL %d - CHOOSE A CARD" % _level,
		HORIZONTAL_ALIGNMENT_CENTER, board_size.x, 26, Color(TEXT, fade))
	draw_string(font, Vector2(0, top - 26), "Click a card or press 1-%d" % _cards.size(),
		HORIZONTAL_ALIGNMENT_CENTER, board_size.x, 14, Color(DIM, fade))
	for i in _cards.size():
		var t := _ease((_age - i * 0.05) / ANIM_TIME)
		var active := (i == _hover) or (_hover < 0 and i == _focus and _focus_visible())
		_draw_card(font, i, t, active)


func _focus_visible() -> bool:
	return _hover < 0 and _age > ANIM_TIME


func _wrap(font: Font, text: String, size: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur := ""
	for word in text.split(" ", false):
		var trial: String = word if cur == "" else cur + " " + word
		if cur != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(cur)
			cur = word
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return lines


## Draws wrapped text shrinking the font until it fits max_h. Returns used height.
func _draw_wrapped(font: Font, text: String, pos: Vector2, width: float, max_h: float,
		start_size: int, color: Color, center := false) -> float:
	var size := start_size
	var lines := _wrap(font, text, size, width)
	while size > 9 and (lines.size() * (size + 4) > max_h):
		size -= 1
		lines = _wrap(font, text, size, width)
	var y := pos.y + size
	for l in lines:
		var align := HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
		draw_string(font, Vector2(pos.x, y), l, align, width, size, color)
		y += size + 4
	return lines.size() * (size + 4)


func _draw_card(font: Font, i: int, t: float, active: bool) -> void:
	var card: Dictionary = _cards[i]
	var rarity := clampi(int(card.get("rarity", 0)), 0, 2)
	var rc := RARITY_COLORS[rarity]
	var r := card_rect(i)
	r.position.y += (1.0 - t) * 40.0 - (RAISE if active else 0.0)
	var a := t
	var pad := 12.0
	var inner_w := r.size.x - pad * 2.0

	# glow for super / active
	if rarity == 2 or active:
		var gc := Color(rc, (0.28 if rarity == 2 else 0.2) * a)
		for g in 3:
			draw_rect(r.grow(2.0 + g * 2.5), Color(gc, gc.a * (1.0 - g * 0.3)), false, 2.0)
	draw_rect(r, Color(PANEL, a))
	var border := Color(rc, a) if active else Color(rc.darkened(0.35), a)
	draw_rect(r, border, false, 3.0 if active else 2.0)
	# rarity header strip
	var strip := Rect2(r.position, Vector2(r.size.x, 26))
	draw_rect(strip, Color(rc.darkened(0.45 if not active else 0.3), a))
	draw_string(font, r.position + Vector2(pad, 18), RARITY_NAMES[rarity],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(TEXT, a))

	# keycap
	var kc := Rect2(r.position + Vector2(r.size.x - 26, 3), Vector2(20, 20))
	draw_rect(kc, Color(BG, a))
	draw_rect(kc, Color(DIM, a), false, 1.5)
	draw_string(font, kc.position + Vector2(0, 15), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, kc.size.x, 14, Color(TEXT, a))

	var y := r.position.y + 36.0
	# badges row
	var bx := r.position.x + pad
	if card.get("risky", false):
		var bw := 48.0
		draw_rect(Rect2(bx, y, bw, 18), Color(RED, 0.2 * a))
		draw_rect(Rect2(bx, y, bw, 18), Color(RED, a), false, 1.5)
		draw_string(font, Vector2(bx, y + 13), "RISKY", HORIZONTAL_ALIGNMENT_CENTER, bw, 12, Color(RED, a))
		bx += bw + 6.0
	if card.get("versus_only", false):
		var vw := 54.0
		draw_rect(Rect2(bx, y, vw, 18), Color(DIM, 0.15 * a))
		draw_rect(Rect2(bx, y, vw, 18), Color(DIM, a), false, 1.5)
		draw_string(font, Vector2(bx, y + 13), "VERSUS", HORIZONTAL_ALIGNMENT_CENTER, vw, 12, Color(DIM, a))
	y += 26.0

	# name (shrink to fit, wrap to 2 lines max)
	var nm: String = card.get("name", "")
	var nsize := 20
	while nsize > 13 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x > inner_w:
		nsize -= 1
	if font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nsize).x > inner_w:
		y += _draw_wrapped(font, nm, Vector2(r.position.x + pad, y), inner_w, 36.0, 15, Color(TEXT, a))
	else:
		draw_string(font, Vector2(r.position.x + pad, y + nsize), nm, HORIZONTAL_ALIGNMENT_LEFT, inner_w, nsize, Color(TEXT, a))
		y += nsize + 6.0
	draw_line(Vector2(r.position.x + pad, y), Vector2(r.end.x - pad, y), Color(rc, 0.6 * a), 1.0)
	y += 8.0

	# bottom block heights
	var bottom := r.end.y - 10.0
	var maxn: int = int(card.get("max", 1))
	var lvl_text := "Unique"
	if maxn > 1:
		lvl_text = "Level %d/%d" % [mini(int(card.get("owned", 0)) + 1, maxn), maxn]
	draw_string(font, Vector2(r.position.x + pad, bottom - 2), lvl_text, HORIZONTAL_ALIGNMENT_LEFT, inner_w, 13, Color(DIM, a))
	bottom -= 22.0
	var down: String = card.get("downside", "")
	if down != "":
		var dh := 60.0
		var used := _measure_wrapped(font, "Downside: " + down, inner_w, dh, 12)
		_draw_wrapped(font, "Downside: " + down, Vector2(r.position.x + pad, bottom - used), inner_w, dh, 12, Color(RED, a))
		bottom -= used + 8.0

	# description fills remaining space
	var desc: String = card.get("desc", "")
	_draw_wrapped(font, desc, Vector2(r.position.x + pad, y), inner_w, maxf(bottom - y, 20.0), 15, Color(TEXT, a * 0.92))


func _measure_wrapped(font: Font, text: String, width: float, max_h: float, start_size: int) -> float:
	var size := start_size
	var lines := _wrap(font, text, size, width)
	while size > 9 and lines.size() * (size + 4) > max_h:
		size -= 1
		lines = _wrap(font, text, size, width)
	return lines.size() * (size + 4)
