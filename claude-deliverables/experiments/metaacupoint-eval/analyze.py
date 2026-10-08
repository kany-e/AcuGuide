#!/usr/bin/env python3
"""Score the shipped camera-coach anchors against MetaAcuPoint, and test whether the dataset transfers.

Usage (run eval.swift first to produce results.csv):
    python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl <dataset>/avatar_description.xlsx

HOW THE LABELS WERE MADE decides how the cross-validation must be split. Per the paper (§3), a
practitioner placed the five points ONCE PER SKELETON TYPE as bone-attached sockets; they were then
copied to the 6 avatars sharing that skeleton and projected into every frame automatically. So the
900 labels are 5 placement decisions, and a hand held out alone still has its exact bone-relative
TE3 in training via its 5 skeleton-mates. Leave-one-SKELETON-out is the honest split. The
leave-one-hand-out number is printed beside it because the two came out the same here (the
2-parameter frame model barely varies across skeletons) — the split was wrong in principle and
happened not to matter, and a reader should be able to see that rather than take it on trust.

Everything is in the app's own units: positions in Vision's hand frame (origin wrist, axis
wrist → middle MCP, "across" positive toward the little finger), distances in hand-sizes
(isotropic wrist → middle MCP, Coach.isoHandSize). The ring radii are the shipped
toleranceXHandSize values: TE3 0.16, SJ5 0.24.
"""
import csv, json, re, statistics as st, sys, zipfile
import xml.etree.ElementTree as ET
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


def skeleton_of(xlsx):
    """avatar id → skeleton group, from sheet 2 of avatar_description.xlsx (the 30 avatars used).

    The sheet has no skeleton column; grouping by (gender, height, size) yields exactly the paper's
    five groups of six. Its gender column is swapped relative to the paper's 12 male / 18 female,
    so the group key is used only as an opaque label."""
    z = zipfile.ZipFile(xlsx); M = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    shared = ["".join(t.text or "" for t in si.iter(M + "t"))
              for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall(M + "si")]
    out = {}
    for row in ET.fromstring(z.read("xl/worksheets/sheet2.xml")).iter(M + "row"):
        vals = []
        for c in row.findall(M + "c"):
            v = c.find(M + "v")
            vals.append(shared[int(v.text)] if c.get("t") == "s" and v is not None
                        else (v.text if v is not None else ""))
        if len(vals) > 4 and vals[2].strip().isdigit():
            out[vals[2].strip()] = "/".join(vals[i] for i in (1, 3, 4))
    return out


def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(q * len(xs)))]


def pooled_affine(real_samples, syn_samples):
    """Section 4: can the dataset REFINE the shipped model, rather than replace it?

    Same form as the shipped TE3 anchor — label ≈ wrist + α(ringMCP − wrist) + β(littleMCP − wrist),
    weights summing to 1 — fit by least squares in hand-size units on the real labels PLUS the
    synthetic ones at total weight λ, scored leave-one-REAL-label-out. λ = 0 is the shipped model's
    own refit; anything that beats it would be the dataset genuinely helping."""
    def fit(samples, weights):
        a11 = a12 = a22 = b1 = b2 = 0.0
        for (w, r, l, lab, hs), wt in zip(samples, weights):
            for k in (0, 1):
                u = (r[k] - w[k]) / hs; v = (l[k] - w[k]) / hs; y = (lab[k] - w[k]) / hs
                a11 += wt * u * u; a12 += wt * u * v; a22 += wt * v * v; b1 += wt * u * y; b2 += wt * v * y
        det = a11 * a22 - a12 * a12
        return ((a22 * b1 - a12 * b2) / det, (a11 * b2 - a12 * b1) / det)

    def err(s, ab):
        w, r, l, lab, hs = s; a, b = ab
        q = tuple(w[k] + a * (r[k] - w[k]) + b * (l[k] - w[k]) for k in (0, 1))
        return ((q[0] - lab[0]) ** 2 + (q[1] - lab[1]) ** 2) ** .5 / hs

    full = fit(real_samples, [1] * len(real_samples))
    print("4. REFINE, NOT REPLACE: the shipped TE3 form, fit on real labels + synthetic at weight λ,")
    print("   scored leave-one-REAL-label-out")
    print(f"   refit on all {len(real_samples)} real labels: ring {full[0]:.2f}, little {full[1]:.2f}, "
          f"wrist {1 - full[0] - full[1]:.2f}  (shipped 0.11 / 0.47 / 0.42)")
    for lam in (0, 0.25, 1, 10, None):
        errs = []
        for i in range(len(real_samples)):
            train = real_samples[:i] + real_samples[i + 1:]
            if lam is None:
                ab = fit(syn_samples, [1] * len(syn_samples))
            else:
                ab = fit(train + syn_samples,
                         [1] * len(train) + [lam * len(train) / len(syn_samples)] * len(syn_samples))
            errs.append(err(real_samples[i], ab))
        tag = "synthetic only" if lam is None else f"lambda {lam:g}"
        print(f"   {tag:>15}: mean {st.mean(errs):.3f}  worst {max(errs):.3f}  inside 0.16: "
              f"{sum(e <= .16 for e in errs)}/{len(errs)}")


