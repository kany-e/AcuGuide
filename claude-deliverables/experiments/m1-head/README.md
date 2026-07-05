# M1 — learned head v0 (affine-imitation, CoreML export, on-device no-regression proof)

Milestone M1 of the localizer research
([`../../references/acuguide_localizer_research.md`](../../references/acuguide_localizer_research.md) §10).
**Needs no external data** — it trains purely by *imitating* today's affine anchors, proving the on-device
path before any labels are collected.

## What it proves

A tiny keypoint-conditioned head (shared trunk + point embedding → per-axis SimCC soft-argmax → x, y, σ),
trained only to reproduce our 8 hand/wrist affine anchors on synthetic hands, then exported to CoreML and
re-run from Swift on Apple's stack:

| Result | Value |
|---|---|
| Params | **154 k** (FP16 CoreML package **314 KB**) |
| Affine-imitation reproduction (held-out, per point) | **0.02–0.59 px** on a 1488-px image (PC6/SJ5 → 0.02 px; SI3 worst → 0.59 px) |
| Mean over 8 points | **0.15 px** |
| Swift ↔ CoreML round-trip (exported vs trained head) | **mean 0.07 px, max 0.24 px**, CPU-float32 == ANE-float16 |
| Uncertainty head σ | ~0.03 canonical (populated, ready to drive an adaptive ring in M2) |

So the head is a **provable no-regression** generalization of `weightedTarget`: initialize-by-imitation
reproduces today's coach to sub-pixel, and the CoreML model runs identically on-device.

## ⚠️ What "sub-pixel" does and does NOT mean here

It means the head **reproduces our current affine anchors** to sub-pixel — the no-regression floor. It is
**not** a comparison to MetaAcuPoint's real-image accuracy (TE3 3.78 px / TE5 5.68 px), which is a
*different task* (localizing on real photos). Beating or matching that requires **real labels** and the
M0 reprojection experiment — it is M2/M3 work, still gated on MetaAcuPoint data access (which is
Zenodo-`restricted`; see the M0 README).

## Run

```bash
python3 -m venv .venv && ./.venv/bin/pip install numpy torch coremltools
./.venv/bin/python train.py        # train + eval + export AcupointHead.mlpackage + dump test_vectors.json
swift verify.swift                 # load the CoreML model in Swift; confirm it matches the trained head
```

Tested on Apple Silicon, torch 2.12 + coremltools 9.0 + numpy 2.2, Xcode 26.6 (MPS training, ANE inference).

## Files

- `train.py` — synthetic hand generator + canonical frame + anchors (ported verbatim from the Swift M0
  `Core.swift`), the head, training, per-point eval, CoreML export, Swift test-vector dump.
- `verify.swift` — loads `AcupointHead.mlpackage`, runs the 40 test vectors on CPU-float32 and ANE-float16,
  asserts sub-pixel agreement with the trained head.
- `AcupointHead.mlpackage` (314 KB) · `head.pt` · `test_vectors.json` — the M1 artifacts.

## Next: the app integration seam (shadow mode)

M1 produces the model; wiring it into the app is the remaining M1→M2 step, kept **zero-risk**:
1. Add `Hand.learnedTarget(_ pointId: Int) -> (CGPoint, sigma: CGFloat)?` next to `weightedTarget`
   (`HandModel.swift`) — build the canonical frame, run `AcupointHead.mlpackage` via CoreML, un-project.
2. **Shadow mode**: compute both every frame, **draw `weightedTarget`**, **log the delta** — never change
   behavior until the on-device delta distribution is validated on real hands.
3. Cut over per-point only after the delta is confirmed; keep `weightedTarget` as the CoreML-load-failure
   fallback (seamless, since the head is initialized to reproduce it).
4. Then M2 swaps the imitation labels for MetaAcuPoint-reprojected TE3/TE5 + expert labels, and the σ head
   starts driving the adaptive hit-ring.
