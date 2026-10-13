extends RefCounted
## Headless re-implementation of one Playfield (solo or versus) on top of the real Board, Danger,
## Modifiers and Progression classes: try_place / _celebrate / _danger_step / incoming are ported 1:1,
## minus all drawing. Prototype rules live in `proto` (see the PROTO flags below) so candidate
## changes can be measured without touching scripts/.
##
## PROTO flags (all optional):
##   fair: "reroll"  window without a live-extending atom => redraw the new atom (fair_tries, fair_after streak)
##   relief: N       each clear delays the next stray by N placements (turn-based) / relief_sec seconds (timed)
##   dissolve: N     a permanently dead molecule dissolves after N placements
##   scrap: K        player can delete one atom every K placements (Scrap action)
##   lps, step_size, sec_step   pressure curve (levels per step, placements and seconds per step)
##   stray_crowded: float       crowded-shape multiplier for strays only
##   xp_a, xp_b                 XP needed = (xp_a + xp_b * level) * xp_scale
##   cards: false               level-ups give no cards
##   catchup: k      versus: incoming gap * (1 + k * max(0, fill - 0.5)) so the player behind gets breathing room
##   send_cap: n     versus: max stray atoms pending at once

const Geom = preload("res://tests/sim/geom.gd")
const SimDanger = preload("res://tests/sim/sim_danger.gd")

const SOLO_ORDER := ["loose_ends", "two_hand", "lifeline", "stash", "long_view", "reroll", "lucky_shapes", "tidy_start", "combo_chain", "overcharge", "salvage", "mini_bombs", "demolition", "joker_supply", "fast_learner", "high_scorer", "hot_potato", "overclock", "big_game"]
const VERSUS_ORDER := ["shield", "thick_skin", "efficient_cleaner", "loose_ends", "two_hand", "lifeline", "long_view", "counterstrike", "stash", "reroll", "lucky_shapes", "heavy_hitter", "combo_chain", "gardener", "overcharge", "salvage", "mini_bombs", "joker_supply", "fast_learner", "high_scorer", "demolition", "glass_cannon", "hot_potato", "overclock", "big_game"]

var cfg := GameConfig.new()
var versus := false
var proto: Dictionary = {}
var geom: Geom
var topo: Topology
var board: Board
var prog := Progression.new()
var qrng := RandomNumberGenerator.new()
var frng := RandomNumberGenerator.new()
var queue: Array[int] = []
var danger: SimDanger
var incoming: SimDanger
var pending := 0
var attack_charge := 0.0
var stash := 0
var reroll_cd := 0
var lifeline_cd := 0
var scrap_cd := 0
var placements := 0
var since_clear := 99
var score := 0
var finished := false
var time := 0.0
var offers := 0
var level_up_marks: Array[int] = [] ## placements at which a level-up happened
var strays := {}
var last_cell := Vector2i(-1, -1)
var attack_out := 0 ## attacks produced since the caller last reset it
var strays_dropped := 0
var fair_streak := 0
var dead_age := {}
var timed: bool:
	get:
		return cfg.pressure() == GameConfig.PRESSURE_TIMED
var mods: Modifiers:
	get:
		return prog.mods


func setup(seed_value: int) -> void:
	qrng.seed = seed_value
	frng.seed = seed_value * 7919 + 13
	topo = Topology.for_id(cfg.board_id())
	var dims := cfg.board_dims()
	board = Board.new(dims.x, dims.y, topo)
	geom = Geom.new(topo, dims.x, dims.y)
	_apply_rules()
	var block := cfg.get_value("preplaced_layout") == "block"
	board.preplace(mods.preplaced_count(cfg.get_int("block_atoms" if block else "preplaced")), qrng, block)
	if proto.has("stray_crowded"):
		board.shape_weights = Modifiers.new().shape_weights(topo, float(proto.stray_crowded))
	danger = SimDanger.new()
	danger.base_interval = cfg.get_int("turn_start")
	danger.min_interval = cfg.get_int("turn_min")
	danger.first_grace = cfg.get_int("turn_grace")
	danger.base_seconds = cfg.get_float("time_start")
	danger.min_seconds = cfg.get_float("time_min")
	danger.first_grace_seconds = cfg.get_float("time_grace")
	danger.double_above_level = cfg.get_int("double_level")
	danger.levels_per_step = int(proto.get("lps", Danger.LEVELS_PER_STEP))
	danger.step_size = int(proto.get("step_size", 1))
	danger.seconds_per_step = float(proto.get("sec_step", Danger.SECONDS_PER_STEP))
	danger.timed = timed
	incoming = SimDanger.new()
	incoming.timed = true
	incoming.count_override = 1
	if danger_active():
		danger.start(board, prog.level, frng)
	queue.clear()
	_fit_queue()


