# MetaAcuPoint vs the shipped camera coach

**Verdict: for the coach AcuGuide has today, it is a check on where points are, not training data.**
The coach builds every point from Apple Vision's hand joints, and Vision places those joints
differently on these renders than on real camera frames, so a model fit through them is worse on
real hands than what ships. The paper behind the dataset reports the opposite for a different kind
of model — a network trained on the images themselves — so the dataset becomes much more useful if
AcuGuide ever moves to an image-based point detector (see "What the paper shows", below).

Evaluated 2026-10-07. Nothing in the app's point placement was changed on the strength of it.

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

```bash
swift eval.swift <dataset>/annotation_resized_RGB.json <dataset>/resized_RGB results.csv
python3 -I analyze.py results.csv ../../data/te3_labels_2026-07-07.jsonl <dataset>/avatar_description.xlsx
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
   MetaAcuPoint labels (5 placements, 60 hands)  along 0.70  across +0.40
   real device labels (9, 1 session)  along 0.65  across +0.39
   shipped target on REAL frames      along 0.63  across +0.38
   shipped target on the RENDERS      along 0.47  across +0.23
   SJ5 labels: along -0.63 across -0.02; shipped SJ5 is along -0.70 across 0.00 by definition

3. TRANSFER: a hand-frame TE3 fit ONLY on the dataset, scored on the real labels it never saw
   fit: TE3 = wrist + 0.699·axis +0.396·across
   within the dataset, leave-one-SKELETON-out (5 folds): mean 0.073, inside 0.16: 98%
   (leave-one-hand-out, which leaks skeleton-mates: mean 0.075, inside 0.16: 98%)
   on the 9 real labels:  dataset fit mean 0.158, inside 5/9   |   shipped (in-sample) mean 0.112, inside 8/9
   (the shipped model's own leave-one-out score is section 4, lambda 0)

4. REFINE, NOT REPLACE: the shipped TE3 form, fit on real labels + synthetic at weight λ,
   scored leave-one-REAL-label-out
   refit on all 9 real labels: ring 0.12, little 0.46, wrist 0.42  (shipped 0.11 / 0.47 / 0.42)
          lambda 0: mean 0.124  worst 0.214  inside 0.16: 6/9
       lambda 0.25: mean 0.133  worst 0.205  inside 0.16: 6/9
          lambda 1: mean 0.169  worst 0.281  inside 0.16: 5/9
         lambda 10: mean 0.349  worst 0.499  inside 0.16: 0/9
    synthetic only: mean 0.448  worst 0.599  inside 0.16: 0/9
```

## What it means

**1. "0/900" is a property of the renders, not of the formula.** Read alone, section 1 says the
coach's TE3 never lands in its own ring. Section 2 shows why that is wrong: the same formula sits at
0.63/+0.38 on real camera frames — beside the real labels — and at 0.47/+0.23 on the renders. The
labels did not move between the two domains; **Vision's joint positions did.** Handedness shows the
same gap from another side: Vision reports "right" for all 450 rendered left hands, while on the real
frames it reported both hands (5 right, 4 left — there is no ground truth for those, so this shows
only that the renders behave differently).

**2. A practitioner's WHO-based placement agrees with your by-feel labels.** Be precise about what
is independent of what. The dataset's TE3 (0.70/+0.40) is five placements by one practitioner reading
the WHO standard; the app's own `HandAnatomy` table (0.70 along) also comes from WHO text, so those
two are partly the same source and their agreement proves little. The genuinely independent
comparison is WHO-based placement against the 9 real device labels, which were found by feel on a
real hand (0.65/+0.39) — and those agree within about 0.05 hand-sizes. The shipped coach aims at
0.63/+0.38. That is good evidence that a "the marker is off the hand" report is not caused by the TE3
anchor math — but it rests on 9 labels from one session on the real side.

**3. Do not refit — or refine — the CURRENT coach with this dataset.** Two tests, both negative.
*Replacing* (section 3): a hand-frame TE3 model fit on the dataset alone is 98% inside the ring
within it (leave-one-skeleton-out) and 5/9 on the real labels it never saw (mean 0.158).
*Refining* (section 4): adding the synthetic labels to the shipped model's own fit makes it worse on
real hands at every weight tried, and monotonically — 0.124 with real labels only, 0.169 at equal
weight, 0.448 with synthetic only. As the synthetic weight grows the fit slides onto the
little-finger knuckle, because that is where Vision's joints sit relative to the label on renders.
The loss comes from Vision, not from the labels.

A correction to a number quoted earlier: the comment on TE3's weights in `Acupoints.swift` cites a
leave-one-out mean error of 0.096. Reproducing that fit here recovers the same weights (0.12 / 0.46 /
0.42 against the shipped 0.11 / 0.47 / 0.42) but a leave-one-out mean of **0.124** (6/9 inside the
ring). The difference is probably in how the original fit weighted or normalised its residuals; with
9 labels both are noisy. Every comparison in this README uses the reproduced number.

**4. SJ5 checks out, with less certainty.** Its formula uses only the wrist and middle MCP — the
frame itself — so it is the least exposed to the gap. The labels sit at −0.63 along against the
formula's −0.70, comfortably inside the 0.24 ring. There are no real SJ5 labels to confirm it, and
the dataset's ±10° animation says nothing about the forearm-rotation sensitivity that earned SJ5 its
"Reliability: low" note.

## What the paper shows, and why it does not contradict point 3

The authors trained HRNet-W48 — a network that reads the IMAGE and outputs the points directly — on
these renders, and report it working on real forearm photos: 5.67 ± 3.13 px against a real-data
baseline of 4.81 px, and on four external sets 5.84–6.45 mm versus 10.63–15.80 mm for the
real-trained model. They also report that the automatic labels beat a blinded manual re-annotation
of the same renders (12.76 px), which is the paper's point: generated labels are more consistent
than clicked ones.

That is a different architecture from AcuGuide's, and the difference is exactly the gap measured
above. An image-trained network never goes through Vision's joints, so Vision misreading renders
cannot hurt it. AcuGuide's coach does go through them, so it can. Two caveats keep the paper's
result from transferring wholesale even to an image model: HRNet-W48 is far heavier than anything
the coach runs per frame, and the paper's real test images are controlled top-down photos, not a
front-camera view of one hand pressing another.

## What would actually improve accuracy

For the coach as built: more **real** labels — several people, both hands, varied lighting, and the
occluded mid-press frames — captured with the existing label-capture tool (Settings → Developer in
Debug builds). Nine labels from one session is the binding constraint on every real-hand number here
— the shipped fit scores 0.112 on the labels it was fit on and 0.124 on a label it was not, which is
what a model short of data looks like.
If the coach ever moves to an image-based point detector, this dataset becomes a strong training
source rather than a check, and the real labels become its validation set.
