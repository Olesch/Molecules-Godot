class_name SetupScreen
extends Control
## Game setup screen, built from the option schema (GameConfig.OPTIONS by default). Options
## flagged "advanced" sit behind an "Advanced properties" button (collapsed at first).

signal started(config: GameConfig)
signal back

const OPTION_W := 600.0 ## width of one option cell; the options sit in two columns
const GAP_X := 48
const COLUMN_W := OPTION_W * 2.0 + GAP_X + 16.0 ## both columns plus room for the scrollbar

var title_text := "SOLO SETUP"
## The option schema to build rows from; set before adding to the tree.
var options: Array[Dictionary] = GameConfig.OPTIONS

var _config := GameConfig.new()
var _title: Label
var _content: VBoxContainer
var _main_grid: GridContainer
var _advanced_box: VBoxContainer ## the advanced options; hidden until the toggle is pressed
var _advanced_grid: GridContainer ## the grid of the current group inside _advanced_box
var _advanced_btn: Button
var _scroll: ScrollContainer
var _start_btn: Button
var _back_btn: Button
## One entry per option: {id, choices, buttons: Array[Button], slider: HSlider or null, value_label, help: Label}
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
	column.add_theme_constant_override("separation", 8)
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
	_content.custom_minimum_size = Vector2(COLUMN_W - 16.0, 0)
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	_content.minimum_size_changed.connect(_fit_scroll)
	resized.connect(_fit_scroll)

	_main_grid = _new_grid(_content)
	var advanced: Array[Dictionary] = []
	for option in options:
		if option.get("advanced", false):
			advanced.append(option)
		else:
			_add_section(option, _main_grid)
	if not advanced.is_empty():
		UiKit.spacer(_content, 6)
		_advanced_btn = UiKit.make_button("", Palette.DIM.darkened(0.4))
		_advanced_btn.add_theme_font_size_override("font_size", 16)
		_advanced_btn.custom_minimum_size = Vector2(0, 38)
		_advanced_btn.pressed.connect(func() -> void: set_advanced_open(not _advanced_box.visible))
		_content.add_child(_advanced_btn)
		_advanced_box = VBoxContainer.new()
		_advanced_box.add_theme_constant_override("separation", 8)
		_advanced_box.visible = false
		_content.add_child(_advanced_box)
		var group: Variant = null # null: no heading yet, so the first option opens a grid
		for option in advanced:
			if option.get("group", "") != group:
				group = option.get("group", "")
				_add_group_heading(String(group))
			_add_section(option, _advanced_grid)
		_update_advanced_button()

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


func _new_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", GAP_X)
	grid.add_theme_constant_override("v_separation", 14)
	parent.add_child(grid)
	return grid


## A full-width group heading; the options after it go into a fresh two-column grid.
func _add_group_heading(text: String) -> void:
	if _advanced_box.get_child_count() > 0:
		UiKit.spacer(_advanced_box, 8)
	if text != "":
		var heading := Label.new()
		heading.text = text.to_upper()
		heading.add_theme_font_size_override("font_size", 16)
		heading.add_theme_color_override("font_color", Palette.GOLD)
		_advanced_box.add_child(heading)
	_advanced_grid = _new_grid(_advanced_box)


## One option as a cell of the grid: label (and the current choice for sliders), the control, the help line.
func _add_section(option: Dictionary, grid: GridContainer) -> void:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(OPTION_W, 0)
	cell.add_theme_constant_override("separation", 4)
	grid.add_child(cell)
	var id := String(option.id)
	var as_slider := GameConfig.uses_slider(option)

	var head := HBoxContainer.new()
	cell.add_child(head)
	var label := Label.new()
	label.text = String(option.label).to_upper()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Palette.DIM)
	head.add_child(label)
	var value_label: Label = null
	var slider: HSlider = null
	var buttons: Array[Button] = []
	if as_slider:
		value_label = Label.new()
		value_label.add_theme_font_size_override("font_size", 16)
		value_label.add_theme_color_override("font_color", Palette.GOLD)
		head.add_child(value_label)
		slider = UiKit.slider(option.choices.size(), Palette.GOOD)
		slider.value_changed.connect(func(v: float) -> void: _on_choice(id, String(option.choices[int(v)].value)))
		cell.add_child(slider)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		cell.add_child(row)
		var group := ButtonGroup.new()
		for choice in option.choices:
			var b := UiKit.segmented_button(String(choice.label), Palette.GOOD)
			b.button_group = group
			var value := String(choice.value)
			b.pressed.connect(func() -> void: _on_choice(id, value))
			row.add_child(b)
			buttons.append(b)

	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(OPTION_W, 40) # two lines, so the grid does not jump
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(Palette.TEXT, 0.6))
	cell.add_child(help)
	_rows.append({"id": id, "default": String(option.default), "choices": option.choices, "buttons": buttons, "slider": slider, "value_label": value_label, "help": help, "option_help": String(option.get("help", ""))})


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


## Number of option rows, advanced ones included (collapsed or not).
func section_count() -> int:
	_build()
	return _rows.size()


## True if the screen has an Advanced properties section.
func has_advanced() -> bool:
	_build()
	return _advanced_box != null


func is_advanced_open() -> bool:
	_build()
	return _advanced_box != null and _advanced_box.visible


func set_advanced_open(open: bool) -> void:
	_build()
	if _advanced_box == null:
		return
	_advanced_box.visible = open
	_update_advanced_button()
	_fit_scroll.call_deferred()


func advanced_button() -> Button:
	_build()
	return _advanced_btn


## Number of option rows currently showing (the advanced ones only while open).
func visible_section_count() -> int:
	_build()
	var n := 0
	for r in _rows:
		if (r.help as Label).is_visible_in_tree():
			n += 1
	return n


func _update_advanced_button() -> void:
	_advanced_btn.text = "Advanced properties  [-]" if _advanced_box.visible else "Advanced properties  [+]"


## Height the whole screen asks for; it fits the window when this is at most the window height.
func needed_height() -> float:
	_build()
	return _title.get_combined_minimum_size().y + 20.0 + _scroll.custom_minimum_size.y + 20.0 + _start_btn.get_combined_minimum_size().y + _back_btn.get_combined_minimum_size().y + 36.0


## The slider of a numeric option (null for options shown as a button row).
func option_slider(id: String) -> HSlider:
	_build()
	for r in _rows:
		if r.id == id:
			return r.slider
	return null


## Picks a choice by value whatever widget the option uses; false if it is not offered.
func choose(id: String, value: String) -> bool:
	_build()
	for r in _rows:
		if r.id == id:
			for i in r.choices.size():
				if String(r.choices[i].value) == value:
					_on_choice(id, value)
					return true
	return false


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
			if r.slider != null:
				if on:
					(r.slider as HSlider).set_value_no_signal(i)
					(r.value_label as Label).text = String(choice.label)
			else:
				(r.buttons[i] as Button).set_pressed_no_signal(on)
			if on:
				(r.help as Label).text = String(choice.get("help", r.option_help))


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
