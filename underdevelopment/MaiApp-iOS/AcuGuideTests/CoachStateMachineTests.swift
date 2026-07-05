import XCTest
@testable import AcuGuide

// Synthetic-frame unit tests that exercise the CoachStateMachine GUARDS directly — the parts
// the replay fixtures can't pin because they never present on-target contact to mutate. Each
// test hand-builds a CoachFrameInput stream and asserts the phase / hold-timer behavior, so a
// regression in enter/exit hysteresis, min-hold-confirm, pause-grace, the dt clamp, or the
// occlusion handling fails here.
// Engine-level test for the press-tip dropout grace: Vision drops the massaging fingertip
// constantly (it's the joint doing the occluding — confirmed unstable in on-device shadow capture),
// and before tipGraceS a single missed frame nil'd the dot, reset its smoother, and instantly
// disengaged HOLDING. The grace must keep the dot + engagement through a brief dropout WITHOUT
// crediting hold time, then clear cleanly once the finger is really gone.
final class CoachEngineTipGraceTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let base: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
        .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    func testTipGraceSurvivesBriefPresserDropout() {
        // This synthetic right hand reads dorsal only under the positive sign — pin the calibration
        // flag for the test (it's a device-calibration static) and restore it after.
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        XCTAssertEqual(receiver.isDorsal, true, "synthetic receiver must pass the TE3 dorsal gate")
        let tip = receiver.weightedTarget(target.anchors)!
        var presserPts: [HandJoint: CGPoint] = [.wrist: CGPoint(x: tip.x + 0.20, y: tip.y + 0.28),
                                                .middleMCP: CGPoint(x: tip.x + 0.16, y: tip.y + 0.20)]
        presserPts[target.pressFinger] = tip                     // pressing exactly on target
        let presser = Hand(points: presserPts, chirality: .left)

        let engine = CoachEngine()
        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.phase, .holding, "steady on-target press must reach HOLDING")
        XCTAssertNotNil(engine.pressTip)
        let progressBefore = engine.progress
        XCTAssertGreaterThan(progressBefore, 0)

        // Presser vanishes for 2 frames (66ms < tipGraceS): dot + engagement survive, hold frozen.
        for _ in 0..<2 { engine.update(hands: [receiver], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip, "brief tip dropout must not clear the press dot")
        XCTAssertTrue(engine.phase == .holding || engine.phase == .onTargetUnstable,
                      "brief tip dropout must not disengage; got \(engine.phase)")
        XCTAssertEqual(engine.progress, progressBefore, accuracy: 1e-9,
                       "hold time must not advance on unverifiable geometry")

        // Presser returns: holding resumes and credits again.
        for _ in 0..<6 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.phase, .holding)
        XCTAssertGreaterThan(engine.progress, progressBefore, "hold credit must resume after the dropout")

        // Presser gone for good: past grace + debounce the dot clears and the phase falls to PAUSED.
        for _ in 0..<20 { engine.update(hands: [receiver], point: te3, now: t); t += dt }
        XCTAssertNil(engine.pressTip, "expired grace must clear the press dot")
        XCTAssertEqual(engine.phase, .paused, "hold >0 within pause grace → PAUSED, not SEARCHING")
    }
}

