#!/usr/bin/env python
"""Aggregates the JSON written by tests/fun_sim.gd (one file per shard).

usage: python -I tests/sim/fun_stats.py [--full] label=glob [label=glob ...]
Solo files give the per-label fun metrics, match files the versus metrics, vsfree files the attack rate.
Without --full only the one-line comparison table is printed.
"""
import glob
import json
import statistics
import sys


def load(pattern):
    games = []
    header = None
    for f in sorted(glob.glob(pattern)):
        d = json.load(open(f))
        header = d["header"]
        games.extend(d["games"])
    return header, games


def pct(values, q):
    if not values:
        return float("nan")
    v = sorted(values)
    k = min(len(v) - 1, max(0, int(round(q * (len(v) - 1)))))
    return v[k]


def mean(values):
    return sum(values) / len(values) if values else float("nan")


def solo_metrics(games):
    m = {}
    ns = [g["n"] for g in games]
    m["games"] = len(games)
    m["n_mean"] = mean(ns)
    m["n_med"] = statistics.median(ns)
    m["n_p10"] = pct(ns, 0.10)
    m["n_p90"] = pct(ns, 0.90)
    m["score"] = mean([g["score"] for g in games])
    m["short30"] = mean([1.0 if (g["lost"] and g["n"] < 30) else 0.0 for g in games])
    m["capped"] = mean([0.0 if g["lost"] else 1.0 for g in games])
    m["first_clear"] = mean([g["first_clear"] if g["first_clear"] >= 0 else g["n"] for g in games])
    m["no_clear_games"] = mean([1.0 if g["first_clear"] < 0 else 0.0 for g in games])
    total = sum(ns)
    # fill curve
    curve = {}
    for t in (10, 20, 40, 80, 160, 320):
        vals = [g["fill"][t] / 1000.0 for g in games if len(g["fill"]) > t]
        curve[t] = (mean(vals), len(vals))
    m["curve"] = curve
    m["above60"] = sum(1 for g in games for f in g["fill"] if f > 600) / total
    m["above80"] = sum(1 for g in games for f in g["fill"] if f > 800) / total
    m["mean_fill"] = sum(f for g in games for f in g["fill"]) / total / 1000.0
    # clears
    sizes = [c for g in games for c in g["clr"] if c > 0]
    m["clears_per10"] = 10.0 * len(sizes) / total
    dist = {}
    for s in sizes:
        k = s if s < 6 else 6
        dist[k] = dist.get(k, 0) + 1
    m["size_dist"] = {k: v / max(1, len(sizes)) for k, v in sorted(dist.items())}
    m["size_mean"] = mean(sizes)
    # droughts
    gaps = []
    per_game_max = []
    for g in games:
        last = 0
        mx = 0
        for i, c in enumerate(g["clr"]):
            if c > 0:
                gaps.append(i + 1 - last)
                mx = max(mx, i + 1 - last)
                last = i + 1
        tail = g["n"] - last
        if g["lost"] and tail > 0:
            gaps.append(tail)
            mx = max(mx, tail)
        per_game_max.append(mx)
    m["drought_mean"] = mean(gaps)
    m["drought_p90"] = pct(gaps, 0.9)
    m["drought_p99"] = pct(gaps, 0.99)
    m["drought_max"] = max(gaps) if gaps else 0
    m["drought_gamemax_mean"] = mean(per_game_max)
    # decisions
    for key in ("good", "prod"):
        allv = [v for g in games for v in g[key]]
        b = [0, 0, 0, 0]
        for v in allv:
            b[min(v, 3)] += 1
        m[key + "_b"] = [x / len(allv) for x in b]
        m[key + "_mean"] = mean(allv)
        # in the second half of life (fill>50%)
        late = [v for g in games for v, f in zip(g[key], g["fill"]) if f > 500]
        if late:
            bl = [0, 0, 0, 0]
            for v in late:
                bl[min(v, 3)] += 1
            m[key + "_b_late"] = [x / len(late) for x in bl]
    # dead hand
    dh = [v for g in games for v in g["dh"]]
    m["dead_hand"] = mean(dh)
    late_dh = [v for g in games for v, f in zip(g["dh"], g["fill"]) if f > 500]
    m["dead_hand_late"] = mean(late_dh)
    streaks = []
    for g in games:
        run = 0
        for v in g["dh"]:
            if v:
                run += 1
            elif run:
                streaks.append(run)
                run = 0
        if run:
            streaks.append(run)
    m["dh_streak_mean"] = mean(streaks)
    m["dh_streak_p90"] = pct(streaks, 0.9)
    m["dh_streak_max"] = max(streaks) if streaks else 0
    m["no_safe"] = mean([v for g in games for v in g["ns"]])
    # dead molecules over time
    bins = [(0, 10), (10, 20), (20, 40), (40, 80), (80, 160), (160, 320), (320, 600)]
    dead = {}
    for lo, hi in bins:
        perm = []
        fix = []
        for g in games:
            for i in range(lo, min(hi, len(g["occ"]))):
                if g["occ"][i] > 0:
                    perm.append(g["dperm"][i] / g["occ"][i])
                    fix.append(g["dfix"][i] / g["occ"][i])
        if perm:
            dead[(lo, hi)] = (mean(perm), mean(fix), len(perm))
    m["dead"] = dead
    allp = [g["dperm"][i] / g["occ"][i] for g in games for i in range(len(g["occ"])) if g["occ"][i] > 0]
    allf = [g["dfix"][i] / g["occ"][i] for g in games for i in range(len(g["occ"])) if g["occ"][i] > 0]
    m["dead_perm"] = mean(allp)
    m["dead_fix"] = mean(allf)
    # hopeless
    checked = sum(g["hp_checked"] for g in games)
    hop = sum(len(g["hopeless"]) for g in games)
    m["hopeless_rate"] = hop / checked if checked else float("nan")
    m["hopeless_checked_share"] = checked / total
    hg = [g for g in games if g["hopeless"]]
    m["hopeless_games"] = len(hg) / len(games)
    lost10 = 0
    recov = 0
    rem = []
    for g in hg:
        p = g["hopeless"][0][0]
        rem.append(g["n"] - p)
        if g["lost"] and g["n"] - p <= 10:
            lost10 += 1
        if any(c > 0 for c in g["clr"][p:p + 6]):
            recov += 1
    m["hopeless_lost10"] = lost10 / len(hg) if hg else float("nan")
    m["hopeless_recovered6"] = recov / len(hg) if hg else float("nan")
    m["hopeless_remaining"] = mean(rem)
    # bombs
    m["bomb_share"] = sum(g["bombs"] for g in games) / total
    bexp = sum(g["bexp"] for g in games)
    m["bomb_exploded_per_game"] = bexp / len(games)
    m["bomb_wipe_per_explosion"] = sum(g["bwipe"] for g in games) / bexp if bexp else 0.0
    resc = [r for g in games for r in g["rescues"]]
    m["rescues_per_game"] = len(resc) / len(games)
    m["rescue_drop"] = mean([(r[0] - r[1]) / 1000.0 for r in resc])
    # levels
    m["levelups_per100"] = 100.0 * sum(g["level"] - 1 for g in games) / total
    m["offers_per_game"] = mean([g["offers"] for g in games])
    gaps_lv = []
    for g in games:
        marks = g["lv_marks"]
        prev = 0
        for x in marks:
            gaps_lv.append(x - prev)
            prev = x
    m["lv_gap_mean"] = mean(gaps_lv)
    m["lv_gap_p90"] = pct(gaps_lv, 0.9)
    m["strays_per_100"] = 100.0 * sum(g["strays"] for g in games) / total
    return m


