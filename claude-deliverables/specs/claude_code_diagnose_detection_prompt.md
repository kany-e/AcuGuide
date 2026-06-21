# Claude Code Instructions — Diagnose the hand-detection failure (DIAGNOSE ONLY)

Paste into Claude Code, run from repo root. The video pipeline
(`src/extract_acupoint_features.py`) detects hands only ~30% of the time. We are
DIAGNOSING, not fixing — do NOT modify the production extractor or the React app.
New diagnostic files only. Surface assumptions; verify with data, don't guess.

## Step 1 — run the existing output analyzer and report the split
- Run: `python src/diagnose_outputs.py` (defaults to ./json).
- Summarize: the failure-bucket distribution, the true-CV-failure rate on valid
  attempts, and the failure rate by point (A=PC6/arm vs B=TE3/hand) and region.
- State the dominant failure stage:
  - "no_target_hand" dominant  -> MediaPipe isn't finding the hand (stage 1).
  - "no_pressing_finger" dominant -> the color/nail heuristic is the bottleneck (stage 2).
This decides what Step 2 focuses on. Paste the read-out into your summary.

## Step 2 — build a detection-variant harness (new file: src/diagnose_detection.py)
Goal: MEASURE which MediaPipe configuration actually recovers detection on the real
videos, especially the worst clips diagnose_outputs.py flagged. This is measurement
only — it must not change the extractor's behavior or outputs.

Inputs (auto-detect, but make them CLI flags; confirm paths before running):
- video dir (extractor default: `drive-download-20260620T234210Z-3-001`),
- `data/labels.csv`,
- pick the clip set = the worst ~6 valid-failure clips from Step 1 + 2 healthy clips
  as controls (so we see a config that helps failures without breaking the good ones).

For each clip, for each CONFIG below, process sampled frames and record, per frame:
  number of hands detected, target-hand present (>=1 hand), pressing-hand present
  (>=2 hands), mean detection score. Aggregate per clip: target_detect_ratio,
  pressing_detect_ratio, mean_score.

CONFIGS to compare (legacy mp.solutions.hands unless noted):
  C0  baseline = current settings (static_image_mode=True, model_complexity=1,
      max_num_hands=4, min_detection_confidence=0.35, max_width=960).
  C1  static_image_mode=False  (enable tracking across frames).
  C2  full resolution (no downscale).
  C3  C1 + full resolution.
  C4  MediaPipe Tasks HandLandmarker in VIDEO running mode (modern model), if the
      package is available; otherwise skip and note it.
  C5  Pose/Holistic FOREARM FALLBACK: run MediaPipe Pose; record whether wrist+elbow
      (and thus the forearm axis) are detected. This targets the PC6/arm case where
      Hands can't see a "hand". Report pose_forearm_detect_ratio per clip.

Output:
- a table: clip x config -> target_detect_ratio / pressing_detect_ratio / mean_score
  (and pose_forearm_detect_ratio for C5),
- write 3-4 overlay frames per (worst clip, best config) into diagnostics/overlays/
  so we can EYEBALL that detections are real, not phantom,
- a short read-out: which config most improves detection, broken down by point
  (PC6/arm vs TE3/hand), and whether Pose recovers the forearm clips.

## Constraints
- DIAGNOSE ONLY: do not edit src/extract_acupoint_features.py, the json/ outputs, or
  the React app. All new code in src/diagnose_detection.py (+ overlays in diagnostics/).
- Python, reuse the extractor's deps (cv2, mediapipe, numpy). If a config needs a
  package that's missing, skip it and say so — don't add heavy deps.
- Keep configs as a small named list so it's easy to add one. No fixing yet.
- Determinism: fixed frame sampling; print the exact frames used.

## Deliver
- src/diagnose_detection.py, the comparison table + overlays, and a written read-out
  recommending which config(s) to adopt — with the evidence. We decide the fix after
  seeing this; do not implement the production change in this task.
