# Capture Coaching Protocol — making PC6 and TE3 landmark-trackable

**Status:** spec (June 20, 2026). Wellness self-care only; no diagnosis, no treatment claims.
**Source of truth:** the verified findings in `diagnostics/AB_validation_GO_NO_GO.md`,
`diagnostics/validate_a_report.md`, `diagnostics/validate_b_report.md`, and the point geometry in
`claude-deliverables/data/acuguide_hand_points.json`. This document does not modify any code.

## Why this exists (the one verified lever)

The receiving (target) hand is detected ~100%. The whole failure surface is **tracking the
pressing finger**. Both validation tracks converged on the same conclusion: *the capture gesture
is the lever, not the algorithm.*

- **Track A (PC6 / forearm) = PARTIAL.** Tracking the pressing **thumb landmark (lm 4)** genuinely
  works on clean **one-hand** clips (3858/3859/3860: localize 0.65–0.84, position correct). It
  breaks when (a) two hands are in frame so "lone hand = presser" is false — a naive largest-bbox
  selector tracked the *receiving* hand and produced a **false 0.90** position score, dropping to an
  honest **0.70** with a real presser selector; and (b) Pose forearm localization is unstable —
  `pose_forearm_ratio` 0.10–0.99 with the elbow off-screen, so on two-hand clips (3852/3855) the
  presser's along-forearm coordinate **sign-flips** (median-u ~ +1.3) and a correct press reads
  "incorrect."
- **Track B (TE3 / dorsal hand) = NO-GO for flow.** The pressing thumb is **merged on top of the
  receiving hand**, so it has no landmark. Optical flow found **no coherent circular motion**
  (angular coherence ~0.01–0.13 = isotropic jitter, not an orbit) and could not localize the press
  (ROI flow 0.31× background, < 1.0). The prescribed fallback is to **change the capture gesture so
  the pressing finger separates from the receiving hand and gets its own MediaPipe landmark.**

So the entire protocol below has one job: make the press a **single, clearly separated pressing
finger that does not merge onto the receiving hand**, with the point's anatomy framed. That turns
TE3 into an A-style landmark problem and removes the two-hand / off-model failures from A.

---

## 1. Capture constraints (each tied to the failure it prevents)

| # | Constraint | Prevents (verified failure) |
|---|---|---|
| C1 | **One clearly separated pressing finger.** Press with the **pad of the extended INDEX finger (INDEX_TIP, lm 8)**; keep the other fingers curled away. The pressing finger must be **lifted off / approaching at an angle — NOT laid flat across or resting along the receiving hand.** | TE3 NO-GO: the merged thumb had no landmark and produced only isotropic ROI jitter (coherence ~0.01–0.13). A separated, extended finger gets its own MediaPipe landmark, so it can be tracked like Track A instead of via optical flow. Index is chosen over thumb because the thumb sits closest to the receiving hand and is the one that merged. |
| C2 | **Point anatomy in frame and visible.** For **TE3**: back of the receiving hand up, **loose fist** so the dorsal groove behind the ring/pinky knuckles is open (anchors lm 13/17/0). For **PC6**: palm up with the **wrist crease clearly in frame** (point is extrapolated ~1.1×handSize proximal from lm 0 along the forearm axis). | A's position signal only survives when the anatomy is framed; the off-model PC6 needs the wrist in frame to extrapolate. A loose fist also makes the TE3 groove (and any separated pressing finger above it) easier to resolve. |
| C3 | **Exactly the right hands in frame.** For **TE3**: one receiving hand + one pressing finger; do **not** let a second full hand crowd the frame. For **PC6**: receiving forearm + pressing hand; keep them clearly distinct. | A's biggest honest error was the **two-hand presser-identity trap** (false 0.90 → honest 0.70). Fewer, clearly-distinct hands removes the "lone hand = presser" ambiguity. |
| C4 | **Keep the receiving forearm and elbow as level/in-frame as possible (PC6).** Hold the forearm roughly horizontal and steady; avoid swinging it. | A's **key risk**: elbow off-screen makes Pose extrapolate the forearm axis, `pose_forearm_ratio` swings 0.10–0.99, and the presser's along-forearm coordinate **sign-flips** so a correct press reads "incorrect." A stable, framed forearm keeps the axis sane. |
| C5 | **Camera distance / angle.** Fill ~⅓–½ of the frame with the receiving hand/forearm; camera roughly perpendicular to the back of the hand (TE3) or to the palm/forearm (PC6). Don't shoot down a foreshortened forearm. | Foreshortening worsens the forearm-axis instability (C4) and shrinks the separation between the pressing finger and the receiving hand (C1). |
| C6 | **Lighting and background.** Even, diffuse light on the hand; plain, non-skin-toned, low-motion background. | The extractor's fingertip heuristic relies on skin/nail color segmentation and a person mask; busy or skin-toned backgrounds and shadows inject the very background motion that made Track B's ROI flow indistinguishable from the press (0.31× background). |
| C7 | **Steady, deliberate rhythm.** A clear, even press cadence (roughly ~1 Hz, the steady end of the technique). Avoid tiny, near-still presses. | On 3852 the true presser moved so little that < 3 peaks survived (Hz = 0) — the subtle-press case is fragile. A clear amplitude is needed for any cadence read; note we only target a **coarse steady-vs-fast** cue, never a precise BPM or a 3-way label (freq-label acc was 0.50). |