def f(x, p=1):
    return ("%." + str(p) + "f") % x


def print_full(label, header, m):
    print("\n=== %s  (%s %s %s size %s, cfg %s, proto %s) ===" % (label, header["bot"], header["board"], header["pressure"], header["size"], header["cfg"], header["proto"]))
    print("games %d | survival placements mean %s median %s p10 %s p90 %s | score %s" % (m["games"], f(m["n_mean"]), f(m["n_med"], 0), f(m["n_p10"], 0), f(m["n_p90"], 0), f(m["score"], 0)))
    print("died<30: %s%% | never died within cap: %s%% | first clear at %s (games w/o clear %s%%)" % (f(100 * m["short30"]), f(100 * m["capped"]), f(m["first_clear"]), f(100 * m["no_clear_games"])))
    print("fill curve (mean, n): " + ", ".join("p%d=%s(%d)" % (t, f(v[0], 2), v[1]) for t, v in m["curve"].items()))
    print("placements above 60%% fill %s%%, above 80%% %s%%, mean fill %s" % (f(100 * m["above60"]), f(100 * m["above80"]), f(m["mean_fill"], 2)))
    print("clears per 10 placements %s | mean molecule %s | sizes %s" % (f(m["clears_per10"], 2), f(m["size_mean"], 2), {k: round(v, 2) for k, v in m["size_dist"].items()}))
    print("drought (placements w/o clear): mean %s p90 %s p99 %s max %s | mean per-game max %s" % (f(m["drought_mean"]), f(m["drought_p90"], 0), f(m["drought_p99"], 0), m["drought_max"], f(m["drought_gamemax_mean"])))
    print("good options 0/1/2/3+: %s | (fill>50%%: %s) mean %s" % ([round(x, 3) for x in m["good_b"]], [round(x, 3) for x in m.get("good_b_late", [])], f(m["good_mean"])))
    print("productive options 0/1/2/3+: %s | (fill>50%%: %s) mean %s" % ([round(x, 3) for x in m["prod_b"]], [round(x, 3) for x in m.get("prod_b_late", [])], f(m["prod_mean"])))
    print("dead hand %s%% of placements (fill>50%%: %s%%) | streak mean %s p90 %s max %s | no safe placement for held atom %s%%" % (f(100 * m["dead_hand"]), f(100 * m["dead_hand_late"]), f(m["dh_streak_mean"]), f(m["dh_streak_p90"], 0), m["dh_streak_max"], f(100 * m["no_safe"])))
    print("dead-molecule share of atoms: permanent %s%% fixable %s%% | by placement:" % (f(100 * m["dead_perm"]), f(100 * m["dead_fix"])) + " ".join("[%d-%d: %s/%s]" % (k[0], k[1], f(100 * v[0], 0), f(100 * v[1], 0)) for k, v in m["dead"].items()))
    print("hopeless (fill>70%%, no clear in 6): %s%% of checked boards, %s%% of games; lost within 10 afterwards %s%%, recovered in 6 %s%%, placements left %s" % (f(100 * m["hopeless_rate"]), f(100 * m["hopeless_games"]), f(100 * m["hopeless_lost10"]), f(100 * m["hopeless_recovered6"]), f(m["hopeless_remaining"])))
    print("bombs: %s%% of atoms, %s exploded/game, %s wiped per explosion, %s rescues(>70%% fill)/game drop %s" % (f(100 * m["bomb_share"]), f(m["bomb_exploded_per_game"], 2), f(m["bomb_wipe_per_explosion"], 2), f(m["rescues_per_game"], 2), f(m["rescue_drop"], 2)))
    print("level-ups per 100 placements %s | offers/game %s | placements between level-ups mean %s p90 %s | strays per 100 placements %s" % (f(m["levelups_per100"], 2), f(m["offers_per_game"]), f(m["lv_gap_mean"]), f(m["lv_gap_p90"], 0), f(m["strays_per_100"])))


