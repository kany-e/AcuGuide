import XCTest
@testable import AcuGuide

// Synthetic-frame unit tests that exercise the CoachStateMachine GUARDS directly — the parts
// the replay fixtures can't pin because they never present on-target contact to mutate. Each
// test hand-builds a CoachFrameInput stream and asserts the phase / hold-timer behavior, so a
// regression in enter/exit hysteresis, min-hold-confirm, pause-grace, the dt clamp, or the
// occlusion handling fails here.
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