func _apply_rules() -> void:
	board.max_open_ends = mods.max_open_ends(cfg.get_int("open_ends"))
	board.min_molecule = mods.min_molecule(cfg.get_int("min_molecule"))
	board.blast_radius = cfg.get_int("blast_radius")
	board.bomb_chance = cfg.get_float("bombs")
	board.wild_chance = cfg.get_float("wild_chance")
	board.min_bomb_connections = cfg.get_int("bomb_min")
	board.shape_weights = Modifiers.new().shape_weights(topo, cfg.get_float("crowded"))


func danger_active() -> bool:
	return not versus and cfg.pressure() != GameConfig.PRESSURE_NONE


func _roll_atom() -> int:
	return Atoms.random_atom(qrng, mods.bomb_chance(cfg.get_float("bombs")), mods.wild_chance(cfg.get_float("wild_chance")), mods.shape_weights(topo, cfg.get_float("crowded")), mods.min_bomb_connections(topo, cfg.get_int("bomb_min")), topo)


## The atom entering the queue. With the fair prototype it is redrawn while the whole window
## (what is already queued plus the newcomer) cannot extend any live open end.
func _new_atom() -> int:
	var a := _roll_atom()
	if String(proto.get("fair", "")) == "":
		return a
	var cells := board.snapshot()
	var cl := geom.classify(board)
	var live: PackedByteArray = cl[2]
	if geom.live_ends(cells, live) == 0:
		fair_streak = 0
		return a
	for q in queue:
		if geom.can_extend(cells, live, q):
			fair_streak = 0
			return a
	if geom.can_extend(cells, live, a):
		fair_streak = 0
		return a
	fair_streak += 1
	if fair_streak < int(proto.get("fair_after", 1)):
		return a
	for t in int(proto.get("fair_tries", 4)):
		var b := _roll_atom()
		if geom.can_extend(cells, live, b):
			return b
	return a


func _fit_queue() -> void:
	var target := mods.queue_size(cfg.get_int("preview"))
	while queue.size() < target:
		queue.append(_new_atom())
	while queue.size() > target:
		queue.pop_back()


## The next n atoms (queue first, then what the generator will roll). Only exact without the fair prototype.
func peek_atoms(n: int) -> Array[int]:
	var out: Array[int] = queue.duplicate()
	if out.size() >= n:
		return out.slice(0, n)
	var saved := qrng.state
	var saved_proto := proto
	proto = {}
	while out.size() < n:
		out.append(_roll_atom())
	proto = saved_proto
	qrng.state = saved
	return out


# ------------------------------------------------------------------ actions

func rotate_held() -> void:
	if Atoms.is_wild(queue[0]):
		return
	queue[0] = topo.rotate_cw(queue[0])


func stash_swap() -> void:
	if finished or not mods.has(Cards.STASH):
		return
	if stash == 0:
		stash = queue[0]
		queue.pop_front()
		_fit_queue()
	else:
		var held := queue[0]
		queue[0] = stash
		stash = held


func reroll_held() -> void:
	if finished or not mods.has(Cards.REROLL) or reroll_cd > 0:
		return
	queue[0] = _roll_atom()
	reroll_cd = cfg.get_int("reroll_cooldown")


func swap_next() -> void:
	if finished or not mods.has(Cards.TWO_HAND) or queue.size() < 2:
		return
	var held := queue[0]
	queue[0] = queue[1]
	queue[1] = held


func scrap_ready() -> bool:
	return int(proto.get("scrap", 0)) > 0 and scrap_cd <= 0 and not finished


func scrap(p: Vector2i) -> void:
	if not scrap_ready() or board.get_atom(p) == 0:
		return
	board.remove_atom(p)
	scrap_cd = int(proto.get("scrap", 0))


func receive_attack(amount: int) -> void:
	if finished or amount <= 0:
		return
	pending += int(ceil(amount * mods.incoming_mult()))
	if proto.has("send_cap"):
		pending = mini(pending, int(proto.send_cap))
	_announce_incoming()


