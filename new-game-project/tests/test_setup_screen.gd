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
	_finish()
