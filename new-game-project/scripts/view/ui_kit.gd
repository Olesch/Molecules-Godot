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
