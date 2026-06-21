# Claude Code Instructions — Calibrate + validate frequency & location on the NEW clips

Paste into Claude Code, run from repo root. We have new (correctly-shot) labeled clips. Produce
VALIDATED location + frequency outputs and emit the calibrated constants the AR app will use.
This is CALIBRATION + VALIDATION of rule-based estimators, NOT ML training — n is ~22 clips, so a
learned model would overfit; calibrate thresholds and prove they generalize (leave-one-clip-out).
Measurement/calibration only: do NOT modify the React app yet. Use the .venv-diag. Be adversarial
about your own numbers and state the small-n caveat.

Inputs: the new video folder (ask the user for the path) + data/labels.csv built from
claude-deliverables/specs/reshoot_shot_list.md (columns: video_id,file,target,region_hint,
position_label,frequency_label,issue_label).

## STEP 0 — detection gate (do this first; it can stop everything)
Run src/extract_acupoint_features.py on the new clips, then report per clip:
`target_hand_detected_ratio` and `pressing_hand_detected_ratio`.
- If pressing_hand_detected_ratio is high (toward ~0.8+) on the press clips → the separated-finger
  capture worked → proceed.
- If it's still ~0 → the capture did NOT separate the finger (likely oblique angle / cropped elbow,
  like the earlier sample). STOP, report it, and recommend a re-shoot. Calibration on undetected
  presses is meaningless. Do not paper over this.

## STEP 1 — LOCATION (position correct vs wrong)
- Build the press point in the target-hand-local frame (or Pose-forearm frame for PC6/A).
- CALIBRATE per point: TARGET = centroid of the pressing-fingertip (u,v) over `position==correct`
  clips; TOLERANCE = cluster spread (floor at the JSON tolerance_radius_xHandSize).
- Classify each clip correct/wrong by distance-to-TARGET; report accuracy + 2x2 confusion vs label.
- Use leave-one-clip-out for the threshold so it isn't fit and tested on the same data.

## STEP 2 — FREQUENCY (3-way steady / too_fast / unstable)
- CORRECTED estimator (the 0.50 was a broken estimator): 1-D press signal = fingertip displacement
  projected on the press axis (PCA), detrend + bandpass ~0.3-4 Hz, dominant frequency by
  autocorrelation/FFT, cross-checked with refractory-gated (>=0.3 s) peak counting. NOT frame-diff
  zero-crossings (that doubled the cadence).
- CALIBRATE from labels: the Hz cutoff separating steady vs too_fast, and the inter-interval CoV
  threshold for unstable.
- Classify 3-way; report a 3x3 confusion matrix + per-class accuracy; PHASE-SHUFFLE NULL per clip
  (abstain on clips that fail the null); leave-one-clip-out for the cutoffs.

## STEP 3 — EMIT CONSTANTS + verdict
Write diagnostics/calibration_results.md with:
- per-point TARGET (u,v) + tolerance, the Hz cutoff, the CoV threshold — in a copy-paste block ready
  to wire into acupoints.json (tolerance) and a new cadence config.
- GO / PARTIAL / NO-GO per point and per signal (location, frequency), with the accuracy numbers,
  null results, and the small-n caveat stated plainly.
- Explicit recommendation: which point(s) and which signals are demo-trustworthy.

## Constraints
- No app changes; new files + diagnostics report only. Reuse extractor deps in .venv-diag.
- Named constants; print exact clips/frames used. If a signal only passes by overfitting a handful
  of clips, say so and mark it PARTIAL, not GO.

## Deliver
- the calibration/validation script(s), diagnostics/calibration_results.md (constants + confusion
  matrices + GO/PARTIAL/NO-GO), and a 5-7 sentence summary. After this we decide color mapping,
  hero point, and AR integration from REAL numbers.
