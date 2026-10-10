extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_setup_screen.gd
## Setup screen: built from the option schema, edits a copy, emits started/back.


func _init() -> void:
	_run()


func _run() -> void:
	var screen := SetupScreen.new()
	root.add_child(screen)
	await process_frame

	_check(screen.section_count() == GameConfig.OPTIONS.size(), "one section per option")

	var cfg := GameConfig.new()
	cfg.set_value("pressure", GameConfig.PRESSURE_TIMED)
	screen.set_config(cfg)
	var buttons := screen.option_buttons("pressure")
	var values := GameConfig.choice_values("pressure")
	_check(buttons.size() == values.size(), "one button per choice")
	var states_ok := true
	for i in buttons.size():
		if buttons[i].button_pressed != (values[i] == GameConfig.PRESSURE_TIMED):
			states_ok = false
	_check(states_ok, "only the timed button is pressed")
	var timed_help := screen.help_text("pressure")
	_check(timed_help != "", "help text shown")

	var relaxed := buttons[values.find(GameConfig.PRESSURE_NONE)]
	relaxed.pressed.emit()
	_check(screen.current_config().pressure() == GameConfig.PRESSURE_NONE, "pressing Relaxed selects none")
	_check(screen.help_text("pressure") != timed_help, "help text changed")
	_check(relaxed.button_pressed and not buttons[values.find(GameConfig.PRESSURE_TIMED)].button_pressed, "highlight moved")
	_check(cfg.pressure() == GameConfig.PRESSURE_TIMED, "passed config is not mutated")

	var got: Array = []
	screen.started.connect(func(c: GameConfig) -> void: got.append(c))
	screen.start_button().pressed.emit()
	_check(got.size() == 1 and got[0].pressure() == GameConfig.PRESSURE_NONE, "Start emits once with the config")

	var backs := [0]
	screen.back.connect(func() -> void: backs[0] += 1)
	screen.back_button().pressed.emit()
	_check(backs[0] == 1, "Back emits back")
	screen.queue_free()

	# A larger schema scales and scrolls.
	var fake: Array[Dictionary] = []
	for n in 6:
		fake.append({"id": "opt%d" % n, "label": "Option %d" % n, "default": "a", "choices": [
			{"value": "a", "label": "A", "help": "Help A for %d" % n},
			{"value": "b", "label": "B", "help": "Help B for %d" % n},
		]})
	var big := SetupScreen.new()
	big.options = fake
	root.add_child(big)
	await process_frame
	await process_frame
	_check(big.section_count() == 6, "custom option list builds six sections")
	_check(big.help_text("opt3") == "Help A for 3", "custom option help shown")
	_check(not big.has_advanced() and big.advanced_button() == null, "no advanced section when no option is advanced")

	await _advanced_section()
	await _sliders()
	_finish()


