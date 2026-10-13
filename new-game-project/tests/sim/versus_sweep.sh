#!/usr/bin/env bash
# Versus sweep: symmetric human-like bot matches. usage: versus_sweep.sh OUTDIR [matches=96]
OUT="$1"; N="${2:-96}"
D="$(dirname "$0")"
for board in square hex; do
while IFS='|' read -r label args; do
	[ -z "$label" ] && continue
	bash "$D/run_sim.sh" "$OUT" "m_${board}_$label" 16 "mode=match board=$board games=$N $args"
done <<'LIST'
base|
atk15|cfg=attack_points:15
atk40|cfg=attack_points:40
gap3|cfg=incoming_seconds:3
gap8|cfg=incoming_seconds:8
catchup2|proto=catchup:2
cap6|proto=send_cap:6
catchup_atk40|proto=catchup:2 cfg=attack_points:40
open1|cfg=open_ends:1
fair|proto=fair:reroll,fair_tries:8
LIST
done
bash "$D/run_sim.sh" "$OUT" "free_square" 16 "mode=vsfree board=square games=96 cap=120"
bash "$D/run_sim.sh" "$OUT" "free_hex" 16 "mode=vsfree board=hex games=96 cap=120"
