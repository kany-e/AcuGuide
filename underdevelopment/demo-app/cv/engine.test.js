// Fixture-driven validation of the CV temporal + feedback engine.
// Run: `npm test`  (from demo-app/)  or  `node --test cv/`
//
// For each replay fixture we run the engine over its frames and assert against
// _meta.groundTruth:
//   - the observed phase-transition timeline contains the expected phases IN ORDER
//     (extra transient states allowed),
//   - pressCount matches exactly,
//   - the rhythm classification matches,
//   - the motion classification matches (when the fixture specifies one).

import test from 'node:test';
import assert from 'node:assert/strict';

import { loadFixture, loadPointsData, FIXTURES } from './fixtures.js';
import { runEngine, buildCoachCopy, collapsePhases, countPresses, PHASES } from './engine.js';

// Fixtures are 8-12s clips, but the production hold target is 30s. Use a short
// completion target so the end-to-end fixture reaches COMPLETE within the clip.
const TEST_HOLD_TARGET_S = 2.0;

const coachCopy = buildCoachCopy(loadPointsData());
const ENGINE_OPTS = { coachCopy, HOLD_TARGET_S: TEST_HOLD_TARGET_S };

// Ground-truth labels are coarse; map each to the engine phase(s) that satisfy it,
// then require an ordered subsequence match.
//   HOLDING/tap                       -> HOLDING
//   WRONG_POSITION                    -> SEARCHING (finger present, off target)
//   (partial->still NO_HAND/low_conf) -> NO_HAND
// Taps start released (d=dmax at t=0) and PC6 taps clear the exit radius, so every
// ground-truth SEARCHING corresponds to a genuine engine SEARCHING — no PAUSED leniency.
const PHASE_ACCEPT = {
  NO_HAND: [PHASES.NO_HAND],
  WRONG_FACE: [PHASES.WRONG_FACE],
  WRONG_POSITION: [PHASES.SEARCHING],
  SEARCHING: [PHASES.SEARCHING],
  ON_TARGET_UNSTABLE: [PHASES.ON_TARGET_UNSTABLE],
  HOLDING: [PHASES.HOLDING],
  COMPLETE: [PHASES.COMPLETE],
};

function normalizeLabel(label) {
  if (label.startsWith('HOLDING')) return 'HOLDING';
  if (label.includes('NO_HAND')) return 'NO_HAND';
  return label;
}

function acceptedPhases(label) {
  return PHASE_ACCEPT[label] || [label];
}

// Is `expectedLabels` (after normalize + collapse) an ordered subsequence of the
// observed phase timeline, where each label is satisfied by an accepted engine phase?
function containsPhasesInOrder(observed, expectedLabels) {
  const expected = collapsePhases(expectedLabels.map(normalizeLabel));
  let i = 0;
  for (const label of expected) {
    const ok = acceptedPhases(label);
    while (i < observed.length && !ok.includes(observed[i])) i++;
    if (i >= observed.length) return false;
    i++;
  }
  return true;
}

for (const file of FIXTURES) {
  const doc = loadFixture(file);
  const gt = doc._meta.groundTruth;

  test(`${file} — phases, presses, rhythm`, () => {
    const res = runEngine(doc.frames, ENGINE_OPTS);

    assert.ok(
      containsPhasesInOrder(res.phases, gt.expected_phase_sequence),
      `expected phases ${JSON.stringify(gt.expected_phase_sequence)} in order; got ${JSON.stringify(res.phases)}`,
    );

    if (typeof gt.expected_pressCount === 'number') {
      assert.equal(res.pressCount, gt.expected_pressCount, `pressCount ${res.pressCount} != ${gt.expected_pressCount}`);
    }

    if (gt.expected_rhythm != null) {
      // "n/a" (no meaningful cadence) corresponds to the engine's rhythm_none bucket.
      const expectedRhythm = gt.expected_rhythm === 'n/a' ? 'rhythm_none' : gt.expected_rhythm;
      assert.equal(res.rhythm, expectedRhythm);
    }

    // Motion is only asserted when the fixture pins one ("n/a" = not applicable).
    if (gt.expected_motion != null && gt.expected_motion !== 'n/a') {
      assert.equal(res.motion, gt.expected_motion);
    }
  });
}

// fixture_5 is the integration smoke test: it must walk the whole machine and finish.
test('fixture_5_te3_full_flow — reaches COMPLETE', () => {
  const doc = loadFixture('fixture_5_te3_full_flow.json');
  const res = runEngine(doc.frames, ENGINE_OPTS);
  assert.equal(res.finalState.phase, PHASES.COMPLETE);
});

// Focused unit check: the hysteresis press counter debounces release jitter.
test('countPresses debounces sub-0.4s release jitter', () => {
  const mk = (t, enter) => ({ t, fps: 30, contact: { insideEnterRadius: enter, insideExitRadius: enter } });
  // one real press, then a 0.1s flicker out-and-back (jitter), then a real press 1s later
  const frames = [
    mk(0.0, true), mk(0.1, true),
    mk(0.2, false), mk(0.3, true), // 0.1s dip -> same press
    mk(1.3, false), mk(1.4, true), // 1.0s gap -> new press
  ];
  assert.equal(countPresses(frames), 2);
});
