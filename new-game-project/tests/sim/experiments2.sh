#!/usr/bin/env bash
# Second sweep: dead-molecule remedies and combinations, several bots/pressures.
# usage: tests/sim/experiments2.sh OUTDIR [games=240]
OUT="$1"; N="${2:-160}"
D="$(dirname "$0")"
run() { # label bot pressure args
	for board in square hex; do
		bash "$D/run_sim.sh" "$OUT" "${board}_$3_b$2_$1" 16 "mode=solo bot=$2 board=$board pressure=$3 games=$N cap=300 hp=0 $4"
	done
}
for spec in "dissolve4|proto=dissolve:4" "dissolve6|proto=dissolve:6" "dissolve10|proto=dissolve:10" "scrap3|proto=scrap:3" "open1dis12|cfg=open_ends:1 proto=dissolve:12" "open1fair|cfg=open_ends:1 proto=fair:reroll,fair_tries:8" "dis8fair|proto=dissolve:8,fair:reroll,fair_tries:8" "dis8fairp2|proto=dissolve:8,fair:reroll,fair_tries:8 cfg=preview:2" "dis8relief|proto=dissolve:8,relief:1" "dis6xp07|proto=dissolve:6 cfg=xp_scale:0.7"; do
	run "${spec%%|*}" 4 turns "${spec#*|}"
done
for spec in "base|" "dissolve8|proto=dissolve:8" "open1|cfg=open_ends:1" "scrap6|proto=scrap:6"; do
	for b in 1 2 3; do run "${spec%%|*}" $b turns "${spec#*|}"; done
done
for spec in "base|" "dissolve8|proto=dissolve:8" "open1|cfg=open_ends:1" "dis8fair|proto=dissolve:8,fair:reroll,fair_tries:8" "relief|proto=relief:1,relief_sec:3"; do
	run "${spec%%|*}" 4 timed "${spec#*|}"
done
