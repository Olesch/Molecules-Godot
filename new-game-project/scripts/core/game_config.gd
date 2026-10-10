class_name GameConfig
extends RefCounted
## The options a player picks on the setup screen before a game. The screen is built from
## OPTIONS, so a new option only needs an entry here plus code that reads it.

const PRESSURE_TURNS := "turns"
const PRESSURE_TIMED := "timed"
const PRESSURE_NONE := "none"

## Every option: id, label, default (a choice value) and its choices. Each choice has a
## value (stored), a label (button text) and a help line shown while it is selected.
## Optional keys: "advanced" (true: minor option, shown behind the Advanced properties
## button), "group" (heading inside the advanced list), "modes" (["solo"] or ["versus"]; no
## key means both) and "help" (a line shown when a choice has none of its own).
## Numeric options are discrete string choices; read them with get_int() / get_float().
const OPTIONS: Array[Dictionary] = [
	{
		"id": "pressure",
		"label": "Pressure",
		"modes": ["solo"],
		"default": "turns",
		"choices": [
			{"value": "turns", "label": "Turn-based", "help": "Stray atoms drop every few placements. Think as long as you like."},
			{"value": "timed", "label": "Time pressure", "help": "Stray atoms drop on a clock. The pace picks up with your level."},
			{"value": "none", "label": "Relaxed", "help": "No stray atoms. Play at your own pace."},
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
	{
		"id": "board_size",
		"label": "Board size",
		"default": "8",
		"choices": [
			{"value": "6", "label": "Small 6x6", "help": "36 cells: cramped, the board fills up fast."},
			{"value": "8", "label": "Normal 8x8", "help": "64 cells: the standard board."},
			{"value": "10", "label": "Large 10x10", "help": "100 cells: more room, smaller cells."},
		],
	},
	{
		"id": "bombs",
		"label": "Bombs",
		"default": "0.35",
		"choices": [
			{"value": "0", "label": "None", "help": "No bombs (level-up cards can still add some)."},
			{"value": "0.15", "label": "Few", "help": "15% of eligible atoms are bombs."},
			{"value": "0.35", "label": "Normal", "help": "35% of eligible atoms are bombs."},
			{"value": "0.6", "label": "Many", "help": "60% of eligible atoms are bombs."},
		],
	},
	{
		"id": "preplaced",
		"label": "Preplaced atoms",
		"default": "10",
		"choices": [
			{"value": "0", "label": "None", "help": "The board starts empty."},
			{"value": "5", "label": "Few", "help": "5 loose atoms are scattered on the board at the start."},
			{"value": "10", "label": "Normal", "help": "10 loose atoms are scattered on the board at the start."},
			{"value": "16", "label": "Many", "help": "16 loose atoms are scattered on the board at the start."},
		],
	},
	{
		"id": "preview",
		"label": "Preview atoms",
		"default": "1",
		"choices": [
			{"value": "1", "label": "1", "help": "Shows the next atom only."},
			{"value": "2", "label": "2", "help": "Shows the next 2 atoms."},
			{"value": "3", "label": "3", "help": "Shows the next 3 atoms."},
			{"value": "4", "label": "4", "help": "Shows the next 4 atoms."},
		],
	},
	{
		"id": "bomb_min",
		"label": "Bomb minimum connections",
		"advanced": true,
		"group": "Bombs",
		"help": "Only atoms with at least this many connections can be bombs.",
		"default": "4",
		"choices": [
			{"value": "2", "label": "2", "help": "Atoms with 2 or more connections can be bombs (the Mini Bombs card lowers this)."},
			{"value": "3", "label": "3", "help": "Atoms with 3 or more connections can be bombs (the Mini Bombs card lowers this)."},
			{"value": "4", "label": "4", "help": "Atoms with 4 or more connections can be bombs (the Mini Bombs card lowers this)."},
			{"value": "5", "label": "5", "help": "Atoms with 5 or more connections can be bombs (the Mini Bombs card lowers this)."},
		],
	},
	{
		"id": "blast_radius",
		"label": "Blast radius",
		"advanced": true,
		"group": "Bombs",
		"help": "How far a bomb blast reaches.",
		"default": "1",
		"choices": [
			{"value": "1", "label": "1", "help": "A bomb wipes every atom within 1 cell of it."},
			{"value": "2", "label": "2", "help": "A bomb wipes every atom within 2 cells of it."},
			{"value": "3", "label": "3", "help": "A bomb wipes every atom within 3 cells of it."},
		],
	},
	{
		"id": "wild_chance",
		"label": "Wildcards",
		"advanced": true,
		"group": "Atoms",
		"help": "Chance that a new atom is a wildcard (links to any neighbour).",
		"default": "0",
		"choices": [
			{"value": "0", "label": "None", "help": "No wildcards until the Joker Supply card is leveled."},
			{"value": "0.05", "label": "5%", "help": "One atom in 20 is a wildcard."},
			{"value": "0.1", "label": "10%", "help": "One atom in 10 is a wildcard."},
			{"value": "0.2", "label": "20%", "help": "One atom in 5 is a wildcard."},
		],
	},
	{
		"id": "open_ends",
		"label": "Loose molecules",
		"advanced": true,
		"group": "Atoms",
		"help": "Open connections a molecule of 3+ atoms may keep and still clear.",
		"default": "0",
		"choices": [
			{"value": "0", "label": "Closed only", "help": "Every connection of a molecule must be bonded."},
			{"value": "1", "label": "1 open end", "help": "A molecule of 3+ atoms clears with 1 connection left open."},
			{"value": "2", "label": "2 open ends", "help": "A molecule of 3+ atoms clears with up to 2 connections left open."},
		],
	},
	{
		"id": "min_molecule",
		"label": "Minimum molecule size",
		"advanced": true,
		"group": "Atoms",
		"help": "Fewest atoms a molecule needs before it clears.",
		"default": "2",
		"choices": [
			{"value": "2", "label": "2", "help": "Molecules need at least 2 atoms to clear; smaller closed ones block their cells."},
			{"value": "3", "label": "3", "help": "Molecules need at least 3 atoms to clear; smaller closed ones block their cells."},
			{"value": "4", "label": "4", "help": "Molecules need at least 4 atoms to clear; smaller closed ones block their cells."},
		],
	},
	{
		"id": "crowded",
		"label": "Crowded atoms",
		"advanced": true,
		"group": "Atoms",
		"help": "Odds of atoms with 4 or more connections.",
		"default": "1",
		"choices": [
			{"value": "0", "label": "Never", "help": "Atoms with 4+ connections never come up."},
			{"value": "0.5", "label": "Rare", "help": "Half as many 4+ connection atoms as usual."},
			{"value": "1", "label": "Normal", "help": "The usual odds of 4+ connection atoms."},
			{"value": "2", "label": "Common", "help": "Twice as many 4+ connection atoms."},
			{"value": "4", "label": "Frequent", "help": "Four times as many 4+ connection atoms."},
		],
	},
	{
		"id": "max_points",
		"label": "Points per atom cap",
		"advanced": true,
		"group": "Scoring and levels",
		"help": "The Nth atom of a molecule and every later one score this many points.",
		"default": "5",
		"choices": [
			{"value": "3", "label": "3", "help": "Atoms score 1, 2, 3 ... up to 3 points each (big molecules pay less)."},
			{"value": "4", "label": "4", "help": "Atoms score 1, 2, 3 ... up to 4 points each (big molecules pay less)."},
			{"value": "5", "label": "5", "help": "Atoms score 1, 2, 3 ... up to 5 points each (the usual)."},
			{"value": "6", "label": "6", "help": "Atoms score 1, 2, 3 ... up to 6 points each (big molecules pay more)."},
			{"value": "8", "label": "8", "help": "Atoms score 1, 2, 3 ... up to 8 points each (big molecules pay more)."},
		],
	},
	{
		"id": "xp_scale",
		"label": "XP needed per level",
		"advanced": true,
		"group": "Scoring and levels",
		"help": "Multiplier on the XP each level-up costs.",
		"default": "1",
		"choices": [
			{"value": "0.5", "label": "x0.5", "help": "Levels (and cards) come twice as fast."},
			{"value": "1", "label": "x1", "help": "The usual XP cost per level."},
			{"value": "1.5", "label": "x1.5", "help": "Levels take 50% more XP."},
			{"value": "2", "label": "x2", "help": "Levels take twice the XP."},
		],
	},
	{
		"id": "reroll_cooldown",
		"label": "Reroll recharge",
		"advanced": true,
		"group": "Scoring and levels",
		"help": "Placements before the Reroll card recharges.",
		"default": "4",
		"choices": [
			{"value": "2", "label": "2", "help": "Reroll is ready again after 2 placements."},
			{"value": "4", "label": "4", "help": "Reroll is ready again after 4 placements."},
			{"value": "6", "label": "6", "help": "Reroll is ready again after 6 placements."},
			{"value": "8", "label": "8", "help": "Reroll is ready again after 8 placements."},
		],
	},
	{
		"id": "attack_points",
		"label": "Points per stray atom",
		"advanced": true,
		"group": "Versus",
		"modes": ["versus"],
		"help": "Versus: points you must score to send one stray atom.",
		"default": "25",
		"choices": [
			{"value": "15", "label": "15", "help": "Every 15 points scored send one stray atom to the opponent."},
			{"value": "25", "label": "25", "help": "Every 25 points scored send one stray atom to the opponent."},
			{"value": "40", "label": "40", "help": "Every 40 points scored send one stray atom to the opponent."},
			{"value": "60", "label": "60", "help": "Every 60 points scored send one stray atom to the opponent."},
		],
	},
	{
		"id": "incoming_seconds",
		"label": "Seconds between strays",
		"advanced": true,
		"group": "Versus",
		"modes": ["versus"],
		"help": "Versus: gap between incoming stray atoms landing.",
		"default": "5",
		"choices": [
			{"value": "3", "label": "3 s", "help": "Incoming stray atoms land 3 seconds apart."},
			{"value": "5", "label": "5 s", "help": "Incoming stray atoms land 5 seconds apart."},
			{"value": "8", "label": "8 s", "help": "Incoming stray atoms land 8 seconds apart."},
			{"value": "12", "label": "12 s", "help": "Incoming stray atoms land 12 seconds apart."},
		],
	},
	{
		"id": "turn_start",
		"label": "Turn-based: first interval",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "Placements between stray drops at level 1.",
		"default": "8",
		"choices": [
			{"value": "5", "label": "5", "help": "Strays drop every 5 placements at level 1."},
			{"value": "8", "label": "8", "help": "Strays drop every 8 placements at level 1."},
			{"value": "12", "label": "12", "help": "Strays drop every 12 placements at level 1."},
		],
	},
	{
		"id": "turn_min",
		"label": "Turn-based: minimum interval",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "The shortest gap, in placements, the pressure ever reaches.",
		"default": "3",
		"choices": [
			{"value": "2", "label": "2", "help": "The interval never gets shorter than 2 placements."},
			{"value": "3", "label": "3", "help": "The interval never gets shorter than 3 placements."},
			{"value": "5", "label": "5", "help": "The interval never gets shorter than 5 placements."},
		],
	},
	{
		"id": "turn_grace",
		"label": "Turn-based: first drop grace",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "Extra placements before the very first drop.",
		"default": "2",
		"choices": [
			{"value": "0", "label": "0", "help": "0 extra placements before the first drop."},
			{"value": "2", "label": "2", "help": "2 extra placements before the first drop."},
			{"value": "4", "label": "4", "help": "4 extra placements before the first drop."},
		],
	},
	{
		"id": "time_start",
		"label": "Timed: starting seconds",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "Seconds between stray drops at level 1.",
		"default": "18",
		"choices": [
			{"value": "12", "label": "12 s", "help": "Strays drop every 12 seconds at level 1."},
			{"value": "18", "label": "18 s", "help": "Strays drop every 18 seconds at level 1."},
			{"value": "25", "label": "25 s", "help": "Strays drop every 25 seconds at level 1."},
		],
	},
	{
		"id": "time_min",
		"label": "Timed: minimum seconds",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "The shortest gap, in seconds, the clock ever reaches.",
		"default": "5",
		"choices": [
			{"value": "3", "label": "3 s", "help": "The gap never gets shorter than 3 seconds."},
			{"value": "5", "label": "5 s", "help": "The gap never gets shorter than 5 seconds."},
			{"value": "8", "label": "8 s", "help": "The gap never gets shorter than 8 seconds."},
		],
	},
	{
		"id": "time_grace",
		"label": "Timed: first drop grace",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "Extra seconds before the very first drop.",
		"default": "6",
		"choices": [
			{"value": "3", "label": "3 s", "help": "3 extra seconds before the first drop."},
			{"value": "6", "label": "6 s", "help": "6 extra seconds before the first drop."},
			{"value": "10", "label": "10 s", "help": "10 extra seconds before the first drop."},
		],
	},
	{
		"id": "double_level",
		"label": "Double strays after level",
		"advanced": true,
		"group": "Solo pressure",
		"modes": ["solo"],
		"help": "Above this level two strays drop at once.",
		"default": "10",
		"choices": [
			{"value": "5", "label": "5", "help": "Two strays per drop from level 6."},
			{"value": "10", "label": "10", "help": "Two strays per drop from level 11."},
			{"value": "20", "label": "20", "help": "Two strays per drop from level 21."},
			{"value": "999", "label": "Never", "help": "Always one stray per drop."},
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


## The options that make sense in a game mode ("solo" or "versus"), main ones first.
static func options_for(mode: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for advanced in [false, true]:
		for option in OPTIONS:
			if bool(option.get("advanced", false)) == advanced and option.get("modes", [mode]).has(mode):
				result.append(option)
	return result


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


func get_int(id: String) -> int:
	return get_value(id).to_int()


func get_float(id: String) -> float:
	return get_value(id).to_float()


func pressure() -> String:
	return get_value("pressure")


func board_id() -> String:
	return get_value("board")


## Board width and height in cells (the board_size option; boards are square).
func board_dims() -> Vector2i:
	var n := get_int("board_size")
	return Vector2i(n, n)


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
			config.set_value(str(id), str(data[id])) # str(): any JSON value is safe
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
