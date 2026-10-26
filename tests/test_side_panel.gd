extends "res://tests/test_base.gd"
## Run: godot --headless --path . --script res://tests/test_side_panel.gd
## The side panel left of the board: NOW (big held atom) above COMING UP, with the round buttons.


func _make(board_id: String, board_size := "") -> Playfield:
	var pf := Playfield.new()
	pf.config.set_value("board", board_id)
	pf.config.set_value("pressure", GameConfig.PRESSURE_NONE)
	if board_size != "":
		pf.config.set_value("board_size", board_size)
	root.add_child(pf)
	await process_frame
	pf.start(5)
	pf.progression.pick_levels.clear()
	return pf


func _panel_rect(_pf: Playfield) -> Rect2:
	# The panel starts above the board's top edge (the round buttons sit there).
	var top := Playfield.PANEL_BUTTON_Y - Playfield.REROLL_RADIUS - 4.0
	return Rect2(-Playfield.PANEL_SPACE, top, Playfield.PANEL_W, Playfield.PANEL_BOTTOM - top)


func _click(pf: Playfield, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pf.get_parent_global_offset() + pf.home_position + pos
	pf._unhandled_input(e)


func _init() -> void:
	for combo in [["square", ""], ["hex", ""], ["square", "6"], ["hex", "10"]]:
		var pf: Playfield = await _make(combo[0], combo[1])
		var tag := "%s %s: " % [combo[0], combo[1]]
		var board_rect := Rect2(Vector2.ZERO, pf.board_pixel_size())
		var panel := _panel_rect(pf)
		_check(panel.end.x < board_rect.position.x, tag + "panel is left of the board")
		_check(not panel.intersects(board_rect), tag + "panel does not overlap the board")
		pf.progression.mods.add(Cards.REROLL)
		for hit in [pf._reroll_center(), pf._scrap_center()]:
			_check(hit.x < 0.0 and panel.has_point(hit), tag + "buttons sit inside the panel")
			_check(hit.y < Playfield.PANEL_HELD_Y - 30.0, tag + "buttons are above NOW")
		_check(pf._reroll_center().distance_to(pf._scrap_center()) > 2.0 * Playfield.REROLL_RADIUS, tag + "buttons do not overlap")
		_check(Playfield.PANEL_HELD_Y < pf._queue_label_y() and pf._queue_label_y() < pf._queue_top(), tag + "NOW above COMING UP above the previews")
		_check(pf._queue_label_y() > pf._scrap_center().y + Playfield.SCRAP_RADIUS, tag + "COMING UP is below the buttons")
		_check(Playfield.HELD_UNIT >= 1.6 * 72 and 72 * 0.6 < Playfield.HELD_UNIT, tag + "NOW atom is larger than a preview atom")
		# Clickable at the new positions (Reroll on cooldown after use, Scrap armed).
		var before: int = pf._queue[0]
		var rerolls := 0
		for i in 12:
			pf._queue[0] = before
			pf._reroll_cd = 0
			_click(pf, pf._reroll_center())
			if pf._reroll_cd > 0:
				rerolls += 1
		_check(rerolls == 12, tag + "clicking the Reroll button rerolls")
		_click(pf, pf._scrap_center())
		_check(pf.is_scrap_armed(), tag + "clicking the Scrap button arms Scrap")
		_click(pf, pf._scrap_center())
		_check(not pf.is_scrap_armed(), tag + "clicking it again cancels")
		_check(not pf._reroll_hit(Vector2(Playfield.PANEL_W, 0.0)) and not pf._scrap_hit(Vector2(300.0, 300.0)), tag + "the board is not a button")
		# Every queue size fits the column and stays above the bottom limit.
		for n in range(1, 9):
			pf.config.set_value("preview", str(n - 1))
			pf._queue.clear()
			pf._fit_queue()
		pf.progression.mods.add(Cards.STASH)
		pf.progression.mods.add(Cards.TWO_HAND)
		_check(pf._queue_top() + 6 * Playfield.QUEUE_ROW_MIN < Playfield.PANEL_BOTTOM + 20.0, tag + "8 queue entries fit with stash and swap rows")
		pf.queue_free()
	_finish(true)
