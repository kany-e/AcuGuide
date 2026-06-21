# Claude Code Build Prompt — Person A: Perception Layer (MediaPipe → FrameState)

One-time task spec to paste into Claude Code (run from repo root). Separate from the
always-on guidelines in `/CLAUDE.md`. Builds the upstream half of the CV pipeline that
feeds the existing `demo-app/cv/engine.js`.

---

You are working in the AcuGuide Hand Coach repo. Build the "Person A" PERCEPTION layer:
MediaPipe Hands -> per-frame FrameState, wired into the existing engine, plus a
record/replay harness so real camera recordings become fixtures. Vanilla JS to match
demo-app. Follow /CLAUDE.md (surface assumptions, surgical changes, verify with the data).

## Context / files (read these first)
- Geometry + safety spec:   claude-deliverables/data/acuguide_hand_points.json
- Existing engine (consumer): demo-app/cv/engine.js  <- emit the EXACT FrameState it reads
- Existing fixtures (shape):  claude-deliverables/fixtures/fixture_*.json
- Fixture generator (ref):    claude-deliverables/fixtures/generate_fixtures.py
- Tests:                      demo-app/cv/engine.test.js

## THE HARD CONSTRAINT — identical FrameState
The FrameState you emit live MUST be byte-compatible with what engine.js consumes and
what the fixtures contain (same keys, same semantics):
  t, frameIndex, fps,
  receivingHand: { present, handedness, face, handSize, landmarks[21] },
  pressingFinger: { present, contactPart, tipXY, tipLandmark },
  target: { id, name, surface, xy, toleranceR, trackable },
  contact: { onTarget, offset_xHandSize, depthProxy, insideEnterRadius, insideExitRadius },
  quality: { confidence, lowLight, wristInFrame }
Derive every threshold/geometry from acuguide_hand_points.json so live and synthetic
data agree — do NOT invent new numbers:
- handSize = dist(landmark[0], landmark[9]).
- On-model target = weighted sum of the point's `anchors` (weights, landmark indices).
- Off-model target (PC6/TE5, trackable=="off_model_extrapolated"):
  point = L0 + k*handSize*normalize(L0 - L9), k from the JSON (1.1).
- toleranceR = tolerance_radius_xHandSize * handSize.
- insideEnterRadius = dist(tip, target) < toleranceR;
  insideExitRadius   = dist(tip, target) < 1.6 * toleranceR  (same hysteresis as fixtures).
- onTarget == insideEnterRadius.

## What to build (new files under demo-app/cv/, do not modify engine.js's contract)
1. perception.js — MediaPipe Tasks Vision HandLandmarker loaded from CDN (no bundler;
   demo-app has no package step for the browser). For each video frame:
   - detect up to 2 hands; assign ROLES: the hand whose face matches the active point's
     required face is the RECEIVING hand; the other (if present) is the PRESSING hand.
     Its index-finger or thumb tip is the pressing fingertip (tipLandmark + tipXY).
   - infer hand FACE (palm vs dorsal) from handedness + thumb position relative to pinky.
   - compute target (on/off-model per above), contact fields, quality
     (confidence from detection score; lowLight from mean luma; wristInFrame = landmark 0 present & inside frame).
   - contactPart (tip/pad/base): best-effort from pressing-finger geometry; if not
     reliably inferable, default "tip" and DOCUMENT it as approximate.
   - emit one FrameState. Keep perception.js browser-only but pure-ish (no UI in it).
2. App wiring (in demo-app's existing page/script): webcam -> perception.js -> the
   existing engine (FeedbackStateMachine / runEngine) -> overlay UI: draw the target
   ring at target.xy with radius toleranceR, show the per-frame cue, timer ring, press
   count. Reuse engine.js as-is; don't fork its logic.
3. recorder.js — a "Record" toggle that buffers the live FrameState stream and exports
   a fixture file in the SAME shape as claude-deliverables/fixtures/*.json:
   { "_meta": { fixtureLabel, point, surface, durationSec, fps, scenario, groundTruth:{} },
     "frames": [FrameState] }. Download as JSON. groundTruth left empty for hand-labeling.
4. processVideo.js — load an uploaded .mp4/.webm, run HandLandmarker frame-by-frame at
   the file's fps, emit the same FrameState stream + export the fixture JSON. This turns
   the team's existing recordings into fixtures. Accept an optional labels JSON (the
   "labeled json incoming") and merge it into _meta.groundTruth.
5. A replay/validate path: feed any recorded fixture through engine.js and print the
   CoachState timeline; if _meta.groundTruth is present, compare (reuse the matcher style
   from engine.test.js). Add a node test that runs at least one REAL recording fixture.

## Tests / acceptance
- Live: webcam page runs, target ring tracks the hand, cue + timer + press count update,
  and PC6 shows the larger/softer ring and degrades gracefully when wristInFrame is false.
- A live "Record" produces a fixture that engine.test.js can load and run without changes.
- processVideo over one of the team's real recordings produces a fixture whose engine
  output matches the merged label (same matcher tolerance as engine.test.js).
- All existing engine tests still pass (npm test). No change to engine.js behavior.

## Constraints
- Vanilla JS, browser via CDN ESM for MediaPipe; no build step added to demo-app.
- Reuse constants from the JSON; expose any new ones as named, tunable consts.
- Surgical: new files + minimal wiring only; don't refactor engine.js or existing UI.
- Document FrameState fields that can't be reliably produced from a webcam
  (contactPart, depthProxy) as approximate, with how they're estimated.
- Keep perception.js free of DOM where practical so it stays unit-testable.

Deliver: perception.js, recorder.js, processVideo.js, the app wiring, a real-recording
test, a short README for the perception module, and the one-line command to run it.
