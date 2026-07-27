import XCTest
import Vision
@testable import AcuGuide

// THE PALM-VS-BACK GATE, TESTED AT THE VALUE IT SHIPS WITH.
//
// This file exists because nothing tested the shipped configuration. Twenty-three call sites across
// the other suites force `HandCalibration.dorsalWhenSignedPositive = true` — the OPPOSITE of
// production — because their synthetic hands are mirror images of what a device actually produces,
// and the fixture suite bypasses isDorsal entirely (it reads a `face` field straight out of the
// JSON). So the one branch that decides "turn your hand over" had no coverage at all, and a user
// reported exactly that: "the hand orientation detection is reversed for the right and left hand."
//
// The hands below are built from REAL device geometry, not invented: the landmark layouts are the
// shape of the captures in claude-deliverables/data/te3_labels_2026-07-07.jsonl (front camera,
// mirrored coordinates, TE3 — a DORSAL point — so every one of those nine is a known-dorsal hand,
// five labelled .right and four .left). Nothing here touches the calibration flag.
final class HandFaceGateTests: XCTestCase {

    override func setUp() {
        super.setUp()
        XCTAssertFalse(HandCalibration.dorsalWhenSignedPositive,
                       "these cases are written for the SHIPPED convention; do not flip the flag to make them pass")
    }

    /// A hand in the mirrored front-camera convention (top-left origin, fingers up, wrist below).
    /// `thumbOnRight` places the radial side at larger x. Against the device captures: a hand Vision
    /// labels `.right` has its thumb at larger x, and a `.left` one at smaller x — the pairing that
    /// makes all nine dorsal captures agree.
    private func hand(_ chirality: VNChirality, thumbOnRight: Bool,
                      mirrored: Bool = true) -> Hand {
        let s: CGFloat = thumbOnRight ? 1 : -1
        var pts: [HandJoint: CGPoint] = [
            .wrist:     CGPoint(x: 0.50, y: 0.80),
            .indexMCP:  CGPoint(x: 0.50 + s * 0.12, y: 0.52),
            .middleMCP: CGPoint(x: 0.50 + s * 0.02, y: 0.50),
            .ringMCP:   CGPoint(x: 0.50 - s * 0.08, y: 0.52),
            .pinkyMCP:  CGPoint(x: 0.50 - s * 0.17, y: 0.57),
            .thumbTip:  CGPoint(x: 0.50 + s * 0.26, y: 0.66),
        ]
        if !mirrored { pts = pts.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) } }
        return Hand(points: pts, chirality: chirality, mirroredCoords: mirrored)
    }

    // The load-bearing case, both hands. Vision-".right with the thumb at larger x" and
    // "Vision-.left with the thumb at smaller x" are the two dorsal shapes the device produced, and
    // the shipped convention must call BOTH of them dorsal — that symmetry is what rules out a
    // systematic left/right inversion in the gate itself.
    func testBothHandsReadDorsalInTheDeviceCapturedPose() {
        XCTAssertEqual(hand(.right, thumbOnRight: true).isDorsal, true,
                       "the .right-labelled device pose is a DORSAL hand")
        XCTAssertEqual(hand(.left, thumbOnRight: false).isDorsal, true,
                       "the .left-labelled device pose is a DORSAL hand")
    }

    // Turn either hand over and the verdict must turn over with it — otherwise the gate is a
    // constant, not a test.
    func testFlippingTheHandFlipsTheVerdict() {
        XCTAssertEqual(hand(.right, thumbOnRight: false).isDorsal, false)
        XCTAssertEqual(hand(.left, thumbOnRight: true).isDorsal, false)
    }

    // The back camera hands Vision the SAME un-mirrored buffer, so chirality is unchanged while our
    // own x-flip is not applied. `mirroredCoords` is what keeps the verdict stable across that.
    func testBackCameraAgreesWithFrontForTheSamePhysicalPose() {
        for chirality in [VNChirality.right, .left] {
            let thumbRight = chirality == .right
            XCTAssertEqual(hand(chirality, thumbOnRight: thumbRight, mirrored: true).isDorsal,
                           hand(chirality, thumbOnRight: thumbRight, mirrored: false).isDorsal,
                           "\(chirality) reads differently on the back camera — the parity term is wrong")
        }
    }

    // UNKNOWN IS NOT LEFT. The old ternary's else arm swallowed .unknown and returned the left
    // answer, i.e. a coin flip dressed as a verdict.
    func testUnknownChiralityIsUnreadableNotLeft() {
        XCTAssertNil(hand(.unknown, thumbOnRight: true).isDorsal,
                     "an unreadable handedness must not produce a confident face verdict")
        // …and it must not merely be inheriting the left answer by accident.
        XCTAssertEqual(hand(.unknown, thumbOnRight: true).isDorsal(assuming: .left),
                       hand(.left, thumbOnRight: true).isDorsal,
                       "isDorsal(assuming:) must use the label it is given")
    }

    // A missing MCP is still unreadable, as before.
    func testMissingLandmarkIsUnreadable() {
        var pts = hand(.right, thumbOnRight: true).points
        pts[.pinkyMCP] = nil
        XCTAssertNil(Hand(points: pts, chirality: .right).isDorsal)
    }

    // The whole point of isDorsal(assuming:): the coach can overrule a single frame's misread with
    // a label it has held across frames, and get the STEADY answer rather than the flapping one.
    func testAssumingLabelOverridesTheFramesOwnMisread() {
        // A physically dorsal right hand that Vision mislabelled `.left` this frame.
        let misread = hand(.left, thumbOnRight: true)
        XCTAssertEqual(misread.isDorsal, false, "the misread frame alone gets it wrong — this is the bug")
        XCTAssertEqual(misread.isDorsal(assuming: .right), true,
                       "with the held label, the same geometry reads dorsal again")
    }
}

