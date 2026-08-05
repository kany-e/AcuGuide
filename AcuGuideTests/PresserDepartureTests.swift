import XCTest
import CoreGraphics
@testable import AcuGuide

// "The finger tip detection circle remains on the screen for too long even after the finger has been
// removed, the latency too great."
//
// The dot's life after the finger starts leaving was (keepRadius − d₀)/v + tipGraceS + filter lag,
// and the GRACE — the only part anyone had looked at — was the smallest term. `selectPresserTip`
// went on PAINTING the held finger all the way out to acquireRadius × 1.6 ≈ 1.04 hand-lengths (a
// whole palm, 6.5× the drawn ring), refreshing the grace clock on every one of those frames, so the
// 0.5 s only began once the finger was already a palm clear of the point.
//
// These pin the fix AND the report it must not re-open: an earlier user reported the dot FLICKERING
// for a hand parked on the point whose Vision read blinks, which is why tipGraceS is 0.5. The
// distinction the code now makes — and that these tests hold it to — is between a MEASUREMENT
// DROPOUT (no candidate at all → full grace) and a DEPARTURE (the same fingertip measured outside
// the acquire band → clears in two frames).
final class PresserDepartureTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let te3 = Acupoint.byId["TE3"]!

    /// Everything is derived from the constants, never hard-coded: a fixed offset that silently
    /// stops straddling the boundary when a constant moves is a test that passes for no reason.
    private func geometry() -> (receiver: Hand, target: CGPoint, hs: CGFloat, acquire: CGFloat) {
        let receiver = HandFixture.receiver()
        let t = receiver.weightedTarget(te3.mediapipeTarget!.anchors)!
        let aspect: CGFloat = 9.0 / 16.0
        let w = receiver.p(.wrist)!, m = receiver.p(.middleMCP)!
        let hs = hypot(m.x - w.x, (m.y - w.y) / aspect)          // the engine's ISOTROPIC hand size
        let tol = te3.mediapipeTarget!.toleranceXHandSize * hs
        let acquire = max(hs * CoachConst.presserAcquireXHandSize, tol * CoachConst.exitRadiusMult)
        return (receiver, t, hs, acquire)
    }

    /// Place a presser tip `isoDistance` to the RIGHT of the target (x is already width units, so a
    /// pure-x offset is its own isotropic distance).
    private func presser(_ g: (receiver: Hand, target: CGPoint, hs: CGFloat, acquire: CGFloat),
                         isoDistance: CGFloat, finger: HandJoint = .indexTip) -> Hand {
        HandFixture.presser(at: CGPoint(x: g.target.x + isoDistance, y: g.target.y), finger: finger)
    }

    // THE REPORT. A finger withdrawn past the acquire band must stop being painted almost at once —
    // not tracked out to a palm-length and only then handed to a 0.5 s grace.
    func testDotClearsWithinTwoFramesOfLeavingTheAcquireRadius() {
        let g = geometry()
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        // Establish a real press on the point.
        for _ in 0..<10 { engine.update(hands: [g.receiver, presser(g, isoDistance: 0)], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip, "precondition: a press on the point is tracked")

        // The finger is now measured clearly OUTSIDE the acquire band — but still well inside the
        // old keep band (acquire × 1.6), which is exactly where it used to keep its dot.
        let out = g.acquire * 1.25
        XCTAssertLessThan(out, g.acquire * CoachConst.exitRadiusMult,
                          "the test must sit inside the old keep band or it proves nothing")
        var frames = 0
        while engine.pressTip != nil && frames < 30 {
            engine.update(hands: [g.receiver, presser(g, isoDistance: out)], point: te3, now: t)
            t += dt; frames += 1
        }
        XCTAssertNil(engine.pressTip, "a departed finger must not keep its dot")
        XCTAssertLessThanOrEqual(frames, CoachConst.presserDepartureFrames + 1,
                                 "departure is EVIDENCE, not an absence — it must not wait out the "
                                 + "dropout grace (took \(frames) frames)")
    }

    // THE FLICKER REPORT, STILL FIXED. A whole-hand dropout has no measurement at all, so it is not
    // evidence of departure and must keep the full tipGraceS. Shortening this is the one way to
    // re-open the report that set tipGraceS to 0.5.
    func testWholeHandDropoutStillGetsTheFullGrace() {
        let g = geometry()
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [g.receiver, presser(g, isoDistance: 0)], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip)

        // 12 frames = 400 ms, inside tipGraceS (0.5 s). The presser hand is simply not detected.
        for i in 0..<12 {
            engine.update(hands: [g.receiver], point: te3, now: t); t += dt
            XCTAssertNotNil(engine.pressTip, "a blinking Vision read must not blank the dot (frame \(i))")
        }
    }

    // Fix 1's own failure mode. The keep band still resolves IDENTITY, so when the held finger
    // drifts out while another is inside the acquire band, the dot must move to the fresh finger —
    // never blank. Blanking here is the hopping that presserHoldMargin was widened to stop.
    func testHeldFingerBeyondAcquireYieldsToAFreshFingerInsideIt() {
        let g = geometry()
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [g.receiver, presser(g, isoDistance: 0)], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip)

        // The index tip straddles just outside the band; the middle tip sits just inside it.
        let outside = g.acquire * 1.1, inside = g.acquire * 0.5
        var pts: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: g.target.x + 0.20, y: g.target.y + 0.28),
            .middleMCP: CGPoint(x: g.target.x + 0.16, y: g.target.y + 0.20),
            .indexTip: CGPoint(x: g.target.x + outside, y: g.target.y),
            .middleTip: CGPoint(x: g.target.x + inside, y: g.target.y),
        ]
        let straddling = Hand(points: pts, chirality: .left)
        for i in 0..<60 {
            engine.update(hands: [g.receiver, straddling], point: te3, now: t); t += dt
            XCTAssertNotNil(engine.pressTip,
                            "a usable fingertip is inside the acquire band — the dot must never "
                            + "blank at the identity boundary (frame \(i))")
        }
        pts.removeAll()
    }

    // A RECONSTRUCTED tip is a guess, and a guess used to keep the dot alive forever: the DIP/PIP
    // rebuild is a full candidate, so while those two joints survived it painted a dot AND refreshed
    // the grace clock, with no fingertip ever measured. Bounded now by tipReconstructionSustainS.
    func testReconstructionCannotOutliveItsCap() {
        let g = geometry()
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [g.receiver, presser(g, isoDistance: 0)], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip)

        // The fingertip landmark is gone for good; DIP and PIP survive, on the point.
        let rebuilt = Hand(points: [
            .wrist: CGPoint(x: g.target.x + 0.20, y: g.target.y + 0.28),
            .middleMCP: CGPoint(x: g.target.x + 0.16, y: g.target.y + 0.20),
            .indexDIP: CGPoint(x: g.target.x, y: g.target.y + 0.02),
            .indexPIP: CGPoint(x: g.target.x, y: g.target.y + 0.05),
        ], chirality: .left)

        let start = t
        var clearedAt: Double? = nil
        for _ in 0..<180 {                              // 6 s — the old behaviour never cleared
            engine.update(hands: [g.receiver, rebuilt], point: te3, now: t); t += dt
            if engine.pressTip == nil, clearedAt == nil { clearedAt = t - start }
        }
        let cleared = try? XCTUnwrap(clearedAt)
        XCTAssertNotNil(cleared, "a guessed tip must not keep the dot alive indefinitely")
        if let cleared {
            XCTAssertGreaterThan(cleared, CoachConst.tipGraceS,
                                 "…but it must still outlast the plain dropout grace, or a genuinely "
                                 + "occluded press blinks")
            XCTAssertLessThanOrEqual(cleared, CoachConst.tipReconstructionSustainS + 0.2,
                                     "the guess must expire at its cap")
        }
    }
}
