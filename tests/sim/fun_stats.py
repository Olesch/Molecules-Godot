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
    # time: placements plus scraps are player actions, 3 s / 4 s each
    acts = [g["n"] + g.get("scraps", 0) for g in games]
    m["min3_mean"] = mean(acts) * 3.0 / 60.0
    m["min3_med"] = statistics.median(acts) * 3.0 / 60.0
    m["min3_p90"] = pct(acts, 0.9) * 3.0 / 60.0
    m["min4_mean"] = mean(acts) * 4.0 / 60.0
    m["min4_med"] = statistics.median(acts) * 4.0 / 60.0
    m["levelups_per_game"] = mean([g["level"] - 1 for g in games])
    m["level_mean"] = mean([g["level"] for g in games])
    m["level_med"] = statistics.median([g["level"] for g in games])
    m["reach5"] = mean([1.0 if g["level"] >= 5 else 0.0 for g in games])
    m["reach10"] = mean([1.0 if g["level"] >= 10 else 0.0 for g in games])
    m["scraps_per_game"] = mean([g.get("scraps", 0) for g in games])
    m["scraps_per100"] = 100.0 * sum(g.get("scraps", 0) for g in games) / total
    gains = [x for g in games for x in g.get("scrap_gain", [])]
    m["scrap_gain_mean"] = mean(gains)
    m["scrap_gain_ge2"] = mean([1.0 if x >= 2 else 0.0 for x in gains]) if gains else float("nan")
    m["cap_share"] = m["capped"]
    m["big"] = big_metrics([[c for c in g["clr"] if c > 0] for g in games], ns)
    m["big"].update(big_gaps([g["clr"] for g in games]))
    return m


def base_points(size, max_atom=5):
    shown = min(size, max_atom)
    return shown * (shown + 1) // 2 + (size - shown) * max_atom


def big_metrics(size_lists, placements):
    """size_lists: one list of clear sizes per game/player; placements: matching placement counts."""
    sizes = [s for l in size_lists for s in l if s > 0]
    n = max(1, len(sizes))
    out = {"clears": len(sizes)}
    bins = {"2": 0, "3": 0, "4": 0, "5-6": 0, "7+": 0}
    for s in sizes:
        k = "2" if s <= 2 else "3" if s == 3 else "4" if s == 4 else "5-6" if s <= 6 else "7+"
        bins[k] += 1
    out["size_bins"] = {k: v / n for k, v in bins.items()}
    out["share5"] = sum(1 for s in sizes if s >= 5) / n
    out["share7"] = sum(1 for s in sizes if s >= 7) / n
    out["big_per_game"] = sum(1 for s in sizes if s >= 5) / max(1, len(size_lists))
    out["big7_per_game"] = sum(1 for s in sizes if s >= 7) / max(1, len(size_lists))
    out["big_per100"] = 100.0 * sum(1 for s in sizes if s >= 5) / max(1, sum(placements))
    tot = sum(base_points(s) for s in sizes)
    out["points_share5"] = sum(base_points(s) for s in sizes if s >= 5) / tot if tot else float("nan")
    out["points_share7"] = sum(base_points(s) for s in sizes if s >= 7) / tot if tot else float("nan")
    out["no_big_games"] = mean([1.0 if not any(s >= 5 for s in l) else 0.0 for l in size_lists])
    return out


def big_gaps(clr_lists):
    """clr_lists: per game list of per-placement clear size; gap (placements) between 5+ clears."""
    gaps = []
    for l in clr_lists:
        last = 0
        for i, c in enumerate(l):
            if c >= 5:
                gaps.append(i + 1 - last)
                last = i + 1
    return {"big_gap_mean": mean(gaps), "big_gap_p90": pct(gaps, 0.9), "big_gap_max": max(gaps) if gaps else float("nan")}


