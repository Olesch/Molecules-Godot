class_name Menu
extends Control

signal choose(mode: String, address: String)

## Shown in the menu and along the bottom of the game screen.
const CONTROLS_HINT := "Click: place   R / right-click / wheel: rotate   M: music   Esc: menu   Cards: H stash, X reroll, Tab swap"

var _solo_btn: Button
var _host_btn: Button
var _join_btn: Button
var _cancel_btn: Button
var _reset_btn: Button
var _address: LineEdit
var _status: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := Label.new()
	title.text = "MOLECULES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(title)

	var sub := Label.new()
	sub.text = "close the loops"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Palette.ORANGE)
	box.add_child(sub)

	_spacer(box, 18)
	_solo_btn = _make_button("Solo", Palette.GOOD)
	box.add_child(_solo_btn)
	_host_btn = _make_button("Host online game", Palette.BLUE)
	box.add_child(_host_btn)
	_spacer(box, 6)

	_address = LineEdit.new()
	_address.placeholder_text = "Host IP address"
	_address.text = "127.0.0.1"
	_address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address.custom_minimum_size = Vector2(0, 40)
	_address.add_theme_color_override("font_color", Palette.TEXT)
	_address.add_theme_color_override("font_placeholder_color", Color(Palette.TEXT, 0.4))
	_address.add_theme_color_override("caret_color", Palette.TEXT)
	_address.add_theme_stylebox_override("normal", _box(Palette.FIELD))
	_address.add_theme_stylebox_override("focus", _box(Palette.FIELD, Palette.BLUE))
	_address.add_theme_stylebox_override("read_only", _box(Palette.FIELD))
	_address.text_submitted.connect(func(_t: String) -> void: _on_join())
	box.add_child(_address)

	_join_btn = _make_button("Join game", Palette.ORANGE)
	box.add_child(_join_btn)

	_cancel_btn = _make_button("Cancel", Palette.RED)
	_cancel_btn.visible = false
	box.add_child(_cancel_btn)

	_reset_btn = _make_button("Reset solo progress", Palette.DIM)
	_reset_btn.add_theme_font_size_override("font_size", 13)
	_reset_btn.pressed.connect(func() -> void: choose.emit("reset_progress", ""))
	box.add_child(_reset_btn)

	_spacer(box, 10)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(360, 0)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Palette.TEXT)
	box.add_child(_status)

	var hint := Label.new()
	hint.text = "Controls: " + CONTROLS_HINT
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.custom_minimum_size = Vector2(360, 0)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(Palette.TEXT, 0.55))
	box.add_child(hint)

	_solo_btn.pressed.connect(func() -> void: choose.emit("solo", ""))
	_host_btn.pressed.connect(func() -> void: choose.emit("host", ""))
	_join_btn.pressed.connect(_on_join)
	_cancel_btn.pressed.connect(func() -> void: choose.emit("cancel", ""))


func _on_join() -> void:
	if _join_btn.disabled:
		return
	choose.emit("join", _address.text.strip_edges())


func set_status(text: String) -> void:
	_status.text = text


func set_busy(busy: bool) -> void:
	_solo_btn.disabled = busy
	_host_btn.disabled = busy
	_join_btn.disabled = busy
	_reset_btn.disabled = busy
	_address.editable = not busy
	_cancel_btn.visible = busy


func get_default_status_for(mode: String) -> String:
	match mode:
		"host":
			var ips: Array[String] = []
			for a in IP.get_local_addresses():
				if a.count(".") == 3 and not a.contains(":") and not a.begins_with("127.") and not a.begins_with("169.254."):
					if not ips.has(a):
						ips.append(a)
			var shown := ips.slice(0, 3)
			var list := ", ".join(shown) if not shown.is_empty() else "unknown"
			return "Waiting for opponent... your addresses: %s (port %d)" % [list, NetSession.DEFAULT_PORT]
		"join":
			return "Connecting to %s..." % _address.text.strip_edges()
	return ""


func _spacer(parent: Control, h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


func _box(c: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if border.a > 0.0:
		sb.set_border_width_all(2)
		sb.border_color = border
	return sb


func _make_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Palette.BG)
	b.add_theme_color_override("font_hover_color", Palette.BG)
	b.add_theme_color_override("font_pressed_color", Palette.BG)
	b.add_theme_color_override("font_disabled_color", Color(Palette.TEXT, 0.35))
	b.add_theme_stylebox_override("normal", _box(accent))
	b.add_theme_stylebox_override("hover", _box(accent.lightened(0.18)))
	b.add_theme_stylebox_override("pressed", _box(accent.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", _box(Palette.DISABLED))
	return b
