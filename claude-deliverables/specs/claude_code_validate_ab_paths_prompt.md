# Claude Code Instructions — Validate the A and B tracking paths (MEASUREMENT ONLY)

Paste into Claude Code, run from repo root. Diagnosis is done: target hand is detected
~100%; the failure is the PRESSING hand. The two points need different methods —
A = pressing thumb is a real landmark; B = pressing thumb is merged into the receiving
hand (no landmark) and must be tracked as optical flow. Build BOTH validation paths in
parallel. Do NOT modify src/extract_acupoint_features.py, the json/ outputs, or the
React app. New files only. Reuse the best detection config from the detection harness
(tracking / static_image_mode=False). Surface assumptions; verify with data.

Shared success bar for every clip: compare the recovered (position, frequency, motion
type) against `manual_label`. Anchor frequency to the motion_proxy (~1.8-2.1) / dataset
(~1 Hz) — NOT the frame-diff number, which double-counts. Output a per-clip predicted-vs-
label table, an accuracy summary, overlays, and a written GO / NO-GO per point.

---

## Track A — PC6 (the demo hero): landmark path  (new file: src/validate_a_path.py)
On A/arm clips the lone detected hand is the PRESSING hand; the receiving "target" is the
forearm (no hand landmarks). So:

- Localize the point with POSE, not the hand. Run MediaPipe Pose -> wrist + elbow ->
  forearm axis. Place the PC6 zone along that axis using the DATA-CALIBRATED location
  (centroid of fingertip positions on position=="correct" A clips; expect it ~u -0.3..-0.6
  down the forearm, NOT the spec's k=1.1 / u -1.1). Tolerance from the cluster spread.
  CAUTION: do NOT reuse the extractor's hand-local frame for A — that frame is anchored
  to the moving PRESSING hand, so it drifts. Build the frame from the Pose forearm.
- Track the press with the LANDMARK: thumb tip (lm 4) of the detected pressing hand
  (cross-check index tip lm 8). Trajectory of lm 4 over time.
- Position: is lm 4 inside the PC6 zone (distance < tolerance) -> predicted correct/wrong.
- Frequency: proper cadence from the lm-4 trajectory (peak-count the along-forearm
  component, or FFT the speed) -> Hz -> map to correct/fast/slow.
- Score vs manual_label.position and .frequency on all A clips; write overlays.

GO criterion for A: position prediction matches the label on most valid A clips, and the
frequency label is recovered from a sane Hz. If A clears this, it is the demo hero.

## Track B — TE3 (stretch): optical-flow path  (new file: src/validate_b_path.py)
On B/hand clips the receiving hand is detected ~100% but the pressing thumb is merged in
and has no landmark. So:

- Localize TE3 from the RECEIVING-hand landmarks (ring_mcp 13, pinky_mcp 17, wrist 0) —
  reliable. Build the ROI there.
- STABILIZE first: register frames to the receiving-hand landmarks (remove whole-hand
  drift) BEFORE running flow — the earlier probe showed ROI motion only ~0.9x frame
  average, so stabilization is required to lift the press above background.
- Dense optical flow inside the stabilized ROI; track the moving-region centroid.
- Frequency: ANGULAR TRAVEL of the centroid (or FFT of flow), NOT frame-diff zero
  crossings (those double the cadence). Report true Hz.
- Motion type: circularity from the centroid path (minor/major + angular coherence) ->
  circular vs in/out tap. Confirm a coherent circle, not isotropic jitter.
- Position: TE3 from landmarks; contact point ~ centroid of the moving region.
- Score vs manual_label.frequency AND vs the existing motion_proxy on all B clips.

GO criterion for B: recovered Hz matches manual_label.frequency mapping, and circular is
separable from tap above chance. If B does NOT clear this quickly, the fallback is a
capture-gesture change (separate the pressing finger so it gets its own landmark, like A)
— flag that rather than over-investing in flow.

## Constraints
- Measurement-only; no production/app changes; new files (+ overlays in diagnostics/).
- Reuse extractor deps (cv2, mediapipe, numpy, scipy) in the throwaway .venv-diag.
- Keep thresholds as named constants; print the exact clips/frames used.

## Deliver
- src/validate_a_path.py, src/validate_b_path.py, per-clip predicted-vs-label tables,
  overlays, and a written GO/NO-GO for each point with the evidence. We decide the
  production integration after seeing both.
