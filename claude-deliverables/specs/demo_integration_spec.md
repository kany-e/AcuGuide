# Demo Integration Spec — what the LIVE app should do given A=PARTIAL / B=NO-GO

**Status:** decision spec, grounded in `diagnostics/AB_validation_GO_NO_GO.md`,
`validate_a_report.md`, `validate_b_report.md`. Measurement-only validation; n=10 clips/point,
so numbers are indicative, not statistical. This document describes integration intent only —
**no repo files are modified** here.

The validation verdict is blunt: the **receiving (target) hand is detected ~100%**; the hard
part is tracking the **pressing finger**. The pressing finger is only landmark-trackable when it
is **separated** from the receiving hand (gets its own MediaPipe hand). The whole demo strategy
follows from that one fact.

---

## 1. Which point leads, and what we DROP

### Lead point: PC6 (`menstrual_discomfort`)

| Symptom | Point | Hand face | Demo role |
|---|---|---|---|
| `menstrual_discomfort` | **PC6** | palm to camera, forearm framed | **LEAD — Track A, controlled one-hand capture** |
| `tension_headache` | TE3 | back of hand to camera | Secondary / position-only (Track B path was NO-GO) |
| `neck_shoulder_tension` | SI3 | back / ulnar edge to camera | Secondary / position-only |

**Why PC6 leads:** Track A's thumb-landmark path is the only one that **verified as viable**, and
only on **clean one-hand captures** (clips 3858/3859/3860: localize 0.65–0.84, position correct,
cadence the same order as `motion_proxy`). PC6 is a two-hand gesture (thumb of one hand presses
the other forearm), so the **pressing thumb is naturally separated** → it gets its own MediaPipe
landmark and is trackable. TE3 was Track B (dorsal hand, thumb **merged** onto the receiving
hand): optical flow was **NO-GO** (angular coherence ~0.01–0.13, ROI localization 0.31× background
< 1, cadence halves/doubles). We do not lead with a point whose pressing finger cannot be tracked.

### What to DROP for the demo (do not ship, do not claim)

1. **Precise BPM / a numeric press rate.** The cadence estimator inflates ~1.5× and **doubles**
   on some clips; a phase-shuffle null found **2 of 4** labeled clips have **no statistically real
   cadence**. Never show a number like "2.3 Hz" or "138 bpm."
2. **The 3-way `correct / fast / unstable` rhythm label — REQUIRED, but GATED (see §3-way below).**
   It scored **0.50** (≈chance) on the *existing* footage — but that was on un-separated/merged
   fingers fed through a broken estimator (frame-diff `find_peaks`, ~1.5× inflation + doubling).
   It is a product REQUIREMENT, so it is not dropped; instead it must be EARNED on the constrained
   capture with a corrected estimator and then re-validated against a phase-shuffle null before it
   ships. Until it clears that bar, the live app shows only the coarse two-way hint as a fallback.
3. **Any "circular motion" / orbit feedback** (the TE3 flow idea). Angular coherence ~0 on every
   clip — there is no detectable circle. No "make small circles" tracking claim.
4. **2-D zone / perpendicular-axis position precision.** Only the **1-D along-forearm coordinate**
   carried cross-clip signal; the perpendicular `v` and full 2-D zone did not. Do not render a tight
   "you are X mm off-center" precision overlay.
5. **Any framing that implies treatment efficacy.** (Carries the standing safety rule — see §5.)

---

## 2. The HONEST feedback set the live app can defensibly show

Three feedback channels, each matched to a verified capability:

### (a) Presence / orientation gating — KEEP AS-IS (fully reliable)
The existing quality-gated states stay exactly as built; the receiving hand detects ~100%:
- **NO_HAND** — "Bring your hand into the frame"
- **WRONG_FACE** — orientation prompt ("Turn your palm toward the camera" for PC6)
- **SEARCHING** — pressing finger not yet found / drifting

### (b) Position — "finger in zone" via landmark, KEEP but coarse
When the pressing thumb is a **separated landmark**, the distance-to-target test in
`usePressDetection` is defensible — it is the **one-hand, separated-finger** condition under which
A localized well. Show a **binary in-zone / not-in-zone** signal (the existing `isOnTarget` +
`isStable`), surfaced as the existing **ON_TARGET_UNSTABLE → HOLDING** progression.
**Do not** surface sub-zone precision (see §1.4). Position accuracy is ~0.70 overall and only solid
on the one-hand geometry we are deliberately staging — so it is honest **only** behind the §3 gate.