// Engine-level test for the mid-press ROLE LOCK: on the forearm points (SJ5/PC6) the target is
// extrapolated past the wrist, and mid-press the hands overlap enough that the nearest-target role
// preference oscillates — live, the ring visibly jumped onto the MASSAGING hand (user-reported on
// Waiguan). While engaged, roles must stay locked no matter how long the preference disagrees.
final class CoachEngineRoleLockTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let base: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
        .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    func testRoleLockPreventsMidPressSwap() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true      // synthetic right hand reads dorsal
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let sj5 = Acupoint.byId["SJ5"]!
        let target = sj5.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let tR = receiver.weightedTarget(target.anchors)!    // forearm target, past the wrist

        // Presser: a second full hand to the side; its OWN extrapolated forearm target is tP.
        var presserPts = base
        for (j, p) in presserPts { presserPts[j] = CGPoint(x: p.x + 0.35, y: p.y - 0.20) }
        presserPts[target.pressFinger] = CGPoint(x: tR.x + 0.003, y: tR.y)   // pressing tR (ε off-centre)
        let presser = Hand(points: presserPts, chirality: .left)
        let tP = presser.weightedTarget(target.anchors)!

        let engine = CoachEngine()
        var t = 0.0
        // Phase A — unambiguous: receiver's fingertip far from tP → preference agrees. Reach HOLDING.
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: sj5, now: t); t += dt }
        XCTAssertEqual(engine.phase, .holding)
        let ringA = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ringA.x - tR.x, ringA.y - tR.y)), 0, accuracy: 0.02,
                       "ring must start on the RECEIVER's forearm target")

        // Phase B — ambiguity begins mid-hold: the receiver's relaxed fingertip drifts onto the
        // PRESSER's own forearm target (hands crossed — exactly the live Waiguan posture), so the
        // nearest-target preference now prefers the swapped roles EVERY frame.
        var crossed = base
        crossed[target.pressFinger] = tP
        let receiverCrossed = Hand(points: crossed, chirality: .right)
        for _ in 0..<12 { engine.update(hands: [receiverCrossed, presser], point: sj5, now: t); t += dt }

        // 12 frames > swapConfirmFrames (6): without the engaged-role-lock the swap fires and the
        // ring jumps to the massaging hand's forearm (tP). With the lock it must stay on tR.
        let ringB = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ringB.x - tR.x, ringB.y - tR.y)), 0, accuracy: 0.02,
                       "mid-press role swap: ring jumped off the receiver (toward \(tP))")
        XCTAssertTrue(engine.phase == .holding || engine.phase == .onTargetUnstable,
                      "engagement must survive the ambiguity; got \(engine.phase)")
    }

    // The OTHER jump mechanism (user-reported on multiple points): mid-press Vision often loses the
    // occluded RECEIVING hand and reports only the massaging hand. The old single-hand branch crowned
    // whatever hand it saw as receiver — snapping the ring onto the massaging hand instantly, no swap
    // votes involved. A lone hand matching the sticky PRESSER anchor must be treated as
    // "receiver occluded", keeping the last ring and pausing within grace.
    func testLonePresserFrameDoesNotStealRing() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let tR = receiver.weightedTarget(target.anchors)!
        var presserPts = base
        for (j, p) in presserPts { presserPts[j] = CGPoint(x: p.x + 0.30, y: p.y - 0.15) }
        presserPts[target.pressFinger] = tR
        let presser = Hand(points: presserPts, chirality: .left)

        let engine = CoachEngine()
        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.phase, .holding)
        let progressBefore = engine.progress

        // Receiver drops out; ONLY the massaging hand stays detected for half a second.
        for _ in 0..<15 { engine.update(hands: [presser], point: te3, now: t); t += dt }
        let ring = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ring.x - tR.x, ring.y - tR.y)), 0, accuracy: 0.02,
                       "lone-presser frames must keep the last ring, not move it to the massaging hand")
        XCTAssertEqual(engine.progress, progressBefore, accuracy: 1e-9,
                       "no hold credit while the receiver is unverifiable")
        XCTAssertTrue(engine.phase == .paused || engine.phase == .holding || engine.phase == .onTargetUnstable,
                      "occluded receiver must pause within grace; got \(engine.phase)")

        // Receiver returns → the hold resumes and credits again.
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.phase, .holding)
        XCTAssertGreaterThan(engine.progress, progressBefore)
    }
}