// The inverted-frame second pass must not import its handedness over the primary pass's.
final class InvertedPassChiralityTests: XCTestCase {
    private func hand(_ c: VNChirality, wristX: CGFloat, confidence: Float) -> Hand {
        Hand(points: [.wrist: CGPoint(x: wristX, y: 0.5), .middleMCP: CGPoint(x: wristX, y: 0.3)],
             chirality: c, detectionConfidence: confidence)
    }

    func testConflictingLabelMergeKeepsThePrimaryHandedness() {
        var hands = [hand(.right, wristX: 0.50, confidence: 0.4)]
        // Near-coincident wrist, opposite label, clearly more confident → the merge takes its
        // geometry. It must NOT take its chirality: this pass exists for the foreshortened poses
        // Vision mislabels, and chirality is the sign multiplier inside isDorsal.
        let inverted = hand(.left, wristX: 0.52, confidence: 0.9)
        XCTAssertTrue(CameraCoach.mergeInvertedRead(inverted, into: &hands))
        XCTAssertEqual(hands.count, 1)
        XCTAssertEqual(hands[0].chirality, .right, "the inverted pass overwrote the handedness label")
        XCTAssertEqual(hands[0].detectionConfidence, 0.9, "…but its better geometry should have been taken")
    }

    func testAgreeingLabelMergeIsUnchanged() {
        var hands = [hand(.right, wristX: 0.50, confidence: 0.4)]
        XCTAssertTrue(CameraCoach.mergeInvertedRead(hand(.right, wristX: 0.52, confidence: 0.9), into: &hands))
        XCTAssertEqual(hands[0].chirality, .right)
        XCTAssertEqual(hands[0].detectionConfidence, 0.9)
    }
}

// THE REPORTED SYMPTOM, at engine level: a flickering handedness label must not produce
// "turn your hand over" at a hand that never moved.
final class FaceGateStabilityTests: XCTestCase {
    private let dt = 1.0 / 30.0

