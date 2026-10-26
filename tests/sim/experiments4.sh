#!/usr/bin/env bash
# Fourth sweep: full metrics for the recommended settings and XP pacing. usage: experiments4.sh OUTDIR [games=160]
OUT="$1"; N="${2:-160}"
D="$(dirname "$0")"
run() { for board in square hex; do bash "$D/run_sim.sh" "$OUT" "${board}_$3_b$2_$1" 16 "mode=solo bot=$2 board=$board pressure=$3 games=$N cap=300 hp=$5 $4"; done; }
run open2full 4 turns "cfg=open_ends:2" 3
run open1full 4 turns "cfg=open_ends:1" 3
run open2xp5 4 turns "cfg=open_ends:2,xp_scale:0.5" 0
run open2xpc 4 turns "cfg=open_ends:2 proto=xp_a:8,xp_b:6" 0
run open1xp5 4 turns "cfg=open_ends:1,xp_scale:0.5" 0
run open2 4 timed "cfg=open_ends:2" 0
run open1 4 timed "cfg=open_ends:1" 0