**Scope note (honest):** even with these constraints, surface only a **coarse cadence (steady vs
fast)** and a **coarse position (near vs off the zone)** — not precise BPM, not a 3-way
correct/fast/unstable label, and not a 2-D zone. The validation showed only the 1-D along-forearm
coordinate and a coarse correct-vs-fast cadence transfer across clips.

---

## 2. Live on-screen coaching cues (enforce the constraint; no medical claims)

Short, user-facing copy. Never uses treat / cure / heal / diagnose. Maps onto the existing feedback
state machine (NO_HAND, WRONG_FACE, SEARCHING, ON_TARGET_UNSTABLE, HOLDING, PAUSED, COMPLETE).

**Setup / framing cues (before HOLDING):**
- "Use one fingertip to press — keep your other fingers tucked away." *(C1)*
- "Lift your pressing finger slightly so it doesn't lie flat on your hand." *(C1)*
- TE3: "Back of your hand up, loose fist — find the dip behind your ring and pinky knuckles." *(C2)*
- PC6: "Palm up, and keep your wrist in the frame." *(C2, C4)*
- "Keep just your one hand and your pressing finger in view." *(C3)*
- PC6: "Rest your forearm level and hold it steady." *(C4)*
- "Move a little closer so your hand fills the frame." *(C5)*
- "Find some even light and a plain background." *(C6)*

**During-press cues:**
- SEARCHING: the active point's `drift` copy from the JSON (e.g. TE3: "Slide toward the gap between
  the last two knuckles"; PC6: "Move a little toward the center of your forearm").
- ON_TARGET_UNSTABLE: "Hold it steady."
- HOLDING: the point's `hold` copy (e.g. TE3: "Good — firm, steady pressure with slow breathing").
- Cadence (coarse only): "Nice steady rhythm." / "Try easing the pace a little." *(C7)* — never a
  number, never "too slow."

**Guardrails:** if a second full hand crowds the frame → "Keep just one hand in view." If the
pressing finger looks flat/merged (low contact confidence) → "Lift your fingertip a touch." Keep the
standard always-on safety line; stop and suggest professional care on red-flag symptoms.

---

## 3. Re-shoot shot list (validation, not a dataset)

Goal: confirm the **constrained** capture makes the pressing **finger** landmark-trackable for both
points. Minimal n — this validates the gesture, not a training set. Shoot all clips with C1–C7
enforced; ~10–15 s each, single subject, ~12 fps is fine (matches the extractor).

**Per point × label (2 clips each):**

| Point | Label | Clips | Framing notes |
|-------|-------|-------|---------------|
| TE3 | correct-position | 2 | Loose fist, back of hand up; extended index pad pressing the dorsal groove behind ring/pinky knuckles; finger clearly separated. |
| TE3 | wrong-position | 2 | Same gesture, but press visibly off the groove (e.g. on a knuckle / mid-back-of-hand). |
| TE3 | correct-rhythm | 2 | Correct position, steady ~1 Hz press. |
| TE3 | too-fast | 2 | Correct position, clearly faster press. |
| TE3 | no-press | 2 | Finger held near the point but **not** pressing / not moving (negative control). |
| PC6 | correct-position | 2 | Palm up, wrist + forearm in frame, forearm level, elbow as in-frame as possible; extended index pad ~3 finger-widths proximal of the wrist crease, centered. |
| PC6 | wrong-position | 2 | Same setup, press visibly off-target (too close to wrist crease, or off to one edge). |
| PC6 | correct-rhythm | 2 | Correct position, steady ~1 Hz. |
| PC6 | too-fast | 2 | Correct position, clearly faster. |
| PC6 | no-press | 2 | Finger near target, not pressing/moving (negative control). |

**Total: 20 clips** (2 points × 5 labels × 2 takes). Optionally add **1 deliberate
two-hands-crowding clip per point (+2 = 22)** to confirm the "one hand in view" cue is needed and
that the separated-finger gesture still resolves.

**Pass criteria (coarse, matching what transferred):**
- Pressing **finger gets its own MediaPipe landmark** on the large majority of frames for **both**
  points (the core TE3 fix — no reliance on optical flow).
- correct-position vs wrong-position separate for each point (coarse near/off, 1-D where applicable).
- correct-rhythm vs too-fast separate (coarse steady-vs-fast; no precise BPM expected).
- no-press clips read as "not pressing" (low/absent cadence), confirming the negative control.

If TE3's pressing finger is now landmark-tracked across the correct-position/rhythm clips, the
NO-GO is retired and TE3 collapses into the same A-style path as PC6.