def main(results_csv, real_jsonl, xlsx):
    skel = skeleton_of(xlsx)
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
    groups, by_skel, syn_t, syn_lab, syn_te5, syn_aff = {}, {}, [], [], [], []
    for r in det:
        P = lambda k: (float(r[k + "_x"]), float(r[k + "_y"]))
        to, back, hs = basis(P("wrist"), P("middleMCP"), P("littleMCP"), SYN_ASPECT)
        t = tuple(sum(TE3_W[k] * P(k)[i] for k in TE3_W) for i in (0, 1))
        lab = to((float(r["te3_x"]), float(r["te3_y"])))
        syn_t.append(to(t)); syn_lab.append(lab)
        syn_te5.append(to((float(r["te5_x"]), float(r["te5_y"]))))
        iso = lambda q: (q[0], q[1] / SYN_ASPECT)
        syn_aff.append((iso(P("wrist")), iso(P("ringMCP")), iso(P("littleMCP")),
                        iso((float(r["te3_x"]), float(r["te3_y"]))), hs))
        groups.setdefault(r["avatar"] + r["side"], []).append(lab)
        by_skel.setdefault(skel[r["avatar"]], []).append(lab)

    real = [json.loads(l) for l in open(real_jsonl) if l.strip()]
    real_t, real_lab, real_frames, real_aff = [], [], [], []
    for r in real:
        j = r["joints"]; g = lambda k: tuple(j[k])
        w, m = g("wrist"), g("middleMCP"); dx = m[0] - w[0]; dy = m[1] - w[1]
        asp = abs(dy) / (r["handSize"] ** 2 - dx ** 2) ** .5         # capture aspect, from stored size
        to, back, hs = basis(w, m, g("pinkyMCP"), asp)
        t = (.11 * g("ringMCP")[0] + .47 * g("pinkyMCP")[0] + .42 * w[0],
             .11 * g("ringMCP")[1] + .47 * g("pinkyMCP")[1] + .42 * w[1])
        real_t.append(to(t)); real_lab.append(to(tuple(r["target"])))
        real_frames.append((back, hs, asp, t, tuple(r["target"])))
        iso = lambda q, a=asp: (q[0], q[1] / a)
        real_aff.append((iso(w), iso(g("ringMCP")), iso(g("pinkyMCP")), iso(tuple(r["target"])), hs))

    med = lambda xs, i: st.median(x[i] for x in xs)
    print("2. TE3 IN THE HAND FRAME (along: 0 wrist → 1 middle knuckle; across: + toward little finger)")
    print(f"   MetaAcuPoint labels ({len(by_skel)} placements, {len(groups)} hands)  along {med(syn_lab, 0):.2f}  across {med(syn_lab, 1):+.2f}")
    print(f"   real device labels ({len(real)}, 1 session)  along {med(real_lab, 0):.2f}  across {med(real_lab, 1):+.2f}")
    print(f"   shipped target on REAL frames      along {med(real_t, 0):.2f}  across {med(real_t, 1):+.2f}")
    print(f"   shipped target on the RENDERS      along {med(syn_t, 0):.2f}  across {med(syn_t, 1):+.2f}")
    print(f"   SJ5 labels: along {med(syn_te5, 0):+.2f} across {med(syn_te5, 1):+.2f}; shipped SJ5 is along -0.70 "
          f"across 0.00 by definition\n")

    # 3. Does a model fit on the dataset transfer to real hands?
    def held_out(parts):
        errs = []
        for gid in parts:
            train = [p for h in parts if h != gid for p in parts[h]]
            a, c = st.median(p[0] for p in train), st.median(p[1] for p in train)
            errs += [((p[0] - a) ** 2 + (p[1] - c) ** 2) ** .5 for p in parts[gid]]
        return errs
    loo, loso = held_out(groups), held_out(by_skel)
    A, C = med(syn_lab, 0), med(syn_lab, 1)
    fm = [isod(back(A, C), lab, asp) / hs for back, hs, asp, t, lab in real_frames]
    sh = [isod(t, lab, asp) / hs for back, hs, asp, t, lab in real_frames]
    print("3. TRANSFER: a hand-frame TE3 fit ONLY on the dataset, scored on the real labels it never saw")
    print(f"   fit: TE3 = wrist + {A:.3f}·axis {C:+.3f}·across")
    print(f"   within the dataset, leave-one-SKELETON-out ({len(by_skel)} folds): mean {st.mean(loso):.3f}, "
          f"inside 0.16: {100 * sum(x <= .16 for x in loso) / len(loso):.0f}%")
    print(f"   (leave-one-hand-out, which leaks skeleton-mates: mean {st.mean(loo):.3f}, "
          f"inside 0.16: {100 * sum(x <= .16 for x in loo) / len(loo):.0f}%)")
    print(f"   on the {len(real)} real labels:  dataset fit mean {st.mean(fm):.3f}, inside {sum(x <= .16 for x in fm)}/{len(fm)}"
          f"   |   shipped (in-sample) mean {st.mean(sh):.3f}, inside {sum(x <= .16 for x in sh)}/{len(sh)}")
    print("   (the shipped model's own leave-one-out score is section 4, lambda 0)\n")
    pooled_affine(real_aff, syn_aff)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
