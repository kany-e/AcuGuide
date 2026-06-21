# AcuGuide Re-shoot Shot List (validation set)

Purpose: validate the **constrained capture** that makes both points landmark-trackable, and supply
the **cadence examples** (esp. `unstable`) the 3-way label needs. ~22 clips, 8–10 s each, 30 fps.
This is a validation set, not a training dataset — small and balanced beats large and messy.

## The one rule that makes this work
**One clearly SEPARATED pressing finger that gets its own MediaPipe landmark — never merged/flat on
the receiving hand.**
- **PC6 (A):** press with the **THUMB** on the palm-up forearm, thumb lifted/distinct.
- **TE3 (B):** press with a **separated INDEX finger** (the thumb is what merged on TE3) — index
  extended, tip on the back-of-hand groove, kept clearly off the receiving hand.

## Pre-flight checklist (applies to EVERY clip)
- [ ] Camera **fixed** (tripod/propped), **frontal, slightly above**, ~40–60 cm; hand fills a good
      part of the frame. (Matches the live demo angle — don't shoot at 45°.)
- [ ] Point anatomy framed: **PC6** = palm-up forearm with **wrist AND as much elbow as possible**
      in frame (Pose needs the elbow); **TE3** = back of hand, ring+pinky knuckles visible.
- [ ] **One hand-pair only.** No other hands/faces in frame.
- [ ] Bright, even light; **no backlight**; plain background (not skin-toned).
- [ ] Pressing finger stays **separated** the whole clip (the make-or-break).
- [ ] One label per clip; hold the gesture for the full 8–10 s.
- [ ] Across the set: record **both left and right** hands, and **2–3 different people** if possible.

## Cadence targets (use a metronome on a second phone)
- **steady (`correct`)** ≈ **1 tap/sec** (~8–10 presses in the clip).
- **too_fast (`fast`)** ≈ **2.5–3 taps/sec**.
- **unstable** = **deliberately erratic** — alternate fast bursts with pauses, change speed mid-clip.
  These are the most important NEW clips; the old data had none, so the 3rd bucket couldn't calibrate.

## Shot table (×2 takes each unless noted)
| # | id stem | point | finger | position | rhythm | issue | what to do |
|---|---------|-------|--------|----------|--------|-------|-----------|
| 1 | A_corr_steady | PC6 (A) | thumb | correct | steady | — | thumb on PC6 zone, ~1 Hz |
| 2 | A_wrong_steady | PC6 (A) | thumb | **wrong** | steady | — | press ~1 hand-width OFF the zone, ~1 Hz |
| 3 | A_corr_fast | PC6 (A) | thumb | correct | **fast** | — | on zone, ~3 Hz |
| 4 | A_corr_unstable | PC6 (A) | thumb | correct | **unstable** | — | on zone, erratic bursts/pauses |
| 5 | A_nopress (×1) | PC6 (A) | — | — | — | pressing_hand_absent | forearm only, no pressing hand |
| 6 | A_wrongface (×1) | PC6 (A) | thumb | — | steady | orientation_wrong | forearm wrong side toward camera |
| 7 | B_corr_steady | TE3 (B) | index | correct | steady | — | index on TE3 groove, ~1 Hz |
| 8 | B_wrong_steady | TE3 (B) | index | **wrong** | steady | — | press OFF the groove, ~1 Hz |
| 9 | B_corr_fast | TE3 (B) | index | correct | **fast** | — | on zone, ~3 Hz |
| 10 | B_corr_unstable | TE3 (B) | index | correct | **unstable** | — | on zone, erratic |
| 11 | B_nopress (×1) | TE3 (B) | — | — | — | pressing_hand_absent | back of hand only, no presser |
| 12 | B_wrongface (×1) | TE3 (B) | index | — | steady | orientation_wrong | palm toward camera (should be dorsal) |
| 13 | NOHAND (×2) | — | — | — | — | no_hand | empty background, no hand |

Count: rows 1–4 and 7–10 are ×2 takes (16), rows 5,6,11,12 are ×1 (4), row 13 ×2 (2) = **22 clips**.

## Filename + labels.csv (matches the extractor's loader exactly)
Name files `AG_<idstem>_<take>.mov` (e.g. `AG_A_corr_unstable_1.mov`). Build `data/labels.csv` with
these columns — `video_id,file,target,region_hint,position_label,frequency_label,issue_label`:

```csv
video_id,file,target,region_hint,position_label,frequency_label,issue_label
AG_A_corr_steady_1,AG_A_corr_steady_1.mov,A,arm,correct,correct,
AG_A_corr_steady_2,AG_A_corr_steady_2.mov,A,arm,correct,correct,
AG_A_wrong_steady_1,AG_A_wrong_steady_1.mov,A,arm,wrong,correct,
AG_A_wrong_steady_2,AG_A_wrong_steady_2.mov,A,arm,wrong,correct,
AG_A_corr_fast_1,AG_A_corr_fast_1.mov,A,arm,correct,fast,
AG_A_corr_fast_2,AG_A_corr_fast_2.mov,A,arm,correct,fast,
AG_A_corr_unstable_1,AG_A_corr_unstable_1.mov,A,arm,correct,unstable,
AG_A_corr_unstable_2,AG_A_corr_unstable_2.mov,A,arm,correct,unstable,
AG_A_nopress_1,AG_A_nopress_1.mov,A,arm,,,pressing_hand_absent
AG_A_wrongface_1,AG_A_wrongface_1.mov,A,arm,,steady,orientation_wrong
AG_B_corr_steady_1,AG_B_corr_steady_1.mov,B,hand_dorsal,correct,correct,
AG_B_corr_steady_2,AG_B_corr_steady_2.mov,B,hand_dorsal,correct,correct,
AG_B_wrong_steady_1,AG_B_wrong_steady_1.mov,B,hand_dorsal,wrong,correct,
AG_B_wrong_steady_2,AG_B_wrong_steady_2.mov,B,hand_dorsal,wrong,correct,
AG_B_corr_fast_1,AG_B_corr_fast_1.mov,B,hand_dorsal,correct,fast,
AG_B_corr_fast_2,AG_B_corr_fast_2.mov,B,hand_dorsal,correct,fast,
AG_B_corr_unstable_1,AG_B_corr_unstable_1.mov,B,hand_dorsal,correct,unstable,
AG_B_corr_unstable_2,AG_B_corr_unstable_2.mov,B,hand_dorsal,correct,unstable,
AG_B_nopress_1,AG_B_nopress_1.mov,B,hand_dorsal,,,pressing_hand_absent
AG_B_wrongface_1,AG_B_wrongface_1.mov,B,hand_dorsal,,steady,orientation_wrong
AG_NOHAND_1,AG_NOHAND_1.mov,A,arm,,,no_hand
AG_NOHAND_2,AG_NOHAND_2.mov,B,hand_dorsal,,,no_hand
```
> Note `region_hint` for B is `hand_dorsal` (TE3 is the **back** of the hand — the old clips' `palm`
> tag was wrong; don't repeat it).

## Pass criteria (what makes this re-shoot a success)
- **Separation worked:** on the `correct`/`fast`/`unstable` clips, the pressing finger is detected as
  its **own hand** (≥2 hands) in the large majority of frames — i.e. `pressing_hand_detected_ratio`
  jumps from ~0 (old merged clips) toward the 0.9+ the healthy clips showed. This is the headline.
- **Position separates:** `correct` vs `wrong` clips are distinguishable by the in-zone test.
- **Cadence separates:** `steady` / `fast` / `unstable` are separable by the corrected estimator and
  beat a phase-shuffle null (this is what lets the 3-way label ship).

## After shooting
Run the existing extractor on the new clips, then `validate_a_path.py` and `validate_cadence_3way.py`
against these labels. If `pressing_hand_detected_ratio` is high on the new clips, the capture fix is
confirmed and both position + the 3-way cadence become validatable.
