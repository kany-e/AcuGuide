> ⛔ SUPERSEDED / DO NOT USE FOR THE PRODUCT. A lift-and-tap is NOT correct acupressure technique
> for a point like TE3 — the proper method is a SUSTAINED press with light small-circular contact
> (you don't lift off). Coaching a tap would teach wrong practice. Correct technique has no countable
> cadence, which is why every cadence attempt failed the null — it's the gesture, not the camera.
> SHIP INSTEAD: position + sustained hold-time + steadiness (see claude_code_ar_integration_TE3_prompt.md).
> This file is kept only as a record of why cadence was dropped.

# Tap-Cadence: gesture spec + minimal validation (top-down, deployment view)

Goal: get a trustworthy cadence signal from the ACTUAL deployment view — camera top-down on the
massaging hand. The earlier NO-GO was not the view (an injection test proved a clean repetitive press
at the observed amplitude IS detectable from these top-down clips); it was (1) the hand getting
cropped and (2) the gesture not being a clean repetitive motion. Both are fixed by defining the
gesture as a visible TAP and measuring FINGER FLEXION (not depth).

## 1. The gesture the routine coaches
Reframe the cadence step as a **rhythmic tap** (a legitimate tapping/percussion-style self-massage),
NOT a sustained press or smooth rub (those have no cadence to measure — from any camera).
- Press the point, then **clearly lift the finger off and tap back down**, repeating at a steady pace.
- The whole pressing finger **visibly flexes/extends** each tap — that's what the top-down camera sees.
- Keep the **pressing hand fully in frame** (the #1 cause of the failed clips was a cropped/edge hand).
- On-screen coaching copy (no medical claims): "Tap the spot in a steady rhythm — lift your finger
  fully between taps." If the hand drifts out of frame: "keep your whole hand in the circle."

## 2. Why this is measurable top-down (the technical key)
A press straight into the skin is depth motion a 2D camera can't see. But a TAP **flexes the finger**,
and MediaPipe gives the fingertip AND the knuckle — so the **tip↔MCP distance (finger curl) changes
in the 2D image** every tap, independent of depth. That curl signal is the cadence signal. It is far
more robust than the raw fingertip pixel position (which jitters) or any depth/z estimate (unreliable).

## 3. Minimal validation shoot (~6 clips, top-down, hand fully in frame, metronome on)
| id | gesture | rate | purpose |
|---|---|---|---|
| tap_steady_1/2 | rhythmic tap | ~1 Hz (metronome) | steady cadence, ×2 |
| tap_fast_1/2 | rhythmic tap | ~2.5 Hz | fast cadence, ×2 |
| hold_1 | sustained press, NO tapping | — | negative control: must count ~0 / abstain |
| tap_irregular_1 | deliberately erratic tap | varies | (optional) unstable example |
Shoot the pressing INDEX finger on the back of the hand (TE3 staging) so it doubles as a position
clip. Label each by its metronome rate (ground truth).

## 4. Claude Code validation prompt (paste after shooting)
```
Validate a top-down TAP-cadence estimator on the new tap clips. Measurement only — no app changes.
Use .venv-diag + the Tasks-API HandLandmarker (the legacy mp.solutions extractor can't run on Py3.14).

Videos: <folder>. Label each clip with its metronome rate (taps/sec) + a "hold" negative.

Estimator (measure FINGER FLEXION, not depth or raw tip pixels):
- For the pressing finger, build a 1-D signal = tip↔MCP distance (e.g. landmarks 8↔5 for index),
  normalized by handSize, per frame. Also try total finger-curl (sum of segment angles) and pick the
  cleaner one. Detrend + bandpass ~0.3–4 Hz.
- Count taps two independent ways: refractory-gated peak counting (refractory ≥0.25 s) AND
  autocorrelation/FFT dominant frequency. They must AGREE (within ~15%) or abstain.

Validate honestly:
- counted rate vs the metronome ground truth — report error per clip (target: within ±1 tap over the clip).
- PHASE-SHUFFLE NULL per clip: the periodicity must beat shuffled surrogates.
- the HOLD clip must NOT produce a spurious cadence (must abstain / count ~0) — this is the key
  false-positive test.
- if the two counters disagree or the null fails, ABSTAIN; do not force a number.

Output diagnostics/tap_cadence_report.md: per-clip counted-vs-metronome, null results, the hold-clip
result, GO/NO-GO, and (if GO) the calibrated steady-vs-fast cutoff. State the small-n caveat.
```

## 5. GO criterion (so "cadence" stops being a maybe)
GO if: counted rate matches the metronome within ±1 over the clip on the tap clips, beats the null,
AND the hold clip correctly abstains. If GO, wire it into the app as a simple **tap counter / coarse
steady-vs-fast** (still no BPM number shown); if NO-GO even on clean taps, cadence is genuinely out and
we ship position + hold only.

> Honest scope: this only claims cadence for a deliberate, visible, in-frame tap. A sustained hold or
> smooth rub has no cadence to measure — that's a gesture choice, not a CV limitation.
