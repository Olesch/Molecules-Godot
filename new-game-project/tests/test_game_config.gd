extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_game_config.gd
## The options of the setup screen: defaults, validation, persistence.

const PATH := "user://test_game_config.json"


func _init() -> void:
	var c := GameConfig.new()
	_check(c.pressure() == GameConfig.PRESSURE_TURNS, "pressure defaults to turn-based")
	for option in GameConfig.OPTIONS:
		_check(c.get_value(option.id) == option.default and GameConfig.choice_values(option.id).has(option.default), "default of '%s' is one of its choices" % option.id)

	_check(c.set_value("pressure", GameConfig.PRESSURE_TIMED) and c.pressure() == GameConfig.PRESSURE_TIMED, "a valid value is accepted")
	_check(not c.set_value("pressure", "chaos") and c.pressure() == GameConfig.PRESSURE_TIMED, "an unknown value is rejected and nothing changes")
	_check(not c.set_value("no_such_option", "x") and c.get_value("no_such_option") == "", "an unknown option is rejected")

	var copy := c.duplicate_config()
	copy.set_value("pressure", GameConfig.PRESSURE_NONE)
	_check(c.pressure() == GameConfig.PRESSURE_TIMED and copy.pressure() == GameConfig.PRESSURE_NONE, "a duplicate is independent")

	var round_trip := GameConfig.from_dict(c.to_dict())
	_check(round_trip.pressure() == GameConfig.PRESSURE_TIMED, "dictionary round trip keeps the value")
	_check(GameConfig.from_dict({"pressure": "chaos", "future_option": "x"}).pressure() == GameConfig.PRESSURE_TURNS, "bad values and unknown options fall back to defaults")
	_check(GameConfig.from_dict("not a dictionary").pressure() == GameConfig.PRESSURE_TURNS, "garbage input gives defaults")

	_check(c.save_to(PATH) == OK, "saves to disk")
	_check(GameConfig.load_from(PATH).pressure() == GameConfig.PRESSURE_TIMED, "loads what was saved")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{ definitely not json")
	file.close()
	_check(GameConfig.load_from(PATH).pressure() == GameConfig.PRESSURE_TURNS, "a corrupt file gives defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_check(GameConfig.load_from(PATH).pressure() == GameConfig.PRESSURE_TURNS, "a missing file gives defaults")

	_finish()
