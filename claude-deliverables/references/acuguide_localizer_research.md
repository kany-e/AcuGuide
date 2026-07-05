# A keypoint-conditioned, uncertainty-aware acupoint localizer for AcuGuide

*On-device, Vision-native. Research design study — July 2026.*

> **Can we improve on MetaAcuPoint / FAcupoint and match what we have?**
> **Yes — but the honest claim is narrow.** We can build a novel, competitive localizer that
> *matches* their per-point accuracy **on the 2 points we share**, *wins* on the axes they never
> report (on-device latency, cross-viewpoint stability, coverage, data-efficiency), and is a
> **provable no-regression** upgrade to our current coach. We **cannot** honestly claim to "beat
> MetaAcuPoint" outright: we share only 2 of 8 points with it, and on its own high-res tripod
> benchmark a pixel-reading HRNet can out-localize anything sitting downstream of Vision's landmarks.
> Method + data verified; grounded in the 3 papers + a SOTA scan + a code audit of our own system.

## 1. Thesis

The gap in MetaAcuPoint/FAcupoint is exactly our advantage. Both regress acupoints **from raw pixels**
(MetaAcuPoint: YOLOv3→HRNet-W48 on a 256×256 crop; FAcupoint: dense heatmap nets on face images).
Neither conditions on skeleton keypoints. But acupoints are *defined* relative to bones/creases/tendons
(cun, metacarpals, wrist crease) — and **our coach already exploits this**: our WHO anchors are a
hand-tuned **affine map from Vision hand keypoints → acupoint** (verified: all 8 points' weights sum to
exactly 1.0). So the research upgrade is to **learn** that keypoint-conditioned map. Apple Vision has
already done the expensive pixels→joints work that HRNet-W48's ~60M params exist to solve; the residual
joints→acupoint map is low-dimensional geometry (a pure-cun geometric baseline already reaches ~4–9 mm at
**zero** learned params — Frontiers Neurorobotics 2024). A tiny head only has to beat hand-tuned ratios,
not out-detect HRNet.

## 2. Problem statement

Today's localizer: `target = Σ wᵢ·keypointᵢ` (`weightedTarget`, [HandModel.swift:42], the `total>0`
guard is divide-by-zero safety, not normalization). Four concrete weaknesses, all confirmed in code:
1. **No rotation normalization** — targets are in raw top-left image coords, so the two forearm points
   (PC6, SJ5 = `1.7·wrist − 0.7·middleMCP`) *swing* under forearm roll (the code even shrank the
   extrapolation factor to damp this).
2. **No uncertainty** — a single fixed per-point tolerance (0.12–0.24·handSize) drives the hit ring
   regardless of how well-constrained the geometry is that frame.
3. **All-or-nothing** — any missing anchor joint returns `nil` (no graceful degradation).
4. **Hand-guessed weights** + a stale header ([Acupoints.swift:5] still says "TE3 ONLY" while all 8
   carry live targets).

## 3. Hypothesis (falsifiable)

A **<100k-param head** that reads Vision keypoints in a **canonical** (translation/scale/rotation/chirality-
normalized) hand frame and emits **(x, y, σ)** per acupoint will:
- **(a)** reproduce today's affine map exactly at initialization → **guaranteed no regression**;
- **(b)** **match** MetaAcuPoint's per-point MDE on the two shared points (TE3, TE5/SJ5) *in our capture conditions*;
- **(c)** **beat** cross-viewpoint stability because view-invariance is built in by construction, not learned;
- **(d)** do so at **~1000× fewer params** and **1–2 orders of magnitude fewer labels** than an image-native HRNet.

Scope is deliberately narrow: a like-for-like claim exists for **2 of 8 points only**; the other 6 have no
external benchmark and rest on our own sparse labels + the affine prior. The detector is Apple **Vision**
`VNDetectHumanHandPoseRequest` (not MediaPipe); the two face points (Yintang/Taiyang) use a separate
Vision-FACE locator and are **out of this seam**.

## 4. Related-work positioning