def jsonable(x):
    if isinstance(x, dict):
        return {(k if isinstance(k, str) else (str(k[0]) + "-" + str(k[1]) if isinstance(k, tuple) else str(k))): jsonable(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [jsonable(v) for v in x]
    if isinstance(x, float) and x != x:
        return None
    return x


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
    print("minutes @3s: mean %s median %s p90 %s | @4s mean %s | levels: up/game %s reached mean %s median %s | reach L5 %s%% L10 %s%% | scraps/game %s (per 100 pl %s) gain mean %s" % (f(m["min3_mean"]), f(m["min3_med"]), f(m["min3_p90"]), f(m["min4_mean"]), f(m["levelups_per_game"], 2), f(m["level_mean"]), f(m["level_med"], 0), f(100 * m["reach5"], 0), f(100 * m["reach10"], 0), f(m["scraps_per_game"], 2), f(m["scraps_per100"], 1), f(m["scrap_gain_mean"])))
    b = m["big"]
    print("big clears: sizes %s | 5+ share %s%% 7+ share %s%% | 5+ per game %s per 100 pl %s | gap mean %s p90 %s max %s | games without any 5+ %s%% | points share from 5+ %s%% (7+ %s%%)" % ({k: round(v, 2) for k, v in b["size_bins"].items()}, f(100 * b["share5"], 0), f(100 * b["share7"], 0), f(b["big_per_game"], 2), f(b["big_per100"], 2), f(b["big_gap_mean"]), f(b["big_gap_p90"], 0), b["big_gap_max"], f(100 * b["no_big_games"], 0), f(100 * b["points_share5"], 0), f(100 * b["points_share7"], 0)))
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
    mins = [t / 60.0 for t in ts]
    m["min_mean"] = mean(mins)
    m["min_med"] = statistics.median(mins) if mins else float("nan")
    m["min_p10"] = pct(mins, 0.1)
    m["min_p90"] = pct(mins, 0.9)
    m["min_max"] = max(mins) if mins else float("nan")
    m["over10"] = mean([1.0 if x > 10.0 else 0.0 for x in mins])
    m["under2"] = mean([1.0 if x < 2.0 else 0.0 for x in mins])
    m["in4_8"] = mean([1.0 if 4.0 <= x <= 8.0 else 0.0 for x in mins])
    m["first_t_med"] = statistics.median([g["first_t"] for g in withfirst]) if withfirst else float("nan")
    m["scraps_per_player"] = mean([x for g in decided for x in g.get("scraps", [0, 0])])
    m["strays_per_player"] = mean([x for g in decided for x in g.get("strays", [0, 0])])
    m["sent_per_player"] = mean([x for g in decided for x in g["sent"]])
    m["placements_per_player"] = mean([x for g in decided for x in g["n"]])
    # strays decide matches: the loser received more strays than the winner
    st = [g for g in decided if "strays" in g and g["strays"][0] != g["strays"][1]]
    m["more_strays_loses"] = mean([1.0 if (g["strays"][0] > g["strays"][1]) == (g["winner"] == 1) else 0.0 for g in st]) if st else float("nan")
    # matches decided by a stray: the loser's last atoms were strays (approximation: loser got >= 3 strays and sender count > 0)
    m["loser_strays"] = mean([g["strays"][1 - g["winner"]] for g in decided if "strays" in g])
    m["winner_strays"] = mean([g["strays"][g["winner"]] for g in decided if "strays" in g])
    if decided and "csz" in decided[0]:
        lists = [l for g in decided for l in g["csz"]]
        pls = [x for g in decided for x in g["n"]]
        m["big"] = big_metrics(lists, pls)
        m["big"]["big_per_player_min"] = sum(1 for l in lists for s in l if s >= 5) / max(1e-9, sum(g["t"] for g in decided) * 2 / 60.0)
    return m


def print_match(label, header, m):
    print("\n=== %s versus (%s %s cfg %s proto %s) ===" % (label, header["board"], header["size"], header["cfg"], header["proto"]))
    print("minutes: mean %s median %s p10 %s p90 %s max %s | over 10 min %s%% under 2 min %s%% in 4-8 min %s%% | first attack median %s s | strays/player %s (winner %s loser %s) | more-strays-loses %s%% | scraps/player %s" % (f(m["min_mean"]), f(m["min_med"]), f(m["min_p10"]), f(m["min_p90"]), f(m["min_max"]), f(100 * m["over10"], 0), f(100 * m["under2"], 0), f(100 * m["in4_8"], 0), f(m["first_t_med"], 0), f(m["strays_per_player"]), f(m["winner_strays"]), f(m["loser_strays"]), f(100 * m["more_strays_loses"], 0), f(m["scraps_per_player"], 1)))
    if "big" in m:
        b = m["big"]
        print("big clears: sizes %s | 5+ share %s%% 7+ %s%% | 5+ per player %s (per min %s) | players without any 5+ %s%% | points share 5+ %s%%" % ({k: round(v, 2) for k, v in b["size_bins"].items()}, f(100 * b["share5"], 0), f(100 * b["share7"], 0), f(b["big_per_game"], 2), f(b["big_per_player_min"], 2), f(100 * b["no_big_games"], 0), f(100 * b["points_share5"], 0)))
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
    json_out = None
    for a in args:
        if a.startswith("--json="):
            json_out = a.split("=", 1)[1]
    args = [a for a in args if not a.startswith("--")]
    rows = []
    dump = {}
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
            dump[label] = {"kind": "solo", "header": header, "metrics": jsonable(m)}
        elif header["mode"] == "match":
            mm = match_metrics(games)
            print_match(label, header, mm)
            dump[label] = {"kind": "match", "header": header, "metrics": jsonable(mm)}
        else:
            v = vsfree_metrics(games)
            print("\n=== %s vsfree: attacks/min %s, first attack at %s s (p90 %s), placements %s, score %s" % (label, f(v["per_min"], 2), f(v["first_mean"]), f(v["first_p90"]), f(v["n"]), f(v["score"])))
    if rows:
        print("\n%-34s %5s %7s %5s %5s %5s %6s %6s %6s %6s %6s %6s %6s %6s %6s %6s" % ("label", "games", "surv", "med", "p10", "p90", "<30%", "cap%", "clr/10", "dr_avg", "dr_p90", "dr_max", "DH%", "hopeless%", "lv/100", "dead%"))
        for label, m in rows:
            print("%-34s %5d %7s %5s %5s %5s %6s %6s %6s %6s %6s %6s %6s %6s %6s %6s" % (label[:34], m["games"], f(m["n_mean"]), f(m["n_med"], 0), f(m["n_p10"], 0), f(m["n_p90"], 0), f(100 * m["short30"], 0), f(100 * m["capped"], 0), f(m["clears_per10"], 2), f(m["drought_mean"]), f(m["drought_p90"], 0), m["drought_max"], f(100 * m["dead_hand"]), f(100 * m["hopeless_rate"], 0), f(m["levelups_per100"], 1), f(100 * (m["dead_perm"] + m["dead_fix"]), 0)))


if __name__ == "__main__":
    main()
