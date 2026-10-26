extends SceneTree
## Fun-metrics simulation harness. Plays many full games with bots and dumps per-game records as JSON;
## tests/sim/fun_stats.py turns them into the report tables.
##
## Run:  godot --headless --path . --script res://tests/fun_sim.gd -- mode=solo bot=3 board=hex \
##         pressure=turns games=100 shard=0/4 out=C:/tmp/x.json [cap=600] [seed0=1000] [cfg=preview:2,bombs:0.15] \
##         [proto=fair:reroll,relief:1] [hp=2] [sec=3.0]
## mode:  solo   one bot plays a solo game (pressure turns|timed|none)
##        match  two human-like bots (kind 4) play a symmetric versus match (real attack mapping, 3 s per placement)
##        vsfree versus rules but no opponent: how fast does a human-like bot generate attacks
## bot:   1 random, 2 greedy 1-ply, 3 beam search, 4 human-like (search + noise + limited attention)
## cfg:   GameConfig overrides  id:value,id:value     proto: SimGame prototype flags (see sim/sim_game.gd)
## hp:    hopeless-board check every Nth placement above 70% fill (0 = off)

const SimGame = preload("res://tests/sim/sim_game.gd")
const Bots = preload("res://tests/sim/bots.gd")

var mode := "solo"
var bot_kind := 3
var games := 50
var shard_k := 0
var shard_n := 1
var out_path := ""
var cap := 600
var seed0 := 1000
var hp_every := 2
var sec_per_place := 3.0
var cfg_over: Dictionary = {}
var proto: Dictionary = {}
var bw: Dictionary = {} ## bot heuristic weights, see Bots.setup
var board_id := "square"
var pressure := "turns"
var size := "8"


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		var v := kv[1]
		match kv[0]:
			"mode":
				mode = v
			"bot":
				bot_kind = int(v)
			"games":
				games = int(v)
			"shard":
				var parts := v.split("/")
				shard_k = int(parts[0])
				shard_n = int(parts[1])
			"out":
				out_path = v
			"cap":
				cap = int(v)
			"seed0":
				seed0 = int(v)
			"hp":
				hp_every = int(v)
			"sec":
				sec_per_place = float(v)
			"board":
				board_id = v
			"pressure":
				pressure = v
			"size":
				size = v
			"cfg":
				cfg_over = _parse_kv(v)
			"proto":
				proto = _parse_kv(v)
			"bw":
				bw = _parse_kv(v)
	var t0 := Time.get_ticks_msec()
	var records: Array = []
	for i in games:
		if i % shard_n != shard_k:
			continue
		var seed_value := seed0 + i * 7
		match mode:
			"solo":
				records.append(play_solo(seed_value))
			"match":
				records.append(play_match(seed_value))
			"vsfree":
				records.append(play_vsfree(seed_value))
	var header := {"mode": mode, "bot": bot_kind, "board": board_id, "pressure": pressure, "size": size, "cfg": cfg_over, "proto": proto, "bw": bw, "sec": sec_per_place, "secs": (Time.get_ticks_msec() - t0) / 1000.0}
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"header": header, "games": records}))
		f.close()
	else:
		print(JSON.stringify(header))
	print("done %d games in %.1fs" % [records.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


func _parse_kv(text: String) -> Dictionary:
	var d := {}
	for pair in text.split(","):
		var kv := pair.split(":", true, 1)
		if kv.size() < 2:
			continue
		var s := kv[1]
		if s == "true" or s == "false":
			d[kv[0]] = (s == "true")
		elif s.is_valid_float():
			d[kv[0]] = s.to_float()
		else:
			d[kv[0]] = s
	return d


func make_game(versus: bool) -> RefCounted:
	var gm = SimGame.new()
	gm.versus = versus
	gm.proto = proto.duplicate()
	gm.cfg.set_value("board", board_id)
	gm.cfg.set_value("board_size", size)
	gm.cfg.set_value("pressure", pressure)
	for k in cfg_over.keys():
		var v = cfg_over[k]
		var s: String = str(int(v)) if (typeof(v) == TYPE_FLOAT and float(int(v)) == v) else str(v)
		if not gm.cfg.set_value(k, s):
			push_error("bad cfg %s:%s" % [k, s])
	return gm


# ------------------------------------------------------------------ solo

func play_solo(seed_value: int) -> Dictionary:
	var gm = make_game(false)
	gm.setup(seed_value)
	var bot = Bots.new()
	bot.setup(gm, bot_kind, seed_value, bw)
	var oracle = Bots.new()
	oracle.setup(gm, 3, seed_value, bw)
	var fill: Array = []
	var clr: Array = []
	var blasted: Array = []
	var good: Array = []
	var prod: Array = []
	var dh: Array = []
	var ns: Array = []
	var dperm: Array = []
	var dfix: Array = []
	var occ: Array = []
	var hopeless: Array = [] # [placement, fill_permille, bomb_in_window]
	var hp_checked := 0
	var hp_counter := 0
	var bombs_placed := 0
	var bombs_exploded := 0
	var bomb_wiped := 0
	var rescues: Array = [] # [fill_before, fill_after, wiped] for bomb clears above 70%
	var strays := 0
	var lost := false
	var first_clear := -1
	var scrap_gain: Array = [] # permanent-dead atoms before - after each scrap
	var scrap_at: Array = [] # placement count at each scrap
	while not gm.finished and gm.placements < cap:
		if bot_kind >= 2 and gm.scrap_ready():
			var before: int = gm.geom.classify(gm.board)[0]
			var sinfo: Dictionary = bot.scrap_if_useful()
			if not sinfo.is_empty():
				scrap_gain.append(before - int(gm.geom.classify(gm.board)[0]))
				scrap_at.append(gm.placements)
				if not gm.finished and pressure == "timed":
					gm.advance_time(sec_per_place)
				lost = gm.finished
				continue
		var cells: PackedInt32Array = gm.board.snapshot()
		var f: float = gm.board.fill_ratio()
		var used := 0
		for c in cells:
			if c != 0:
				used += 1
		fill.append(int(round(f * 1000.0)))
		occ.append(used)
		var cl: Array = gm.geom.classify(gm.board)
		dperm.append(cl[0])
		dfix.append(cl[1])
		var live: PackedByteArray = cl[2]
		var opt: Array = gm.geom.options(cells, gm.queue[0])
		good.append(mini(opt[0], 99))
		prod.append(mini(opt[1], 99))
		ns.append(1 if opt[0] == 0 else 0)
		var ends: int = gm.geom.live_ends(cells, live)
		var hand_ok := ends == 0
		if not hand_ok:
			for q in gm.queue:
				if gm.geom.can_extend(cells, live, q):
					hand_ok = true
					break
		dh.append(0 if hand_ok else 1)
		if hp_every > 0 and f > 0.7:
			hp_counter += 1
			if hp_counter % hp_every == 0:
				hp_checked += 1
				if not oracle.can_clear_within(6, 8):
					var bomb_in := false
					for q in gm.queue:
						if Atoms.is_bomb(q):
							bomb_in = true
					hopeless.append([gm.placements, int(round(f * 1000.0)), 1 if bomb_in else 0])
		var pick: Array = bot.choose()
		var info: Dictionary = gm.place(pick[0], pick[1])
		var mol_total := 0
		for m in info.mols:
			mol_total = maxi(mol_total, m)
		clr.append(mol_total)
		blasted.append(info.blasted)
		if mol_total > 0 and first_clear < 0:
			first_clear = gm.placements
		if info.bomb:
			bombs_placed += 1
		bombs_exploded += info.bombs_exploded
		if info.blasted > 0:
			bomb_wiped += info.blasted
			if f > 0.7:
				rescues.append([int(round(f * 1000.0)), int(round(gm.board.fill_ratio() * 1000.0)), info.blasted])
		if not gm.finished and pressure == "timed":
			var ti: Dictionary = gm.advance_time(sec_per_place)
			if not ti.mols.is_empty():
				# a stray closed a molecule on its own: count as a clear for the next placement slot
				clr[clr.size() - 1] = maxi(clr[clr.size() - 1], 0)
		lost = gm.finished
	return {
		"seed": seed_value, "n": gm.placements, "lost": lost, "score": gm.score, "level": gm.prog.level, "offers": gm.offers,
		"first_clear": first_clear, "fill": fill, "clr": clr, "bl": blasted, "good": good, "prod": prod, "dh": dh, "ns": ns,
		"dperm": dperm, "dfix": dfix, "occ": occ, "hopeless": hopeless, "hp_checked": hp_checked,
		"bombs": bombs_placed, "bexp": bombs_exploded, "bwipe": bomb_wiped, "rescues": rescues,
		"scraps": gm.scraps, "csz": gm.clear_sizes, "scrap_gain": scrap_gain, "scrap_at": scrap_at, "lv_marks": gm.level_up_marks, "strays": gm.strays_dropped, "cards": gm.prog.mods.to_dict(),
	}


# ------------------------------------------------------------------ versus

func play_match(seed_value: int) -> Dictionary:
	var gms: Array = []
	var bots: Array = []
	for k in 2:
		var gm = make_game(true)
		gm.setup(seed_value)
		gm.frng.seed = seed_value * 31 + k
		gms.append(gm)
		var b = Bots.new()
		b.setup(gm, 5 if bot_kind == 5 else 4, seed_value + k * 1000, bw)
		bots.append(b)
	var jitter := RandomNumberGenerator.new()
	jitter.seed = seed_value + 5
	var t := 0.0
	var dt := 0.5
	var next_act := [jitter.randf_range(1.0, 4.0), jitter.randf_range(1.0, 4.0)]
	var sent := [0, 0]
	var first_attacker := -1
	var first_attack_t := -1.0
	var winner := -2
	var end_t := 0.0
	var attack_log: Array = [[], []]
	var max_fill := [0.0, 0.0]
	while winner == -2:
		t += dt
		for k in 2:
			var gm = gms[k]
			if gm.finished:
				continue
			gm.advance_time(dt)
			_flush_attacks(gms, k, t, sent, attack_log)
			if first_attacker < 0 and sent[k] > 0:
				first_attacker = k
				first_attack_t = t
			if gm.finished:
				winner = 1 - k
				break
		if winner != -2:
			break
		for k in 2:
			var gm = gms[k]
			if t >= next_act[k]:
				next_act[k] = t + maxf(1.0, sec_per_place + jitter.randf_range(-1.0, 1.0))
				if not bots[k].scrap_if_useful().is_empty():
					continue
				var pick: Array = bots[k].choose()
				gm.place(pick[0], pick[1])
				_flush_attacks(gms, k, t, sent, attack_log)
				if first_attacker < 0 and sent[k] > 0:
					first_attacker = k
					first_attack_t = t
				max_fill[k] = maxf(max_fill[k], gm.board.fill_ratio())
				if gm.finished:
					winner = 1 - k
					break
		if t >= 1200.0 and winner == -2:
			winner = -1
	end_t = t
	return {
		"seed": seed_value, "t": end_t, "winner": winner, "first": first_attacker, "first_t": first_attack_t,
		"sent": sent, "attacks": attack_log, "n": [gms[0].placements, gms[1].placements], "scraps": [gms[0].scraps, gms[1].scraps], "csz": [gms[0].clear_sizes, gms[1].clear_sizes], "strays": [gms[0].strays_dropped, gms[1].strays_dropped], "score": [gms[0].score, gms[1].score],
		"fill": [gms[0].board.fill_ratio(), gms[1].board.fill_ratio()], "level": [gms[0].prog.level, gms[1].prog.level],
	}


func _flush_attacks(gms: Array, k: int, t: float, sent: Array, log: Array) -> void:
	var a: int = gms[k].attack_out
	if a > 0:
		gms[k].attack_out = 0
		sent[k] += a
		log[k].append([t, a])
		gms[1 - k].receive_attack(a)


func play_vsfree(seed_value: int) -> Dictionary:
	var gm = make_game(true)
	gm.setup(seed_value)
	var bot = Bots.new()
	bot.setup(gm, 4, seed_value, bw)
	var log: Array = []
	while not gm.finished and gm.placements < cap:
		if not bot.scrap_if_useful().is_empty():
			continue
		var pick: Array = bot.choose()
		gm.place(pick[0], pick[1])
		if gm.attack_out > 0:
			log.append([gm.placements * sec_per_place, gm.attack_out])
			gm.attack_out = 0
	return {"seed": seed_value, "n": gm.placements, "score": gm.score, "attacks": log, "level": gm.prog.level, "lost": gm.finished}
