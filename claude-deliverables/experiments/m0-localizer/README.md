# M0 — keypoint-conditioned acupoint localizer (Day-1 falsification experiment)

The first milestone of the research in
[`../../references/acuguide_localizer_research.md`](../../references/acuguide_localizer_research.md) (§9).
A macOS CLI that answers one question cheaply, **before any annotation spend**:

> On the points we share with MetaAcuPoint (**TE3**, **TE5 = our SJ5**), does a *keypoint-conditioned*
> map — our current affine anchors, and a learned linear refit — match their Mean Distance Error when
> evaluated on their images **through our own Apple Vision pipeline**?

It reuses the **exact** AcuGuide localization contract (zero train/serve skew): the same 10 Vision
joints, the same confidence gates (obs ≥ 0.5, per-point > 0.3), the same top-left convention
(`y = 1 − y`), `handSize = |middleMCP − wrist|`, and the affine `weightedTarget` — all mirrored from
`AcuGuide/HandModel.swift`, `AcuGuide/CameraCoach.swift`, `AcuGuide/Acupoints.swift`.

## What it does

1. Runs Apple Vision `VNDetectHumanHandPoseRequest` on each dataset image → our keypoints, our convention.
2. Builds the **canonical hand frame** (middleMCP origin, `wrist→middleMCP` scale/rotation, chirality fold).
3. Loads the COCO acupoint labels; associates the correct hand to the labels.
4. Reports, per point: **affine-anchor MDE** (today's hand-tuned map, the no-regression baseline) vs a
   **learned linear map** (least-squares fit of canonical-features → canonical acupoint, k-fold CV,
   un-projected per frame), both in pixels, against MetaAcuPoint's numbers (TE3 3.78 px real / 5.01 synth;
   TE5 5.68 / 5.81) — plus the **retained fraction** after the detector-agreement filter.

## Run

```bash
# 1) validate the geometry + learned-fit pipeline (no data needed) — should print all PASS
swift run m0 --selftest

# 2) the real Day-1 experiment (once MetaAcuPoint access is granted — see below)
swift run m0 --images path/to/metaacupoint/images --labels path/to/coco.json --points TE3,SJ5 --folds 5
```

Self-test currently passes: canonical round-trip exact; similarity (view/scale/translation) invariance
at machine precision (~7e-16) — this is the cross-viewpoint stability *by construction*; affine anchors
exact; and a planted keypoint-dependent linear map is recovered to ~2e-4 held-out MDE.

## ⚠️ Data access (the honest blocker)

The MetaAcuPoint dataset is **license-open but access-restricted**. Zenodo record `17713204`
(DOI 10.5281/zenodo.17713204) reports `metadata.access_right: "restricted"` (the page shows
"Restricted" + "embargo", ~1.9 GB) even though the *license* is CC BY 4.0, and a direct API query
returns `files: []`. So the files are **not freely downloadable right now** — they require an access
request to the depositors (Guruge et al., Healthcare 2025 / PMC12691809). Until then, M0 runs its
self-test but cannot produce the real TE3/TE5 numbers. Expected COCO schema is documented in
`Sources/m0/VisionLabels.swift`; MetaAcuPoint also ships a CSV (X,Y per keypoint).

## Environment note

This harness is pure Swift + Apple Vision + Accelerate — **no Python/torch/mediapipe** — precisely so
M0 reuses the shipping detector and has no ML-tooling dependency. `swift build` needs Xcode (tested on
Xcode 26.6, macOS).

## Files

- `Sources/m0/Core.swift` — joints, affine anchors, canonical frame, ridge least-squares, features.
- `Sources/m0/VisionLabels.swift` — Vision hand-pose extraction (mirrors `buildHand`) + COCO loader.
- `Sources/m0/main.swift` — orchestration, k-fold learned eval, and the self-test.