def match_metrics(games):
    m = {"games": len(games)}
    decided = [g for g in games if g["winner"] >= 0]
    m["draws"] = 1 - len(decided) / len(games)
    ts = [g["t"] for g in decided]
    m["len_mean"] = mean(ts)
    m["len_med"] = statistics.median(ts) if ts else float("nan")
    m["len_p10"] = pct(ts, 0.1)
    m["len_p90"] = pct(ts, 0.9)
    withfirst = [g for g in decided if g["first"] >= 0]
    m["first_wins"] = mean([1.0 if g["first"] == g["winner"] else 0.0 for g in withfirst])
    m["no_attack_matches"] = 1 - len(withfirst) / max(1, len(decided))
    m["first_t"] = mean([g["first_t"] for g in withfirst])
    m["first_t_p90"] = pct([g["first_t"] for g in withfirst], 0.9)
    tot_sent = sum(sum(g["sent"]) for g in decided)
    tot_time = sum(g["t"] * 2 for g in decided)
    m["attacks_per_min_each"] = 60.0 * tot_sent / tot_time if tot_time else float("nan")
    # more-sent-total wins
    more = [g for g in decided if g["sent"][0] != g["sent"][1]]
    m["more_sent_wins"] = mean([1.0 if (g["sent"][0] > g["sent"][1]) == (g["winner"] == 0) else 0.0 for g in more])
    # loser sends fewer
    m["sent_winner"] = mean([g["sent"][g["winner"]] for g in decided])
    m["sent_loser"] = mean([g["sent"][1 - g["winner"]] for g in decided])
    m["seat0_wins"] = mean([1.0 if g["winner"] == 0 else 0.0 for g in decided])
    m["level_end"] = mean([max(g["level"]) for g in decided])
    return m


