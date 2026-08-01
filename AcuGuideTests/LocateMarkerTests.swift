import XCTest
import CoreGraphics
import Vision
@testable import AcuGuide

// The four things a user reported about the locate step's on-screen marks, none of which had a test:
//
//   1. "the confirmed marker placement was nowhere near the location i pressed"
//   2. "the previously recorded spot of the acupoint drifted out of the hand"
//   3. "way too many markers at display at the same time"
//   4. the frozen frame showed no approximate ring, and kept detecting behind the still
//
// (1) and (2) are the same defect seen twice — the canonical fold is a SIGN, and it was being read
// from Vision's raw per-frame handedness guess while every other consumer in the engine used the
// vote-held label. (3) and (4) are the overlay having no single place that decided what is on
// screen. These pin the fixes.
final class LocateMarkerTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let base: [HandJoint: CGPoint] = HandFixture.dorsalRight

    override func tearDown() {
        PointCalibration.purgeEphemeral()
        super.tearDown()
    }

    private func presserHand(pressing p: CGPoint, finger: HandJoint) -> Hand {
        var pts: [HandJoint: CGPoint] = [.wrist: CGPoint(x: p.x + 0.20, y: p.y + 0.28),
                                         .middleMCP: CGPoint(x: p.x + 0.16, y: p.y + 0.20)]
        pts[finger] = p
        return Hand(points: pts, chirality: .left)
    }

    // MARK: - The saved spot must not mirror across the hand on a chirality misread

    /// THE DEFECT: `PointCalibration.canonicalFrame` folds left hands by negating canonical x, so
    /// the handedness label is a SIGN on the stored correction. It used to read `hand.chirality` —
    /// Vision's independent per-frame guess, at its least reliable in exactly this framing (two
    /// overlapping hands, no forearm, no body). One misread frame therefore reflected the whole
    /// correction across the hand's long axis, which is a saved spot appearing on the far side of
    /// the hand — or off it. CoachEngine already holds that label against a 10-frame vote for the
    /// face gate; it now uses the same held label for the fold.
    ///
    /// The misread here is 9 consecutive frames, deliberately one short of
    /// `CoachConst.chiralityFlipFrames`: a sustained genuine change SHOULD move the label, so the
    /// test proves the hold works rather than that the label is ignored.
    func testChiralityMisreadCannotMirrorTheConfirmedSpot() {
        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.035, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))

        // Settle into coaching on the confirmed spot.
        for _ in 0..<20 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        let confirmed = engine.ringCenter!
        XCTAssertEqual(Double(hypot(confirmed.x - press.x, confirmed.y - press.y)), 0, accuracy: 0.015,
                       "precondition: the coach ring sits on the confirmed spot")

        // Vision now mislabels the SAME physical hand. Nothing about the hand has moved.
        let misread = Hand(points: base, chirality: .left)
        for _ in 0..<9 { engine.update(hands: [misread, presser], point: te3, now: t); t += dt }

        let after = engine.ringCenter!
        XCTAssertEqual(Double(hypot(after.x - confirmed.x, after.y - confirmed.y)), 0, accuracy: 0.004,
                       "a handedness misread must not move the saved spot — folding on the raw "
                       + "per-frame label mirrors it across the hand, which is the reported "
                       + "'drifted out of the hand'")
    }

    /// The capture side of the same rule: the window's handedness comes from the held label, so a
    /// press does not have to out-wait Vision's jitter to be confirmable, and the label the
    /// correction is CAPTURED under is the one it is later APPLIED under.
    func testSettleSurvivesAChiralityFlickerDuringThePress() {
        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let steady = Hand(points: base, chirality: .right)
        let flicker = Hand(points: base, chirality: .left)
        let affine = steady.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.03, y: affine.y)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        // One misread frame in every five, none of them long enough to carry the vote.
        for i in 0..<40 {
            engine.update(hands: [i % 5 == 4 ? flicker : steady, presser], point: te3, now: t)
            t += dt
        }
        XCTAssertEqual(engine.locateState, .ready,
                       "a press held through Vision's handedness jitter must still settle — the "
                       + "engine has already voted that jitter away")
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
        XCTAssertNotNil(cal.offset(for: "TE3"))
    }

    // MARK: - One ring, one press mark, one chip

    /// The overlay used to draw whatever happened to be non-nil across four published positions.
    /// `CoachMarks` makes the rule a property of the type: these assertions are over the value the
    /// view renders, so a new marker cannot be added without going through it.
    func testOverlayDrawsAtMostOneRingAndOnePressMark() {
        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.03, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0

        // Hunting: dashed approximation + the live fingertip. Nothing else.
        for _ in 0..<3 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        var marks = CoachMarks.make(engine: engine, overlay: engine.overlay, ringLabel: nil)
        XCTAssertEqual(marks.ring?.dashed, true, "the locate guide is an approximation, drawn dashed")
        XCTAssertEqual(marks.ring?.centerDot, false,
                       "a precise centre dot on an approximate ring is a claim the app can't back")
        XCTAssertNotNil(marks.ring?.label, "the approximate ring carries the one chip")
        if case .live = marks.press {} else { XCTFail("the fingertip mark must be the live one") }

        // Settled: the mark stops chasing the finger and becomes the thing confirm is about. Both
        // positions are published at this moment — only ONE is drawn.
        for _ in 0..<27 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        XCTAssertNotNil(engine.overlay.pressTip)
        XCTAssertNotNil(engine.overlay.settledPress)
        marks = CoachMarks.make(engine: engine, overlay: engine.overlay, ringLabel: nil)
        if case .settled = marks.press {} else {
            XCTFail("a settled press must REPLACE the live fingertip mark, not sit beside it")
        }

        // Coaching: solid ring with a solid centre — that centre IS the confirmed spot, so it needs
        // no second dot to say so.
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
        for _ in 0..<5 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        marks = CoachMarks.make(engine: engine, overlay: engine.overlay,
                                ringLabel: "where you pressed")
        XCTAssertEqual(marks.ring?.dashed, false)
        XCTAssertEqual(marks.ring?.centerDot, true, "the coach ring marks the exact saved spot")
        XCTAssertEqual(marks.ring?.label, "where you pressed")
        XCTAssertNil(marks.settledPressForTest,
                     "the settled-press mark belongs to the locate step and must not survive it")
    }

    /// The frozen frame annotates the picture it was taken with. Marks are a VALUE captured
    /// alongside the still — not a live stream drawn over an old photograph, which is what made the
    /// frozen shot show markers from a moment that had already passed.
    func testFrozenMarksAreASnapshotNotALiveReference() {
        let te3 = Acupoint.byId["TE3"]!
        let receiver = Hand(points: base, chirality: .right)
        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<5 { engine.update(hands: [receiver], point: te3, now: t); t += dt }

        let captured = CoachMarks.make(engine: engine, overlay: engine.overlay, ringLabel: nil)
        let ringAtFreeze = captured.ring?.center

        // The world moves on (in the app the camera is stopped at this point, but the value must
        // not depend on that being true).
        let moved = Hand(points: base.mapValues { CGPoint(x: $0.x - 0.15, y: $0.y - 0.10) },
                         chirality: .right)
        for _ in 0..<10 { engine.update(hands: [moved], point: te3, now: t); t += dt }

        XCTAssertEqual(captured.ring?.center, ringAtFreeze, "the captured marks must not move")
        XCTAssertNotEqual(engine.overlay.ringCenter, ringAtFreeze,
                          "precondition: the LIVE ring did move, so the snapshot is meaningful")
    }
}

private extension CoachMarks {
    /// Reads as nil unless a settled-press mark is present — spelled out so the assertion above
    /// says what it means rather than pattern-matching an enum inline.
    var settledPressForTest: CGPoint? {
        if case .settled(let p) = press { return p }
        return nil
    }
}
