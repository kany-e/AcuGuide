# Claude Code Instructions — Earn the 3-way cadence label (MEASUREMENT ONLY)

Paste into Claude Code, run from repo root. The 3-way `steady / too_fast / unstable` rhythm label
is a PRODUCT REQUIREMENT. It scored ~0.50 (chance) earlier, but on un-separated fingers fed through
a BROKEN estimator (frame-diff `find_peaks`, ~1.5x inflation + doubling) — not because it's
impossible. Build a CORRECTED estimator + 3-way classifier and honestly measure whether it clears a
real bar. Do NOT modify src/extract_acupoint_features.py, the json/ outputs, or the React app — new
file(s) only. Use the throwaway .venv-diag. Surface assumptions; verify with data.

## Build: src/validate_cadence_3way.py
Input = the pressing-finger landmark TRAJECTORY (clean), in the receiving-hand-local frame.
Source it from the validated A path (lm-4/lm-8 of the separated pressing hand). Two data sources:
- NOW: the cleanest existing ONE-HAND A clips (e.g. 3858/3859/3860 + any labeled correct/fast) for
  an early read before any re-shoot.
- LATER: the constrained re-shoot clips (separated-finger capture) — same script, more data.

Corrected cadence estimator (fix the doubling/aliasing):
- Build a 1-D press signal = fingertip displacement projected onto the dominant press axis
  (PCA of the trajectory, or toward/away-from-target component). Detrend + bandpass ~0.3-4 Hz.
- Estimate dominant frequency by AUTOCORRELATION and/or FFT of that signal — NOT frame-diff
  zero-crossings. Cross-check with refractory-gated peak counting (refractory >= 0.3 s); one full
  min->max->min = one cycle (this is what was double-counting).
- Output: mean Hz, inter-interval CoV (coefficient of variation), and a periodicity confidence.

3-way classifier:
- steady    = periodic, mean Hz within the target range,
- too_fast  = mean Hz over the calibrated cutoff,
- unstable  = inter-interval CoV over threshold REGARDLESS of mean (maps to engine rhythm_unstable),
- (none/low-confidence = periodicity confidence too low -> abstain, don't force a bucket).
Calibrate the Hz cutoff and CoV threshold from the labeled clips (don't hardcode blindly).

## Validate honestly (this is the deliverable)
- Per-class accuracy + a 3x3 confusion matrix vs manual_label.frequency.
- PHASE-SHUFFLE NULL per clip: the estimated periodicity must beat shuffled-signal surrogates
  (else the clip has no real cadence and must abstain, not guess).
- If enough clips: leave-one-clip-out so cutoffs aren't fit and tested on the same data.
- Report the headline: does it beat 0.50 (3-class chance), and does it beat the null?

## GO / NO-GO
- GO (ship 3-way): beats chance with margin AND passes the null on the clips that carry a real
  cadence. Recommend the calibrated cutoffs.
- PARTIAL: steady-vs-too_fast separable but "unstable" not reliable -> recommend shipping 2-way now,
  keep "unstable" behind the gate until the re-shoot gives more unstable examples.
- NO-GO on current data: report it plainly and recommend the constrained re-shoot is required before
  the 3-way label can ship. Do NOT ship a label that only passes by overfitting 4 clips.

## Constraints
- Measurement-only; no production/app changes; new file(s) + a short report in diagnostics/.
- Reuse deps in .venv-diag; thresholds as named constants; print exact clips/frames used.
- Be adversarial about your own result (you have ~4 labeled clips now — say so; small-n is a real
  caveat, and the re-shoot is what makes the verdict trustworthy).

## Deliver
- src/validate_cadence_3way.py, diagnostics/cadence_3way_report.md (confusion matrix, null results,
  recommended cutoffs, GO/PARTIAL/NO-GO), and a 4-6 sentence summary. We decide production wiring
  after seeing it.