// Session layer: repeated press/release ROUNDS (matching published self-care guidance + the app's own
// FAQ) on top of the per-round machine. A round's completion must bank its hold, enter a timer-driven
// RESTING gap (hands may leave — no NO_HAND flash), restart clean, and only the LAST round yields
// session COMPLETE. totalHeldS must never double-count a banked round.
final class CoachEngineSessionTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let base: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
        .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    func testSessionRoundsRestThenComplete() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let tR = receiver.weightedTarget(target.anchors)!
        var presserPts = base
        for (j, p) in presserPts { presserPts[j] = CGPoint(x: p.x + 0.30, y: p.y - 0.15) }
        presserPts[target.pressFinger] = tR
        let presser = Hand(points: presserPts, chirality: .left)

        let engine = CoachEngine(roundsTarget: 2, roundHoldS: 0.4, restS: 0.3)
        var t = 0.0
        var sawResting = false, restFrames = 0, maxProgressDuringRest = 0.0
        var framesToComplete = 0
        for i in 0..<300 {
            engine.update(hands: [receiver, presser], point: te3, now: t); t += dt
            if engine.phase == .resting {
                sawResting = true; restFrames += 1
                maxProgressDuringRest = max(maxProgressDuringRest, engine.progress)
                XCTAssertEqual(engine.roundsDone, 1, "the gap comes after exactly one banked round")
            }
            if engine.phase == .complete { framesToComplete = i; break }
        }

        XCTAssertTrue(sawResting, "a release gap must separate the rounds")
        XCTAssertEqual(engine.phase, .complete, "two rounds must finish the session")
        XCTAssertTrue(engine.sessionComplete)
        XCTAssertEqual(engine.roundsDone, 2)
        XCTAssertGreaterThan(framesToComplete, 0)
        // The gap is timer-driven at restS≈0.3s (≈9 frames at 30fps; ±2 for boundary rounding).
        XCTAssertTrue((7...12).contains(restFrames), "rest gap should last ≈0.3s; got \(restFrames) frames")
        XCTAssertEqual(maxProgressDuringRest, 0, accuracy: 1e-9, "the next round starts from zero progress")
        // Two 0.4s rounds: banked + latched hold, each overshooting by at most ~one frame.
        XCTAssertEqual(engine.totalHeldS, 0.8, accuracy: 0.12,
                       "totalHeldS must be ≈ two rounds, never double-counting a banked round")
    }

    // Ending mid-session is a first-class outcome: partial rounds + live partial hold are reported.
    func testQuitAnytimeReportsPartialHonestly() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let tR = receiver.weightedTarget(target.anchors)!
        var presserPts = base
        for (j, p) in presserPts { presserPts[j] = CGPoint(x: p.x + 0.30, y: p.y - 0.15) }
        presserPts[target.pressFinger] = tR
        let presser = Hand(points: presserPts, chirality: .left)

        let engine = CoachEngine(roundsTarget: 4, roundHoldS: 0.4, restS: 0.2)
        var t = 0.0
        // Drive until round 1 is banked and round 2 is PARTWAY through (condition-driven, so the
        // test can't drift past round 2's completion), then "quit" and check the honest partials.
        var i = 0
        while !(engine.roundsDone == 1 && engine.phase == .holding && engine.progress > 0.2) && i < 150 {
            engine.update(hands: [receiver, presser], point: te3, now: t); t += dt; i += 1
        }
        XCTAssertEqual(engine.roundsDone, 1, "one round banked by now")
        XCTAssertFalse(engine.sessionComplete)
        XCTAssertGreaterThan(engine.totalHeldS, 0.4, "banked round + live partial hold")
        XCTAssertLessThan(engine.totalHeldS, 0.8, "must not have double-counted the banked round")
    }
}

final class CoachStateMachineTests: XCTestCase {

    private let fps = 30.0
    private func dtStep() -> Double { 1.0 / fps }

    // Press tip on target, steady.
    private func onTarget(_ t: Double, offset: Double = 0.0) -> CoachFrameInput {
        CoachFrameInput(t: t, present: true, faceCorrect: true,
                        insideEnterRadius: true, insideExitRadius: true, offsetXHandSize: offset)
    }
    // Inside the exit band but outside the enter radius (a brief dip).
    private func inBand(_ t: Double, offset: Double) -> CoachFrameInput {
        CoachFrameInput(t: t, present: true, faceCorrect: true,
                        insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: offset)
    }
    // Fully off target (outside the exit radius).
    private func offTarget(_ t: Double) -> CoachFrameInput {
        CoachFrameInput(t: t, present: true, faceCorrect: true,
                        insideEnterRadius: false, insideExitRadius: false, offsetXHandSize: 0.5)
    }
    // Hand present but the target geometry is momentarily unresolvable (occlusion): no offset.
    private func occluded(_ t: Double) -> CoachFrameInput {
        CoachFrameInput(t: t, present: true, faceCorrect: true,
                        insideEnterRadius: false, insideExitRadius: true, offsetXHandSize: nil)
    }

    // Drive `count` steady on-target frames at 30fps starting at t=0; returns the machine.
    @discardableResult
    private func holdSteady(_ sm: CoachStateMachine, frames count: Int) -> [CoachPhase] {
        (0..<count).map { sm.step(onTarget(Double($0) * dtStep())) }
    }

    // MIN_HOLD_CONFIRM: on-target+steady is ON_TARGET_UNSTABLE until ~0.07s of steadiness, then HOLDING.
    func testMinHoldConfirmGatesHolding() {
        let sm = CoachStateMachine()
        let phases = holdSteady(sm, frames: 8)
        XCTAssertEqual(phases.first, .onTargetUnstable, "first on-target frame can't be HOLDING yet")
        XCTAssertFalse(phases.prefix(2).contains(.holding), "HOLDING before min-hold-confirm is a regression")
        XCTAssertTrue(phases.contains(.holding), "steady on-target must reach HOLDING")
        XCTAssertGreaterThan(sm.holdTime, 0, "HOLDING must advance the timer")
    }