func _advanced_section() -> void:
	var screen := SetupScreen.new()
	root.add_child(screen)
	await process_frame
	await process_frame
	var total := GameConfig.OPTIONS.size()
	var main_count := 0
	for o in GameConfig.OPTIONS:
		if not o.get("advanced", false):
			main_count += 1
	_check(screen.section_count() == total, "all %d options are built" % total)
	_check(screen.has_advanced() and screen.advanced_button() != null, "an Advanced properties button exists")
	_check(not screen.is_advanced_open() and screen.visible_section_count() == main_count, "advanced is collapsed by default: only the %d main options show" % main_count)
	var advanced_id := "bomb_min"
	_check(not screen.option_slider(advanced_id).is_visible_in_tree(), "an advanced row is hidden while collapsed")
	var collapsed_h := screen.needed_height()
	screen.advanced_button().pressed.emit()
	await process_frame
	await process_frame
	_check(screen.is_advanced_open() and screen.visible_section_count() == total, "pressing the button shows every option")
	_check(screen.option_slider(advanced_id).is_visible_in_tree(), "an advanced row is visible when open")
	_check(screen.needed_height() <= screen.size.y, "the open screen still fits the window (%.0f of %.0f)" % [screen.needed_height(), screen.size.y])
	_check(screen.needed_height() >= collapsed_h, "the scroll area grows when opened")
	screen.advanced_button().pressed.emit()
	await process_frame
	_check(not screen.is_advanced_open() and screen.visible_section_count() == main_count, "pressing again collapses it")

	# Choices inside the collapsed section still work and are reported.
	screen.set_advanced_open(true)
	var values := GameConfig.choice_values("blast_radius")
	screen.option_slider("blast_radius").value = values.find("2")
	_check(screen.current_config().get_int("blast_radius") == 2, "an advanced choice changes the config")
	_check(screen.help_text("blast_radius").contains("2"), "an advanced choice shows its help")
	var cfg := GameConfig.new()
	cfg.set_value("incoming_seconds", "12")
	screen.set_config(cfg)
	var inc_values := GameConfig.choice_values("incoming_seconds")
	_check(int(screen.option_slider("incoming_seconds").value) == inc_values.find("12") and screen.current_config().get_int("blast_radius") == 1, "set_config moves the sliders to the saved values")
	screen.queue_free()

	# A versus-only screen (what the host sees) lists the shared and the versus options.
	var host := SetupScreen.new()
	host.options = GameConfig.options_for("versus")
	root.add_child(host)
	await process_frame
	await process_frame
	_check(host.option_slider("pressure") == null and host.option_buttons("pressure").is_empty() and not host.option_buttons("board").is_empty() and host.option_slider("attack_points") != null, "host screen: no solo pressure, has board and versus options")
	_check(host.has_advanced() and not host.is_advanced_open(), "host screen: advanced is collapsed")
	host.set_advanced_open(true)
	await process_frame
	await process_frame
	_check(host.needed_height() <= host.size.y, "the open host screen fits the window")
	for id in ["board_size", "bombs", "incoming_seconds"]:
		_check(host.option_slider(id) != null, "host screen lists %s" % id)
	host.queue_free()


## Numeric options with ordered choices are sliders that snap to the choice list.
func _sliders() -> void:
	_check(GameConfig.uses_slider(GameConfig.option_def("bombs")) and GameConfig.uses_slider(GameConfig.option_def("double_level")), "numeric ordered options use sliders")
	_check(not GameConfig.uses_slider(GameConfig.option_def("pressure")) and not GameConfig.uses_slider(GameConfig.option_def("board")), "categorical options stay buttons")
	_check(GameConfig.uses_slider({"choices": [{"value": "a"}, {"value": "b"}], "widget": "slider"}) and not GameConfig.uses_slider({"choices": [{"value": "1"}, {"value": "2"}, {"value": "3"}], "widget": "buttons"}), "the widget key overrides the detection")
	var screen := SetupScreen.new()
	root.add_child(screen)
	await process_frame
	await process_frame
	var slider := screen.option_slider("bombs")
	var values := GameConfig.choice_values("bombs")
	_check(slider != null and screen.option_buttons("bombs").is_empty(), "bombs is a slider, not buttons")
	_check(slider.min_value == 0 and slider.max_value == values.size() - 1 and slider.step == 1, "the slider steps through the choice indices")
	_check(int(slider.value) == values.find("0.35"), "the slider starts on the default choice")
	var before := screen.help_text("bombs")
	slider.value = values.find("0.6")
	_check(screen.current_config().get_value("bombs") == "0.6", "moving the slider writes the choice value")
	_check(screen.help_text("bombs") != before and screen.help_text("bombs").contains("60%"), "the help line follows the slider")
	slider.value = values.size() + 3 # out of range clamps to the last choice
	_check(screen.current_config().get_value("bombs") == values[values.size() - 1], "the slider cannot leave the choice list")
	_check(screen.choose("bombs", "0") and int(slider.value) == 0 and screen.current_config().get_value("bombs") == "0", "choose() moves the slider")
	_check(not screen.choose("bombs", "7"), "choose() rejects a value that is not offered")
	var cfg := GameConfig.new()
	cfg.set_value("bombs", "0.15")
	screen.set_config(cfg)
	_check(int(slider.value) == values.find("0.15"), "set_config moves the slider")
	_check(screen.option_slider("pressure") == null and screen.option_slider("nope") == null, "buttons options and unknown ids have no slider")
	_check(screen.needed_height() <= screen.size.y, "the collapsed screen fits the window without scrolling (%.0f of %.0f)" % [screen.needed_height(), screen.size.y])
	screen.queue_free()
