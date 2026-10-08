# MetaAcuPoint vs the shipped camera coach

**Verdict: use it to CHECK where points are, not to TRAIN or refit the coach.** A model fit on it
is worse on real hands than what ships. Its value is independent confirmation that the coach
aims TE3 and SJ5 at the right anatomy, and a measured warning about Vision's behaviour on renders.

Evaluated 2026-10-07. Nothing in the app was changed on the strength of this dataset.

## The dataset

MetaAcuPoint — MetaHuman-generated synthetic forearm/hand images, v1.0.
Guruge, P. K.; Padmanabha, P.; Herath, H. M. K. K. M. B.; Vithanage, N. M.; Park, H.-J.; Na, C.;
Yi, M.; Lee, B. (2025). Zenodo. https://doi.org/10.5281/zenodo.17713204 — **CC BY 4.0**.
Paper: *MetaAcuPoint: MetaHuman-Generated Synthetic Data for Hand Acupoint Localization*,
Healthcare 2025, 13 (MDPI).

- 900 renders, but 30 avatars × 2 hands × 15 animation frames — about **60 independent hands**.
- Labels five points: LI11, LI10, TE5 (= the app's **SJ5**), LI4, **TE3**. Two of the app's eight
  camera-coached points. **LI4 is excluded from AcuGuide entirely and was ignored here.**
- One pose throughout: forearm flat and pronated, fingers spread, top-down camera, plain grey
  background, studio light. None of the conditions where the live coach actually struggles —
  two overlapping hands, a pressing finger covering the point, front-camera lighting.
- Synthetic, so there is no personal-data concern. **The images are NOT in this repository**
  (465 MB; `dataset_MetaAcuPoint/` is gitignored). Download from the DOI above to rerun.

## Method

`eval.swift` runs Apple Vision hand-pose (`VNDetectHumanHandPoseRequest`) on every image with the
app's own conventions copied in: top-left normalisation (`HandVision.normalize`), per-joint
confidence gate 0.3, isotropic distance (`Coach.isoDist`) and hand size = wrist → middle MCP
(`Coach.isoHandSize`). It then scores the **shipped** anchors from `Acupoints.swift`:

- TE3 = 0.11·ringMCP + 0.47·littleMCP + 0.42·wrist, ring radius 0.16 hand-sizes
- SJ5 = 1.7·wrist − 0.7·middleMCP, ring radius 0.24

`analyze.py` re-expresses every point in Vision's **hand frame** (origin wrist, axis toward the
middle MCP, "across" positive toward the little finger) and compares against the 9 real device
TE3 labels in `claude-deliverables/data/te3_labels_2026-07-07.jsonl`, which the shipped TE3 weights
were fit on.

```bash
swift eval.swift <dataset>/annotation_resized_RGB.json <dataset>/resized_RGB results.csv
python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl
```

## Results

Output of `analyze.py`, verbatim:

```
MetaAcuPoint images 900; Vision found the four anchor joints in 900

1. SHIPPED FORMULAS ON THE RENDERS (distance to label, hand-sizes)
   TE3: median 0.289  p90 0.361  inside ring 0.16: 0/900
   SJ5: median 0.103  p90 0.213  inside ring 0.24: 851/900
   Vision handedness: true right → {'right': 410, 'left': 40}, true left → {'right': 450}

2. TE3 IN THE HAND FRAME (along: 0 wrist → 1 middle knuckle; across: + toward little finger)
   MetaAcuPoint labels (60 hands)   along 0.70  across +0.40
   real device labels (9, 1 session)  along 0.65  across +0.39
   shipped target on REAL frames      along 0.63  across +0.38
   shipped target on the RENDERS      along 0.47  across +0.23
   SJ5 labels: along -0.63 across -0.02; shipped SJ5 is along -0.70 across 0.00 by definition

3. TRANSFER: a hand-frame TE3 fit ONLY on the dataset, scored on the real labels it never saw
   fit: TE3 = wrist + 0.699·axis +0.396·across
   within the dataset, leave-one-hand-out: mean 0.075, inside 0.16: 98%
   on the 9 real labels:  dataset fit mean 0.158, inside 5/9   |   shipped (in-sample) mean 0.112, inside 8/9
```

## What it means

**1. "0/900" is a property of the renders, not of the formula.** Read alone, section 1 says the
coach's TE3 never lands in its own ring. Section 2 shows why that is wrong: the same formula sits
at 0.63/+0.38 on real camera frames — right next to the real labels — but at 0.47/+0.23 on the
renders. The labels did not move between the two domains; **Vision's joint positions did.** The
handedness result is the same gap from another side: on the renders Vision reports "right" for
all 450 left hands, while on the real frames it reported both hands (5 right, 4 left — there is
no ground truth for those, so this shows only that the renders behave differently).

**2. Three independent sources agree on where TE3 is.** The dataset's 60 hands (0.70/+0.40), the
real device labels (0.65/+0.39) and the app's own anatomical table (`HandAnatomy`, 0.70 along)
agree within about 0.05 hand-sizes, and the shipped coach aims at 0.63/+0.38. This is the
strongest evidence available that a "the marker is off the hand" report is not caused by the
TE3 anchor math.

**3. Do not refit the coach on this dataset.** A model fit on it alone is excellent inside the
dataset (98%) and worse on real hands than what ships (5/9 vs 8/9, mean 0.158 vs 0.112). The
shipped number is in-sample, which flatters it; its original leave-one-out mean was 0.096 — still
better. Anyone training on these renders needs to correct for the gap and validate on real frames,
and right now the only real validation set is 9 labels from one session.

**4. SJ5 checks out, with less certainty.** Its formula uses only the wrist and middle MCP — the
frame itself — so it is the least exposed to the gap. The labels sit at −0.63 along against the
formula's −0.70, comfortably inside the 0.24 ring. There are no real SJ5 labels to confirm it,
and the dataset's single fixed forearm pose says nothing about the rotation sensitivity that
earned SJ5 its "Reliability: low" note.

## What would actually improve accuracy

More **real** labels, not more synthetic ones: several people, both hands, varied lighting, and
the occluded mid-press frames, captured with the existing label-capture tool (Settings → Developer
in Debug builds). Nine labels from one session is the binding constraint on every number above.
