extends "res://tests/test_base.gd"
## Run: godot --headless --path new-game-project --script res://tests/test_progression.gd


func _mods(d: Dictionary) -> Modifiers:
	var m := Modifiers.new()
	for k in d.keys():
		for i in d[k]:
			m.add(k)
	return m


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _init() -> void:
	# Defs
	var ok := true
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		if str(d.name) == "" or str(d.desc) == "" or int(d.max) < 1 or int(d.rarity) < 0 or int(d.rarity) > 2:
			ok = false
			print("bad def ", id)
		if d.risky and str(d.downside) == "":
			ok = false
	_check(ok and Cards.all_ids().size() == 26, "all defs well formed (26)")
	_check(Cards.describe("demolition", 2).owned == 2, "describe owned")

	# Stacking
	var m := Modifiers.new()
	_check(m.add("long_view") and m.add("long_view") and m.add("long_view") and m.add("long_view") and not m.add("long_view"), "long_view caps at 4")
	_check(not m.add("nope"), "unknown id rejected")
	_check(m.count("long_view") == 4 and m.has("long_view") and not m.has("stash"), "count/has")
	var m2 := Modifiers.from_dict({"long_view": 9, "bogus": 3, "stash": 1, "demolition": -2})
	_check(m2.count("long_view") == 4 and m2.count("stash") == 1 and not m2.has("bogus") and not m2.has("demolition"), "from_dict clamps")
	_check(Modifiers.from_dict(m.to_dict()).stacks == m.stacks, "dict round trip")
	m.clear()
	_check(m.stacks.is_empty(), "clear")

	# Derived
	m = Modifiers.new()
	_check(m.queue_size() == 2 and m.garbage_cap() == Scoring.GARBAGE_PER_TURN and m.min_molecule() == 2, "defaults")
	_check(is_equal_approx(m.bomb_chance(), Atoms.BOMB_CHANCE) and is_equal_approx(m.wild_chance(), Atoms.WILD_CHANCE), "base chances")
	m = _mods({"long_view": 2, "overclock": 1})
	_check(m.queue_size() == 3, "queue 2+2-1")
	_check(_mods({"overclock": 1}).queue_size() == 1, "queue overclock leaves no preview")
	_check(_mods({"long_view": 4}).queue_size() == 6, "queue with 4 long views")
	_check(m.min_bomb_connections() == 4 and _mods({"mini_bombs": 1}).min_bomb_connections() == 3 and _mods({"mini_bombs": 3}).min_bomb_connections() == 1, "mini bombs lower the bomb threshold")
	_check(is_equal_approx(_mods({"demolition": 3, "hot_potato": 1}).bomb_chance(), Atoms.BOMB_CHANCE + 0.15 + 0.08), "bomb chance")
	_check(is_equal_approx(_mods({"joker_supply": 2}).wild_chance(), Atoms.WILD_CHANCE + 0.06), "wild chance")
	_check(is_equal_approx(_mods({"hot_potato": 1}).wild_chance(), maxf(0.0, Atoms.WILD_CHANCE - 0.07)), "wild with hot potato")
	var sw := _mods({"lucky_shapes": 2}).shape_weights()
	_check(is_equal_approx(sw[sw.size() - 1], Atoms.SHAPE_WEIGHTS[Atoms.SHAPE_WEIGHTS.size() - 1] * 0.25) and sw[0] == Atoms.SHAPE_WEIGHTS[0], "shape weights")
	_check(is_equal_approx(_mods({"high_scorer": 3, "overclock": 1}).score_mult(), 1.3 * 1.15), "score mult")
	_check(is_equal_approx(_mods({"heavy_hitter": 2, "glass_cannon": 1}).attack_mult(), 1.2 * 1.5), "attack mult")
	_check(_mods({"thick_skin": 2}).garbage_cap() == maxi(1, Scoring.GARBAGE_PER_TURN - 2), "garbage cap")
	_check(is_equal_approx(_mods({"glass_cannon": 1}).incoming_mult(), 1.25), "incoming mult")
	_check(is_equal_approx(_mods({"efficient_cleaner": 3}).cancel_mult(), 2.5), "cancel mult")
	_check(is_equal_approx(_mods({"fast_learner": 5}).xp_mult(), 1.5), "xp mult")
	_check(_mods({"tidy_start": 2}).preplaced_count(5) == 0 and _mods({"tidy_start": 1}).preplaced_count(5) == 2, "preplaced min 0")
	_check(_mods({"loose_ends": 1}).max_open_ends() == 1 and m.max_open_ends() == 0, "open ends")
	var bg := _mods({"big_game": 1})
	_check(bg.min_molecule() == 3 and bg.big_game_mult() == 2.0, "big game")

	# Points / attack
	var base := Modifiers.new()
	_check(base.scaled_points(3, 0, false) == 6 and base.scaled_points(0, 5, true) == 0, "base points")
	_check(base.scaled_attack(3, 2) == 4 and base.scaled_attack(0, 2) == 0, "base attack")
	var sal := _mods({"salvage": 1})
	_check(sal.scaled_points(3, 2, false) == 10 and sal.scaled_attack(3, 2) == 6, "salvage")
	_check(_mods({"combo_chain": 1}).scaled_points(3, 0, true) == 9 and _mods({"combo_chain": 1}).scaled_points(3, 0, false) == 6, "combo")
	_check(bg.scaled_points(3, 0, false) == 12, "big game x2")
	_check(_mods({"overclock": 1}).scaled_points(5, 0, false) == 17, "overclock 15*1.15 rounds")
	_check(_mods({"heavy_hitter": 1}).scaled_attack(11, 0) == 11, "attack ceil no float error")
	_check(_mods({"heavy_hitter": 1}).scaled_attack(3, 0) == 3, "attack ceil 2.2 -> 3")
	_check(_mods({"glass_cannon": 1}).scaled_attack(4, 0) == 5, "glass cannon ceil 4.5")

	# XP
	var p := Progression.new()
	_check(Progression.xp_needed(1) == 32 and Progression.xp_needed(2) == 44, "xp curve")
	_check(p.add_xp(10) == 0 and p.xp == 10 and not p.has_pending_pick(), "xp accumulates")
	_check(p.add_xp(22) == 1 and p.level == 2 and p.xp == 0 and p.pick_levels == [2], "level up")
	p = Progression.new()
	_check(p.add_xp(32 + 44 + 56 + 5) == 3 and p.level == 4 and p.xp == 5 and p.pick_levels == [2, 3, 4], "multi level jump")
	p.mods.add("fast_learner")
	p.mods.add("fast_learner")
	p.xp = 0
	p.add_xp(10)
	_check(p.xp == 12, "xp mult applied")
	p = Progression.new()
	p.add_xp(200)
	var pending := p.pick_levels.size()
	_check(not p.pick("bogus") and p.pick_levels.size() == pending, "invalid pick keeps pending")
	_check(p.pick("demolition") and p.pick_levels.size() == pending - 1 and p.mods.count("demolition") == 1, "pick consumes")
	var q := Progression.new()
	_check(not q.pick("demolition"), "pick with nothing pending fails")
	p.reset()
	_check(p.level == 1 and p.xp == 0 and p.mods.stacks.is_empty() and p.pick_levels.is_empty(), "reset")

	# Offers
	var rng := RandomNumberGenerator.new()
	var bad := ""
	var super_l5 := 0
	var ids := Cards.all_ids()
	for s in 3000:
		rng.seed = s
		var pr := Progression.new()
		pr.pick_levels = [1 + s % 12]
		var versus := s % 2 == 0
		for i in s % 9:
			pr.mods.add(ids[rng.randi() % ids.size()])
		var lvl: int = pr.pick_levels[0]
		var offer := pr.roll_offer(rng, versus)
		var seen := {}
		var owned_rare := pr._owned_with(Cards.Rarity.RARE)
		var owned_super := pr._owned_with(Cards.Rarity.SUPER)
		for id in offer:
			var d := Cards.get_def(id)
			if seen.has(id):
				bad = "dup"
			seen[id] = true
			if pr.mods.count(id) >= int(d.max):
				bad = "maxed " + id
			if d.versus_only and not versus:
				bad = "versus " + id
			if d.rarity == Cards.Rarity.RARE and owned_rare >= Progression.MAX_RARE_CARDS:
				bad = "rare cap"
			if d.rarity == Cards.Rarity.SUPER and (owned_super > 0 or lvl < 5):
				bad = "super " + id
		if offer.size() > 3:
			bad = "size"
		if lvl % 5 == 0 and owned_super == 0:
			var has_s := false
			for id in offer:
				if Cards.get_def(id).rarity == Cards.Rarity.SUPER:
					has_s = true
			if not has_s:
				bad = "no guaranteed super"
			else:
				super_l5 += 1
		if lvl < 3 and offer.size() != 3:
			bad = "early size"
		if bad != "":
			print("offer failure seed ", s, ": ", bad)
			break
	_check(bad == "", "roll_offer invariants over 3000 seeds")
	_check(super_l5 > 0, "guaranteed supers observed")

	var early := true
	var sup_seen := false
	for s in 2000:
		rng.seed = s
		var pr := Progression.new()
		pr.pick_levels = [2]
		if pr.roll_offer(rng, false).size() != 3:
			early = false
		pr.pick_levels = [6]
		for id in pr.roll_offer(rng, true):
			if Cards.get_def(id).rarity == Cards.Rarity.SUPER:
				sup_seen = true
	_check(early, "always 3 early")
	_check(sup_seen, "supers can appear at level 6")
	_check(Progression.new().roll_offer(rng, false).size() == 3, "offer with no pending uses level")

	# Persistence
	var path := "user://test_progress.json"
	p = Progression.new()
	p.add_xp(150)
	p.pick("demolition")
	_check(p.save_to(path) == OK, "save ok")
	var l := Progression.load_from(path)
	_check(l.level == p.level and l.xp == p.xp and l.pick_levels == p.pick_levels and l.mods.stacks == p.mods.stacks, "save/load round trip")
	_write(path, "{{{ not json garbage")
	_check(Progression.load_from(path).level == 1, "corrupt file -> fresh")
	_write(path, '{"level":"x","xp":[1],"mods":{"demolition":99,"zzz":1},"pick_levels":["a",3,2.0]}')
	var g := Progression.load_from(path)
	_check(g.level == 1 and g.mods.count("demolition") == 3 and g.pick_levels == [3, 2], "hand-edited garbage tolerated")
	_write(path, "[1,2,3]")
	_check(Progression.load_from(path).level == 1, "wrong json type -> fresh")
	_check(Progression.load_from("user://does_not_exist.json").level == 1, "missing file -> fresh")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	_finish(true)
