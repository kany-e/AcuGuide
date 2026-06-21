# Claude Code Build Prompt — Real-Recording Adapter (json/ clips → engine)

Paste into Claude Code (run from repo root). Separate from /CLAUDE.md. Builds the bridge
between the collaborator's processed clip JSONs (the `json/` folder) and the existing
`demo-app/cv/engine.js`, so real labeled recordings validate the engine.

> NOTE: the json/ data is preliminary ("not usable yet"). Build the adapter against the
> observed schema, but the items in OPEN QUESTIONS must be confirmed, not guessed
> (per /CLAUDE.md). Make each one a single named constant/config so it's trivial to set.

---

## Observed input schema (json/3852.json etc.)
Per clip:
  video_id, file, target ("A"|"B"), region_hint ("arm"|"palm"),
  duration_sec, source_fps, process_fps, sample_interval_sec (0.5),
  manual_label: { position, frequency, issue },     <- GROUND TRUTH
  quality: { target_region_visible, pressing_hand_present, frequency_reliable,
             confidence, ... },
  coordinate_system: target_hand_local_2d,
     u = wrist->middle_mcp (+toward fingers, -toward forearm),
     v = index_mcp->pinky_mcp (orthogonalized), scale = hand size (so u,v are
     hand-scale-normalized, i.e. same unit as engine's handSize),
  relative_location_samples[] @0.5s: { time_sec, u, v, contact_score, contact_source,
     finger_contact_detected, hand_count, target_hand_detected, pressing_hand_detected },
  press_or_rub_events[]: { time_sec, u, v, type:"cycle_peak", confidence },
  frequency_curve[]: { time_sec, hz, confidence },
  summary: { mean_frequency_hz, frequency_std_hz, cycle_count, mean_u, mean_v, std_u, std_v }

## Confirmed config (lock these as named constants at top of adapter.js)
POINT_MAP = {
  "A": { id: "PC6", name: "Neiguan", surface: "palmar", trackable: "off_model_extrapolated", TOL: 0.22 },
  "B": { id: "TE3", name: "Zhongzhu", surface: "dorsal", trackable: "on_model",            TOL: 0.16 }
}
- A = PC6 (forearm / "arm" region). B = TE3 (dorsal hand).
- DATA FLAG: the B clips carry region_hint "palm", but TE3 is dorsal (back of hand), not
  palmar. Treat POINT_MAP as authoritative, but verify the B recordings actually show TE3
  before trusting their labels.
COORDINATE FRAME (confirmed): u,v = PRESSING fingertip relative to the TARGET hand's wrist
(landmark 0). u axis = wrist->middle_mcp (+fingers / -forearm); v axis = index_mcp->pinky_mcp;
size-normalized. So each point has its OWN (u,v) location; on-target = distance to THAT, not origin.

TARGET_UV (calibrate from data — do NOT hardcode the geometry):
- Compute TARGET_UV[A=PC6] and TARGET_UV[B=TE3] as the CENTROID of fingertip (u,v) over all
  clips whose manual_label.position=="correct" for that target. Set per-point tolerance from
  the cluster spread (e.g. ~2*std, floored at TOL above). This makes on-target agree with the
  human labels by construction.
- CALIBRATION FINDING: PC6 "correct" clips cluster around u ~ -0.2..-0.6 (mean -0.22), NOT the
  spec's extrapolated u ~ -1.1 (k=1.1). The synthetic geometry places PC6 too far down the
  forearm vs where it was actually filmed. Trust the data centroid here, and flag that the
  acuguide_hand_points.json PC6 extrapolation k likely needs reducing for the real demo.

## What to build: adapter.js  (json/ clip -> FrameState[] + groundTruth)
For each clip, emit a fixture { "_meta": {...}, "frames": [FrameState] } that engine.js
and engine.test.js can consume unchanged:

Per relative_location_sample -> one FrameState:
- t = time_sec; fps = round(1/sample_interval_sec) (=2); frameIndex = running index.
- receivingHand: { present: target_hand_detected, handedness: <unknown/null>,
    face: faceForPoint(point), handSize: 1.0 (u,v already hand-normalized), landmarks: null }.
- pressingFinger: { present: pressing_hand_detected,
    contactPart: "tip", tipXY: [u, v], tipLandmark: parseTip(contact_source) }.
- target: { id: pointFor(target), name, surface, xy: TARGET_UV[point] (calibrated centroid),
    toleranceR: TOL[point], trackable: trackableFor(point) }.
- contact: offset = dist([u,v], TARGET_UV[point]);   // distance to the point, NOT to origin
    onTarget = finger_contact_detected && offset < TOL[point];
    insideEnterRadius = offset < TOL[point];
    insideExitRadius  = offset < 1.6*TOL[point];
    depthProxy = contact_score.
- quality: { confidence: sample/clip confidence, lowLight: false, wristInFrame: target_hand_detected }.

_meta.groundTruth (mapped from manual_label, SEE Q4/Q5):
- expected position: "correct" -> expect on-target reached; "wrong"/null + issue -> WRONG_POSITION / NO_HAND.
- expected_rhythm: map manual_label.frequency -> {correct:"rhythm_good", fast:"rhythm_too_fast",
    slow:"rhythm_too_slow"} ; null/unreliable -> "n/a".
- expected_pressCount: summary.cycle_count.
- expected_issue: manual_label.issue.

## CRITICAL: rhythm/press counts come from the clip, NOT recomputed
The samples are 0.5s (2 Hz). Tapping is ~0.5-1.5 Hz, so cycles CANNOT be recovered from
these samples (Nyquist). Do NOT run countPresses on adapted frames. Instead:
- carry summary.cycle_count and summary.mean_frequency_hz / frequency_curve into _meta,
- the engine's position + state-machine logic may run on the samples for the PHASE
  sequence, but RHYTHM/COUNT assertions use the clip's precomputed values.
Add a clear seam so the engine can accept "precomputed rhythm" instead of deriving it.

## Tests / acceptance
- adapter.js converts a clip into a fixture that engine.test.js loads without changes.
- For each labeled clip with reliable quality, the engine's position/phase outcome +
  the clip's precomputed rhythm match manual_label (same matcher tolerance style as
  engine.test.js). Low-quality / pressing_hand_absent clips map to NO_HAND / n/a, not failures.
