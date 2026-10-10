class_name GameConfig
extends RefCounted
## The options a player picks on the setup screen before a game. The screen is built from
## OPTIONS, so a new option only needs an entry here plus code that reads it.

const PRESSURE_TURNS := "turns"
const PRESSURE_TIMED := "timed"
const PRESSURE_NONE := "none"

## Every option: id, label, default (a choice value) and its choices. Each choice has a
## value (stored), a label (button text) and a help line shown while it is selected.
const OPTIONS: Array[Dictionary] = [
	{
		"id": "pressure",
		"label": "Pressure",
		"default": PRESSURE_TURNS,
		"choices": [
			{"value": PRESSURE_TURNS, "label": "Turn-based", "help": "Stray atoms drop every few placements. Think as long as you like."},
			{"value": PRESSURE_TIMED, "label": "Time pressure", "help": "Stray atoms drop on a clock. The pace picks up with your level."},
			{"value": PRESSURE_NONE, "label": "Relaxed", "help": "No stray atoms. Play at your own pace."},
		],
	},
	{
		"id": "board",
		"label": "Board",
		"default": "square",
		"choices": [
			{"value": "square", "label": "Square", "help": "Classic grid: atoms connect up, down, left and right."},
			{"value": "hex", "label": "Hexagonal", "help": "Six neighbours per cell: atoms rotate in 60 degree steps and bombs blast a flower of 7 cells."},
		],
	},
]

var values := {} ## option id -> chosen value


func _init() -> void:
	for option in OPTIONS:
		values[option.id] = option.default


static func option_def(id: String) -> Dictionary:
	for option in OPTIONS:
		if option.id == id:
			return option
	return {}


static func choice_values(id: String) -> Array[String]:
	var result: Array[String] = []
	for choice in option_def(id).get("choices", []):
		result.append(String(choice.value))
	return result


func get_value(id: String) -> String:
	return String(values.get(id, option_def(id).get("default", "")))


## Returns false (and changes nothing) for an unknown option or a value it does not offer.
func set_value(id: String, value: String) -> bool:
	if not choice_values(id).has(value):
		return false
	values[id] = value
	return true


func pressure() -> String:
	return get_value("pressure")


func board_id() -> String:
	return get_value("board")


func duplicate_config() -> GameConfig:
	var copy := GameConfig.new()
	copy.values = values.duplicate()
	return copy


func to_dict() -> Dictionary:
	return values.duplicate()


## Unknown ids and values that are not offered fall back to the defaults.
static func from_dict(data: Variant) -> GameConfig:
	var config := GameConfig.new()
	if data is Dictionary:
		for id in data:
			config.set_value(String(id), String(data[id]))
	return config


func save_to(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	return OK


## A missing or corrupt file gives the defaults.
static func load_from(path: String) -> GameConfig:
	if not FileAccess.file_exists(path):
		return GameConfig.new()
	var json := JSON.new() # parse() reports failure quietly, unlike JSON.parse_string()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return GameConfig.new()
	return from_dict(json.data)
