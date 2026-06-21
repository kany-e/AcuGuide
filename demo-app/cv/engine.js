// AcuGuide CV temporal + feedback engine ("Person B" layer).
//
// Rule-based, deterministic. Consumes the per-frame FrameState stream produced by
// the landmark/feature layer (Person A) — position correctness (onTarget / enter /
// exit radii) is already provided per frame; this module is the TEMPORAL layer on
// top: press counting, rhythm, motion, and the coaching state machine.
//
// Pure ES module: no I/O, no DOM, no Node built-ins, so it runs unchanged in the
// browser and under `node --test`. File I/O lives in fixtures.js.

// ---------------------------------------------------------------------------
// Tunable constants. Defaults follow acuguide_hand_points.json / the build spec;
// every state-machine option can be overridden per call for tuning or for the
// short replay fixtures (see HOLD_TARGET_S).
// ---------------------------------------------------------------------------
export const CONST = {
  // A frame is usable only above this landmark confidence.
  MIN_CONFIDENCE: 0.5,
  // Press detection: min seconds between two counted presses (release-jitter reject).
  MIN_PRESS_GAP_S: 0.4,
  // Rhythm: cycles counted in this trailing window, then bucketed.
  RHYTHM_WINDOW_S: 10,
  RHYTHM_GOOD_MIN: 3, // 3..6 cycles in window  -> rhythm_good
  RHYTHM_FAST_MIN: 7, // >=7 cycles in window   -> rhythm_too_fast  (0..2 -> rhythm_none)
  // Rhythm stability: high inter-press interval spread flags忽快忽慢.
  RHYTHM_UNSTABLE_CV: 0.5,
  // Stability: std of target-relative offset (in handSize units) over a short
  // trailing window. Below threshold = "steady". 0.06 is the TE3 value in the JSON.
  STABILITY_WINDOW_S: 0.2,
  STABILITY_STD_THRESHOLD: 0.06,
  // HOLDING must be steady for at least this long before the timer advances.
  MIN_HOLD_CONFIRM_S: 0.07,
  // Stay "engaged" through brief dips out of the enter radius shorter than this
  // (jitter / fast taps inside the large exit band); longer dips disengage.
  ENTER_DROPOUT_DEBOUNCE_S: 0.25,
  // After leaving HOLDING, keep the timer paused (not reset) for this grace window.
  PAUSE_GRACE_S: 1.5,
  // Accumulated HOLDING time to reach COMPLETE. Production routines use 30s; the
  // replay fixtures are 8-12s clips, so tests pass a smaller value.
  HOLD_TARGET_S: 30,
};

export const PHASES = Object.freeze({
  NO_HAND: 'NO_HAND',
  WRONG_FACE: 'WRONG_FACE',
  SEARCHING: 'SEARCHING',
  ON_TARGET_UNSTABLE: 'ON_TARGET_UNSTABLE',
  HOLDING: 'HOLDING',
  PAUSED: 'PAUSED',
  COMPLETE: 'COMPLETE',
});

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------
function frameDt(frame, prevFrame) {
  if (prevFrame) {
    const dt = frame.t - prevFrame.t;
    if (dt > 0) return dt;
  }
  return 1 / (frame.fps || 30);
}

function std(values) {
  const n = values.length;
  if (n < 2) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / n;
  const variance = values.reduce((a, b) => a + (b - mean) ** 2, 0) / n;
  return Math.sqrt(variance);
}

// A frame is usable when a hand is present, confident enough, and — for off-model
// extrapolated points (PC6/TE5) — the wrist is in frame. Otherwise we cannot trust
// the geometry and must not advance the timer.
export function isUsable(frame, { minConfidence = CONST.MIN_CONFIDENCE } = {}) {
  const hand = frame.receivingHand;
  if (!hand || !hand.present) return false;
  const q = frame.quality || {};
  if ((q.confidence ?? 0) < minConfidence) return false;
  const offModel = frame.target && frame.target.trackable === 'off_model_extrapolated';
  if (offModel && q.wristInFrame === false) return false;
  return true;
}

