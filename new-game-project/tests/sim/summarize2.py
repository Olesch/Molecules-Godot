#!/usr/bin/env python
"""Builds the combined JSON + markdown tables from a run directory (labels written by baseline2.sh / run2_extra.sh).
usage: python -I tests/sim/summarize2.py RUNDIR OUT.json
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fun_stats as fs  # noqa: E402


def labels(rundir):
    s = set()
    for p in glob.glob(os.path.join(rundir, "*.json")):
        m = re.match(r"(.*)_\d+\.json$", os.path.basename(p))
        if m:
            s.add(m.group(1))
    return sorted(s)


def main():
    rundir, out = sys.argv[1], sys.argv[2]
    res = {"solo": [], "versus": []}
    for lab in labels(rundir):
        header, games = fs.load(os.path.join(rundir, lab + "_*.json"))
        if not games:
            continue
        if header["mode"] == "solo":
            m = fs.jsonable(fs.solo_metrics(games))
            for k in ("curve", "size_dist", "good_b", "prod_b", "good_b_late", "prod_b_late"):
                m.pop(k, None)
            res["solo"].append({"label": lab, "board": header["board"], "pressure": header["pressure"], "bot": header["bot"], "cfg": header["cfg"], "proto": header["proto"], "metrics": m})
        elif header["mode"] == "match":
            m = fs.jsonable(fs.match_metrics(games))
            res["versus"].append({"label": lab, "board": header["board"], "bot": header["bot"], "cfg": header["cfg"], "metrics": m})
    import json
    json.dump(res, open(out, "w"), indent=1)
    print("rows: solo %d versus %d" % (len(res["solo"]), len(res["versus"])))
    print("\n| label | n | surv mean/med/p90 | min@3s mean (med) | min@4s | clr/10 | drought mean/p90 | DH% | perm%/fix% | lvl-ups/game | lvl mean | L5% | scraps/g | hopeless% | 5+ share% | 7+ share% | 5+/game | 5+/100pl | big gap mean/p90/max | no-5+ games% | pts share 5+% |")
    print("|" + "---|" * 21)
    for r in res["solo"]:
        m = r["metrics"]
        b = m["big"]
        print("| %s | %d | %.0f / %.0f / %.0f | %.1f (%.1f) | %.1f | %.2f | %.1f / %.0f | %.1f | %.0f / %.0f | %.1f | %.1f | %.0f | %.1f | %.0f | %.0f | %.0f | %.2f | %.2f | %.0f / %.0f / %.0f | %.0f | %.0f |" % (
            r["label"], m["games"], m["n_mean"], m["n_med"], m["n_p90"], m["min3_mean"], m["min3_med"], m["min4_mean"], m["clears_per10"], m["drought_mean"], m["drought_p90"], 100 * m["dead_hand"], 100 * m["dead_perm"], 100 * m["dead_fix"], m["levelups_per_game"], m["level_mean"], 100 * m["reach5"], m["scraps_per_game"], 100 * (m["hopeless_rate"] or 0), 100 * b["share5"], 100 * b["share7"], b["big_per_game"], b["big_per100"], b["big_gap_mean"] or 0, b["big_gap_p90"] or 0, b["big_gap_max"] or 0, 100 * b["no_big_games"], 100 * b["points_share5"]))
    print("\n| versus label | matches | min mean/med/p90/max | >10min% | <2min% | 4-8min% | first attack med s | atk/min/player | no-attack% | first-sender wins% | more-strays-loses% | strays/player | scraps/player | 5+ share% | 5+/player | no-5+% |")
    print("|" + "---|" * 16)
    for r in res["versus"]:
        m = r["metrics"]
        b = m.get("big", {})
        print("| %s | %d | %.1f / %.1f / %.1f / %.1f | %.0f | %.0f | %.0f | %.0f | %.2f | %.0f | %.0f | %.0f | %.1f | %.1f | %.0f | %.2f | %.0f |" % (
            r["label"], m["games"], m["min_mean"], m["min_med"], m["min_p90"], m["min_max"], 100 * m["over10"], 100 * m["under2"], 100 * m["in4_8"], m["first_t_med"] or 0, m["attacks_per_min_each"], 100 * m["no_attack_matches"], 100 * m["first_wins"], 100 * (m["more_strays_loses"] or 0), m["strays_per_player"], m["scraps_per_player"], 100 * b.get("share5", 0), b.get("big_per_game", 0), 100 * b.get("no_big_games", 0)))


if __name__ == "__main__":
    main()
