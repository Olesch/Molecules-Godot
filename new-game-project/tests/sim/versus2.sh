#!/usr/bin/env bash
# Versus rows (two human-like bots, current defaults unless overridden).
# usage: tests/sim/versus2.sh OUTDIR MATCHES BOARD label1 "extra args1" [label2 "extra args2" ...]
OUT="$1"; N="$2"; BOARD="$3"; shift 3
D="$(dirname "$0")"
while [ $# -ge 2 ]; do
	bash "$D/run_sim.sh" "$OUT" "m_${BOARD}_$1" 16 "mode=match board=$BOARD games=$N $2"
	shift 2
done
