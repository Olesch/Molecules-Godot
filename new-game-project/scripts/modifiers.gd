class_name Modifiers
extends RefCounted
## Owned card stacks and the gameplay values derived from them.

var stacks := {}


func add(id: String) -> bool:
	var d := Cards.get_def(id)
	if d.is_empty():
		return false
	var n: int = stacks.get(id, 0)
	if n >= int(d.max):
		return false
	stacks[id] = n + 1
	return true


func count(id: String) -> int:
	return int(stacks.get(id, 0))


func has(id: String) -> bool:
	return count(id) > 0


func clear() -> void:
	stacks = {}


func to_dict() -> Dictionary:
	return stacks.duplicate()


static func from_dict(d) -> Modifiers:
	var m := Modifiers.new()
	if typeof(d) != TYPE_DICTIONARY:
		return m
	for k in d.keys():
		var def := Cards.get_def(str(k))
		var v = d[k]
		if def.is_empty() or (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT):
			continue
		var n := clampi(int(v), 0, int(def.max))
		if n > 0:
			m.stacks[str(k)] = n
	return m


func queue_size() -> int:
	return clampi(4 + count("long_view") - 2 * count("overclock"), 2, 8)


func bomb_chance() -> float:
	return Atoms.BOMB_CHANCE + count("demolition") * 0.02 + count("hot_potato") * 0.08


func wild_chance() -> float:
	return maxf(0.0, Atoms.WILD_CHANCE + count("joker_supply") * 0.02 - count("hot_potato") * 0.07)


func shape_weights() -> Array[float]:
	var w: Array[float] = []
	for x in Atoms.SHAPE_WEIGHTS:
		w.append(x)
	if not w.is_empty():
		w[w.size() - 1] *= pow(0.5, count("lucky_shapes"))
	return w


func score_mult() -> float:
	return (1.0 + 0.10 * count("high_scorer")) * (1.15 if has("overclock") else 1.0)


func attack_mult() -> float:
	return (1.0 + 0.10 * count("heavy_hitter")) * (1.5 if has("glass_cannon") else 1.0)


func garbage_cap() -> int:
	return maxi(1, Scoring.GARBAGE_PER_TURN - count("thick_skin"))


func incoming_mult() -> float:
	return 1.25 if has("glass_cannon") else 1.0


func cancel_mult() -> float:
	return 1.0 + 0.5 * count("efficient_cleaner")


func xp_mult() -> float:
	return 1.0 + 0.10 * count("fast_learner")


func preplaced_count(base: int) -> int:
	return maxi(0, base - 3 * count("tidy_start"))


func max_open_ends() -> int:
	return 1 if has("loose_ends") else 0


func min_molecule() -> int:
	return 3 if has("big_game") else 2


func big_game_mult() -> float:
	return 2.0 if has("big_game") else 1.0


func scaled_attack(molecule_size: int, blasted: int) -> int:
	if molecule_size <= 0:
		return 0
	var raw := Scoring.attack(molecule_size, 0) + blasted * (2 if has("salvage") else 1)
	return int(ceil(raw * attack_mult() - 0.000001))


func scaled_points(molecule_size: int, blasted: int, combo_active: bool) -> int:
	if molecule_size <= 0:
		return 0
	var raw := Scoring.triangle(molecule_size) + blasted * (2 if has("salvage") else 1)
	var combo := 1.5 if has("combo_chain") and combo_active else 1.0
	return roundi(raw * score_mult() * big_game_mult() * combo)