    // A DORSAL right hand in the device-captured parity (thumb at larger x for a `.right` label),
    // so this suite needs no calibration-flag override — unlike every older engine test.
    private func receiver(_ chirality: VNChirality) -> Hand {
        Hand(points: [
            .wrist:     CGPoint(x: 0.50, y: 0.80),
            .indexMCP:  CGPoint(x: 0.62, y: 0.52),
            .middleMCP: CGPoint(x: 0.52, y: 0.50),
            .ringMCP:   CGPoint(x: 0.42, y: 0.52),
            .pinkyMCP:  CGPoint(x: 0.33, y: 0.57),
            .indexTip:  CGPoint(x: 0.64, y: 0.30),
            .middleTip: CGPoint(x: 0.52, y: 0.27),
            .ringTip:   CGPoint(x: 0.40, y: 0.30),
            .pinkyTip:  CGPoint(x: 0.29, y: 0.36),
            .thumbTip:  CGPoint(x: 0.76, y: 0.66),
        ], chirality: chirality)
    }

    private func presser(at tip: CGPoint) -> Hand {
        Hand(points: [.wrist: CGPoint(x: tip.x + 0.20, y: tip.y + 0.28),
                      .middleMCP: CGPoint(x: tip.x + 0.16, y: tip.y + 0.20),
                      .indexTip: tip],
             chirality: .left, detectionConfidence: 0.9)
    }

    func testABriefChiralityMisreadDoesNotAskTheUserToFlipTheirHand() {
        let te3 = Acupoint.byId["TE3"]!
        let good = receiver(.right)
        let tip = good.weightedTarget(te3.mediapipeTarget!.anchors)!
        let p = presser(at: tip)
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0

        for _ in 0..<20 { engine.update(hands: [good, p], point: te3, now: t); t += dt }
        XCTAssertNotEqual(engine.phase, .wrongFace, "a correct dorsal hand must pass the gate")

        // Vision now mislabels the SAME hand for a handful of frames — the documented failure mode
        // for a close-up of two overlapping hands with no forearm in view. The geometry is
        // identical; only the label flickers.
        let misread = receiver(.left)
        for _ in 0..<(CoachConst.chiralityFlipFrames - 1) {
            engine.update(hands: [misread, p], point: te3, now: t); t += dt
            XCTAssertNotEqual(engine.phase, .wrongFace,
                              "a flickering handedness label flipped the palm/back verdict — this is the reported bug")
        }
    }

    // The hold must not become a lock: a SUSTAINED change (the user really did swap hands) still
    // gets through, or the gate would be stuck on the first label it ever saw.
    func testASustainedHandednessChangeStillTakesEffect() {
        let te3 = Acupoint.byId["TE3"]!
        let good = receiver(.right)
        let tip = good.weightedTarget(te3.mediapipeTarget!.anchors)!
        let p = presser(at: tip)
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<20 { engine.update(hands: [good, p], point: te3, now: t); t += dt }

        let other = receiver(.left)
        for _ in 0..<(CoachConst.chiralityFlipFrames + 5) {
            engine.update(hands: [other, p], point: te3, now: t); t += dt
        }
        XCTAssertEqual(engine.phase, .wrongFace,
                       "a sustained label change must still reach the gate — the hold is a debounce, not a latch")
    }

    // And when the gate is wrong anyway, the user gets a way out rather than a dead button.
    func testAStuckGateOffersAnOverrideAndTheOverrideWorks() {
        let te3 = Acupoint.byId["TE3"]!
        let palmar = receiver(.right)                    // dorsal geometry…
        let pc8 = Acupoint.byId["PC8"]!                  // …asked for as a PALMAR point → refused
        let tip = palmar.weightedTarget(pc8.mediapipeTarget!.anchors)!
        let p = presser(at: tip)
        let engine = CoachEngine(calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<20 { engine.update(hands: [palmar, p], point: pc8, now: t); t += dt }
        XCTAssertEqual(engine.phase, .wrongFace)
        XCTAssertFalse(engine.faceGateStuck, "the escape must not be offered immediately")

        while t < CoachConst.wrongFaceStuckS + 1 { engine.update(hands: [palmar, p], point: pc8, now: t); t += dt }
        XCTAssertTrue(engine.faceGateStuck, "a gate stuck this long must offer the user a way past it")

        engine.overrideFaceGate()
        engine.update(hands: [palmar, p], point: pc8, now: t); t += dt
        XCTAssertNotEqual(engine.phase, .wrongFace, "the override must actually unblock the session")
        XCTAssertFalse(engine.faceGateStuck)
        _ = te3
    }
}
