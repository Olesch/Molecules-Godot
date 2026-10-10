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

	_options_schema()
	_finish()


## The wider option list: defaults reproduce the old constants, every choice has a help line,
## numeric choices parse, and the mode filter splits solo from versus.
func _options_schema() -> void:
	var d := GameConfig.new()
	_check(d.get_int("board_size") == 8 and d.board_dims() == Vector2i(8, 8), "default board is 8x8")
	_check(is_equal_approx(d.get_float("bombs"), Atoms.BOMB_CHANCE) and d.get_int("bomb_min") == Atoms.BOMB_MIN_CONNECTIONS and d.get_int("blast_radius") == Atoms.BLAST_RADIUS, "bomb defaults are the old constants")
	_check(is_equal_approx(d.get_float("wild_chance"), Atoms.WILD_CHANCE) and d.get_int("open_ends") == 0 and d.get_int("min_molecule") == 2 and d.get_float("crowded") == 1.0, "atom defaults are the old constants")
	_check(d.get_int("preplaced") == 10 and d.get_int("preview") == 1, "preplaced and preview defaults")
	_check(d.get_int("max_points") == Scoring.MAX_ATOM_POINTS and d.get_int("attack_points") == Scoring.POINTS_PER_ATTACK and is_equal_approx(d.get_float("incoming_seconds"), Danger.INCOMING_BASE_SECONDS), "scoring and versus defaults are the old constants")
	_check(d.get_int("turn_start") == Danger.BASE_INTERVAL and d.get_int("turn_min") == Danger.MIN_INTERVAL and d.get_int("turn_grace") == Danger.FIRST_GRACE, "turn-based pressure defaults")
	_check(is_equal_approx(d.get_float("time_start"), Danger.BASE_SECONDS) and is_equal_approx(d.get_float("time_min"), Danger.MIN_SECONDS) and is_equal_approx(d.get_float("time_grace"), Danger.FIRST_GRACE_SECONDS) and d.get_int("double_level") == Danger.DOUBLE_ABOVE_LEVEL, "timed pressure defaults")
	_check(d.get_int("reroll_cooldown") == Playfield.REROLL_COOLDOWN and d.get_float("xp_scale") == 1.0, "card and level defaults")

	var ids := {}
	var advanced := 0
	for option in GameConfig.OPTIONS:
		_check(not ids.has(option.id), "option id '%s' is unique" % option.id)
		ids[option.id] = true
		var all_help := true
		var numeric: bool = option.id not in ["pressure", "board"]
		for choice in option.choices:
			if String(choice.get("help", option.get("help", ""))) == "":
				all_help = false
			if numeric and not String(choice.value).is_valid_float():
				numeric = false
				_check(false, "choice '%s' of '%s' is a number" % [choice.value, option.id])
		_check(all_help, "every choice of '%s' has a help line" % option.id)
		if option.get("advanced", false):
			advanced += 1
			_check(String(option.get("group", "")) != "", "advanced option '%s' has a group" % option.id)
	_check(advanced >= 10 and advanced < GameConfig.OPTIONS.size(), "there are main and advanced options (%d advanced)" % advanced)
	for id in ["pressure", "board", "board_size", "bombs", "preplaced", "preview"]:
		_check(not GameConfig.option_def(id).get("advanced", false), "'%s' is a main option" % id)

	var solo := GameConfig.options_for("solo")
	var versus := GameConfig.options_for("versus")
	var solo_ids: Array[String] = []
	var versus_ids: Array[String] = []
	for o in solo:
		solo_ids.append(o.id)
	for o in versus:
		versus_ids.append(o.id)
	_check(solo_ids.has("pressure") and solo_ids.has("turn_start") and solo_ids.has("board_size") and not solo_ids.has("attack_points") and not solo_ids.has("incoming_seconds"), "solo options: pressure yes, versus-only no")
	_check(versus_ids.has("board") and versus_ids.has("board_size") and versus_ids.has("bombs") and versus_ids.has("attack_points") and versus_ids.has("incoming_seconds"), "versus options: shared plus versus-only")
	_check(not versus_ids.has("pressure") and not versus_ids.has("turn_start") and not versus_ids.has("time_start") and not versus_ids.has("double_level"), "versus options: no solo pressure")
	_check(not solo[0].get("advanced", false) and solo[solo.size() - 1].get("advanced", false), "main options come before the advanced ones")

	var c := GameConfig.new()
	_check(c.set_value("board_size", "10") and c.board_dims() == Vector2i(10, 10), "a board size is accepted")
	_check(not c.set_value("board_size", "9") and c.get_int("board_size") == 10, "an unoffered board size is rejected")
	_check(not c.set_value("bombs", "0.5") and not c.set_value("bombs", "lots") and is_equal_approx(c.get_float("bombs"), 0.35), "unoffered numbers are rejected")
	c.set_value("max_points", "8")
	c.set_value("incoming_seconds", "12")
	var back := GameConfig.from_dict(c.to_dict())
	_check(back.get_int("board_size") == 10 and back.get_int("max_points") == 8 and back.get_float("incoming_seconds") == 12.0, "advanced values survive a dictionary round trip")
	var bad := GameConfig.from_dict({"board_size": "99", "max_points": 5.5, "bombs": "-1", "turn_min": ["x"]})
	_check(bad.get_int("board_size") == 8 and bad.get_int("max_points") == 5 and is_equal_approx(bad.get_float("bombs"), 0.35) and bad.get_int("turn_min") == 3, "invalid advanced values fall back to defaults")
