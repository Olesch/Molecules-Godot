#!/usr/bin/env bash
# Third sweep: combinations around the Loose-molecules option. usage: experiments3.sh OUTDIR [games=160]
OUT="$1"; N="${2:-160}"
D="$(dirname "$0")"
run() { for board in square hex; do bash "$D/run_sim.sh" "$OUT" "${board}_$3_b$2_$1" 16 "mode=solo bot=$2 board=$board pressure=$3 games=$N cap=300 hp=0 $4"; done; }
for spec in "open2|cfg=open_ends:2" "open1dis8|cfg=open_ends:1 proto=dissolve:8" "open1scrap4|cfg=open_ends:1 proto=scrap:4" "open1start12|cfg=open_ends:1,turn_start:12" "open1fairp2|cfg=open_ends:1,preview:2 proto=fair:reroll,fair_tries:8" "open1scrap4dis12|cfg=open_ends:1 proto=scrap:4,dissolve:12"; do
	run "${spec%%|*}" 4 turns "${spec#*|}"
done
for spec in "open2|cfg=open_ends:2" "open1dis8|cfg=open_ends:1 proto=dissolve:8" "open1scrap4|cfg=open_ends:1 proto=scrap:4"; do
	for b in 1 3; do run "${spec%%|*}" $b turns "${spec#*|}"; done
done