// Correct hand face = the receiving hand shows the surface the point sits on.
export function faceIsCorrect(frame) {
  const need = frame.target && frame.target.surface; // 'dorsal' | 'palmar'
  const have = frame.receivingHand && frame.receivingHand.face;
  if (!need) return true; // no requirement encoded -> don't gate
  return have === need;
}

// ---------------------------------------------------------------------------
// 1) countPresses — rising edges of the enter radius, with a refractory gap so
//    release jitter (brief out-and-back within MIN_PRESS_GAP_S) is one press.
//    Note: we intentionally key on insideEnterRadius, not insideExitRadius — with
//    large tolerances (PC6) a fast tap never crosses the 1.6x exit radius, yet each
//    re-entry is a distinct press (matches the fixtures' ground truth).
// ---------------------------------------------------------------------------
export function pressTimes(frames, { minPressGapS = CONST.MIN_PRESS_GAP_S } = {}) {
  const times = [];
  let prevEnter = false;
  let lastT = -Infinity;
  for (const f of frames) {
    const enter = !!(f.contact && f.contact.insideEnterRadius);
    if (enter && !prevEnter && f.t - lastT >= minPressGapS) {
      times.push(f.t);
      lastT = f.t;
    }
    prevEnter = enter;
  }
  return times;
}

export function countPresses(frames, opts) {
  return pressTimes(frames, opts).length;
}

// ---------------------------------------------------------------------------
// 2) classifyRhythm — cycles in a trailing window -> none / good / too_fast, plus a
//    separate "unstable" flag from inter-press interval spread (independent of count).
// ---------------------------------------------------------------------------
export function classifyRhythm(frames, opts = {}) {
  const {
    windowSec = CONST.RHYTHM_WINDOW_S,
    goodMin = CONST.RHYTHM_GOOD_MIN,
    fastMin = CONST.RHYTHM_FAST_MIN,
    unstableCv = CONST.RHYTHM_UNSTABLE_CV,
  } = opts;
  const all = pressTimes(frames, opts);
  const endT = frames.length ? frames[frames.length - 1].t : 0;
  const times = all.filter((pt) => pt >= endT - windowSec);
  const count = times.length;

  let category;
  if (count < goodMin) category = 'rhythm_none';
  else if (count < fastMin) category = 'rhythm_good';
  else category = 'rhythm_too_fast';

  // inter-press interval spread (coefficient of variation)
  const intervals = [];
  for (let i = 1; i < times.length; i++) intervals.push(times[i] - times[i - 1]);
  let unstable = false;
  if (intervals.length >= 2) {
    const mean = intervals.reduce((a, b) => a + b, 0) / intervals.length;
    if (mean > 0) unstable = std(intervals) / mean > unstableCv;
  }
  return { category, count, unstable, intervals };
}

// ---------------------------------------------------------------------------
// 3) classifyMotion — hold / circular / repeated / none.
//    Exposed behind a small interface (motionClassifier) so a learned classifier
//    could replace the heuristic later without touching the state machine.
// ---------------------------------------------------------------------------
export function classifyMotion(frames, opts = {}) {
  const { minSamples = 5 } = opts;
  // Use frames where the pressing fingertip and target are both known.
  const pts = [];
  for (const f of frames) {
    const tip = f.pressingFinger && f.pressingFinger.tipXY;
    const tgt = f.target && f.target.xy;
    if (tip && tgt) pts.push({ dx: tip[0] - tgt[0], dy: tip[1] - tgt[1], off: f.contact?.offset_xHandSize });
  }
  if (pts.length < minSamples) return 'none';

  const presses = countPresses(frames, opts);
  const offsets = pts.map((p) => p.off).filter((o) => typeof o === 'number');
  const offStd = std(offsets);

  // cumulative angular travel of the fingertip around the target
  let angTravel = 0;
  for (let i = 1; i < pts.length; i++) {
    let dA = Math.atan2(pts[i].dy, pts[i].dx) - Math.atan2(pts[i - 1].dy, pts[i - 1].dx);
    while (dA > Math.PI) dA -= 2 * Math.PI;
    while (dA < -Math.PI) dA += 2 * Math.PI;
    angTravel += Math.abs(dA);
  }
  const radii = pts.map((p) => Math.hypot(p.dx, p.dy));
  const radiusMean = radii.reduce((a, b) => a + b, 0) / radii.length;
  const radiusCv = radiusMean > 0 ? std(radii) / radiusMean : 1;

  if (presses >= 2 && offStd > 0.05) return 'repeated';
  if (angTravel >= 1.5 * Math.PI && radiusCv < 0.35) return 'circular';
  if (offStd < 0.05) return 'hold';
  return 'none';
}