    // ENTER/EXIT hysteresis + dropout debounce: a brief dip into the exit band stays engaged;
    // a dip sustained past ENTER_DROPOUT_DEBOUNCE_S disengages into PAUSED.
    func testDropoutDebounceKeepsEngagementThroughBriefDip() {
        let sm = CoachStateMachine()
        holdSteady(sm, frames: 8)
        let dipStart = 8 * dtStep()
        let p1 = sm.step(inBand(dipStart, offset: 0.3))
        XCTAssertTrue(p1 == .holding || p1 == .onTargetUnstable,
                      "a brief in-band dip must stay engaged, got \(p1)")

        var sawPaused = false
        var t = dipStart + dtStep()
        while t < dipStart + 0.5 {            // well past the 0.25s dropout window
            if sm.step(inBand(t, offset: 0.3)) == .paused { sawPaused = true; break }
            t += dtStep()
        }
        XCTAssertTrue(sawPaused, "a dip sustained past the dropout debounce must PAUSE")
    }

    // PAUSE_GRACE: leaving the target PAUSES (timer preserved, not reset) within the grace window,
    // then falls to SEARCHING after it — and only reset() ever clears the accumulated hold.
    func testPauseGracePreservesTimerThenSearches() {
        let sm = CoachStateMachine()
        holdSteady(sm, frames: 8)
        let held = sm.holdTime
        XCTAssertGreaterThan(held, 0)
        let leaveT = 8 * dtStep()

        XCTAssertEqual(sm.step(offTarget(leaveT)), .paused, "leaving with prior hold must PAUSE")
        XCTAssertEqual(sm.holdTime, held, accuracy: 1e-9, "timer must be preserved during the pause")

        XCTAssertEqual(sm.step(offTarget(leaveT + 1.0)), .paused, "still within grace -> PAUSED")
        XCTAssertEqual(sm.holdTime, held, accuracy: 1e-9)

        let p = sm.step(offTarget(leaveT + CoachConst.pauseGraceS + 0.1))
        XCTAssertEqual(p, .searching, "past PAUSE_GRACE -> SEARCHING")
        XCTAssertEqual(sm.holdTime, held, accuracy: 1e-9, "hold is preserved (only reset() clears it)")
    }

    // dt CLAMP: at a low frame rate (0.125s/frame > maxFrameDtS=0.1) each holding step credits at
    // most maxFrameDtS, never the full wall-clock delta — so a stall can't fast-forward the hold.
    func testDtClampLimitsHoldCredit() {
        let sm = CoachStateMachine()
        var t = 0.0
        for _ in 0..<10 { _ = sm.step(onTarget(t)); t += 0.125 }   // 8 fps
        // 9 holding frames after the first (unstable) frame; clamped credit = 9 * 0.1 = 0.9,
        // vs 9 * 0.125 = 1.125 without the clamp.
        XCTAssertLessThan(sm.holdTime, 9 * 0.125 - 0.05, "dt must be clamped below the wall-clock delta")
        XCTAssertEqual(sm.holdTime, 9 * CoachConst.maxFrameDtS, accuracy: 0.05, "clamped credit ~= frames * maxFrameDt")
    }

    // OCCLUSION: a frame where the receiver is present but the target geometry is unresolvable
    // (offset nil) must NOT advance the hold timer, and must keep engagement alive briefly rather
    // than dropping to NO_HAND. (Without the offset-nil gate this credits phantom hold.)
    func testOcclusionDoesNotAdvanceHold() {
        let sm = CoachStateMachine()
        holdSteady(sm, frames: 8)
        let held = sm.holdTime
        XCTAssertGreaterThan(held, 0)

        let p = sm.step(occluded(8 * dtStep()))
        XCTAssertTrue(p == .holding || p == .onTargetUnstable, "occlusion must keep engagement, got \(p)")
        XCTAssertEqual(sm.holdTime, held, accuracy: 1e-9, "occlusion frame must not credit hold")

        // Sustained occlusion: still never credits hold (the window ages out, dropout elapses).
        var t = 9 * dtStep()
        for _ in 0..<20 { _ = sm.step(occluded(t)); t += dtStep() }
        XCTAssertEqual(sm.holdTime, held, accuracy: 1e-9, "no hold credited across a sustained occlusion")
    }

    // COMPLETE latches: once the (short) target is reached the machine stays COMPLETE.
    func testCompletesAndLatches() {
        let sm = CoachStateMachine(holdTargetS: 0.3)
        var t = 0.0
        var reachedComplete = false
        for _ in 0..<40 { if sm.step(onTarget(t)) == .complete { reachedComplete = true; break }; t += dtStep() }
        XCTAssertTrue(reachedComplete, "steady on-target must reach COMPLETE at the target")
        // Even an off-target frame stays COMPLETE (terminal latch).
        XCTAssertEqual(sm.step(offTarget(t + 0.1)), .complete)
    }
}
