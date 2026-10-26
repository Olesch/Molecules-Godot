#!/usr/bin/env bash
# Prototype sweep: each line is  label|fun_sim args (cfg=/proto=) ; run on both boards with the human-like bot.
# usage: tests/sim/experiments.sh OUTDIR [games=240] [bot=4] [pressure=turns]
OUT="$1"; N="${2:-240}"; BOT="${3:-4}"; PR="${4:-turns}"
D="$(dirname "$0")"
while IFS='|' read -r label args; do
	[ -z "$label" ] && continue
	for board in square hex; do
		bash "$D/run_sim.sh" "$OUT" "${board}_${PR}_b${BOT}_$label" 16 "mode=solo bot=$BOT board=$board pressure=$PR games=$N hp=0 $args"
	done
done <<'LIST'
base|
fair4|proto=fair:reroll
fair8|proto=fair:reroll,fair_tries:8
pity2|proto=fair:reroll,fair_after:2,fair_tries:8
relief1|proto=relief:1,relief_sec:3
relief2|proto=relief:2,relief_sec:6
dissolve8|proto=dissolve:8
dissolve15|proto=dissolve:15
scrap6|proto=scrap:6
scrap10|proto=scrap:10
start12|cfg=turn_start:12,time_start:25
start12min5|cfg=turn_start:12,turn_min:5,time_start:25,time_min:8
lps3|proto=lps:3
strayNoCross|proto=stray_crowded:0
preview2|cfg=preview:2
preview3|cfg=preview:3
bombs60|cfg=bombs:0.6
bombmin3|cfg=bomb_min:3
blast2|cfg=blast_radius:2
pre5|cfg=preplaced:5
pre0|cfg=preplaced:0
open1|cfg=open_ends:1
xp05|cfg=xp_scale:0.5
nocards|proto=cards:false
combo|proto=fair:reroll,fair_tries:8,relief:1,dissolve:15 cfg=preview:2
LIST
