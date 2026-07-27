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
    private let receiverPts: [HandJoint: CGPoint] = HandFixture.dorsalRight

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

    // (Removed: testStrongHandIsReceiverWheneverAWeakHandIsAvailableToPress.)
    //
    // It pinned a rule — "one strong hand plus a weak hand means the strong one is the receiver" —
    // that is FALSE in the case that matters. Mid-press the receiver is the hand being covered, so
    // it is the RECEIVER that drops to the weak tier while the presser, on top and unoccluded,
    // stays strong. The rule inverted the roles exactly then: selectPresserTip went on to exclude
    // the real massaging hand (device report: "it's not even detecting the massaging finger
    // anymore") and faceCorrect was read off the massaging hand, which enters fingers-first and
    // never passes the dorsal gate (device report: "it triggers flip hand prompt").
    //
    // The test also passed with AND without the rule it claimed to pin — which is how the rule got
    // merged in the first place. A test that cannot fail is not coverage, so it is deleted rather
    // than left looking like a guard. RoleInversionTests below replaces it and is verified to fail
    // against the bad rule (tip lost on 30/45 frames, ring displaced 0.29).

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

// Device-reported: "what if the user's actual acupoint is outside of the dashed circle? the
// 就是这里 doesn't even allow you to press." The locate step exists to record where the user's
// point ACTUALLY is, so a press outside the standard ring is the case it was built for — refusing
// it defeated the feature. These pin the gate/clamp relationship that makes that safe.
final class LocateReachTests: XCTestCase {

    // The storage clamp must never truncate a press the capture gate accepted — otherwise the saved
    // spot silently lands somewhere the user never pressed.
    func testStorageClampReachesAsFarAsTheCaptureGate() {
        XCTAssertGreaterThanOrEqual(PointCalibration.maxOffsetXHandSize,
                                    CoachConst.locateFarCaptureRadiusXHandSize,
                                    "a gate-accepted press would be silently clamped on save")
    }

    // The outer band must genuinely extend past the inner one, or the honest-note path is dead code
    // and users outside the ring are still blocked.
    func testFarBandExtendsBeyondTheNormalRadius() {
        XCTAssertGreaterThan(CoachConst.locateFarCaptureRadiusXHandSize,
                             CoachConst.locateCaptureRadiusXHandSize,
                             "there is no band in which a far-but-real spot can be confirmed")
    }

    // A press out at the far band still round-trips through the store unchanged — the actual
    // guarantee the user cares about: the spot they confirmed is the spot that gets saved.
    func testFarPressRoundTripsWithoutTruncation() {
        let cal = PointCalibration.ephemeral()
        let r = CoachConst.locateFarCaptureRadiusXHandSize * 0.98        // just inside the gate
        let o = PointCalibration.Offset(dx: r, dy: 0)
        cal.set(o, for: "TE3")
        let saved = cal.offset(for: "TE3")
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.norm, o.norm, accuracy: 1e-9,
                       "the confirmed spot was clamped on save — the user's point moved")
    }
}

