# CV Feedback Engine (`demo-app/cv/`)

The **temporal + coaching layer** ("Person B") for AcuGuide Hand Coach. It consumes
the per-frame `FrameState` stream produced by the landmark/feature layer ("Person A")
and turns it into per-frame coaching feedback. This is **rule-based** logic — no
trained model.

Position correctness (`contact.onTarget`, enter/exit radii, `offset_xHandSize`) is
already provided per frame. This module adds the layer on top: press counting,
rhythm, motion, and the feedback state machine.

## Run the tests

```sh
cd demo-app
npm test
```

(equivalently: `node --test "cv/*.test.js"`). No dependencies — uses Node's built-in
test runner. Requires Node ≥ 18.

The suite replays each fixture in `claude-deliverables/fixtures/` through the engine
and asserts the observed phases, press count, and rhythm against each fixture's
`_meta.groundTruth`.

## Files

- **`engine.js`** — pure ES module (no I/O / DOM), runs in the browser and in Node:
  - `countPresses(frames)` — press cycles via enter-radius rising edges with a
    0.4 s refractory gap (release-jitter rejection).
  - `classifyRhythm(frames, { windowSec })` — cycles in a trailing window →
    `rhythm_none` (0–2) / `rhythm_good` (3–6) / `rhythm_too_fast` (7+), plus a
    separate `unstable` flag from inter-press interval spread.
  - `classifyMotion(frames)` — `hold` / `circular` / `repeated` / `none`. Exposed
    behind `motionClassifier` so a learned classifier could replace it later.
  - `FeedbackStateMachine` — emits one `CoachState` per frame across
    `NO_HAND → WRONG_FACE → SEARCHING → ON_TARGET_UNSTABLE → HOLDING → PAUSED →
    COMPLETE`.
  - `runEngine(frames, opts)` — drives the machine; returns the final `CoachState`,
    the `phases` transition timeline, and `pressCount` / `rhythm` / `motion`.
  - `buildCoachCopy(pointsData)` — `{ [pointId]: { align, drift, hold } }` cue map
    from `acuguide_hand_points.json`.
  - `CONST` — all thresholds as named, overridable constants.
- **`fixtures.js`** — Node-only helpers: `loadFixture(name)`, `loadPointsData()`.
- **`engine.test.js`** — the fixture-driven suite.

## `CoachState` (one per frame)

```js
{ phase, motion, pressCount, holdTime_s, stabilityPct, rhythm, cue }
```

## Notes / design decisions

- **Thresholds** come from `acuguide_hand_points.json` / the build spec and live in
  `CONST` (e.g. stability std `0.06×handSize`, enter vs `1.6×` exit radius, rhythm
  3–6 good / 7+ fast). Override per call: `runEngine(frames, { STABILITY_STD_THRESHOLD: 0.05 })`.
- **`HOLD_TARGET_S`** defaults to the production `30 s`. The replay fixtures are
  8–12 s clips, so the test passes a smaller value so the end-to-end fixture reaches
  `COMPLETE`.
- **Off-model PC6/TE5**: when `target.trackable === "off_model_extrapolated"` and
  `quality.wristInFrame === false`, the frame is treated as low-confidence and the
  timer does not advance.
- **Hysteresis**: engagement enters on the enter radius and is held through brief
  dips out of it (`ENTER_DROPOUT_DEBOUNCE_S`) so jitter and a hovering near-edge
  approach (e.g. the unstable segment of fixture 5) don't flicker; it disengages on
  a sustained gap or once the fingertip clears the `1.6×` exit radius. Press counting
  keys on the enter radius (rising edges + refractory gap), not the exit radius, so
  each re-tap is one press even for points with a large tolerance.
- The engine is **non-diagnostic wellness self-care** only — it reports position,
  steadiness, and rhythm; it makes no treatment claims. LI4 is excluded product-wide.
