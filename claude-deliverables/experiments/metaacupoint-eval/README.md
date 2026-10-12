# MetaAcuPoint vs the shipped camera coach

**Verdict: a check on where points are — and the check disagrees with the coach about TE3.** The
dataset's practitioner put TE3 about 0.23 hand-sizes closer to the knuckles than the 9 real by-feel
labels the coach was fit to. Apple Vision is *not* the reason: the coach's TE3 formula lands in
nearly the same place in the hand on these renders as on real camera frames. So pooling the
dataset into the coach's fit would move TE3, not sharpen it, and which placement is right is a
question for new real labels. The dataset can't be used for anything the app ships anyway: its
files are released for academic, non-commercial research only (see "Licence").

Evaluated 2026-10-07, **corrected 2026-10-12** (see "Correction"). Nothing in the app's point
placement was changed on the strength of it.

## Correction (2026-10-12)

The first version of this README reached the opposite conclusion about *why* the dataset hurts the
fit ("the labels agree, the landmarks do not"). That came from a units bug in `analyze.py`: it
recovered each real frame's aspect ratio from the stored `handSize`, but `LabelRecord.handSize` is the
raw normalised |middleMCP − wrist|, so the recovery always returned 1.0. The real frames are 9:16
portrait (`LabelCapture.swift` forces portrait buffers at the `.high` preset; `frameAspect` defaults
to 9/16), so the real hands were measured squashed. The tell was in the old output: the little-finger
knuckle sat at 1.08 along the wrist → middle-knuckle axis, beyond the middle knuckle. At 9:16 it sits
at 0.81, where it belongs. `analyze.py` now uses 9/16 for the records that predate the new
`LabelRecord.frameAspect` field, and the label tool stores the aspect from now on.

What changed: the real by-feel labels move from 0.65/+0.39 to **0.52/+0.25**. The shipped coach's
leave-one-out score on them is **0.097**, 9/9 inside the ring. The earlier "reproduction" of 0.124
was the bug, and the 0.096 in the `Acupoints.swift` comment stands.

## The dataset, and how its labels were made

MetaAcuPoint — MetaHuman-generated synthetic forearm/hand images, v1.0.
Guruge, P. K.; Padmanabha, P.; Herath, H. M. K. K. M. B.; Vithanage, N. M.; Park, H.-J.; Na, C.;
Yi, M.; Lee, B. (2025). Zenodo. https://doi.org/10.5281/zenodo.17713204
Paper: Guruge et al., *MetaAcuPoint: MetaHuman-Generated Synthetic Data for Hand Acupoint
Localization*, Healthcare 2025, 13 (MDPI) — https://pmc.ncbi.nlm.nih.gov/articles/PMC12691809/

**The labels are generated, not clicked.** From the paper's methods: the five points were embedded
as invisible sockets attached to bones of the MetaHuman skeleton. A certified Traditional Korean
Medicine practitioner placed them by hand, following the WHO standard, **once per skeleton type**;
they were then copied automatically to every avatar sharing that skeleton, and every frame's pixel
labels were produced by projecting the 3D sockets into the rendered image.

| | count |
|---|---|
| Point placements a person actually made | **5** (one per skeleton type) |
| Avatars | 30 (6 per skeleton type) |
| Hands | 60 (left and right of each avatar) |
| Images | 900 (each hand animated — elbow ±10°, fingers ±10° — and captured at 1 fps for 15 s) |
| Point labels | 4,500 (5 per image), all projected automatically |

Camera and lighting were held FIXED on purpose, to match the real dataset the authors compared
against: every image is a top-down view of a pronated forearm on a plain grey background. Within
one hand the 15 frames move about 160 px and rotate about 18° (measured here), but the posture
family never changes — none of the conditions where the live coach struggles appear (two
overlapping hands, a pressing finger covering the point, front-camera lighting, palm up).

