#!/usr/bin/env bash
# Baseline fun metrics for the current game: 2 boards x 2 pressure modes x 4 bots.
# usage: tests/sim/baseline.sh OUTDIR [games=320] [extra fun_sim args]
OUT="$1"; N="${2:-320}"; EXTRA="$3"
D="$(dirname "$0")"
for board in square hex; do for pr in turns timed; do for b in 1 2 3 4; do
	bash "$D/run_sim.sh" "$OUT" "${board}_${pr}_b$b" 16 "mode=solo bot=$b board=$board pressure=$pr games=$N $EXTRA"
done; done; done
