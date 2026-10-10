extends SceneTree
## Headless balance simulator. Uses only Board / Atoms / Scoring.
## Run: godot --headless --path new-game-project --script res://tests/balance_sim.gd
## Optional user args after "--": solo=N vs=N quick=1 (tweak table with fewer seeds)

const W := 8
const H := 8
const PREPLACED := 10
const QUEUE_SIZE := 4
const MOVE_CAP := 400

const BASE_WEIGHTS: Array[float] = [1, 1, 1, 1, 1] ## 1-conn, straight, bent, T, cross

# Active tweakable settings (local copies of the formulas).
var atk_offset := 0 ## attack = size - 1 + atk_offset + blasted (min 0) ; baseline 0 => n-1
var garbage_cap := 5
var weights: Array[float] = BASE_WEIGHTS.duplicate()


func _init() -> void:
	var solo_n := 200
	var vs_n := 100
	var quick := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("solo="):
			solo_n = int(a.substr(5))
		elif a.begins_with("vs="):
			vs_n = int(a.substr(3))
		elif a == "quick=1":
			quick = true
	var t0 := Time.get_ticks_msec()
	print("=== BASELINE (attack n-1, cap 5, equal shape weights) ===")
	run_config("baseline", solo_n, vs_n, true)
	print("baseline time %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not quick:
		var sn := 150
		var vn := 80
		print("\n=== TWEAKS (solo %d seeds, vs %d seeds) ===" % [sn, vn])
		var cfgs := [
			["atk n-2", -1, 5, BASE_WEIGHTS],
			["atk n", 1, 5, BASE_WEIGHTS],
			["cap 3", 0, 3, BASE_WEIGHTS],
			["cap 8", 0, 8, BASE_WEIGHTS],
			["fewer cross", 0, 5, [1.5, 1.5, 1.5, 1.0, 0.4] as Array[float]],
			["more bent", 0, 5, [1.0, 1.0, 2.5, 1.0, 0.5] as Array[float]],
			["more bent+n", 1, 5, [1.0, 1.0, 2.5, 1.0, 0.5] as Array[float]],
			["fewer cross,n-2", -1, 5, [1.5, 1.5, 1.5, 1.0, 0.4] as Array[float]],
			["fewer cross,n,cap3", 1, 3, [1.5, 1.5, 1.5, 1.0, 0.4] as Array[float]],
		]
		for c in cfgs:
			atk_offset = c[1]
			garbage_cap = c[2]
			weights = (c[3] as Array[float]).duplicate()
			run_config(c[0], sn, vn, false)
		print("total time %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


# ---------------------------------------------------------------- atoms

func rand_atom(rng: RandomNumberGenerator) -> int:
	if rng.randf() < Atoms.WILD_CHANCE:
		return Atoms.WILD
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	var idx := 0
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			idx = i
			break
		idx = i
	var atom: int = Atoms.SHAPES[idx]
	if rng.randf() < Atoms.BOMB_CHANCE:
		atom |= Atoms.BOMB
	return atom


func attack_amount(size: int, blasted: int) -> int:
	if size <= 0:
		return 0
	return maxi(0, size - 1 + atk_offset + blasted)


# ---------------------------------------------------------------- bot

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


## Returns [cell, mask] of the best placement.
func choose(board: Board, atom: int) -> Array:
	var best_score := -1.0e9
	var best_p := Vector2i(-1, -1)
	var best_mask := atom
	var rots := rotations(atom)
	var snap := board.snapshot()
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
				var maybe_clear := (live == 0 and dead == 0 and (bonded > 0 or (wild and gain > 0)))
				if maybe_clear:
					var b := Board.new(W, H)
					b.load_snapshot(snap)
					var cleared := b.place(p, mask)
					if not cleared.is_empty():
						s = 1000.0 + b.last_molecule_size * 20.0 + (cleared.size() - b.last_molecule_size) * 5.0
						if s > best_score:
							best_score = s
							best_p = p
							best_mask = mask
						continue
				s = bonded * 3.0 + gain * 3.0 - dead * 8.0 - killed * 8.0 - live * 1.5
				# Prefer to keep ends pointing into roomy areas: small bonus for empty neighbours.
				var empties := 0
				for dir in 4:
					var n2 := p + Atoms.OFFSETS[dir]
					if board.is_empty(n2):
						empties += 1
				s += empties * 0.1
				if s > best_score:
					best_score = s
					best_p = p
					best_mask = mask
	return [best_p, best_mask]


# ---------------------------------------------------------------- player state

class Seat:
	var board: Board
	var queue: Array[int] = []
	var qrng := RandomNumberGenerator.new()
	var grng := RandomNumberGenerator.new()
	var pending := 0
	var score := 0
	var moves := 0
	var attacks_sent := 0
	var dead := false


func new_seat(sim, seed_value: int) -> Seat:
	var s := Seat.new()
	s.qrng.seed = seed_value
	s.grng.seed = seed_value * 7919 + 13
	s.board = Board.new(W, H)
	s.board.preplace(PREPLACED, s.qrng)
	for i in QUEUE_SIZE:
		s.queue.append(sim.rand_atom(s.qrng))
	return s


## Plays one turn. Returns outgoing attack (after cancel). Sets dead if board full.
## sizes (optional) collects molecule sizes.
func take_turn(s: Seat, sizes: Dictionary) -> int:
	var pick := choose(s.board, s.queue[0])
	var p: Vector2i = pick[0]
	var mask: int = pick[1]
	s.moves += 1
	var cleared := s.board.place(p, mask)
	s.queue.pop_front()
	s.queue.append(rand_atom(s.qrng))
	if cleared.is_empty():
		if s.pending > 0:
			var landing := mini(s.pending, garbage_cap)
			s.pending -= landing
			s.board.add_garbage(landing, s.grng)
		if s.board.is_full():
			s.dead = true
		return 0
	var molecule := s.board.last_molecule_size
	var blasted := cleared.size() - molecule
	s.score += Scoring.points(molecule)
	var key := clampi(molecule, 2, 5)
	sizes[key] = sizes.get(key, 0) + 1
	var outgoing := attack_amount(molecule, blasted)
	var cancelled := mini(outgoing, s.pending)
	s.pending -= cancelled
	outgoing -= cancelled
	s.attacks_sent += outgoing
	return outgoing


# ---------------------------------------------------------------- experiments

func run_config(label: String, solo_n: int, vs_n: int, verbose: bool) -> void:
	# Solo
	var moves_list: Array[int] = []
	var score_sum := 0.0
	var sizes := {}
	var capped := 0
	for seed_i in solo_n:
		var s := new_seat(self, 1000 + seed_i)
		while not s.dead and s.moves < MOVE_CAP:
			take_turn(s, sizes)
		moves_list.append(s.moves)
		score_sum += s.score
		if not s.dead:
			capped += 1
	moves_list.sort()
	var msum := 0
	for m in moves_list:
		msum += m
	var total_mol := 0
	for k in sizes:
		total_mol += sizes[k]
	var frac := ""
	for k in [2, 3, 4, 5]:
		frac += " size%s%d=%.0f%%" % ["+" if k == 5 else "", k, 100.0 * sizes.get(k, 0) / maxf(1, total_mol)]
	var solo_line := "solo mean=%.1f median=%d max=%d score=%.0f capped=%d/%d |%s" % [
		float(msum) / solo_n, moves_list[solo_n / 2], moves_list[-1], score_sum / solo_n, capped, solo_n, frac]

	# Versus
	var lens: Array[int] = []
	var wins := [0, 0, 0]
	var atk_total := 0
	var short := 0
	for seed_i in vs_n:
		var a := new_seat(self, 5000 + seed_i * 2)
		var b := new_seat(self, 5001 + seed_i * 2)
		var sides := [a, b]
		var dummy := {}
		var turn := 0
		var winner := -1
		while winner < 0 and turn < MOVE_CAP * 2:
			var who: int = turn % 2
			var me: Seat = sides[who]
			var foe: Seat = sides[1 - who]
			var out := take_turn(me, dummy)
			foe.pending += out
			turn += 1
			if me.dead:
				winner = 1 - who
		# game length in "turns" = rounds (moves per player)
		var rounds := (turn + 1) / 2
		lens.append(rounds)
		if winner >= 0:
			wins[winner] += 1
		else:
			wins[2] += 1
		atk_total += a.attacks_sent + b.attacks_sent
		if rounds <= 15:
			short += 1
	lens.sort()
	var lsum := 0
	for l in lens:
		lsum += l
	var vs_line := "vs mean_rounds=%.1f median=%d max=%d seatA/B/draw=%d/%d/%d atk/game=%.1f end<=15=%.0f%%" % [
		float(lsum) / vs_n, lens[vs_n / 2], lens[-1], wins[0], wins[1], wins[2], float(atk_total) / vs_n, 100.0 * short / vs_n]
	print("[%s]" % label)
	print("  " + solo_line)
	print("  " + vs_line)