| Source | What it is | Overlap / use | Their numbers |
|---|---|---|---|
| **MetaAcuPoint** (Healthcare 2025) | image-native YOLOv3+HRNet-W48, 5 pts {LI4,LI10,LI11,TE3,TE5} | share **2** pts (TE3, TE5=SJ5); LI4 = our pregnancy exclusion; LI10/LI11 = auxiliary only. Value = **dataset** (CC BY 4.0) + synthetic→real finding, **not the model** | MDE only. Real-only **4.81 px** (TE3 3.78 / TE5 5.68); synthetic-only 5.67 px; cross-viewpoint **5–6.5 mm** (synthetic) vs **10–16 mm** (real). **No PCK, no params/FPS reported.** |
| **FAcupoint** (ESWA 2025) | dense facial-acupoint heatmap nets, 43 pts, face-only, **request-only** | **0** overlap. Take 3 things, **no data**: the NME/FR/AUC metric defs; the finding that low-texture soft-tissue points localize worst (→ PC8/HT7/PC7 have a ceiling); the pseudo-label-growth idea | best (3FabRec) FA_NME **1.86%** @600 imgs; even best model max error up to 23 px vs physicians' <6 px want |
| **AcuSim** (Nature Sci Data 2025) | synthetic **RGB-D** cervicocranial | orthogonal — wrong anatomy, needs depth, CC BY-**NC-ND** | 92.86% within 5 mm |
| **SOTA lineage** | — | architecture basis | SimCC/RTMPose coord-classification head (79k params, within ~0.5 AP of a 10.5M heatmap head, 0.002 GFLOPs); canonical-hand-frame (arXiv 2006.01320); structure-constrained loss (Frontiers Physiol 2025); cun geometric baseline (~4–9 mm, 0 params) |

## 5. Method (merged design)

**Coordinate frame** (the load-bearing choice): a per-hand 2D **similarity canonicalization**, closed-form,
before the head.
- **Origin** = `middleMCP` (not wrist — the audit shows wrist jitters most under Vision; the MCP is the stable interior anchor).
- **Scale** = `handSize = ‖middleMCP − wrist‖` (reuse the exact scalar at [HandModel.swift:36] so all downstream tolerance/offset math is untouched).
- **Rotation** = align `wrist→middleMCP` to canonical +y (a single 2D angle; **no** 6D/SO(3) — we have no reliable depth and faking it injects noise).
- **Chirality fold** = mirror left hands onto the right-hand frame, so back-camera mirroring + the palmar/dorsal split collapse into one feature (`isDorsal` becomes an input, not a branch).
- Forward: `k̂ᵢ = R·(kᵢ−o)/s`; the head predicts `(x̂,ŷ)` in-frame; invert the similarity to return **top-left normalized image coords** — the **exact output contract `weightedTarget` honors**, so One-Euro smoothing, hit-test, hysteresis, and the validated 7-state machine are **unchanged**. Because the current weights are affine (sum=1.0), a head initialized to imitate today reproduces it to sub-pixel error → **provable no-regression floor**.

**Input features** (per hand, per point-query, ~50–65 dims): canonical keypoint coords; per-joint Vision
confidence (already gated at 0.3) so the head widens σ on shaky joints; a **missing-joint mask** (graceful
degradation instead of all-or-nothing `nil`); signed `isDorsal`; `log-handSize`; and a **point-ID
embedding** (one shared trunk conditioned on which of the 8 points). *Highest-leverage change:* add the four
finger **PIP** joints to the input (edits in 3 small places — the `HandJoint` enum + its `.vision` map +
the joints array at [CameraCoach.swift:130]) — PIPs pin down the metacarpal gaps where TE3/SI3 sit.

**Architecture** — a **SimCC coordinate-classification head** (not a heatmap → no pixels at inference; not
plain regression → gives uncertainty): shared MLP trunk (input→128→128, ~22k) → point-embedding/FiLM
conditioning → two per-axis classification heads (~50–65k) → σ head (~1k). **≈80–90k params, ≈0.002 GFLOPs,
FP16 ~175 KB.** Soft-argmax decode; softmax spread + σ head give calibrated uncertainty that **drives an
adaptive `ringRadius`** — an upgrade the fixed-tolerance system structurally cannot express.

