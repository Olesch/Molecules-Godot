class_name UiKit
extends RefCounted
## Shared flat-style UI helpers (same look as the main menu).


static func spacer(parent: Control, h: int) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


static func box(c: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
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


static func make_button(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Palette.BG)
	b.add_theme_color_override("font_hover_color", Palette.BG)
	b.add_theme_color_override("font_pressed_color", Palette.BG)
	b.add_theme_color_override("font_disabled_color", Color(Palette.TEXT, 0.35))
	b.add_theme_stylebox_override("normal", box(accent))
	b.add_theme_stylebox_override("hover", box(accent.lightened(0.18)))
	b.add_theme_stylebox_override("pressed", box(accent.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", box(Palette.DISABLED))
	return b


## A toggle button: filled with the accent colour when pressed, outlined and dim otherwise.
static func segmented_button(text: String, accent: Color) -> Button:
	var tight := func(sb: StyleBoxFlat) -> StyleBoxFlat:
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		return sb
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 42)
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(Palette.TEXT, 0.7))
	b.add_theme_color_override("font_hover_color", Palette.TEXT)
	b.add_theme_color_override("font_focus_color", Palette.TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.BG)
	b.add_theme_color_override("font_hover_pressed_color", Palette.BG)
	b.add_theme_color_override("font_disabled_color", Color(Palette.TEXT, 0.35))
	b.add_theme_stylebox_override("normal", tight.call(box(Palette.FIELD, Palette.GRID)))
	b.add_theme_stylebox_override("hover", tight.call(box(Palette.FIELD.lightened(0.08), accent.darkened(0.2))))
	b.add_theme_stylebox_override("pressed", tight.call(box(accent)))
	b.add_theme_stylebox_override("hover_pressed", tight.call(box(accent.lightened(0.12))))
	b.add_theme_stylebox_override("focus", tight.call(box(Color(0, 0, 0, 0), Palette.TEXT)))
	b.add_theme_stylebox_override("disabled", tight.call(box(Palette.DISABLED)))
	return b


static func _dot(diameter: int, c: Color, ring: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter / 2.0
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var col := Color(0, 0, 0, 0)
			if d <= r - 1.0:
				col = c if d <= r - 3.0 else ring
			elif d <= r:
				col = Color(ring, ring.a * (r - d)) # soft edge
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## A horizontal slider with a clearly visible track, a filled part up to the grabber and a
## round grabber, in the dark theme. It snaps to whole steps 0 .. steps-1 and shows a tick per step.
static func slider(steps: int, accent: Color) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = maxi(steps - 1, 1)
	s.step = 1
	s.rounded = true
	s.scrollable = false # the mouse wheel scrolls the page, it must not change the option
	s.tick_count = steps
	s.ticks_on_borders = true
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 30)
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.GRID.lightened(0.15)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4 # the track is 8 px tall
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = accent
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_icon_override("grabber", _dot(26, Palette.TEXT, accent))
	s.add_theme_icon_override("grabber_highlight", _dot(26, Color.WHITE, accent.lightened(0.2)))
	s.add_theme_icon_override("grabber_disabled", _dot(26, Palette.DIM, Palette.DISABLED))
	s.add_theme_icon_override("tick", _dot(8, Palette.DIM, Palette.DIM))
	return s
