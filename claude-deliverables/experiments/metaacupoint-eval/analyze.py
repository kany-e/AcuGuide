#!/usr/bin/env python3
"""Score the shipped camera-coach anchors against MetaAcuPoint, and test whether the dataset transfers.

Usage (run eval.swift first to produce results.csv):
    python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl

Everything is in the app's own units: positions in Vision's hand frame (origin wrist, axis
wrist → middle MCP, "across" positive toward the little finger), distances in hand-sizes
(isotropic wrist → middle MCP, Coach.isoHandSize). The ring radii are the shipped
toleranceXHandSize values: TE3 0.16, SJ5 0.24.
"""
import csv, json, statistics as st, sys
from collections import Counter

SYN_ASPECT = 1488 / 837
TE3_W = {"ringMCP": .11, "littleMCP": .47, "wrist": .42}   # Acupoints.swift, TE3 mediapipeTarget


def isod(a, b, asp):
    return ((a[0] - b[0]) ** 2 + ((a[1] - b[1]) / asp) ** 2) ** .5


def basis(w, m, little, asp):
    """Hand frame from three Vision joints. Returns (to-frame, from-frame, hand size)."""
    W = (w[0], w[1] / asp); M = (m[0], m[1] / asp); L = (little[0], little[1] / asp)
    v = (M[0] - W[0], M[1] - W[1]); hs = (v[0] ** 2 + v[1] ** 2) ** .5
    u = (v[0] / hs, v[1] / hs); p = (-u[1], u[0])
    if (L[0] - M[0]) * p[0] + (L[1] - M[1]) * p[1] < 0:
        p = (-p[0], -p[1])                                      # + toward the little finger
    to = lambda q: (((q[0] - W[0]) * u[0] + (q[1] / asp - W[1]) * u[1]) / hs,
                    ((q[0] - W[0]) * p[0] + (q[1] / asp - W[1]) * p[1]) / hs)
    back = lambda a, c: (W[0] + hs * (a * u[0] + c * p[0]), (W[1] + hs * (a * u[1] + c * p[1])) * asp)
    return to, back, hs


def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(q * len(xs)))]


def main(results_csv, real_jsonl):
    syn = [r for r in csv.DictReader(open(results_csv))]
    det = [r for r in syn if r["detected"] == "1"]
    print(f"MetaAcuPoint images {len(syn)}; Vision found the four anchor joints in {len(det)}\n")

    # 1. The shipped formulas, applied to Vision's landmarks on the RENDERS
    print("1. SHIPPED FORMULAS ON THE RENDERS (distance to label, hand-sizes)")
    for key, ring, name in (("te3", .16, "TE3"), ("sj5", .24, "SJ5")):
        e = [float(r[key + "_err"]) for r in det]
        n_in = sum(x <= ring for x in e)
        print(f"   {name}: median {st.median(e):.3f}  p90 {pct(e, .9):.3f}  inside ring {ring}: {n_in}/{len(e)}")
    c = Counter((r["side"], r["chirality"]) for r in det)
    print(f"   Vision handedness: true right → {dict((k[1], v) for k, v in c.items() if k[0] == 'right')}, "
          f"true left → {dict((k[1], v) for k, v in c.items() if k[0] == 'left')}\n")

    # 2. Where things sit in the hand frame, per source
    groups, syn_t, syn_lab, syn_te5 = {}, [], [], []
    for r in det:
        P = lambda k: (float(r[k + "_x"]), float(r[k + "_y"]))
        to, back, hs = basis(P("wrist"), P("middleMCP"), P("littleMCP"), SYN_ASPECT)
        t = tuple(sum(TE3_W[k] * P(k)[i] for k in TE3_W) for i in (0, 1))
        lab = to((float(r["te3_x"]), float(r["te3_y"])))
        syn_t.append(to(t)); syn_lab.append(lab)
        syn_te5.append(to((float(r["te5_x"]), float(r["te5_y"]))))
        groups.setdefault(r["avatar"] + r["side"], []).append(lab)

    real = [json.loads(l) for l in open(real_jsonl) if l.strip()]
    real_t, real_lab, real_frames = [], [], []
    for r in real:
        j = r["joints"]; g = lambda k: tuple(j[k])
        w, m = g("wrist"), g("middleMCP"); dx = m[0] - w[0]; dy = m[1] - w[1]
        asp = abs(dy) / (r["handSize"] ** 2 - dx ** 2) ** .5         # capture aspect, from stored size
        to, back, hs = basis(w, m, g("pinkyMCP"), asp)
        t = (.11 * g("ringMCP")[0] + .47 * g("pinkyMCP")[0] + .42 * w[0],
             .11 * g("ringMCP")[1] + .47 * g("pinkyMCP")[1] + .42 * w[1])
        real_t.append(to(t)); real_lab.append(to(tuple(r["target"])))
        real_frames.append((back, hs, asp, t, tuple(r["target"])))

    med = lambda xs, i: st.median(x[i] for x in xs)
    print("2. TE3 IN THE HAND FRAME (along: 0 wrist → 1 middle knuckle; across: + toward little finger)")
    print(f"   MetaAcuPoint labels ({len(groups)} hands)   along {med(syn_lab, 0):.2f}  across {med(syn_lab, 1):+.2f}")
    print(f"   real device labels ({len(real)}, 1 session)  along {med(real_lab, 0):.2f}  across {med(real_lab, 1):+.2f}")
    print(f"   shipped target on REAL frames      along {med(real_t, 0):.2f}  across {med(real_t, 1):+.2f}")
    print(f"   shipped target on the RENDERS      along {med(syn_t, 0):.2f}  across {med(syn_t, 1):+.2f}")
    print(f"   SJ5 labels: along {med(syn_te5, 0):+.2f} across {med(syn_te5, 1):+.2f}; shipped SJ5 is along -0.70 "
          f"across 0.00 by definition\n")

    # 3. Does a model fit on the dataset transfer to real hands?
    ids = list(groups)
    loo = []
    for gid in ids:
        train = [p for h in ids if h != gid for p in groups[h]]
        a, c = st.median(p[0] for p in train), st.median(p[1] for p in train)
        loo += [((p[0] - a) ** 2 + (p[1] - c) ** 2) ** .5 for p in groups[gid]]
    A, C = med(syn_lab, 0), med(syn_lab, 1)
    fm = [isod(back(A, C), lab, asp) / hs for back, hs, asp, t, lab in real_frames]
    sh = [isod(t, lab, asp) / hs for back, hs, asp, t, lab in real_frames]
    print("3. TRANSFER: a hand-frame TE3 fit ONLY on the dataset, scored on the real labels it never saw")
    print(f"   fit: TE3 = wrist + {A:.3f}·axis {C:+.3f}·across")
    print(f"   within the dataset, leave-one-hand-out: mean {st.mean(loo):.3f}, inside 0.16: "
          f"{100 * sum(x <= .16 for x in loo) / len(loo):.0f}%")
    print(f"   on the {len(real)} real labels:  dataset fit mean {st.mean(fm):.3f}, inside {sum(x <= .16 for x in fm)}/{len(fm)}"
          f"   |   shipped (in-sample) mean {st.mean(sh):.3f}, inside {sum(x <= .16 for x in sh)}/{len(sh)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
