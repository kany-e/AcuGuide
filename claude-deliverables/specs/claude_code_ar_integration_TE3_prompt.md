# Claude Code Instructions — Ship TE3 position feedback as the demo hero (FIRST app change)

Paste into Claude Code. This is the first task that MODIFIES the React app. The calibration verdict
is in (diagnostics/calibration_results.md): **TE3/B position = GO (0.86 LOCO)** → the hero.
**PC6/A position = PARTIAL** (tiny n) → optional secondary. **Frequency = NO-GO for both** (genuine
aperiodicity, proven by an injection test) → do NOT ship any cadence/BPM/3-way label this round.

Follow /CLAUDE.md (locked decisions: no StrictMode, don't await video.play(), timestamp debounce).
Keep changes SURGICAL — extend the existing hooks/state machine. Respect immutable safety rules
(no treat/cure/heal/diagnose; forced SafetyPage ack; "felt worse"→stop; LI4 excluded).

## Read first
- diagnostics/calibration_results.md  ← TE3 GO + calibrated position tolerance (marked indicative).
- claude-deliverables/specs/demo_integration_spec.md  ← integration plan (position-only branch).
- src/data/acupoints.json, src/utils/geometry.ts, src/utils/drawOverlay.ts,
  src/hooks/usePressDetection.ts, src/hooks/useHandClassifier.ts, src/hooks/useCoachingState.ts.

## Implement
1. HERO = TE3 (anchors-based; already renders — no forearm extrapolation needed). Apply the calibrated
   position tolerance from calibration_results.md into acupoints.json for TE3 (keep it indicative).
2. PRESS FINGER per-point: replace the hardcoded `LANDMARKS.THUMB_TIP` in usePressDetection +
   drawOverlay with a per-point `press_finger` from acupoints.json — **INDEX_TIP for TE3** (the
   separated index is what the re-shoot used), default thumb otherwise.
3. POSITION + HOLD feedback ONLY:
   - ring at the TE3 target; `isOnTarget` (within tolerance) + `isStable` → existing
     SEARCHING → ON_TARGET_UNSTABLE → HOLDING → timer → COMPLETE flow.
   - Colors: on-target/holding → GREEN; off-target/searching → warning color. **No speed colors.**
   - SMOOTH the target point: apply a light temporal filter (One-Euro filter preferred, or an EMA
     with α≈0.4) to the `weightedTarget` output BEFORE both drawing the ring and the hit-test, so the
     ring doesn't jitter when the pressing finger occludes the ring/pinky knuckles. The calibration
     GO rested on the MEDIAN target position, not per-frame precision, so this just matches feedback
     to what's actually reliable. Keep the filter window short (low lag) so the ring still tracks fast
     hand movement; tune so it's steady under occlusion but doesn't visibly drag behind the hand.
4. DROP CADENCE entirely: do NOT build a cadence hook, BPM, or steady/fast/unstable label. Frequency
   was NO-GO. Ensure no rhythm color or "press faster/slower" copy ships. (recap may show hold time +
   position stability only — no rhythm grade.)
5. HAND-FACE GATE (required — currently the WRONG_FACE state never fires; see CLAUDE.md "还剩什么"):
   make useHandClassifier distinguish "hand present but WRONG face" → WRONG_FACE vs "no hand" →
   NO_HAND. For TE3 require BACK-OF-HAND (dorsal) toward camera. This is load-bearing: position alone
   cannot catch a wrong-face press (calibration's one false-accept was exactly a wrong-face clip).
6. SEPARATED-PRESSER gate: only treat a second, separately-detected hand as the presser (no
   "lone hand = presser"). When no separated presser or low confidence → coach the capture
   ("separate your pressing finger" / "bring it into the zone"), never emit a wrong verdict.
7. PC6 = optional secondary, position-only (PARTIAL). If time allows, add it behind the same gates
   using the receiving hand's forearm extrapolation (NOT Pose) + the calibrated PC6 target; otherwise
   leave it out of the demo path and say so. Do not ship PC6 cadence.

## Verify (required)
- `npx tsc --noEmit` clean; `npm run build` passes.
- Webcam smoke test of the TE3 routine: ring sits on the dorsal ring/pinky-knuckle region; turns
  GREEN on a steady on-target index press; warns when off-target; **WRONG_FACE fires when the palm is
  shown**; completes the hold timer.
- Occlusion-steadiness check: with the pressing finger covering the knuckles, the ring stays put
  (smoothing works) and does not jitter/jump; when the hand moves quickly, the ring still follows
  without visible lag (smoothing isn't over-damped).
- Confirm no cadence/BPM/3-way copy anywhere; safety copy clean; only necessary files changed.

## Deliver
- The app changes (per-point press finger, TE3 tolerance, position+hold color wiring, working
  hand-face gate), a short note of what changed and what was intentionally omitted (cadence NO-GO,
  PC6 status), and the verify results.
