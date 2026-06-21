# Splitting the CV Feature-Extraction Work Across Two People

The trap: dividing by *feature* (one person does "press count," another does "circular detection") fails, because every feature reads the same MediaPipe landmark stream and the same contact definition — you'd get constant merge conflicts and duplicated plumbing.

The fix: divide by **pipeline layer**, with one frozen data contract between them. Upstream person turns pixels into a clean per-frame state; downstream person turns that state-over-time into gestures, counts, and coaching.

```
        PERSON A  (Perception / Geometry)            PERSON B  (Temporal / Coaching)
   camera ─► landmarks ─► face ─► target ─► contact  ──►  buffer ─► motion ─► count ─► state machine ─► cues
                                                    ▲
                                          FrameState (the contract)
```

---

## The contract: `FrameState` (frozen in hour 1)

Person A emits ONE of these per frame. Person B only ever sees this — never raw landmarks. Freeze the shape early; version it if it must change.

```json
{
  "t": 1234.56,
  "fps": 30,
  "receivingHand": {
    "present": true,
    "face": "dorsal",            // "dorsal" | "palmar" | "unknown"
    "handSize": 0.18,            // scale unit = dist(wrist, middleMCP)
    "landmarks": [[x,y,z], "...21"]
  },
  "pressingFinger": {
    "present": true,
    "contactPart": "tip",        // "tip" | "pad" | "base"
    "tipXY": [0.51, 0.62]
  },
  "target": { "id": "TE3", "xy": [0.49, 0.60], "toleranceR": 0.029 },
  "contact": {
    "onTarget": true,
    "offset_xHandSize": 0.07,
    "depthProxy": 0.42           // press-depth estimate (noisy — see risks)
  },
  "quality": { "confidence": 0.91, "lowLight": false }
}
```

Person B emits a `CoachState` the UI renders:

```json
{
  "phase": "HOLDING",            // drives the timer ring + messaging
  "motion": "circular",          // "hold" | "circular" | "repeated" | "none"
  "pressCount": 3,
  "holdTime_s": 12.4,
  "stabilityPct": 0.88,
  "rhythm": "steady",            // "steady" | "variable"
  "cue": "Nice — keep that steady pressure."
}
```

---

## Person A — Perception / Geometry (upstream)

Owns everything from camera to "is the finger on the point, and with what part."

- MediaPipe Hands setup, webcam, two-hand tracking (receiving hand + pressing hand).
- Landmark **smoothing** (e.g. One-Euro filter) so B receives a clean signal, not jitter.
- **Hand-face detection** (palm vs back) and left/right normalization, so B never deals with mirroring.
- **Target computation** — reads `acuguide_hand_points.json`, applies the anchor weights / forearm extrapolation, outputs `target.xy` + `toleranceR`.
- **Contact detection** — is the pressing fingertip within tolerance; classify `contactPart` (tip vs pad vs base) from which pressing-finger landmark is closest/lowest-z at the target.
- `depthProxy` + `confidence` + `lowLight` quality flags.
- A debug overlay (draw landmarks, target ring, contact dot) so A can verify without B.

**A's definition of done:** a live `FrameState` stream + a recorded `.jsonl` log of real sessions.

## Person B — Temporal / Coaching (downstream)

Owns everything that needs *time*: turning the FrameState stream into behavior and feedback.

- **Ring buffer** of the last ~2s of FrameStates.
- **Motion classifier** — `hold` (offset variance ≈ 0), `circular` (fingertip trajectory has steady angular travel around target), `repeated` (in/out oscillation along one axis).
- **Press counter** — peak-detection on `depthProxy` (or offset oscillation) with a refractory period so one press = one count.
- **Stability % and rhythm** metrics for the recap.
- **State machine** (NO_HAND → WRONG_FACE → SEARCHING → ON_TARGET_UNSTABLE → HOLDING → PAUSED → COMPLETE) + the timer ring logic.
- **Coach copy** selection from the JSON `coach_copy`, plus the optional LLM rephrase hook.
- Recap screen data.

**B's definition of done:** given a recorded `.jsonl`, produces the correct `CoachState` sequence — testable with zero camera.

---

## Why this split actually parallelizes

The contract lets them work at the same time without blocking:

1. **Hour 1:** both agree on `FrameState` + `CoachState` and commit the schema. Person A hand-writes 2–3 fake `.jsonl` logs (hand appears, drifts, holds, leaves).
2. **Middle:** A builds real perception against a debug overlay; B builds the whole temporal/coaching stack against the fake logs. Neither waits on the other.
3. **Integration:** swap B's fake-log reader for A's live stream. If the contract held, it "just works."

B can even **unit-test the hard temporal functions with synthetic signals** — feed a sine wave → expect `circular`; feed square pulses → expect N presses. No CV needed to prove the logic.

---

## Improvements I'd make (beyond a plain split)

1. **Record-and-replay harness (highest value).** Have A log raw sessions to a file from day one. Everyone debugs against canned recordings instead of waving their hand 200 times — and you get a **camera-failure fallback for the live demo** (play a recording if the venue lighting/webcam misbehaves). This one tool de-risks the whole demo.

2. **Freeze the contract, version it.** The single biggest failure mode in a two-person CV split is the interface drifting. Put `FrameState` in a shared file with a `schemaVersion`; any change is a deliberate bump, not a silent edit.

3. **Push all noise-handling upstream (into A).** Smoothing, handedness, mirror correction, low-confidence gating all live in A. B should be able to trust the stream completely. Clean separation = fewer "is this my bug or yours" moments.

4. **Scope the fragile features behind a flag.** `pressCount` and any "pressure" reading are webcam-unreliable. Make the **core path** = onTarget + stable + hold-duration (which is robust), and treat press-count / circular-vs-repeated as `enhancedMetrics: true` that can be switched off. If integration gets tight, you still have a complete, working demo.

5. **One trivial end-to-end integration early.** Before adding features, wire the simplest possible path: hand detected → ring fills → "done." Prove the A→B→UI seam works on day one; then both add richness on a known-good spine.

6. **Test fixtures as a shared asset.** The fake `.jsonl` logs are a deliverable, not throwaway. They're your regression tests, your demo fallback, and the thing that lets B finish even if A's CV is late.

---

## When NOT to split CV at all

Your PRD already defines **one** Vision/AI owner plus Frontend and Product. The CV pipeline here is small and tightly coupled; a second person inside it can add more coordination cost than they save. If your two "CV" people have uneven CV experience, the often-better division is:

- **Person 1:** the entire A+B CV pipeline (it's coherent and owned by one head).
- **Person 2:** the app shell, camera page UI, recap screen, and the LLM coach layer that *consumes* `CoachState`.

That keeps the coupled CV logic with one person and gives the second person a clean, well-defined surface — which is exactly the seam the `CoachState` contract already provides.

**Rule of thumb:** split CV into two only if both are comfortable with signal/CV work. Otherwise split *across* the CV boundary (pipeline vs app), using the same `FrameState` / `CoachState` contracts.
