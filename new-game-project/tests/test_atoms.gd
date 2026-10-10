extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_atoms.gd
## Base strength: bombs only on 4-connection atoms, no wildcards; cards unlock more.


func _sample(mods: Modifiers, n: int, topology: Topology = null) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var stats := {"wild": 0, "bomb": 0, "bomb_connections": {}, "total": n}
	for i in n:
		var atom := Atoms.random_atom(rng, mods.bomb_chance(), mods.wild_chance(), mods.shape_weights(topology), mods.min_bomb_connections(topology), topology)
		if Atoms.is_wild(atom):
			stats.wild += 1
		elif Atoms.is_bomb(atom):
			stats.bomb += 1
			var c := (topology if topology != null else Topology.square()).connection_count(atom)
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

	# Hexagonal boards follow the same threshold: bombs start at 4 connections, Mini Bombs lowers it.
	var hex := Topology.hex()
	var hex_base := _sample(Modifiers.new(), 40000, hex)
	var lowest_hex := 99
	for c in hex_base.bomb_connections.keys():
		lowest_hex = mini(lowest_hex, int(c))
	_check(hex_base.bomb > 0 and lowest_hex == 4, "hex bombs start at 4 connections (lowest seen %d)" % lowest_hex)
	_check(hex_base.bomb_connections.has(5) or hex_base.bomb_connections.has(6), "hex bombs also appear on 5 and 6 connection atoms")
	_check(hex_base.wild == 0, "no wildcards on hex either")
	var hex_mini := _sample(_mods({"mini_bombs": 2}), 40000, hex)
	var lowest_mini := 99
	for c in hex_mini.bomb_connections.keys():
		lowest_mini = mini(lowest_mini, int(c))
	_check(lowest_mini == 2, "Mini Bombs x2 on hex allows bombs down to 2 connections (lowest seen %d)" % lowest_mini)
	_check(Modifiers.new().min_bomb_connections(hex) == Modifiers.new().min_bomb_connections(Topology.square()), "same bomb threshold on both boards")

	# Both boards deal connection counts alike: the crowded atoms (4+) are as rare on hex as
	# the 4-connection cross is on a square board, and each extra connection is rarer.
	var counts := {}
	for topo in [Topology.square(), Topology.hex()]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 321
		var by_count := {}
		var n := 100000
		for i in n:
			var c: int = topo.connection_count(Atoms.random_shape(rng, [], topo))
			by_count[c] = int(by_count.get(c, 0)) + 1
		counts[topo.id] = by_count
	var sq: Dictionary = counts["square"]
	var hx: Dictionary = counts["hex"]
	for k in [1, 2, 3]:
		var diff := absf(float(sq.get(k, 0)) - float(hx.get(k, 0))) / 100000.0
		_check(diff < 0.02, "%d-connection share matches within 2 points (square %.1f%%, hex %.1f%%)" % [k, sq.get(k, 0) / 1000.0, hx.get(k, 0) / 1000.0])
	var sq_crowded := float(sq.get(4, 0)) / 100000.0
	var hx_crowded := float(hx.get(4, 0) + hx.get(5, 0) + hx.get(6, 0)) / 100000.0
	_check(absf(sq_crowded - hx_crowded) < 0.015, "hex 4+5+6 together are as common as the square 4 (square %.1f%%, hex %.1f%%)" % [sq_crowded * 100.0, hx_crowded * 100.0])
	_check(hx.get(4, 0) > hx.get(5, 0) and hx.get(5, 0) > hx.get(6, 0), "on hex each extra connection is rarer (4: %d, 5: %d, 6: %d)" % [hx.get(4, 0), hx.get(5, 0), hx.get(6, 0)])

	# Lucky Shapes thins every crowded hex shape, not only the star.
	var plain_w := Modifiers.new().shape_weights(Topology.hex())
	var lucky_w := _mods({"lucky_shapes": 2}).shape_weights(Topology.hex())
	var hex_t := Topology.hex()
	var thinned := true
	for i in hex_t.shapes.size():
		var crowded: bool = hex_t.connection_count(hex_t.shapes[i]) >= 4
		var expected: float = plain_w[i] * (0.25 if crowded else 1.0)
		if not is_equal_approx(lucky_w[i], expected):
			thinned = false
	_check(thinned, "Lucky Shapes x2 quarters every 4+ connection hex shape and nothing else")

	_finish()