**Training**: SimCC KL loss + Gaussian-NLL on σ + structure-constraint terms (cun-ratio consistency,
left/right canonical symmetry, inter-point ordering along the palm axis) + an affine-imitation MSE annealed
down as real labels arrive. **Augment in joint space** (jitter joints by Vision's empirical noise, drop
low-confidence joints, small canonical rotations) — teaching robustness to the exact noise Vision produces.

**Optional forearm refiner** (gated, zero learned params): for PC6/SJ5 *only* — where no Vision keypoint
exists past the wrist — a cheap oriented-ridge/Frangi filter on a small forearm patch can snap to the tendon
valley. The only honest way to add real forearm information; run at low frequency behind a "hold detected" gate.

## 6. Data strategy (3 tiers)

- **Tier 1 — MetaAcuPoint via Vision re-projection** (the label-transfer core + the Day-1 experiment):
  we do **not** train on their pixels. For each synthetic image, run the *exact* AcuGuide Vision pipeline →
  our keypoints in our convention; read their COCO acupoint labels; canonicalize both; emit
  `(canonical keypoints, confidence, mask → canonical acupoint)` pairs. This yields TE3 + TE5(=SJ5) labels
  **in our own feature space with zero train/serve skew** (same detector at train and run time) and harvests
  their synthetic→real viewpoint robustness *through* the keypoints. LI10/LI11 → auxiliary tasks; **LI4 never used.**
  **Label-transfer error control** (where the rigor lives — *report, don't assume*): (a) detector-agreement
  gate (drop frames Vision handles worse than runtime gates allow); (b) round-trip projection filter (reject
  pairs with back-projection error >~0.05·handSize; **report the retained fraction**); (c) confidence-weight
  each pair; (d) two-track eval — GT-joints vs Vision-joints (the gap = the detector tax).
- **Tier 2 — the 6 points no dataset covers** (SI3, TE4, PC8, HT7, PC7, PC6): affine-imitation
  bootstrapping on tens of thousands of real Vision-detected hands (free weak pseudo-labels → "no worse than
  today"); ~200–400 sparse **expert-clicked** real iPhone frames per point (annotated on the mirrored preview
  → no reprojection error), prioritizing dorsal between-joint (TE3, SI3) + forearm (PC6, SJ5); and **multi-view
  self-supervision** (the canonical target must be invariant across frames of a static hand → penalize its
  variance → buys cross-viewpoint stability with no new labels).
- **Tier 3 — a held-out real, expert-clicked test set** (never trained on, never synthetic) — the only
  honest source for the headline MDE/PCK.

## 7. Evaluation protocol

- **Metrics**: MDE in **px and mm**, reported **per point** (never hide dorsal/forearm worst-cases in an
  average); PCK@thresh (hand-bbox-normalized); NME (hand-size-normalized, FAcupoint's scalar); FR@0.1, AUC.
- **Splits**: (1) head-to-head vs MetaAcuPoint on **TE3 + TE5 only**, on their 180-image real test set
  re-projected through *our* Vision pipeline (apples-to-apples input); (2) our held-out real set for all 8
  (internal-only for the 6 without an external benchmark); (3) cross-viewpoint variance vs their PK/MAP curves.
- **Baselines**: (a) hand-coded cun / today's affine map (no-regression floor + imitation target); (b) our
  learned head; (c) an image-native HRNet on MetaAcuPoint pixels (the heavyweight reference).
- **Success = MATCH-in-our-conditions + WIN-on-axes-they-don't-report**, *not* "beat their tripod number": on
  TE3/TE5, MDE ≤ their synthetic-only 5.67 px approaching real-only 4.81 px in our capture distribution;
  flatter cross-viewpoint variance; 8-point coverage; <1 ms added on-device; and a **data-efficiency curve**
  (NME/mm vs #labels ∈ {0(affine),10,50,100,300,full}) showing we match HRNet's mm-error at 1–2 orders of
  magnitude fewer acupoint labels. Always report the **Vision keypoint-noise floor** separately (we cannot
  beat `detector_error ⊕ head_error`).

## 8. On-device budget

Head ≈ **80–90k params, ≈0.002 GFLOPs, FP16 ~175 KB**. All Dense/GELU/Softmax ops are ANE-native → CoreML
via coremltools, **well under 1 ms** on the Apple Neural Engine (RTMPose-s whole-model is ~13.9 ms on a
Snapdragon 865; our head is a fraction of its trimmed SimCC head). All 8 points in one batched forward pass.
The latency floor is entirely the existing Vision hand-pose pass (~10–30 ms) that **already runs every
frame** — the head adds to an existing pass, not a new one → end-to-end stays at Vision's frame rate (>30 FPS).
**Rollout is shadow mode first**: compute both `weightedTarget` and `learnedTarget` every frame, *draw the
old one*, *log the delta*, cut over per-point only once validated. Fallback on CoreML-load failure or too-few
joints → today's affine map; because the head is initialized to reproduce it, the fallback is seamless.

## 9. Day-1 experiment (falsify the premise cheaply, before any annotation spend)

1. Obtain the public MetaAcuPoint set (900 synthetic RGB + COCO JSON; see **§13 caveat** — access needs confirming).
2. Build a tiny macOS/CLI harness reusing the **exact** `buildHand` logic from [CameraCoach.swift] (Vision
   `VNDetectHumanHandPoseRequest`, the 0.5/0.3 confidence gates, the top-left y-flip + x-mirror + chirality) to
   dump 10 keypoints + confidence + chirality per image.
3. Apply the detector-agreement + round-trip filters; record the retained fraction.
4. Build the canonical similarity frame; project each image's COCO **TE3 & TE5** labels into it.
5. Fit two maps and compare **per-point MDE** (px + mm) to the paper *and* to our current affine anchors on
   the same frames: (a) our existing affine weights (the baseline — also tells us how good today's hand-tuned
   map already is on real-ish data, for free); (b) a least-squares / tiny-MLP learned map.
6. **Deliverable**: a table `{affine baseline, learned head} × {TE3, TE5}` MDE vs MetaAcuPoint's per-point
   (TE3 real 3.78 / synth 5.01 px; TE5 real 5.68 / synth 5.81 px) + the retained fraction + the
   GT-joints-vs-Vision-joints gap. **This single experiment validates or kills the core hypothesis before a
   dollar is spent on expert labels.**

## 10. Roadmap

| Milestone | Effort | Deliverable |
|---|---|---|
| **M0** — Day-1 re-projection experiment | 3–5 days | CLI harness; MetaAcuPoint through Vision; canonical-frame fit; per-point MDE table vs paper + baseline for TE3/TE5. **Go/no-go on the hypothesis.** |
| **M1** — Head v0 + shadow harness | 1–2 wks | SimCC head reproducing today's 8 points to sub-pixel (phase-1 affine imitation on real hands); coremltools export; `learnedTarget(pointID:)→(CGPoint,σ)` alongside `weightedTarget`; shadow-mode logging. **On-device no-regression proof.** |
| **M2** — MetaAcuPoint supervision + canonical frame + PIP joints | 2–3 wks | add PIPs; phase-2 training (reprojected TE3/TE5 + LI10/LI11 aux + structure + multi-view consistency); cross-viewpoint variance report. |
| **M3** — Sparse expert labels + data-efficiency curve | 3–4 wks | 200–400 expert-clicked frames/point; held-out real test set; the headline NME/mm-vs-#labels curve vs HRNet; per-point MDE for all 8; σ-driven adaptive ring validated. |
| **M4** — Cut-over + optional forearm refiner | 1–2 wks | per-point cut-over once shadow delta validated; fix the stale [Acupoints.swift:5] header; optional gated Frangi refiner for PC6/SJ5; ship behind a toggle with affine fallback retained. |

## 11. Where it fails (six honest failure modes — several fundamental)

1. **Thin comparison.** We share only 2 of 8 points with MetaAcuPoint and 0 with FAcupoint. Any
   "we beat MetaAcuPoint" headline is defensible **only** for TE3/TE5, or reframed as coverage (8 vs 5). For
   the other 6 there is *no external benchmark*, so "match or beat" is literally undefined.
2. **We cannot beat their tripod number.** Their 4.81 px is on native 1488×837 fixed-tripod images through a
   pixel-reading HRNet. On their pristine frames an image-native net can exploit texture (nail folds, tendon
   shadows) we never see; on raw px-MDE over *their* bench we would likely **lose** on the between-joint dorsal
   points. Our win is conditional on the on-device / cross-viewpoint regime.
3. **Detector floor is a hard ceiling.** Every acupoint error is ≥ the propagated Vision keypoint error.
   Vision publishes no accuracy spec, and it degrades under occlusion/oblique views — which happens **exactly
   during the press**, when the massaging hand occludes the receiving hand. HRNet-on-pixels has no detector in
   its critical path. Must be measured on real *press* frames, not idle hands.
4. **Forearm points (PC6, SJ5) are fundamentally under-determined** — ~2 cun past the wrist, **outside the
   convex hull of any tracked joint**; Vision returns nothing past the wrist, so no keypoint-only head can
   recover true forearm position. We improve *stability* and honestly output a **wide σ**, but cannot beat a
   method that images the forearm. The Frangi refiner is a partial patch.
5. **Soft-tissue palmar points (esp. PC8, mid-palm) have a real ceiling** — FAcupoint's own finding: no-texture
   regions localize worst; PC8 has no crease/tendon to snap to → we plateau near the geometric prior; the
   honest move is a wider tolerance, not a false-precision marker.
6. **Synthetic-to-Vision domain gap** — if Vision systematically mislocates joints on MetaHuman renders
   (possible skin-tone/demographic gaps), our reprojected labels are biased and our "match" partly measures
   the same detector on both sides. The round-trip filter + held-out real test guard this but cannot remove it.

## 12. Honest verdict

A genuinely strong research direction **and** a safe engineering upgrade — but discipline the marketing.
**Near-certain wins:** provable no-regression (the affine map is the linear special case); ~1000× fewer params
than HRNet at sub-1 ms on-device; structural view-invariance + uncertainty-aware tolerance the current system
can't express; 8-point coverage vs their 5. **What we cannot honestly claim:** that we "beat MetaAcuPoint" —
2 shared points, and on their high-res bench a pixel net wins. **The defensible paper is:** *"a tiny,
view-invariant, uncertainty-aware, on-device head that matches heavyweight image regressors on shared points
at ~1000× lower cost, with 8-point coverage and a favorable data-efficiency curve."* Fund it, ship it in
shadow mode, and let the **Day-1 experiment be the gate**: if a keypoint-conditioned head can't match their
TE3/TE5 MDE on reprojected data, the premise is falsified for the price of a few days.

## 13. Empirical caveats found while scoping (not from the papers)

- **Dataset access is unconfirmed.** The paper states the MetaAcuPoint set is CC BY 4.0 on Zenodo (DOI
  10.5281/zenodo.17713204, ~1.9 GB). A **direct Zenodo API query on record 17713204 returned an empty file
  list** (`files: []`, 4 downloads, 268 views) and the record title reads "…Synthetic **Forearm** Data" (a
  possible subset). **Before M0, confirm the downloadable files** (correct versioned record, or contact the
  authors). If unavailable, M0 falls back to a synthetic-keypoint PoC against our own WHO anchors (validates
  the *mechanism*, not a head-to-head number).
- **No ML tooling in the current environment** (numpy/sklearn/torch/mediapipe/coremltools all absent). M0's
  harness is best built as a small **Swift/macOS CLI reusing Apple Vision directly** (the *right* call anyway —
  it reuses the exact runtime detector, eliminating train/serve skew), with a light Python/sklearn fit step
  for the map. Plan tooling setup into M0.

---

*Sources: MetaAcuPoint (Healthcare 2025, PMC12691809); FAcupoint (Expert Systems w/ Applications 2025, doi
10.1016/j.eswa.2025.126683); AcuSim (Nature Sci Data 2025); SimCC/RTMPose; cun-geometric baseline (Frontiers
Neurorobotics 2024); structure-constrained acupoint loss (Frontiers Physiol 2025). Code audit: `Acupoints.swift`,
`HandModel.swift`, `CameraCoach.swift`, `Coach.swift`. See also [acuguide_source_upgrade.md](acuguide_source_upgrade.md).*
