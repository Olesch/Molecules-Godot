#!/usr/bin/env bash
# Second wave: big-molecule bot variant, solo option variants, versus tuning rows.
# usage: tests/sim/run2_extra.sh OUTDIR
OUT="$1"; D="$(dirname "$0")"
V="mode=solo bot=4 board=square pressure=turns games=60 hp=0"
bash "$D/run_sim.sh" "$OUT" x_b5_square_turns 16 "mode=solo bot=5 board=square pressure=turns games=100 hp=4"
bash "$D/run_sim.sh" "$OUT" x_b5_hex_turns 16 "mode=solo bot=5 board=hex pressure=turns games=100 hp=4"
bash "$D/run_sim.sh" "$OUT" x_b4_hex_turns_csz 16 "mode=solo bot=4 board=hex pressure=turns games=60 hp=0"
bash "$D/run_sim.sh" "$OUT" x_b4_square_turns_csz 16 "$V"
bash "$D/run_sim.sh" "$OUT" x_bombs0 16 "$V cfg=bombs:0"
bash "$D/run_sim.sh" "$OUT" x_bombs06 16 "$V cfg=bombs:0.6"
bash "$D/run_sim.sh" "$OUT" x_open1 16 "$V cfg=open_ends:1"
bash "$D/run_sim.sh" "$OUT" x_open2 16 "$V cfg=open_ends:2"
bash "$D/run_sim.sh" "$OUT" x_xp1 16 "$V cfg=xp_scale:1"
bash "$D/run_sim.sh" "$OUT" x_xp035 16 "$V cfg=xp_scale:0.35"
bash "$D/run_sim.sh" "$OUT" x_scrap4 16 "$V cfg=scrap_cooldown:4"
bash "$D/run_sim.sh" "$OUT" x_scrap12 16 "$V cfg=scrap_cooldown:12"
for board in square hex; do
bash "$D/versus2.sh" "$OUT" 40 $board base "" b5 "bot=5" atk10 "cfg=attack_points:10" atk20 "cfg=attack_points:20" scrap12 "cfg=scrap_cooldown:12" gap4 "cfg=incoming_seconds:4" size6 "cfg=board_size:6" noscrap "cfg=scrap_cooldown:0"
done