Points labelled: LI11, LI10, TE5 (= the app's **SJ5**), LI4, **TE3**. **LI4 is excluded from
AcuGuide entirely and was ignored here.** Synthetic, so there is no personal-data concern. **The
images are NOT in this repository** (465 MB; `dataset_MetaAcuPoint/` is gitignored).

> A note on one wrong turn, kept because it is easy to repeat: the annotation JSON carries the
> fields of the COCO Annotator web tool (`annotated`, `annotating`, `events`, `isbbox`), which reads
> as "a person clicked these". It is only the export format — and every image record says
> `annotated: False`. The paper is the authority on how labels were made, not the file's schema.

## Licence

Two terms, both checked 2026-10-12, and both stricter than the record's "CC BY 4.0" field:

- **Zenodo usage conditions.** The files are restricted. Access is by request, and the record page
  says the data may only be used for academic, non-commercial research.
- **Unreal Engine EULA §6.** It bars using MetaHuman characters, or their animation curves, to build
  or enhance any database or to train or test any machine-learning system. Checked against an
  archived 2026 copy; Epic's live page refused automated fetches.

So nothing derived from this dataset ships: no training, no tuned constants. This evaluation is
internal research. Not legal advice; ask counsel before anything else touches it.

## Method

`eval.swift` runs Apple Vision hand-pose (`VNDetectHumanHandPoseRequest`) over every image with the
app's own conventions copied in: top-left normalisation (`HandVision.normalize`), per-joint
confidence gate 0.3, isotropic distance (`Coach.isoDist`) and hand size = wrist → middle MCP
(`Coach.isoHandSize`). It scores the **shipped** anchors from `Acupoints.swift`:

- TE3 = 0.11·ringMCP + 0.47·littleMCP + 0.42·wrist, ring radius 0.16 hand-sizes
- SJ5 = 1.7·wrist − 0.7·middleMCP, ring radius 0.24

`analyze.py` re-expresses everything in Vision's **hand frame** (origin wrist, axis toward the
middle MCP, "across" positive toward the little finger), in isotropic units: the renders at their
1488×837, the real frames at 9:16. It compares against the 9 real device TE3 labels in
`claude-deliverables/data/te3_labels_2026-07-07.jsonl` (which the shipped TE3 weights were fit on),
and cross-validates by **skeleton type**, since hands that share a skeleton share an identical
bone-relative label.

```bash
swift eval.swift <dataset>/annotation_resized_RGB.json <dataset>/resized_RGB results.csv
python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl <dataset>/avatar_description.xlsx
```

## Results

Output of `analyze.py`, verbatim (2026-10-12):

```
MetaAcuPoint images 900; Vision found the four anchor joints in 900

1. SHIPPED FORMULAS ON THE RENDERS (distance to label, hand-sizes)
   TE3: median 0.289  p90 0.361  inside ring 0.16: 0/900
   SJ5: median 0.103  p90 0.213  inside ring 0.24: 851/900
   Vision handedness: true right → {'right': 410, 'left': 40}, true left → {'right': 450}

2. TE3 IN THE HAND FRAME (along: 0 wrist → 1 middle knuckle; across: + toward little finger)
   MetaAcuPoint labels (5 placements, 60 hands)  along 0.70  across +0.40
   real device labels (9, 1 session)  along 0.52  across +0.25
   shipped target on REAL frames      along 0.49  across +0.26
   shipped target on the RENDERS      along 0.47  across +0.23
   SJ5 labels: along -0.63 across -0.02; shipped SJ5 is along -0.70 across 0.00 by definition

3. TRANSFER: a hand-frame TE3 fit ONLY on the dataset, scored on the real labels it never saw
   fit: TE3 = wrist + 0.699·axis +0.396·across
   within the dataset, leave-one-SKELETON-out (5 folds): mean 0.073, inside 0.16: 98%
   (leave-one-hand-out, which leaks skeleton-mates: mean 0.075, inside 0.16: 98%)
   on the 9 real labels:  dataset fit mean 0.254, inside 0/9   |   shipped (in-sample) mean 0.086, inside 9/9
   (the shipped model's own leave-one-out score is section 4, lambda 0)

4. REFINE, NOT REPLACE: the shipped TE3 form, fit on real labels + synthetic at weight λ,
   scored leave-one-REAL-label-out
   refit on all 9 real labels: ring 0.18, little 0.41, wrist 0.42  (shipped 0.11 / 0.47 / 0.42)
          lambda 0: mean 0.097  worst 0.149  inside 0.16: 9/9
       lambda 0.25: mean 0.105  worst 0.185  inside 0.16: 8/9
          lambda 1: mean 0.156  worst 0.265  inside 0.16: 5/9
         lambda 10: mean 0.287  worst 0.409  inside 0.16: 0/9
    synthetic only: mean 0.322  worst 0.446  inside 0.16: 0/9
```

## What it means

**1. Vision reads the renders' knuckles about where it reads real ones.** The coach's TE3 formula is
built from the ring knuckle, the little-finger knuckle and the wrist. Expressed in Vision's own hand
frame it lands at 0.47/+0.23 on the renders and 0.49/+0.26 on real frames — within 0.03. Where Vision
does fail on the renders is handedness: it calls all 450 rendered left hands "right". The coach's
palm/back gate depends on handedness, so renders are still a poor stand-in for real frames there.

**2. The labels disagree.** The practitioner's WHO-based TE3 sits at 0.70/+0.40; the 9 by-feel labels
sit at 0.52/+0.25, about 0.23 hand-sizes (around 2 cm on an adult hand) toward the wrist and the
thumb side. None of the 9 is within 0.16 of the practitioner's spot. The coach follows the by-feel
labels (it was fit on them), so "0/900 inside the ring" in section 1 is this disagreement, measured
on renders. The WHO wording ("in the depression proximal to the 4th metacarpophalangeal joint") and
the app's own TE3 cue ("the soft groove just behind your ring and pinky knuckles") both read closer
to the practitioner's spot. But this is 5 placements by one practitioner on synthetic skeletons
against 9 labels from one session on one real hand. It is a question worth settling, not an answer.