def print_match(label, header, m):
    print("\n=== %s versus (%s %s cfg %s proto %s) ===" % (label, header["board"], header["size"], header["cfg"], header["proto"]))
    print("matches %d, draws(timeout 20min) %s%% | length s: mean %s median %s p10 %s p90 %s" % (m["games"], f(100 * m["draws"]), f(m["len_mean"], 0), f(m["len_med"], 0), f(m["len_p10"], 0), f(m["len_p90"], 0)))
    print("first sender wins %s%% (matches w/o any attack %s%%) | player with more total attacks wins %s%% | seat0 wins %s%%" % (f(100 * m["first_wins"]), f(100 * m["no_attack_matches"]), f(100 * m["more_sent_wins"]), f(100 * m["seat0_wins"])))
    print("time to first attack: mean %s s p90 %s s | attacks per minute per player %s | sent winner %s loser %s | final level %s" % (f(m["first_t"]), f(m["first_t_p90"]), f(m["attacks_per_min_each"], 2), f(m["sent_winner"]), f(m["sent_loser"]), f(m["level_end"])))


def vsfree_metrics(games):
    times = []
    first = []
    total = 0
    secs = 0
    for g in games:
        secs += g["n"] * 3.0
        for t, a in g["attacks"]:
            total += a
        if g["attacks"]:
            first.append(g["attacks"][0][0])
    return {"per_min": 60.0 * total / secs if secs else float("nan"), "first_mean": mean(first), "first_p90": pct(first, 0.9), "n": mean([g["n"] for g in games]), "score": mean([g["score"] for g in games])}


def main():
    args = sys.argv[1:]
    full = "--full" in args
    args = [a for a in args if not a.startswith("--")]
    rows = []
    for a in args:
        label, pattern = a.split("=", 1)
        header, games = load(pattern)
        if not games:
            print("no data for", label)
            continue
        if header["mode"] == "solo":
            m = solo_metrics(games)
            if full:
                print_full(label, header, m)
            rows.append((label, m))
        elif header["mode"] == "match":
            print_match(label, header, match_metrics(games))
        else:
            v = vsfree_metrics(games)
            print("\n=== %s vsfree: attacks/min %s, first attack at %s s (p90 %s), placements %s, score %s" % (label, f(v["per_min"], 2), f(v["first_mean"]), f(v["first_p90"]), f(v["n"]), f(v["score"])))
    if rows:
        print("\n%-34s %5s %7s %5s %5s %5s %6s %6s %6s %6s %6s %6s %6s %6s %6s %6s" % ("label", "games", "surv", "med", "p10", "p90", "<30%", "cap%", "clr/10", "dr_avg", "dr_p90", "dr_max", "DH%", "hopeless%", "lv/100", "dead%"))
        for label, m in rows:
            print("%-34s %5d %7s %5s %5s %5s %6s %6s %6s %6s %6s %6s %6s %6s %6s %6s" % (label[:34], m["games"], f(m["n_mean"]), f(m["n_med"], 0), f(m["n_p10"], 0), f(m["n_p90"], 0), f(100 * m["short30"], 0), f(100 * m["capped"], 0), f(m["clears_per10"], 2), f(m["drought_mean"]), f(m["drought_p90"], 0), m["drought_max"], f(100 * m["dead_hand"]), f(100 * m["hopeless_rate"], 0), f(m["levelups_per100"], 1), f(100 * (m["dead_perm"] + m["dead_fix"]), 0)))


if __name__ == "__main__":
    main()