export const motionClassifier = { classify: classifyMotion };

// ---------------------------------------------------------------------------
// 4) FeedbackStateMachine — one CoachState per frame.
//    NO_HAND -> WRONG_FACE -> SEARCHING -> ON_TARGET_UNSTABLE -> HOLDING
//            -> PAUSED -> COMPLETE   (per the JSON feedback_state_machine).
// ---------------------------------------------------------------------------
export class FeedbackStateMachine {
  constructor(opts = {}) {
    this.o = { ...CONST, ...opts };
    this.coachCopy = opts.coachCopy || {}; // { [pointId]: { align, drift, hold } }

    this.prevFrame = null;
    this.engaged = false;
    this.dropoutTimer = 0; // seconds out of enter radius while still within exit band
    this.offsetWindow = []; // [{ t, off }]
    this.stableRun = 0; // seconds of continuous steadiness
    this.holdTime = 0; // accumulated HOLDING seconds
    this.lastHoldT = -Infinity;
    this.completed = false;

    this.holdingFrames = 0;
    this.holdingStableFrames = 0; // offset < 0.5 * tolerance
  }

  _updateEngaged(frame, dt) {
    const c = frame.contact || {};
    if (c.insideEnterRadius) {
      this.engaged = true;
      this.dropoutTimer = 0;
    } else if (!c.insideExitRadius) {
      this.engaged = false;
      this.dropoutTimer = 0;
    } else {
      // inside the exit band but outside the enter radius: hold engagement briefly
      this.dropoutTimer += dt;
      if (this.dropoutTimer >= this.o.ENTER_DROPOUT_DEBOUNCE_S) this.engaged = false;
    }
  }

  _updateStability(frame, dt) {
    const off = frame.contact && frame.contact.offset_xHandSize;
    if (typeof off === 'number') {
      this.offsetWindow.push({ t: frame.t, off });
      const cutoff = frame.t - this.o.STABILITY_WINDOW_S;
      while (this.offsetWindow.length && this.offsetWindow[0].t < cutoff) this.offsetWindow.shift();
    }
    const steady =
      this.engaged &&
      this.offsetWindow.length >= 2 &&
      std(this.offsetWindow.map((s) => s.off)) < this.o.STABILITY_STD_THRESHOLD;
    this.stableRun = steady ? this.stableRun + dt : 0;
  }

  _resetTracking() {
    this.engaged = false;
    this.dropoutTimer = 0;
    this.offsetWindow.length = 0;
    this.stableRun = 0;
  }

  _cue(phase, frame) {
    const id = frame.target && frame.target.id;
    const copy = this.coachCopy[id] || {};
    switch (phase) {
      case PHASES.NO_HAND:
        return 'Bring your hand into the frame.';
      case PHASES.WRONG_FACE:
        return frame.target && frame.target.surface === 'palmar'
          ? 'Turn your palm toward the camera.'
          : 'Turn the back of your hand toward the camera.';
      case PHASES.SEARCHING:
      case PHASES.PAUSED:
        return copy.drift || 'Move toward the highlighted area.';
      case PHASES.ON_TARGET_UNSTABLE:
        return 'Hold it steady.';
      case PHASES.HOLDING:
        return copy.hold || 'Good — firm, steady pressure.';
      case PHASES.COMPLETE:
        return 'Routine complete.';
      default:
        return '';
    }
  }

