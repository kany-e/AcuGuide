# Claude Code Instructions — Wire validated location + cadence into the AR feedback (FIRST app change)

Paste into Claude Code AFTER the calibration/validation completes. This is the first task that
MODIFIES the React app. Follow /CLAUDE.md (esp. the locked technical decisions: no StrictMode,
don't await video.play(), timestamp debounce not setTimeout) and keep changes SURGICAL — extend the
existing hooks/state machine, do not rewrite them. Respect the immutable safety rules (no
treat/cure/heal/diagnose; forced SafetyPage ack; "felt worse"→stop; LI4 excluded).

## Read first (ground the work in real results, not assumptions)
- diagnostics/calibration_results.md  ← the GO/PARTIAL/NO-GO per point per signal + the calibrated
  constants (per-point target/tolerance, the steady/fast Hz cutoff, the unstable CoV threshold).
- claude-deliverables/specs/demo_integration_spec.md  ← the integration plan (which point leads,
  what to show, what to drop, how it maps to the hooks). Implement THIS, parameterized by the results.
- src/data/acupoints.json, src/utils/geometry.ts, src/utils/drawOverlay.ts,
  src/hooks/usePressDetection.ts, src/hooks/useHandClassifier.ts, src/hooks/useCoachingState.ts.

## Implement (only what cleared GO/PARTIAL — do not ship a NO-GO signal)
1. HERO POINT = the point that cleared GO in calibration_results.md.
   - If it's PC6 (or any `extrapolation` point): implement the forearm extrapolation. Today
     geometry/usePressDetection/drawOverlay bail with `if (!anchors) return`, so PC6 never renders.
     Add a `computeTarget(landmarks, acupoint)` that handles BOTH the `anchors` (weighted sum) and
     the `extrapolation` case (point = wrist + k·handSize·normalize(wrist−middleMCP)), and route all
     three call sites through it. Use the CALIBRATED target/k from the results (the spec's k=1.1 was
     too far down the forearm).
   - If it's TE3 (anchors): it already renders; no extrapolation needed.
2. PRESS FINGER per-point: replace the hardcoded `LANDMARKS.THUMB_TIP` in usePressDetection +
   drawOverlay with a per-point `press_finger` from acupoints.json (THUMB_TIP for PC6, INDEX_TIP for
   TE3). Default to thumb if unspecified.
3. APPLY CONSTANTS: write the calibrated tolerance + (for the hero) target calibration into
   acupoints.json; add a small cadence config (steady/fast Hz cutoff, unstable CoV threshold).
4. CADENCE hook (new, e.g. src/hooks/useCadence.ts): the corrected estimator — 1-D press signal
   (fingertip displacement on the press axis) → dominant frequency via autocorrelation/FFT +
   refractory-gated peak counting (NOT frame-diff). Emit { class, hz, cov, confidence } where class ∈
   the SHIPPED set: full 3-way `steady|too_fast|unstable` only if cadence GO; otherwise the 2-way
   `steady|too_fast` fallback. Hz is internal only — never displayed as a number.
5. FEEDBACK COLOR: route position + cadence through useCoachingState → stateColor → drawOverlay ring
   + the CameraPage feedback card. COLOR MAPPING (confirm/adjust these — see note):
     on-target + steady  → GREEN  ("nice and steady")
     too_fast            → RED    ("ease the pace")
     too_slow/abstain    → AMBER  ("a little quicker") or omit if low confidence
     wrong location      → warning color ("move toward the highlighted spot")
6. HONEST GATING: when the pressing hand isn't a separated detected hand (hasPressing false) or
   cadence confidence is low → coach the capture ("bring your finger into the zone" / "separate your
   pressing finger"), NEVER emit a wrong color/verdict. Keep the existing NO_HAND/WRONG_FACE/SEARCHING
   states doing this.

## Verify (required)
- `npx tsc --noEmit` clean and `npm run build` passes.
- Replay-test against the validated re-shoot clips if feasible (the calibration outputs the per-frame
  signals); confirm the colors match the labels on the GO clips.
- Manual webcam smoke test of the hero routine: ring renders on the point, turns green on a steady
  on-target press, red on a fast one, warns when off-target.
- Confirm no existing repo file was changed beyond what's needed; no safety copy violates the rules.

## Deliver
- The app changes (geometry/computeTarget, per-point press finger, useCadence, color wiring,
  acupoints.json constants), a short note of exactly what changed and what was intentionally left
  out (NO-GO signals), and the verify results.

NOTE on color mapping: you earlier said "too fast = red, too slow = green." Conventionally green =
good/steady. Confirm the intended mapping before finalizing copy — it's a 3-line change either way.
