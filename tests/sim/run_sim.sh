#!/usr/bin/env bash
# Runs tests/fun_sim.gd in parallel shards and waits.
# usage: tests/sim/run_sim.sh OUTDIR LABEL SHARDS "fun_sim args..."
#   e.g. tests/sim/run_sim.sh /tmp/out sq_turns_b3 8 "mode=solo bot=3 board=square pressure=turns games=96"
# Results: OUTDIR/LABEL_<k>.json ; then: python -I tests/sim/fun_stats.py --full LABEL=OUTDIR/LABEL_*.json
OUT="$1"; LABEL="$2"; SHARDS="$3"; ARGS="$4"
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT"
rm -f "$OUT/${LABEL}"_*.json
for ((k = 0; k < SHARDS; k++)); do
	godot --headless --path "$PROJECT" --script res://tests/fun_sim.gd -- $ARGS shard=$k/$SHARDS out="$OUT/${LABEL}_$k.json" > "$OUT/${LABEL}_$k.log" 2>&1 &
done
wait