**3. Do not pool the dataset into the coach's fit.** Section 4 adds the synthetic labels at weight λ:
real-hand error rises monotonically, 0.097 → 0.105 → 0.156 → 0.287 → 0.322. A model fit only on the
dataset puts 0/9 real labels inside the ring. That is not noise to average away; it is the fit being
pulled from one placement convention to the other. If TE3 should move, it should move because new
real labels say so.

**4. SJ5 checks out, with less certainty.** Its formula uses only the wrist and middle MCP — the
frame itself. The labels sit at −0.63 along against the formula's −0.70, inside the 0.24 ring on
851 of 900 images. There are no real SJ5 labels to confirm it, and the dataset's ±10° animation
says nothing about the forearm-rotation sensitivity that earned SJ5 its "Reliability: low" note.

## What the paper shows

The authors trained HRNet-W48 — a network that reads the IMAGE and outputs the points directly — on
these renders, and report it working on real forearm photos: 5.67 ± 3.13 px against a real-data
baseline of 4.81 px, and on four external sets 5.84–6.45 mm versus 10.63–15.80 mm for the
real-trained model. They also report that the automatic labels beat a blinded manual re-annotation
of the same renders (12.76 px), which is the paper's point: generated labels are more consistent
than clicked ones. Consistent is not the same as agreeing with a different labeller, which is
what section 2 measures. And HRNet-W48 is far heavier than anything the coach runs per frame, and
the paper's real test images are controlled top-down photos, not a front-camera view of one hand
pressing another.

## Can the generation be changed to cover the harder cases?

Asked 2026-10-12: could the dataset's generation code be changed to produce the cases it leaves
out? Short answer: there is no code to change, and rebuilding it with MetaHuman is ruled out.

- **Nothing was released to change.** The Zenodo record holds the renders, the labels and an
  avatar sheet. It has no Unreal project, scripts, seed or socket transforms. The paper has no code
  statement, and no repository turned up. Its labeller is also a linear map from the table plane
  to pixels for one fixed overhead camera, with no occlusion handling. It could not produce
  front-camera, palm-up or mid-press labels even if it were released.
- **Rebuilding it with MetaHuman is ruled out** by EULA §6 (see "Licence"). It would also be heavy
  going on this Mac (8 GB of RAM, no Unreal installed).
- **The repo's own generators don't create new truth.** `m1-head/train.py`'s synthetic hands and
  `fixtures/generate_fixtures.py` label hands with the coach's own formulas (and older TE3 weights),
  so changing them can't teach the coach anything it doesn't already assume.

The harder cases, roughly in order of user impact: the pressing finger covering TE3 and its
anchors; a thumb press (only the index tip has occlusion reconstruction); two overlapping hands, and
the ring jumping to the pressing hand; handedness misreads flipping the palm/back gate; the wrist
joint covered when pressing HT7, PC7 or TE4 (84–90% of their weight); back camera and landscape;
and the palm-side points (PC6, PC7, HT7, PC8) and SI3, which have no real labels at all.

What could generate data for those, without a licence problem:

1. **For the coach as built** (Vision joints in, point out): real pixels, not renders. Cut out a
   real pressing finger (Vision's foreground-instance mask) and paste it onto real idle frames
   whose point is already labelled; the label stays exact and Vision sees real skin. Check first
   that pasted presses make Vision lose and move joints the way real presses do, and stop if they
   don't. Pair it with joint-space sequences (un-mirror for the back camera, rotate to landscape,
   scripted handedness flips at measured rates) as regression tests for the coaching engine. Both
   need real captures first: several people, both hands, idle and mid-press, with the frame aspect
   now stored.
2. **Only if the app adopts an image-reading point detector:** a rendered generator in headless
   Blender with CC0 MakeHuman (MPFB2) bodies and CC0 Poly Haven lighting. MANO-based models and
   most hand datasets with these cases (InterHand2.6M, FreiHAND, ARCTIC, DexYCB…) are licensed
   non-commercial, so they are out.

None of it is built. The first step is the same in every branch: more real labels, which also
settles item 2 above.

## What would actually improve accuracy

More **real** labels, captured with the label tool (Settings → Developer, Debug builds), which now
records the frame aspect: several people, both hands, varied lighting, and the occluded mid-press
frames. For TE3 specifically, capture both conventions on each hand: the spot found by feel, and the
spot marked by the WHO definition (ideally by a practitioner). Eight or more hands would show which
convention to fit, and that decision moves TE3 more than any generator could.