// Regression: the RECEIVER is the hand being occluded by the press, so mid-press it is routinely
// the receiver that drops to the weak tier while the PRESSER — sitting on top, unoccluded — stays
// strong. A rule of "the strong hand is the receiver" therefore inverts the roles exactly when the
// user is pressing, which is the one moment that matters.
//
// Device-reported consequences of shipping that rule: the massaging finger stopped being detected
// at all (selectPresserTip excludes the hand it believes is the receiver — which was the real
// massaging hand), and a WRONG-FACE prompt fired on entry (faceCorrect was read off the massaging
// hand, which comes in fingers-first and never passes the dorsal gate).
final class RoleInversionTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let receiverPts: [HandJoint: CGPoint] = HandFixture.dorsalRight

    func testWeakReceiverDoesNotHandTheRingToTheMassagingHand() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let strongReceiver = Hand(points: receiverPts, chirality: .right)
        let tip = strongReceiver.weightedTarget(target.anchors)!
        var pPts: [HandJoint: CGPoint] = [.wrist: CGPoint(x: tip.x + 0.20, y: tip.y + 0.28),
                                          .middleMCP: CGPoint(x: tip.x + 0.16, y: tip.y + 0.20)]
        pPts[target.pressFinger] = tip
        let presser = Hand(points: pPts, chirality: .left)

        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        // Establish correct roles with both hands strong.
        for _ in 0..<10 { engine.update(hands: [strongReceiver, presser], point: te3, now: t); t += dt }
        let ringWhenHealthy = engine.ringCenter
        XCTAssertNotNil(ringWhenHealthy)

        // Now the RECEIVER degrades to weak (it is the one being covered), presser stays strong.
        let weakReceiver = Hand(points: receiverPts, chirality: .right, weak: true, detectionConfidence: 0.35)
        var wrongFaceFrames = 0, lostTip = 0
        for _ in 0..<45 {
            engine.update(hands: [weakReceiver, presser], point: te3, now: t); t += dt
            if engine.phase == .wrongFace { wrongFaceFrames += 1 }
            if engine.pressTip == nil { lostTip += 1 }
        }
        XCTAssertEqual(wrongFaceFrames, 0,
                       "a WRONG-FACE prompt fired on \(wrongFaceFrames)/45 frames — the face gate is "
                       + "being read off the massaging hand, so the roles have inverted")
        XCTAssertEqual(lostTip, 0,
                       "the massaging fingertip was lost on \(lostTip)/45 frames — selectPresserTip is "
                       + "excluding the real massaging hand because it has been labelled the receiver")
        if let a = ringWhenHealthy, let b = engine.ringCenter {
            XCTAssertLessThan(hypot(a.x - b.x, a.y - b.y), 0.05,
                              "the ring jumped to the massaging hand when the receiver went weak")
        }
    }
}

// STUDY-MODE voice vocabulary. These commands are what makes freezing the frame usable at all: the
// screen's premise is that both hands are occupied, so a tap-only exit would break exactly the
// constraint the feature exists for (user-caught: "if they found the location, they would have to
// take it off and click continue"). Recognition only — no spoken line, no clip, nothing to
// re-render.
final class StudyVoiceCommandTests: XCTestCase {

    func testStudyPhrasesAreRecognised() {
        for p in ["show me", "ok show me how", "read it", "read it again", "how do i find it"] {
            XCTAssertEqual(LocateVoiceCommand.parse(p), .study, "'\(p)' should open the guide")
        }
        for p in ["怎么找", "看说明", "再说一次"] {
            XCTAssertEqual(LocateVoiceCommand.parse(p), .study, "'\(p)' should open the guide")
        }
    }

    func testResumePhrasesAreRecognised() {
        for p in ["continue", "resume", "carry on", "im ready", "ok go on"] {
            XCTAssertEqual(LocateVoiceCommand.parse(p), .resume, "'\(p)' should resume")
        }
        // 找到了 / 开始吧 exercise the filler strip: the trailing 了 / 吧 comes off and the stem
        // matches. Phrases whose STEM would be bare 好 are deliberately absent — see resumeZh.
        for p in ["继续", "找到了", "开始吧", "继续吧"] {
            XCTAssertEqual(LocateVoiceCommand.parse(p), .resume, "'\(p)' should resume")
        }
    }

    // The negation guard is the part most likely to bite: the mic is open next to a person who is
    // talking to themselves while hunting for a sore spot.
    func testNegatedCommandsDoNotFire() {
        for p in ["dont continue", "not ready", "no dont show me", "don't resume"] {
            XCTAssertNotEqual(LocateVoiceCommand.parse(p), .resume, "'\(p)' must not resume")
            XCTAssertNotEqual(LocateVoiceCommand.parse(p), .study, "'\(p)' must not open the guide")
        }
        for p in ["不要继续", "别继续", "不用看说明"] {
            XCTAssertNotEqual(LocateVoiceCommand.parse(p), .resume, "'\(p)' must not resume")
            XCTAssertNotEqual(LocateVoiceCommand.parse(p), .study, "'\(p)' must not open the guide")
        }
    }

    // The new words must not cannibalise the existing ones — confirm and skip are the commands that
    // actually save a calibration, and a mis-parse there costs the user their spot.
    func testExistingCommandsStillWin() {
        XCTAssertEqual(LocateVoiceCommand.parse("this is my spot"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("就是这里"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("skip"), .skip)
        XCTAssertEqual(LocateVoiceCommand.parse("跳过"), .skip)
    }

    // Ambient speech must not trip study mode mid-session.
    func testAmbientChatterDoesNotTrigger() {
        for p in ["i can show you later", "the show was good", "i read a book", "看电视"] {
            XCTAssertNil(LocateVoiceCommand.parse(p), "'\(p)' must not be a command")
        }
    }
}
