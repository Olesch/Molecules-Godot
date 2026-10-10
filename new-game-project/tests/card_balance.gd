extends SceneTree
## Card balance bot: drives the real Playfield with a greedy clear-first bot.
## Run: godot --headless --path new-game-project --script res://tests/card_balance.gd
## User args after "--": quick=1 (40 seeds), seeds=N, only=name1,name2 (filter rows by substring),
##   shard=k/n (run row subset, for parallel processes), nobase=1 (skip baseline row; deltas then unavailable)
## Reports survival (placements, cap 400) and score deltas vs baseline for solo and under attack.

const W := 8
const H := 8
const MOVE_CAP := 400
const ATTACK_EVERY := 6
const BIG_LEVEL := 1000000 ## keeps XP from ever levelling (no overlay)

var seeds := 150
var only: Array[String] = []
var scratch: Board
var shard_k := 0
var shard_n := 1

# Experiment rows: name -> stacks. Singles are generated from Cards.DEFS.
var combos := {
	"big_game + high_scorer x5": {"big_game": 1, "high_scorer": 5},
	"loose_ends + lifeline + stash": {"loose_ends": 1, "lifeline": 1, "stash": 1},
	"glass_cannon+shield+thick_skin x2+eff_cleaner x3": {"glass_cannon": 1, "shield": 1, "thick_skin": 2, "efficient_cleaner": 3},
	"overclock + combo_chain": {"overclock": 1, "combo_chain": 1},
	"loose_ends + big_game": {"loose_ends": 1, "big_game": 1},
	"two_hand + stash + reroll": {"two_hand": 1, "stash": 1, "reroll": 1},
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var skip_base := false
	for a in args:
		if a == "quick=1":
			seeds = 40
		elif a.begins_with("seeds="):
			seeds = int(a.substr(6))
		elif a.begins_with("only="):
			for s in a.substr(5).split(","):
				only.append(s)
		elif a.begins_with("shard="):
			var parts := a.substr(6).split("/")
			shard_k = int(parts[0])
			shard_n = int(parts[1])
		elif a == "nobase=1":
			skip_base = true
	var t0 := Time.get_ticks_msec()
	var rows: Array = [] # [name, stacks, versus_only]
	for id in Cards.all_ids():
		var d := Cards.get_def(id)
		var mx := int(d.max)
		var label := id if mx == 1 else "%s x%d" % [id, mx]
		rows.append([label, {id: mx}, bool(d.versus_only)])
	for k in combos.keys():
		var st: Dictionary = combos[k]
		var vo := false
		for id in st.keys():
			if Cards.get_def(id).versus_only:
				vo = true
		rows.append([k, st, vo])
	var base := {}
	if not skip_base:
		base = {"solo": run_cfg({}, false, 0), "vs2": run_cfg({}, true, 2), "vs3": run_cfg({}, true, 3)}
		print("BASELINE solo: %s" % fmt(base.solo))
		print("BASELINE atk2: %s" % fmt(base.vs2))
		print("BASELINE atk3: %s" % fmt(base.vs3))
	print("%-52s | %-22s | %-22s | %-22s" % ["card (survival d%, score d%, capped%)", "SOLO", "ATTACK n=2 /6pl", "ATTACK n=3 /6pl"])
	var ri := -1
	for r in rows:
		ri += 1
		if ri % shard_n != shard_k:
			continue
		var name: String = r[0]
		if not only.is_empty():
			var ok := false
			for o in only:
				if name.contains(o):
					ok = true
			if not ok:
				continue
		var cells: Array[String] = []
		var extra := ""
		for mode in ["solo", "vs2", "vs3"]:
			if mode == "solo" and r[2]:
				cells.append("-")
				continue
			var res := run_cfg(r[1], mode != "solo", 0 if mode == "solo" else int(mode.substr(2)))
			if base.is_empty():
				cells.append(fmt(res))
			else:
				var b: Dictionary = base[mode]
				cells.append("%+.0f%% / %+.0f%% / c%.0f%%" % [pct(res.mean, b.mean), pct(res.score, b.score), res.capped_pct])
			if res.has("extra") and res.extra != "":
				extra = res.extra
		print("%-52s | %-22s | %-22s | %-22s %s" % [name, cells[0], cells[1], cells[2], extra])
	print("total %.0fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


func pct(a: float, b: float) -> float:
	return 100.0 * (a - b) / maxf(b, 0.0001)


func fmt(r: Dictionary) -> String:
	return "mean=%.1f median=%d score=%.0f capped=%.0f%% clears/game=%.1f" % [r.mean, r.median, r.score, r.capped_pct, r.clears]


func make_progression(stacks: Dictionary) -> Progression:
	var p := Progression.new()
	p.level = BIG_LEVEL
	for id in stacks.keys():
		for i in int(stacks[id]):
			p.mods.add(id)
	return p


func run_cfg(stacks: Dictionary, versus: bool, atk: int) -> Dictionary:
	var moves: Array[int] = []
	var score_sum := 0.0
	var capped := 0
	var clears := 0
	var combo_clears := 0
	var tot_clear := 0
	for i in seeds:
		var pf := Playfield.new()
		pf.progression = make_progression(stacks)
		pf.versus = versus
		root.add_child(pf)
		pf.start(777 + i * 31)
		var res := play(pf, atk)
		moves.append(pf._placements)
		score_sum += pf.score
		if not pf.finished:
			capped += 1
		clears += res[0]
		combo_clears += res[1]
		pf.free()
	moves.sort()
	var s := 0
	for m in moves:
		s += m
	var out := {
		"mean": float(s) / seeds, "median": moves[seeds / 2], "score": score_sum / seeds,
		"capped_pct": 100.0 * capped / seeds, "clears": float(clears) / seeds, "extra": "",
	}
	if stacks.has("combo_chain"):
		out.extra = "combo_frac=%.0f%%" % (100.0 * combo_clears / maxf(1, clears))
	return out


## Returns [clears, combo_clears].
func play(pf: Playfield, atk: int) -> Array:
	var clears := 0
	var combos_n := 0
	var last_atk := -1
	scratch = Board.new(W, H)
	while not pf.finished and pf._placements < MOVE_CAP:
		pf.progression.pick_levels.clear()
		if atk > 0 and pf._placements > 0 and pf._placements % ATTACK_EVERY == 0 and last_atk != pf._placements:
			last_atk = pf._placements
			pf.receive_attack(atk)
		var pick := decide(pf)
		var pre_score := pf.score
		var pre_since := pf._since_clear
		pf._queue[0] = pick[1]
		pf.try_place(pick[0])
		if pf.score > pre_score:
			clears += 1
			if pre_since + 1 <= 3:
				combos_n += 1
	return [clears, combos_n]


# ---------------------------------------------------------------- bot

## Uses active cards, then returns [cell, mask] for the held atom.
func decide(pf: Playfield) -> Array:
	var mods := pf.mods
	var cur := evaluate(pf.board, pf._queue[0])
	if mods.has("two_hand") and pf._queue.size() >= 2:
		var alt := evaluate(pf.board, pf._queue[1])
		if alt[0] > cur[0] + 0.5:
			pf.swap_next()
			cur = alt
	if mods.has("stash") and cur[0] < 1000.0:
		if pf._stash == 0:
			if cur[0] < 2.0:
				pf.stash_swap()
				cur = evaluate(pf.board, pf._queue[0])
		else:
			var st := evaluate(pf.board, pf._stash)
			if st[0] > cur[0] + 2.0:
				pf.stash_swap()
				cur = st
	if mods.has("reroll") and pf._reroll_cd == 0 and cur[0] < 1000.0 and cur[0] < 1.0:
		pf.reroll_held()
		cur = evaluate(pf.board, pf._queue[0])
	return cur.slice(1)


func rotations(atom: int) -> Array[int]:
	var out: Array[int] = [atom]
	if Atoms.is_wild(atom):
		return out
	var a := atom
	for i in 3:
		a = Atoms.rotate_cw(a)
		if not out.has(a):
			out.append(a)
	return out


## Returns [score, cell, mask] of the best placement (clearing placements score >= 1000).
func evaluate(board: Board, atom: int) -> Array:
	var best_score := -1.0e9
	var best_p := Vector2i(-1, -1)
	var best_mask := atom
	var rots := rotations(atom)
	var snap := board.snapshot()
	scratch.max_open_ends = board.max_open_ends
	scratch.min_molecule = board.min_molecule
	var wild := Atoms.is_wild(atom)
	for y in H:
		for x in W:
			var p := Vector2i(x, y)
			if board.get_atom(p) != 0:
				continue
			for mask in rots:
				var live := 0
				var dead := 0
				var bonded := 0
				var gain := 0
				var killed := 0
				for dir in 4:
					var n := p + Atoms.OFFSETS[dir]
					var inb := board.in_bounds(n)
					var other := board.get_atom(n) if inb else 0
					var opp := 1 << Atoms.opposite(dir)
					if not wild and (mask & (1 << dir)):
						if not inb:
							dead += 1
						elif other == 0:
							live += 1
						elif (other & opp) or Atoms.is_wild(other):
							bonded += 1
						else:
							dead += 1
					if inb and other != 0 and not Atoms.is_wild(other) and (other & opp):
						if wild or (mask & (1 << dir)):
							gain += 1
						else:
							killed += 1
				var s: float
				var blocked := false
				if live + dead <= board.max_open_ends and (bonded > 0 or (wild and gain > 0)):
					scratch.load_snapshot(snap)
					var cleared := scratch.place(p, mask)
					if not cleared.is_empty():
						s = 1000.0 + scratch.last_molecule_size * 20.0 + (cleared.size() - scratch.last_molecule_size) * 5.0
						if s > best_score:
							best_score = s
							best_p = p
							best_mask = mask
						continue
					if live == 0 and dead == 0:
						blocked = true # sealed group too small to clear (Big Game)
				s = bonded * 3.0 + gain * 3.0 - dead * 8.0 - killed * 8.0 - live * 1.5
				if blocked:
					s -= 12.0
				var empties := 0
				for dir in 4:
					if board.is_empty(p + Atoms.OFFSETS[dir]):
						empties += 1
				s += empties * 0.1
				if s > best_score:
					best_score = s
					best_p = p
					best_mask = mask
	return [best_score, best_p, best_mask]