- Existing synthetic-fixture tests still pass (npm test). engine.js behavior unchanged.

## OPEN QUESTIONS — confirm with the collaborator; encode each as a named const, don't guess
Q1. [RESOLVED] A = PC6 (forearm, off-model, TOL 0.22), B = TE3 (dorsal hand, on-model, TOL 0.16).
    See POINT_MAP above. Still verify the B-clip region_hint "palm" vs TE3-dorsal discrepancy.
Q2. [RESOLVED] origin = TARGET hand's wrist (landmark 0); u,v = pressing fingertip in that
    hand-local size-normalized frame. Each point has its own TARGET_UV; offset = dist to it.
Q3. [RESOLVED via calibration] derive TARGET_UV + tolerance from the position=="correct"
    clusters per point (see TARGET_UV note). Floor tolerance at tolerance_radius_xHandSize.
Q4. frequency label thresholds: the hz cutoffs that define correct vs fast (vs slow), and
    whether summary.mean_frequency_hz is authoritative. Full enum of manual_label.frequency.
Q5. full enums of manual_label.position and manual_label.issue (e.g. "pressing_hand_absent",
    orientation, edge-touch...), so groundTruth mapping is complete.
Q6. confirm: trust precomputed cycle_count/frequency (do not recount from 0.5s samples).

## Constraints
- Vanilla JS to match demo-app; adapter pure + unit-testable; new files only.
- Reuse engine.js as-is; add only the "precomputed rhythm" seam if needed, minimally.
- Keep the Q1-Q6 choices as named constants at the top of adapter.js.

Deliver: adapter.js, a test that adapts >=1 real clip and checks it against manual_label,
a short README, and the run command.