  step(frame) {
    const dt = frameDt(frame, this.prevFrame);
    this.prevFrame = frame;

    let phase;
    if (this.completed) {
      phase = PHASES.COMPLETE;
    } else if (!isUsable(frame, this.o)) {
      this._resetTracking();
      phase = PHASES.NO_HAND;
    } else if (!faceIsCorrect(frame)) {
      this._resetTracking();
      phase = PHASES.WRONG_FACE;
    } else {
      this._updateEngaged(frame, dt);
      this._updateStability(frame, dt);
      const holdingNow = this.engaged && this.stableRun >= this.o.MIN_HOLD_CONFIRM_S;

      if (this.engaged) {
        if (holdingNow) {
          phase = PHASES.HOLDING;
          this.holdTime += dt;
          this.lastHoldT = frame.t;
          this.holdingFrames += 1;
          const off = frame.contact.offset_xHandSize;
          const hs = frame.receivingHand.handSize;
          const tolX = hs ? frame.target.toleranceR / hs : Infinity;
          if (typeof off === 'number' && off < 0.5 * tolX) this.holdingStableFrames += 1;
        } else {
          phase = PHASES.ON_TARGET_UNSTABLE;
        }
      } else if (this.holdTime > 0 && frame.t - this.lastHoldT <= this.o.PAUSE_GRACE_S) {
        phase = PHASES.PAUSED;
      } else {
        phase = PHASES.SEARCHING;
      }

      if (this.holdTime >= this.o.HOLD_TARGET_S) {
        this.completed = true;
        phase = PHASES.COMPLETE;
      }
    }

    return {
      phase,
      motion: null, // filled in by runEngine (needs windowed context)
      pressCount: 0, // filled in by runEngine (running total)
      holdTime_s: round2(this.holdTime),
      stabilityPct: this.holdingFrames ? Math.round((100 * this.holdingStableFrames) / this.holdingFrames) : 0,
      rhythm: 'rhythm_none', // filled in by runEngine (running)
      cue: this._cue(phase, frame),
    };
  }
}

function round2(x) {
  return Math.round(x * 100) / 100;
}

// Collapse consecutive duplicates -> the phase-transition timeline.
export function collapsePhases(phaseList) {
  const out = [];
  for (const p of phaseList) if (out[out.length - 1] !== p) out.push(p);
  return out;
}

// ---------------------------------------------------------------------------
// 5) runEngine — drive the state machine over a frame stream and return the final
//    CoachState plus the ordered distinct-phase timeline and session summaries.
// ---------------------------------------------------------------------------
export function runEngine(frames, opts = {}) {
  const sm = new FeedbackStateMachine(opts);
  const motion = opts.motionClassifier || motionClassifier;
  const motionWindowS = opts.motionWindowS ?? 2;

  const states = [];
  const phaseList = [];
  for (let i = 0; i < frames.length; i++) {
    const frame = frames[i];
    const state = sm.step(frame);

    // running summaries layered on top of the per-frame state
    const sliceFrom = frames.slice(0, i + 1);
    state.pressCount = countPresses(sliceFrom, opts);
    state.rhythm = classifyRhythm(sliceFrom, opts).category;
    const t0 = frame.t - motionWindowS;
    let w = i;
    while (w > 0 && frames[w - 1].t >= t0) w--;
    state.motion = motion.classify(frames.slice(w, i + 1), opts);

    states.push(state);
    phaseList.push(state.phase);
  }

  const rhythm = classifyRhythm(frames, opts);
  return {
    finalState: states[states.length - 1] || null,
    states,
    phases: collapsePhases(phaseList),
    pressCount: countPresses(frames, opts),
    rhythm: rhythm.category,
    rhythmUnstable: rhythm.unstable,
    motion: motion.classify(frames, opts),
  };
}

// Build a { [pointId]: { align, drift, hold } } map from the acupoints dataset.
export function buildCoachCopy(pointsData) {
  const map = {};
  for (const p of (pointsData && pointsData.acupoints) || []) {
    if (p.coach_copy) map[p.id] = p.coach_copy;
  }
  return map;
}
