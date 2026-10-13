# MetaAcuPoint vs the shipped camera coach

**Verdict: not training data for the coach AcuGuide has today, because it disagrees with the real
labels about where TE3 is.** Vision reads these renders much as it reads real camera frames: its
knuckles land within 0.08 hand-sizes of where it puts them on real frames, and the shipped TE3
formula built on them within 0.04. Handedness is the exception, since Vision calls every rendered
left hand "right". What disagrees is the TE3 **label**. The dataset's practitioner put TE3 0.23 hand-sizes
from where the 9 real by-feel labels put it, wider than the coach's 0.16 ring. Pooling the two
makes real-hand error worse because it averages two different placements. Which placement is right
is an open question that only new real labels can settle (see "Open question", below). SJ5 agrees.

Evaluated 2026-10-07; corrected 2026-10-12. Nothing in the app's point placement was changed on the
strength of either.

> **Correction, 2026-10-12.** The first version of this README reached the opposite conclusion:
> "the labels agree, the landmarks do not". `analyze.py` recovered each real frame's aspect from the
> stored `handSize`, but `LabelRecord.handSize` is `Hand.handSize`, the RAW normalised hypot
> |middleMCP − wrist|, so the recovery returned 1.0 for all 9 rows and the real hands were measured
> squashed. The tell was in the output: the little-finger knuckle at 1.08 along the wrist →
> middle-knuckle axis, past the middle knuckle, which no hand does. At 9:16 it sits at 0.81. The Jul 7
> fit's own baseline confirms 9:16: the old WHO-text TE3 line scores 0.233 mean / 1-of-9 there, the
> exact figure in `Acupoints.swift`, against 0.260 at aspect 1. The script now assumes 9:16 and stops
> if that knuckle comes out past 1.

## The dataset, and how its labels were made

MetaAcuPoint — MetaHuman-generated synthetic forearm/hand images, v1.0.
Guruge, P. K.; Padmanabha, P.; Herath, H. M. K. K. M. B.; Vithanage, N. M.; Park, H.-J.; Na, C.;
Yi, M.; Lee, B. (2025). Zenodo. https://doi.org/10.5281/zenodo.17713204 — **CC BY 4.0**.
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
overlapping hands, a pressing finger covering the point, front-camera lighting).

Points labelled: LI11, LI10, TE5 (= the app's **SJ5**), LI4, **TE3**. **LI4 is excluded from
AcuGuide entirely and was ignored here.** Synthetic, so there is no personal-data concern. **The
images are NOT in this repository** (465 MB; `dataset_MetaAcuPoint/` is gitignored) — download from
the DOI to rerun.

> A note on one wrong turn, kept because it is easy to repeat: the annotation JSON carries the
> fields of the COCO Annotator web tool (`annotated`, `annotating`, `events`, `isbbox`), which reads
> as "a person clicked these". It is only the export format — and every image record says
> `annotated: False`. The paper is the authority on how labels were made, not the file's schema.

## Method

`eval.swift` runs Apple Vision hand-pose (`VNDetectHumanHandPoseRequest`) over every image with the
app's own conventions copied in: top-left normalisation (`HandVision.normalize`), per-joint
confidence gate 0.3, isotropic distance (`Coach.isoDist`) and hand size = wrist → middle MCP
(`Coach.isoHandSize`). It scores the **shipped** anchors from `Acupoints.swift`:

- TE3 = 0.11·ringMCP + 0.47·littleMCP + 0.42·wrist, ring radius 0.16 hand-sizes
- SJ5 = 1.7·wrist − 0.7·middleMCP, ring radius 0.24

`analyze.py` re-expresses everything in Vision's **hand frame** (origin wrist, axis toward the
middle MCP, "across" positive toward the little finger), compares against the 9 real device TE3
labels in `claude-deliverables/data/te3_labels_2026-07-07.jsonl` (which the shipped TE3 weights were
fit on), and cross-validates by **skeleton type**, since hands that share a skeleton share an
identical bone-relative label.

The real labels' frame aspect is **assumed, not stored**: `LabelCapture` runs the `.high` preset with
`forcePortrait()`, so its buffers are 9:16 (width/height 0.5625), but `LabelRecord` does not record
it. The saved frame JPEGs on the capture device would confirm it. `analyze.py` uses `REAL_ASPECT =
9/16`; an optional fourth argument overrides it. Section 2's barycentric line needs no aspect at all.