### (c) Cadence — 3-way `steady / too-fast / unstable` (REQUIRED, gated)
The 3-way label is a product requirement. It is achievable **only** once the press is a clean
separated-finger landmark and cadence comes from a **corrected estimator** (autocorrelation/FFT on
the fingertip displacement + refractory-gated peak counting — NOT frame-diff zero-crossings, which
caused the doubling). Buckets: **steady** = periodic in the target range; **too-fast** = mean Hz
over the calibrated cutoff; **unstable** = high inter-interval coefficient-of-variation regardless
of mean (this maps onto the engine's existing `rhythm_unstable` state). Cutoffs calibrated from the
re-shoot's labeled clips.

GATE: ship the 3-way label only after it (i) beats a phase-shuffle null per clip and (ii) clears a
defined accuracy bar on the constrained re-shoot. **Until then, fall back to the coarse two-way
`steady / too-fast` hint** on the existing two-value `SessionStats.rhythmConsistency`. Never show a
number/BPM in either mode. If cadence confidence is low on a given session, omit the channel rather
than guess.

### What NOT to claim (state explicitly in UI copy review)
- No BPM / numeric rate. No "you're at N presses per second."
- No 3-way rhythm label; no "unstable rhythm" callout.
- No circular-motion guidance or "good orbit" feedback.
- No precise distance/zone offset ("3mm high").
- Position confidence is **conditional on the staged one-hand capture** — never present it as
  robust across arbitrary two-hand framings.

---

## 3. Fallback / quality-gating when tracking confidence is low

The governing rule: **when unsure, coach the capture; never emit position or cadence feedback.**

The verified failure mode is the **merged / un-separated** pressing finger and **two-hand
sign-flip** geometry (presser's along-forearm coordinate flips, a correct press reads "incorrect").
The app must detect "I don't have a clean separated presser" and fall back to capture coaching:

- **Pressing finger not separated / not its own hand** → stay in **SEARCHING** with capture copy:
  *"Separate your pressing finger so I can see it"* / *"Bring your forearm into the frame."*
  Never fall through to a position verdict in this state.
- **Only the receiving hand visible (no distinct presser hand)** → **SEARCHING** /
  *"Show your pressing finger."* (Do **not** track the lone/largest hand as the presser — that was
  the exact bug that produced a false 0.90 position score.)
- **Low cadence confidence** (short window, tiny thumb amplitude) → **omit the cadence channel**;
  keep position + hold timer running. Silence beats a wrong rhythm cue.
- **Forearm/Pose anatomy not framed** → capture-coaching copy, not an "incorrect position" verdict.

Default bias is **withhold feedback**, not guess. A missing cue is honest; a wrong cue is not.

---

## 4. Mapping onto EXISTING hooks / state machine (minimal, surgical)

No rewrite. The 7-state machine and the three hooks already encode this shape; the changes are
small.

### `useHandClassifier.ts` — REUSE, one targeted gate
- Reused: face classification (`isDorsal`/`isPalmar`), `requires_hand_face` routing,
  two-hand target/presser split (target = correct face, pressing = the other).
- Minimal change: require the **presser to be a genuinely separate detected hand** before exposing
  `pressingHand` (the existing `hands.length === 1` branch already returns `pressingHand: null`,
  which correctly forces SEARCHING). Do **not** add a "lone hand = presser" heuristic — keep the
  current two-hand requirement, which is exactly the separated-finger condition A needs. (The known
  WRONG_FACE-vs-NO_HAND gap in CLAUDE.md is orthogonal and out of scope here.)

### `usePressDetection.ts` — REUSE position, gate it; do NOT add precise cadence
- Reused as-is: `weightedTarget`, `tolerance_radius_xHandSize`, `isOnTarget`, `isStable`
  (offset-variance stability). These give the defensible **binary in-zone** signal.
- No change needed to make position honest **provided** §4-classifier only yields a `pressingHand`
  when it is separated. Do **not** add a 2-D zone, perpendicular-axis precision, or a numeric
  cadence/BPM estimator into this hook.

### `useCoachingState.ts` — REUSE the machine, constrain one field
- Reused as-is: all 7 transitions, timestamp debounce, GRACE/MIN_STABLE timing, hold accumulation,
  COMPLETE. The `hasTarget → NO_HAND/WRONG_FACE`, `!hasPressing → SEARCHING`,
  `!isOnTarget → SEARCHING/PAUSED`, `!isStable → ON_TARGET_UNSTABLE`, stable → HOLDING flow already
  implements §2(a)+(b) and the §3 fallback (no presser → SEARCHING).
- Cadence change: `SessionStats.rhythmConsistency` is the only place cadence surfaces. Extend it to
  the gated 3-way `'steady' | 'too_fast' | 'unstable'` **once the validated corrected estimator is in
  and has cleared the §(c) gate**; until then keep the two-valued fallback (`'steady' | 'variable'`).
  Set a bucket only when cadence confidence clears a threshold; otherwise omit the cue. The Hz is
  computed internally for bucketing but is **never displayed as a number/BPM**. The hard-coded
  `stabilityPct: 90` at COMPLETE is cosmetic; do not
  promote it to a precise accuracy claim.

### UI / copy (CameraPage feedback card, RecapPage) — copy review only
- Feedback card already shows state label + coaching text + progress ring: correct surface for the
  honest set. Ensure copy carries **no BPM, no 3-way rhythm label, no circular-motion language.**
- RecapPage: present hold time + a coarse steady/variable self-report, **not** a precise score or
  rhythm grade.

---

## 5. Safety (unchanged, immutable)

All standing rules hold and bound every copy string above:
- Copy must **never** contain *treat / cure / heal / diagnose*.
- SafetyPage forced acknowledgement is not skippable.
- "Felt worse" → stop guidance, no "continue" recommendation.
- LI4 globally excluded.

Coarse, honest feedback ("steady" / "ease the pace" / "bring your finger into the zone") stays
firmly inside wellness-coaching language and makes no efficacy claim.

---

## TL;DR for the demo build

Lead with **PC6** on a **staged one-hand (separated-thumb) capture**. Show: **presence/orientation
gating**, **binary finger-in-zone position** (behind the separated-presser gate), and the **3-way
`steady / too_fast / unstable` cadence label — GATED**: it ships only after a corrected estimator
(autocorrelation/FFT, no frame-diff doubling) clears a phase-shuffle null + accuracy bar on the
constrained re-shoot; until then it falls back to the coarse two-way `steady / too-fast` hint.
**Drop precise BPM/numeric rate and all circular-motion feedback.** Reuse the 7-state machine and
hooks almost verbatim; real changes = gating the presser to a separated hand, and extending
`rhythmConsistency` to the 3-way label once validated. When confidence is low, coach the capture —
never emit a wrong verdict.