func _incoming_gap() -> float:
	var gap := mods.incoming_gap_seconds(cfg.get_float("incoming_seconds"))
	if proto.has("catchup"):
		gap *= 1.0 + float(proto.catchup) * maxf(0.0, board.fill_ratio() - 0.5)
	return gap


func _announce_incoming() -> void:
	if not versus:
		return
	if pending <= 0:
		incoming.ghosts.clear()
		return
	if not incoming.ghosts.is_empty():
		return
	incoming.seconds_override = _incoming_gap()
	incoming.schedule_next(board, prog.level, frng)


## Lets time pass: runs the versus incoming clock or the timed solo clock.
func advance_time(dt: float) -> Dictionary:
	var info := _new_info()
	time += dt
	if finished:
		return info
	if versus:
		if pending <= 0:
			incoming.ghosts.clear()
			return info
		if incoming.ghosts.is_empty():
			_announce_incoming()
			return info
		var drops := incoming.advance(dt, board, frng)
		if drops.is_empty():
			if incoming.ghosts.is_empty():
				_announce_incoming()
			return info
		for d in drops:
			_land_incoming(d, info)
		if not finished:
			incoming.ghosts.clear()
			_announce_incoming()
	elif timed and danger_active():
		var drops := danger.advance(dt, board, frng)
		if not drops.is_empty():
			_drop_strays(drops, info)
			if not finished:
				danger.schedule_next(board, prog.level, frng)
	_post_hooks()
	_do_picks()
	return info


func _new_info() -> Dictionary:
	return {"mols": [], "blasted": 0, "points": 0, "bombs_exploded": 0, "dropped": 0, "attack": 0, "lost": false, "levelups": 0}


func _land_incoming(d: Dictionary, info: Dictionary) -> void:
	var cell: Vector2i = d.cell
	pending = maxi(0, pending - 1)
	if board.is_empty(cell):
		var cleared := board.place(cell, d.mask)
		if cleared.is_empty():
			strays[cell] = true
			info.dropped += 1
			strays_dropped += 1
		else:
			_celebrate(cleared, info)
	if mods.has(Cards.COUNTERSTRIKE):
		attack_out += 1
		info.attack += 1
	if board.is_full():
		_lose(info)


func _drop_strays(drops: Array[Dictionary], info: Dictionary) -> void:
	for d in drops:
		var cell: Vector2i = d.cell
		if not board.is_empty(cell):
			continue
		var cleared := board.place(cell, d.mask)
		if cleared.is_empty():
			info.dropped += 1
			strays_dropped += 1
			strays[cell] = true
		else:
			_celebrate(cleared, info)
	if board.is_full():
		_lose(info)


func _lose(info: Dictionary) -> void:
	finished = true
	info.lost = true


## Port of Playfield.try_place. `mask` replaces the held atom (the bot already rotated it).
func place(p: Vector2i, mask: int) -> Dictionary:
	var info := _new_info()
	queue[0] = mask
	var was_bomb := Atoms.is_bomb(mask)
	var cleared := board.place(p, mask)
	last_cell = p
	queue.pop_front()
	queue.append(_new_atom())
	placements += 1
	since_clear += 1
	reroll_cd = maxi(0, reroll_cd - 1)
	lifeline_cd = maxi(0, lifeline_cd - 1)
	scrap_cd = maxi(0, scrap_cd - 1)
	info["bomb"] = was_bomb
	if cleared.is_empty():
		if board.is_full():
			_lose(info)
	else:
		_celebrate(cleared, info)
	if danger_active() and not finished:
		danger.relocate_at(p, board, frng)
		if not timed:
			var drops := danger.tick(board, frng)
			if not drops.is_empty():
				_drop_strays(drops, info)
				if not finished:
					danger.schedule_next(board, prog.level, frng)
	if versus and not finished:
		var moved := incoming.relocate_at(p, board, frng)
		if moved.x < 0 and incoming.ghosts.is_empty() and pending > 0:
			_announce_incoming()
	_post_hooks()
	_apply_lifeline()
	_do_picks()
	return info


func _apply_lifeline() -> void:
	if finished or not mods.has(Cards.LIFELINE) or lifeline_cd > 0:
		return
	if board.fill_ratio() >= Playfield.LIFELINE_FILL and not Atoms.is_wild(queue[0]):
		queue[0] = Atoms.WILD
		lifeline_cd = Playfield.LIFELINE_COOLDOWN


