import XCTest
import Vision
@testable import AcuGuide

// Device-reported (2026-07-25): "the acupoint detection becomes unstable when the pressing finger
// comes into the circle, the acupoint detection drifts outwards periodically, and the massaging
// finger detection is inconsistent — it detects for a short while and then it doesn't, and repeats."
//
// All three symptoms share one trigger: mid-press the massaging hand is foreshortened and occluding,
// so Vision drops it into the WEAK tier (whole-hand confidence 0.3–0.5). These tests pin what must
// happen while that is true — the ring must stay anchored on the receiving hand, and the press dot
// must keep tracking.
final class PresserStabilityTests: XCTestCase {
    private let dt = 1.0 / 30.0

    // A dorsal right hand at rest — same shape the other engine tests use.
    private let receiverPts: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55),
        .middleMCP: CGPoint(x: 0.50, y: 0.52), .ringMCP: CGPoint(x: 0.56, y: 0.54),
        .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30),
        .pinkyTip: CGPoint(x: 0.66, y: 0.36), .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    private func makePresser(onTarget tip: CGPoint, pressFinger: HandJoint,
                             weak: Bool, wristOffset: CGVector = CGVector(dx: 0.20, dy: 0.28)) -> Hand {
        var pts: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: tip.x + wristOffset.dx, y: tip.y + wristOffset.dy),
            .middleMCP: CGPoint(x: tip.x + wristOffset.dx * 0.8, y: tip.y + wristOffset.dy * 0.7)]
        pts[pressFinger] = tip
        return Hand(points: pts, chirality: .left, weak: weak,
                    detectionConfidence: weak ? 0.35 : 0.9)
    }

    // THE core regression. The massaging hand degrading to the weak tier is the NORMAL mid-press
    // state, not an edge case — so it must not cost us the receiver. If the lone strong hand can be
    // classified as the presser, receiverOpt goes nil, the ring freezes on its last value and the
    // "let the pressed hand show more" hint fires, until lonePresserGraceS (1.5s) expires and roles
    // reset — which is exactly the ~1.5s detect/lose/repeat cycle reported from the device.
    func testWeakPresserNeverCostsUsTheReceiver() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: receiverPts, chirality: .right)
        let tip = receiver.weightedTarget(target.anchors)!
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0

        // Establish both hands STRONG so the role anchors are set correctly.
        let strongPresser = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: false)
        for _ in 0..<10 { engine.update(hands: [receiver, strongPresser], point: te3, now: t); t += dt }
        let ringWhenStrong = try? XCTUnwrap(engine.ringCenter)
        XCTAssertNotNil(ringWhenStrong, "ring must be established while both hands are strong")

        // Now the massaging hand degrades to WEAK and stays there — the real mid-press condition.
        // Run well past lonePresserGraceS so any freeze-then-reset cycle would show up.
        let weakPresser = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: true)
        var sawMissingTip = 0
        var maxRingDrift: CGFloat = 0
        for _ in 0..<90 {                                  // 3 seconds at 30fps — 2x the grace
            engine.update(hands: [receiver, weakPresser], point: te3, now: t); t += dt
            if engine.pressTip == nil { sawMissingTip += 1 }
            if let r = engine.ringCenter, let r0 = ringWhenStrong {
                maxRingDrift = max(maxRingDrift, hypot(r.x - r0.x, r.y - r0.y))
            }
        }

        XCTAssertEqual(sawMissingTip, 0,
                       "the press dot vanished on \(sawMissingTip)/90 frames while a weak massaging "
                       + "hand pressed on target — this is the reported 'detects for a while, then "
                       + "doesn't, and repeats'")
        XCTAssertLessThan(maxRingDrift, 0.02,
                          "the acupoint ring drifted \(maxRingDrift) while the receiving hand never "
                          + "moved — a weak second hand must not move the ring")
    }

    // The receiver must stay the receiver even when the anchors would prefer otherwise. A strong
    // hand plus a weak hand is unambiguous by policy — weak hands are presser-only — so the lone
    // strong hand cannot be the presser, whatever the sticky wrist anchors say.
    func testStrongHandIsReceiverWheneverAWeakHandIsAvailableToPress() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: receiverPts, chirality: .right)
        let tip = receiver.weightedTarget(target.anchors)!
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0

        // Seed the anchors with the roles REVERSED relative to where the hands end up, by running a
        // few frames with the presser sitting where the receiver will be. This is the adversarial
        // version of "the hands moved / crossed", which is what makes the wrist-proximity heuristic
        // pick wrong.
        let decoy = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: false,
                                wristOffset: CGVector(dx: 0.0, dy: 0.02))   // wrist ~ on the receiver's
        for _ in 0..<6 { engine.update(hands: [receiver, decoy], point: te3, now: t); t += dt }

        // Now only the receiver is strong; the massaging hand is weak.
        let weakPresser = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: true)
        for _ in 0..<20 { engine.update(hands: [receiver, weakPresser], point: te3, now: t); t += dt }

        XCTAssertNotNil(engine.ringCenter,
                        "a strong receiving hand plus a weak massaging hand must still produce a ring")
        let ring = engine.ringCenter!
        XCTAssertLessThan(hypot(ring.x - tip.x, ring.y - tip.y), 0.05,
                          "the ring must sit on the RECEIVING hand's target, not wander to the "
                          + "massaging hand")
    }

    // THE reported bug, isolated. TE3's target is a weighted blend of ringMCP (0.11), pinkyMCP
    // (0.47) and wrist (0.42) — and the point itself is the groove BEHIND the ring/little knuckles,
    // so the pressing finger lands on top of ringMCP/pinkyMCP. Vision drops a landmark it cannot see
    // (HandVision keeps only confidence > 0.3), and weightedTarget is all-or-nothing: ONE missing
    // anchor returns nil.
    //
    // So pressing the point correctly destroys the estimate of where the point is — and the
    // anchor-occlusion branch responds by clearing the press dot outright and reporting
    // hasPresser: false, ignoring tipGraceS. Losing the 11%-weight landmark is enough.
    //
    // That is the reported triad: unstable "when the pressing finger comes into the circle", the dot
    // flickering as anchors cross the confidence threshold, and the ring freezing then jumping.
    func testAnchorOccludedByThePressingFingerDoesNotKillTheDot() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: receiverPts, chirality: .right)
        let tip = receiver.weightedTarget(target.anchors)!
        let presser = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: false)
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0

        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertNotNil(engine.pressTip, "precondition: the dot is up with all anchors visible")
        let ringBefore = engine.ringCenter

        // The pressing finger now covers the ring knuckle — the LOWEST-weight anchor (0.11).
        // Everything else about the hand is unchanged and clearly visible.
        var occluded = receiverPts
        occluded[.ringMCP] = nil
        let receiverOccluded = Hand(points: occluded, chirality: .right)

        var dotLost = 0
        for _ in 0..<6 {                       // 6 frames = 200ms, well inside tipGraceS (0.5s)
            engine.update(hands: [receiverOccluded, presser], point: te3, now: t); t += dt
            if engine.pressTip == nil { dotLost += 1 }
        }
        XCTAssertEqual(dotLost, 0,
                       "the press dot vanished on \(dotLost)/6 frames because ONE 11%-weight anchor "
                       + "went behind the pressing finger — the finger occluding the point is the "
                       + "normal case, not a failure, and tipGraceS should have covered it")
        XCTAssertNotNil(engine.ringCenter, "the ring must hold through a partial anchor occlusion")
        if let a = ringBefore, let b = engine.ringCenter {
            XCTAssertLessThan(hypot(a.x - b.x, a.y - b.y), 0.02,
                              "the ring jumped when an anchor was occluded by the pressing finger")
        }
    }

    // Guard the occlusion hint itself: it must not fire while a perfectly good strong receiver is on
    // screen. Telling the user to "show the pressed hand more" when it is already fully visible is
    // the user-facing half of the same bug.
    func testNoOcclusionHintWhileAStrongReceiverIsVisible() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: receiverPts, chirality: .right)
        let tip = receiver.weightedTarget(target.anchors)!
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0

        let weakPresser = makePresser(onTarget: tip, pressFinger: target.pressFinger, weak: true)
        var hintFrames = 0
        for _ in 0..<90 {
            engine.update(hands: [receiver, weakPresser], point: te3, now: t); t += dt
            if let h = engine.hintText, h.contains("show") || h.contains("露出") { hintFrames += 1 }
        }
        XCTAssertEqual(hintFrames, 0,
                       "an occlusion hint fired on \(hintFrames)/90 frames while the receiving hand "
                       + "was fully visible")
    }
}