```bash
swift eval.swift <dataset>/annotation_resized_RGB.json <dataset>/resized_RGB results.csv
python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl <dataset>/avatar_description.xlsx [9/16]
```

## Results

Output of `analyze.py`, verbatim:

```
MetaAcuPoint images 900; Vision found the four anchor joints in 900

1. SHIPPED FORMULAS ON THE RENDERS (distance to label, hand-sizes)
   TE3: median 0.289  p90 0.361  inside ring 0.16: 0/900
   SJ5: median 0.103  p90 0.213  inside ring 0.24: 851/900
   Vision handedness: true right → {'right': 410, 'left': 40}, true left → {'right': 450}

2. THE HAND FRAME (along: 0 wrist → 1 middle knuckle; across: + toward little finger; medians)
   Vision's knuckles, along/across    renders        real frames (aspect 0.5625)
     indexMCP                         0.98 -0.27     0.96 -0.28
     ringMCP                          0.92 +0.23     0.96 +0.25
     littleMCP                        0.79 +0.43     0.81 +0.50
   MetaAcuPoint labels (5 placements, 60 hands)  along 0.70  across +0.40
   real device labels (9, 1 session)  along 0.52  across +0.25
   shipped target on REAL frames      along 0.49  across +0.26
   shipped target on the RENDERS      along 0.47  across +0.23
   pre-Jul-7 WHO-text target (.46/.34/.20): REAL along 0.72 across +0.29, RENDERS along 0.69 across +0.25
   the two TE3 label sets are 0.23 hand-sizes apart (TE3 ring 0.16)
   TE3 labels as wrist + a·(ringMCP − wrist) + b·(littleMCP − wrist), which needs no aspect:
     MetaAcuPoint a -0.09 b +0.97   real a +0.13 b +0.45   shipped a +0.11 b +0.47
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

**1. "0/900" is about the labels, not about Vision.** Read alone, section 1 says the coach's TE3
never lands in its own ring on the renders. Section 2 shows why. Vision lays the knuckles out the
same way in both domains (index 0.98/−0.27 on renders against 0.96/−0.28 on real frames, ring
0.92/+0.23 against 0.96/+0.25, little 0.79/+0.43 against 0.81/+0.50), and the shipped TE3 formula
follows them, at 0.47/+0.23 on the renders and 0.49/+0.26 on real frames. **What differs is the
labels:** the practitioner's TE3 sits at 0.70/+0.40, the real by-feel labels at 0.52/+0.25. The
barycentric line, which assumes nothing about the real frames' aspect, says the same thing. Measured
against Vision's own wrist, ring and little-finger knuckles, the practitioner's TE3 sits just short
of the little-finger knuckle (a −0.09, b 0.97). The by-feel labels sit about halfway from the wrist
to it (a 0.13, b 0.45), where the shipped formula aims (0.11, 0.47). What Vision does get wrong on
the renders is handedness: it reports "right" for all 450 rendered left hands, while on the real
frames it reported both (5 right, 4 left). There is no ground truth for those, so this shows only
that the renders behave differently on that one output.

**2. A practitioner's WHO-based TE3 and the by-feel TE3 disagree, and this data cannot say which is
right.** Be precise about what is independent of what. The dataset's TE3 (0.70/+0.40) is five
placements by one practitioner reading the WHO standard, made on the skeleton's bones. The app's
pre-Jul-7 TE3 line also came from WHO text and lands at 0.69/+0.25 on the renders, the same distance
along but less far toward the little finger; the two are partly the same source, so that agreement
proves little. The independent comparison is WHO-based placement against the 9 real device labels,
which were found by feel on a real hand (0.52/+0.25). Those are **0.23 hand-sizes apart**, outside
the coach's 0.16 ring, and a TE3 fit on the dataset gets 0 of the 9 inside it (section 3). The
shipped coach was fit to the by-feel labels and stays with them (0.49/+0.26, mean 0.086, 9/9
inside). Neither placement is anywhere near off the hand (both sit short of the knuckle row, on the
little-finger half), so a "the marker is off the hand" report is still not explained by the TE3
anchor math. Both sides are thin: 5 placements by one practitioner on renders, 9 labels from one
session on real hands.

**3. Do not refit — or refine — the CURRENT coach with this dataset.** Two tests, both negative.
*Replacing* (section 3): a hand-frame TE3 model fit on the dataset alone is 98% inside the ring
within it (leave-one-skeleton-out) and 0/9 on the real labels it never saw (mean 0.254).
*Refining* (section 4): adding the synthetic labels to the shipped model's own fit makes it worse on
real hands at every weight tried, and monotonically — 0.097 with real labels only, 0.156 at equal
weight, 0.322 with synthetic only. As the synthetic weight grows the fit slides toward the
little-finger knuckle, because that is where the practitioner put TE3. Pooling still hurts, but the
cause is a **different TE3 label convention**, not Vision moving joints between domains. If new real
labels side with the practitioner, the fix is a refit on those labels, not a pool.

A correction to a correction: the first version of this README reported that reproducing the shipped
fit gave a leave-one-out mean of 0.124 (6/9 inside), against the 0.096 that `Acupoints.swift` cites.
That gap was the aspect bug. At 9:16 the leave-one-out mean is **0.097**, worst 0.149, 9/9 inside the
ring, matching the original 0.096 / max 0.154. The refit's weights come out 0.18 / 0.41 / 0.42 rather
than the shipped 0.11 / 0.47 / 0.42. On these 9 frames the two predict points about 0.02 hand-sizes
apart, a flat valley at n = 9 and no reason to move the shipped weights.

**4. SJ5 checks out, with less certainty.** Its formula uses only the wrist and middle MCP, which
define the frame itself. The labels sit at −0.63 along against the formula's −0.70, comfortably
inside the 0.24 ring. There are no real SJ5 labels to confirm it, and the dataset's ±10° animation
says nothing about the forearm-rotation sensitivity that earned SJ5 its "Reliability: low" note.

## What the paper shows, and why it does not contradict point 3

The authors trained HRNet-W48 — a network that reads the IMAGE and outputs the points directly — on
these renders, and report it working on real forearm photos: 5.67 ± 3.13 px against a real-data
baseline of 4.81 px, and on four external sets 5.84–6.45 mm versus 10.63–15.80 mm for the
real-trained model. They also report that the automatic labels beat a blinded manual re-annotation
of the same renders (12.76 px), which is the paper's point: generated labels are more consistent
than clicked ones.

That is a different architecture from AcuGuide's, but the difference matters less than the first
version of this README said. An image-trained network never goes through Vision's joints. Here,
though, Vision reads the renders much as it reads real frames, handedness aside. What an image model
would inherit is the labels: a network trained on this set learns the practitioner's TE3, so the open
question below applies to it as much as to the coach. Two more caveats keep the paper's result from
transferring wholesale even to an image model: HRNet-W48 is far heavier than anything the coach runs
per frame, and the paper's real test images are controlled top-down photos, not a front-camera view
of one hand pressing another.

## What would actually improve accuracy

For the coach as built: more **real** labels — several people, both hands, varied lighting, and the
occluded mid-press frames — captured with the existing label-capture tool (Settings → Developer in
Debug builds). Nine labels from one session is the binding constraint on every real-hand number
here, and it is what leaves the TE3 question open.
If the coach ever moves to an image-based point detector, this dataset becomes a candidate training
source rather than a check (for TE3, only once the question below is settled), and the real labels
become its validation set.

## Open question: which TE3?

The practitioner's WHO-based TE3 (0.70 along / +0.40 across) and the by-feel TE3 the coach is fit to
(0.52 / +0.25) are **0.23 hand-sizes apart**. That is outside the coach's 0.16 ring, and on an adult
hand (wrist to middle knuckle about 9 cm) roughly 2 cm. This evaluation cannot say which is right. One
side is five placements by one practitioner on rendered skeletons, the other is nine labels found by
feel in one session. **Only new real labels can settle it**: several people, both hands, and ideally a
practitioner placing TE3 on real hands with the label-capture tool, so the WHO placement and the
by-feel one are measured in the same frames. Until then the shipped TE3 stays where it is, the best
fit to the only real labels there are, and nothing in this folder moves it.