func _celebrate(cleared: Array[Vector2i], info: Dictionary) -> void:
	var molecule := board.last_molecule_size
	var blasted := cleared.size() - molecule
	var combo := since_clear <= 3
	var points := mods.scaled_points(molecule, blasted, combo, cfg.get_int("max_points"))
	score += points
	info.mols.append(molecule)
	info.blasted += blasted
	info.points += points
	info.bombs_exploded += board.last_exploded.size()
	var per_attack := cfg.get_int("attack_points")
	attack_charge += mods.attack_charge(points)
	var outgoing := int(floor(attack_charge / per_attack + 0.000001))
	attack_charge -= outgoing * per_attack
	attack_charge = maxf(attack_charge, 0.0)
	var cancel_mult := mods.cancel_mult()
	var cancelled := mini(int(ceil(outgoing * cancel_mult)), pending)
	pending -= cancelled
	if pending <= 0:
		incoming.ghosts.clear()
	outgoing -= mini(outgoing, int(ceil(cancelled / cancel_mult)))
	if outgoing > 0:
		attack_out += outgoing
		info.attack += outgoing
	since_clear = 0
	if mods.has(Cards.GARDENER):
		_remove_random_stray()
	if mods.has(Cards.OVERCHARGE) and molecule >= 4:
		queue.insert(0, Atoms.random_shape(qrng, mods.shape_weights(topo, cfg.get_float("crowded")), topo) | Atoms.BOMB)
		_fit_queue()
	# Prototype: a clear buys breathing room.
	if danger_active() and proto.has("relief"):
		if timed:
			danger.countdown += float(proto.get("relief_sec", 0.0))
		else:
			danger.countdown += float(proto.relief)
	var gained := _add_xp(points)
	if gained > 0:
		info.levelups += gained
		for i in gained:
			level_up_marks.append(placements)


func _xp_needed(level: int) -> int:
	var scale := cfg.get_float("xp_scale")
	if proto.has("xp_a"):
		return maxi(1, roundi((float(proto.xp_a) + float(proto.get("xp_b", 12)) * level) * scale))
	return Progression.xp_needed(level, scale)


func _add_xp(points: int) -> int:
	prog.xp += roundi(points * mods.xp_mult())
	var gained := 0
	while prog.xp >= _xp_needed(prog.level):
		prog.xp -= _xp_needed(prog.level)
		prog.level += 1
		prog.pick_levels.append(prog.level)
		gained += 1
	return gained


func _remove_random_stray() -> void:
	var live: Array[Vector2i] = []
	for c in strays.keys():
		if board.get_atom(c) != 0:
			live.append(c)
	strays.clear()
	for c in live:
		strays[c] = true
	if live.is_empty():
		return
	var victim := live[frng.randi_range(0, live.size() - 1)]
	board.remove_atom(victim)
	strays.erase(victim)


func _do_picks() -> void:
	while prog.has_pending_pick() and not finished:
		if not bool(proto.get("cards", true)):
			prog.pick_levels.pop_front()
			continue
		var offer := prog.roll_offer(frng, versus)
		if offer.is_empty():
			prog.pick_levels.pop_front()
			continue
		offers += 1
		prog.pick(_choose_card(offer))
		_apply_rules()
		if proto.has("stray_crowded"):
			board.shape_weights = Modifiers.new().shape_weights(topo, float(proto.stray_crowded))
		_fit_queue()


func _choose_card(offer: Array[String]) -> String:
	var order: Array = VERSUS_ORDER if versus else SOLO_ORDER
	var best := offer[0]
	var best_rank := 999
	for id in offer:
		var r: int = order.find(id)
		if r < 0:
			r = 500
		if r < best_rank:
			best_rank = r
			best = id
	return best


## Prototype rules that act on dead molecules.
func _post_hooks() -> void:
	var after := int(proto.get("dissolve", 0))
	if after <= 0 or finished:
		return
	var cl := geom.classify(board)
	var new_age := {}
	for grp in cl[3]:
		var min_age := 1 << 30
		for i in grp:
			var a: int = int(dead_age.get(i, 0)) + 1
			new_age[i] = a
			min_age = mini(min_age, a)
		if min_age >= after:
			for i in grp:
				board.remove_atom(geom.cell_of(i))
				new_age.erase(i)
	dead_age = new_age
