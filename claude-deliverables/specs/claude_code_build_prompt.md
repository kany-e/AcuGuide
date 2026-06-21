# Claude Code Build Prompt — CV Feature-Extraction + Feedback Engine

One-time task spec to paste into Claude Code (run from the repo root). This is a
build instruction, separate from the always-on guidelines in `/CLAUDE.md`.

---

You are working in the AcuGuide Hand Coach repo. Build the CV feature-extraction
+ feedback engine ("Person B" layer) and a test suite that validates it against
pre-recorded fixtures. This is RULE-BASED logic, not a trained deep-learning model.

## Context / files (read these first)
- Acupoint + geometry spec:   claude-deliverables/data/acuguide_hand_points.json
- Replay fixtures (test data): claude-deliverables/fixtures/fixture_1..5_*.json
- Fixture generator (for ref):  claude-deliverables/fixtures/generate_fixtures.py
- Existing app:                 demo-app/   <- inspect this and MATCH its language/
                                framework (JS/TS/React, etc.). Put new code there.

## Input contract (each fixture = { "_meta": {...}, "frames": [FrameState] })
A FrameState (one per camera frame, ~30fps) contains:
  t, frameIndex, fps,
  receivingHand: { present, handedness, face, handSize, landmarks[21] },
  pressingFinger: { present, contactPart, tipXY, tipLandmark },
  target: { id, name, surface, xy, toleranceR, trackable },
  contact: { onTarget, offset_xHandSize, depthProxy, insideEnterRadius, insideExitRadius },
  quality: { confidence, lowLight, wristInFrame }
Position correctness (onTarget) is already provided per frame. Your job is the
TEMPORAL layer on top of it.

## What to build (pure, deterministic functions + a state machine)
1. countPresses(frames): count press cycles using HYSTERESIS — a press starts when
   insideEnterRadius goes true, ends when insideExitRadius goes false; ignore exits
   shorter than ~0.4s (release jitter). One enter->exit = one press.
2. classifyRhythm(frames, windowSec=10): cycles in window -> 0-2 "too_slow/none",
   3-6 "rhythm_good", 7+ "rhythm_too_fast". Separately flag "rhythm_unstable" when
   the variance of inter-press intervals is high (忽快忽慢), independent of count.
3. classifyMotion(frames): "hold" (offset variance ~0), "circular" (fingertip
   trajectory has steady angular travel around target.xy), "repeated" (in/out
   oscillation), or "none".
4. FeedbackStateMachine: NO_HAND -> WRONG_FACE -> SEARCHING -> ON_TARGET_UNSTABLE
   -> HOLDING -> PAUSED -> COMPLETE, exactly per the feedback_state_machine section
   of acuguide_hand_points.json. Emit a CoachState per frame:
   { phase, motion, pressCount, holdTime_s, stabilityPct, rhythm, cue }.
   Pull cue text from the active point's coach_copy in the JSON.
5. A loadFixture(path) helper and a runEngine(frames) that returns the final
   CoachState + the ordered list of distinct phases seen.

## Tests (this is the deliverable that must pass)
Using the repo's existing test runner, add tests that for EACH fixture:
- load it, run the engine over frames,
- assert the observed distinct-phase sequence matches _meta.groundTruth.expected_phase_sequence
  (allow extra transient states but the key ones must appear in order),
- assert pressCount == groundTruth.expected_pressCount (±1 tolerance),
- assert rhythm classification == groundTruth.expected_rhythm.
All 5 fixtures must pass. fixture_5_te3_full_flow is the end-to-end smoke test.

## Constraints
- Match demo-app's language; if it's JS/TS, no Python. Keep functions pure and unit-testable.
- Use thresholds from the JSON/spec (toleranceR per point; enter vs 1.6x exit radius;
  rhythm 3-6 good / 7+ fast). Make thresholds named constants, easy to tune.
- Handle the PC6 off-model case: if target.trackable=="off_model_extrapolated" and
  quality.wristInFrame is false, treat as low-confidence (don't advance the timer).
- Do NOT modify existing repo files except to register the new module/tests. Add a
  short README for the new module.
- (Optional, only if trivial) expose classifyMotion behind an interface so a small
  learned classifier could replace the heuristic later — but ship the heuristic now.

Deliver: the engine module, the test file, and a one-line command to run the tests.
