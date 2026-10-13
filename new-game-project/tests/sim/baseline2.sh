#!/usr/bin/env bash
# Baseline 2 (scrap on, xp 0.5, current defaults): 2 boards x 2 pressures x bots 2/3/4 (+ random sanity row)
# plus the same bots with scrap off for comparison.
# usage: tests/sim/baseline2.sh OUTDIR [games=80] [part=main|noscrap|random|all]
OUT="$1"; N="${2:-80}"; PART="${3:-all}"
D="$(dirname "$0")"
if [ "$PART" = main ] || [ "$PART" = all ]; then
for board in square hex; do for pr in turns timed; do for b in 2 3 4; do
	bash "$D/run_sim.sh" "$OUT" "${board}_${pr}_b$b" 16 "mode=solo bot=$b board=$board pressure=$pr games=$N hp=4"
done; done; done
fi
if [ "$PART" = random ] || [ "$PART" = all ]; then
for board in square hex; do for pr in turns timed; do
	bash "$D/run_sim.sh" "$OUT" "${board}_${pr}_b1" 15 "mode=solo bot=1 board=$board pressure=$pr games=30 hp=4"
done; done
fi
if [ "$PART" = noscrap ] || [ "$PART" = all ]; then
for board in square hex; do for pr in turns timed; do for b in 3 4; do
	bash "$D/run_sim.sh" "$OUT" "ns_${board}_${pr}_b$b" 16 "mode=solo bot=$b board=$board pressure=$pr games=$N hp=4 cfg=scrap_cooldown:0"
done; done; done
fi
