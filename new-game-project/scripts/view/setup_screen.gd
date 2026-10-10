class_name SetupScreen
extends Control
## Game setup screen, built from the option schema (GameConfig.OPTIONS by default).

signal started(config: GameConfig)
signal back

const COLUMN_W := 420.0

var title_text := "SOLO SETUP"
## The option schema to build rows from; set before adding to the tree.
var options: Array[Dictionary] = GameConfig.OPTIONS

var _config := GameConfig.new()
var _title: Label
var _content: VBoxContainer
var _scroll: ScrollContainer
var _start_btn: Button
var _back_btn: Button
## One entry per option: {id, choices, buttons: Array[Button], help: Label}
var _rows: Array[Dictionary] = []
var _built := false


func _ready() -> void:
	_build()
	_refresh()


func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(COLUMN_W, 0)
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)

	_title = Label.new()
	_title.text = title_text
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Palette.TEXT)
	column.add_child(_title)
	UiKit.spacer(column, 10)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(COLUMN_W, 0)
	column.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(COLUMN_W - 12, 0)
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	_content.minimum_size_changed.connect(_fit_scroll)
	resized.connect(_fit_scroll)

	for option in options:
		_add_section(option)

	UiKit.spacer(column, 10)
	_start_btn = UiKit.make_button("Start", Palette.GOOD)
	_start_btn.pressed.connect(_on_start)
	column.add_child(_start_btn)
	_back_btn = UiKit.make_button("Back", Palette.DIM.darkened(0.4))
	_back_btn.add_theme_font_size_override("font_size", 16)
	_back_btn.custom_minimum_size = Vector2(0, 38)
	_back_btn.pressed.connect(func() -> void: back.emit())
	column.add_child(_back_btn)
	_fit_scroll.call_deferred()


func _add_section(option: Dictionary) -> void:
	if not _rows.is_empty():
		UiKit.spacer(_content, 10)
	var label := Label.new()
	label.text = String(option.label).to_upper()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Palette.DIM)
	_content.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_content.add_child(row)
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	var id := String(option.id)
	for choice in option.choices:
		var b := UiKit.segmented_button(String(choice.label), Palette.GOOD)
		b.button_group = group
		var value := String(choice.value)
		b.pressed.connect(func() -> void: _on_choice(id, value))
		row.add_child(b)
		buttons.append(b)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(COLUMN_W - 12, 0)
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(Palette.TEXT, 0.6))
	_content.add_child(help)
	_rows.append({"id": id, "default": String(option.default), "choices": option.choices, "buttons": buttons, "help": help})


func _fit_scroll() -> void:
	if _scroll == null or _content == null:
		return
	var avail := maxf(160.0, size.y - 250.0)
	_scroll.custom_minimum_size.y = minf(_content.get_combined_minimum_size().y, avail)


func set_title(text: String) -> void:
	title_text = text
	if _title:
		_title.text = text


func set_config(config: GameConfig) -> void:
	_config = config.duplicate_config()
	_refresh()


func current_config() -> GameConfig:
	return _config.duplicate_config()


func section_count() -> int:
	_build()
	return _rows.size()


func option_buttons(id: String) -> Array[Button]:
	_build()
	for r in _rows:
		if r.id == id:
			return r.buttons
	return []


func help_text(id: String) -> String:
	_build()
	for r in _rows:
		if r.id == id:
			return (r.help as Label).text
	return ""


func start_button() -> Button:
	_build()
	return _start_btn


func back_button() -> Button:
	_build()
	return _back_btn


func _refresh() -> void:
	if not _built:
		return
	_title.text = title_text
	for r in _rows:
		var current := String(_config.values.get(r.id, r.default))
		for i in r.choices.size():
			var choice: Dictionary = r.choices[i]
			var on := String(choice.value) == current
			(r.buttons[i] as Button).set_pressed_no_signal(on)
			if on:
				(r.help as Label).text = String(choice.get("help", ""))


func _on_choice(id: String, value: String) -> void:
	_config.values[id] = value
	_refresh()


func _on_start() -> void:
	started.emit(current_config())


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var row_index := -1
	for i in _rows.size():
		if _rows[i].buttons.has(focus):
			row_index = i
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_start()
		KEY_SPACE:
			if row_index >= 0:
				return # the focused button toggles itself
			_on_start()
		KEY_ESCAPE:
			back.emit()
		KEY_LEFT, KEY_RIGHT:
			if row_index < 0:
				return
			var r: Dictionary = _rows[row_index]
			var n := clampi(r.buttons.find(focus) + (1 if event.keycode == KEY_RIGHT else -1), 0, r.buttons.size() - 1)
			(r.buttons[n] as Button).grab_focus()
			_on_choice(r.id, String(r.choices[n].value))
		_:
			return
	get_viewport().set_input_as_handled()
