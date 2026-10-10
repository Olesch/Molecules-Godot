extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_atoms.gd
## Base strength: bombs only on 4-connection atoms, no wildcards; cards unlock more.


func _sample(mods: Modifiers, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var stats := {"wild": 0, "bomb": 0, "bomb_connections": {}, "total": n}
	for i in n:
		var atom := Atoms.random_atom(rng, mods.bomb_chance(), mods.wild_chance(), mods.shape_weights(), mods.min_bomb_connections())
		if Atoms.is_wild(atom):
			stats.wild += 1
		elif Atoms.is_bomb(atom):
			stats.bomb += 1
			var c := Atoms.connection_count(atom)
			stats.bomb_connections[c] = int(stats.bomb_connections.get(c, 0)) + 1
	return stats


func _mods(stacks: Dictionary) -> Modifiers:
	return Modifiers.from_dict(stacks)


func _init() -> void:
	var base := _sample(Modifiers.new(), 30000)
	_check(base.wild == 0, "no wildcards at the start")
	_check(base.bomb > 0, "bombs still appear at the start (%d of 30000)" % base.bomb)
	_check(base.bomb_connections.keys() == [4], "bombs only on 4-connection atoms at the start")
	_check(base.bomb < 30000 * 0.06, "bombs are rare at the start")

	var jokers := _sample(_mods({"joker_supply": 3}), 30000)
	var wild_rate := float(jokers.wild) / 30000.0
	_check(wild_rate > 0.07 and wild_rate < 0.11, "Joker Supply x3 gives about 9%% wildcards (got %.1f%%)" % (wild_rate * 100.0))

	for stacks in [1, 2, 3]:
		var s := _sample(_mods({"mini_bombs": stacks}), 30000)
		var lowest := 99
		for c in s.bomb_connections.keys():
			lowest = mini(lowest, int(c))
		_check(lowest == 4 - stacks, "Mini Bombs x%d allows bombs down to %d connections (lowest seen %d)" % [stacks, 4 - stacks, lowest])
	var plain := _sample(_mods({"mini_bombs": 2}), 30000)
	_check(not plain.bomb_connections.has(1), "Mini Bombs x2 still has no 1-connection bombs")

	# The roll count does not depend on the chances, so seeds stay comparable.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	for i in 20:
		Atoms.random_atom(a, 0.0, 0.0)
		Atoms.random_atom(b, 1.0, 1.0)
	_check(a.randi() == b.randi(), "random_atom always draws the same number of rolls")

	_finish()
