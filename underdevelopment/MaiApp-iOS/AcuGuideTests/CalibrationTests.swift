import XCTest
import CoreGraphics
@testable import AcuGuide

// A calibration store on a throwaway defaults suite — hermetic: engine tests must neither read a
// real calibration saved on this device/simulator nor write junk into the app's defaults.
extension PointCalibration {
    static func ephemeral() -> PointCalibration {
        let name = "test.calibration.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return PointCalibration(defaults: d)
    }
}

// The per-user spot correction (guided locate): store semantics, and the load-bearing invariance —
// an offset captured in one hand pose must land on the anatomically-equivalent point in ANY other
// pose (translated / rotated / scaled / mirrored / other hand), because it lives in the canonical
// hand frame, not in screen space.
final class PointCalibrationTests: XCTestCase {

    private let base: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
        .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    func testStoreClampAndPersistence() {
        let name = "test.calibration.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let cal = PointCalibration(defaults: defaults)
        XCTAssertNil(cal.offset(for: "TE3"))

        // In-range offset stores as-is.
        cal.set(PointCalibration.Offset(dx: 0.10, dy: -0.05), for: "TE3")
        XCTAssertEqual(cal.offset(for: "TE3")?.dx ?? 0, 0.10, accuracy: 1e-12)

        // A wild capture clamps to maxOffsetXHandSize, direction preserved — the correction stays
        // SLIGHT by design (safety: a stray press can't drag the ring onto different anatomy).
        cal.set(PointCalibration.Offset(dx: 3.0, dy: 4.0), for: "SI3")
        let clamped = cal.offset(for: "SI3")!
        XCTAssertEqual(clamped.norm, PointCalibration.maxOffsetXHandSize, accuracy: 1e-9)
        XCTAssertEqual(clamped.dx / clamped.dy, 3.0 / 4.0, accuracy: 1e-9, "clamp must keep direction")

        // Survives a reload from the same defaults; clear removes it.
        let reloaded = PointCalibration(defaults: defaults)
        XCTAssertEqual(reloaded.offset(for: "TE3"), cal.offset(for: "TE3"))
        reloaded.clear("TE3")
        XCTAssertNil(reloaded.offset(for: "TE3"))
        XCTAssertNil(PointCalibration(defaults: defaults).offset(for: "TE3"))

        defaults.removePersistentDomain(forName: name)
    }

    // Similarity-transform invariance: capture on one pose, apply on a moved/rotated/scaled pose →
    // the corrected target is exactly the transformed press point.
    func testOffsetRidesHandPose() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let hand = Hand(points: base, chirality: .right)
        let affine = hand.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y - 0.03)   // "the spot that felt right"

        let off = PointCalibration.offset(press: press, affine: affine, hand: hand)!
        let cal = PointCalibration.ephemeral()
        cal.set(off, for: "TE3")

        // A similarity transform (rotate 0.6 rad, scale 1.4, translate) — a hand moved in frame.
        let th = 0.6, s = 1.4, tx = 0.12, ty = -0.08
        func T(_ p: CGPoint) -> CGPoint {
            CGPoint(x: s * (cos(th) * Double(p.x) - sin(th) * Double(p.y)) + tx,
                    y: s * (sin(th) * Double(p.x) + cos(th) * Double(p.y)) + ty)
        }
        let moved = Hand(points: base.mapValues(T), chirality: .right)
        let movedAffine = moved.weightedTarget(te3.anchors)!
        let corrected = cal.apply(movedAffine, hand: moved, pointId: "TE3")
        let expected = T(press)
        XCTAssertEqual(Double(corrected.x), Double(expected.x), accuracy: 1e-6)
        XCTAssertEqual(Double(corrected.y), Double(expected.y), accuracy: 1e-6)

        // A point with no stored offset passes through untouched.
        XCTAssertEqual(cal.apply(movedAffine, hand: moved, pointId: "SI3"), movedAffine)
    }

    // Chirality invariance: the offset captured on the RIGHT hand must land on the anatomically
    // equivalent (mirror-image) spot of the LEFT hand — the canonical frame's chirality fold.
    func testOffsetTransfersToOtherHand() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let right = Hand(points: base, chirality: .right)
        let affine = right.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y - 0.03)

        let cal = PointCalibration.ephemeral()
        cal.set(PointCalibration.offset(press: press, affine: affine, hand: right)!, for: "TE3")

        // The left hand as the exact mirror image (same parity convention, mirroredCoords: true).
        func mirror(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let left = Hand(points: base.mapValues(mirror), chirality: .left)
        let leftAffine = left.weightedTarget(te3.anchors)!
        let corrected = cal.apply(leftAffine, hand: left, pointId: "TE3")
        XCTAssertEqual(Double(corrected.x), Double(mirror(press).x), accuracy: 1e-6)
        XCTAssertEqual(Double(corrected.y), Double(mirror(press).y), accuracy: 1e-6)
    }

    // Parity invariance: captured under the front camera's MIRRORED convention, applied under the
    // back camera's un-mirrored coordinates (same physical hand, chirality unchanged — Vision reads
    // the un-mirrored buffer either way). Without the parity-aware fold the dx lands on the wrong
    // (radial/ulnar) side.
    func testOffsetSurvivesCameraParityFlip() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let mirroredHand = Hand(points: base, chirality: .right, mirroredCoords: true)
        let affine = mirroredHand.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y - 0.03)

        let cal = PointCalibration.ephemeral()
        cal.set(PointCalibration.offset(press: press, affine: affine, hand: mirroredHand)!, for: "TE3")

        // The same physical scene through the back camera: x un-mirrors, chirality stays .right.
        func unmirror(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let backHand = Hand(points: base.mapValues(unmirror), chirality: .right, mirroredCoords: false)
        let backAffine = backHand.weightedTarget(te3.anchors)!
        let corrected = cal.apply(backAffine, hand: backHand, pointId: "TE3")
        XCTAssertEqual(Double(corrected.x), Double(unmirror(press).x), accuracy: 1e-6)
        XCTAssertEqual(Double(corrected.y), Double(unmirror(press).y), accuracy: 1e-6)
    }
}

// The guided-locate flow at engine level: settle a press near the dashed guide → .ready →
// confirm stores the correction and hands over to the coach with the ring ON the user's spot.
final class CoachEngineLocateTests: XCTestCase {
    private let dt = 1.0 / 30.0
    private let base: [HandJoint: CGPoint] = [
        .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
        .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
        .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
        .thumbTip: CGPoint(x: 0.34, y: 0.62)]

    private func presserHand(pressing p: CGPoint, finger: HandJoint) -> Hand {
        var pts: [HandJoint: CGPoint] = [.wrist: CGPoint(x: p.x + 0.20, y: p.y + 0.28),
                                         .middleMCP: CGPoint(x: p.x + 0.16, y: p.y + 0.20)]
        pts[finger] = p
        return Hand(points: pts, chirality: .left)
    }

    func testLocateConfirmStoresCorrectionAndMovesRing() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true      // synthetic right hand reads dorsal
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        // The user's spot: a touch ulnar of the computed target — inside the capture radius.
        let press = CGPoint(x: affine.x + 0.03, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        XCTAssertEqual(engine.mode, .locate)

        // No press yet: hand alone in frame → locate is searching, nothing accrues.
        var t = 0.0
        for _ in 0..<5 { engine.update(hands: [receiver], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .noPress)
        XCTAssertEqual(engine.progress, 0, "locate step must never credit hold time")

        // A steady press near the guide: after the settle window the confirm unlocks.
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready, "a settled press near the guide must unlock confirm")
        let cand = engine.locateCandidate
        XCTAssertNotNil(cand)
        XCTAssertEqual(Double(hypot(cand!.x - press.x, cand!.y - press.y)), 0, accuracy: 0.01,
                       "the labeled press must sit on the user's actual press")
        XCTAssertEqual(engine.progress, 0, "still locating — no hold credit")

        // Confirm: correction stored, mode flips to coaching.
        XCTAssertTrue(engine.confirmLocate(point: te3))
        XCTAssertEqual(engine.mode, .coach)
        XCTAssertNotNil(cal.offset(for: "TE3"), "confirm must store the per-user correction")

        // Coaching now: the ring sits on the USER's spot, and pressing there reaches HOLDING.
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        let ring = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ring.x - press.x, ring.y - press.y)), 0, accuracy: 0.015,
                       "after confirm the coach ring must sit on the confirmed spot")
        XCTAssertEqual(engine.phase, .holding, "pressing the confirmed spot must engage the coach")
        XCTAssertGreaterThan(engine.progress, 0)
    }

    func testLocateSkipKeepsStandardSpot() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        for _ in 0..<5 { engine.update(hands: [receiver], point: te3, now: t); t += dt }

        engine.endLocate()   // "Skip"
        XCTAssertEqual(engine.mode, .coach)
        XCTAssertNil(cal.offset(for: "TE3"), "skip must not store a correction")

        // The coach ring stays on the standard affine target.
        let presser = presserHand(pressing: affine, finger: target.pressFinger)
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        let ring = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ring.x - affine.x, ring.y - affine.y)), 0, accuracy: 0.01)
        XCTAssertEqual(engine.phase, .holding)
    }

    // A press OUTSIDE the capture radius must read as off-guide and never unlock confirm — the
    // guided correction is a fine-tune near the marked area, not a "put the ring anywhere" tool.
    func testFarPressNeverUnlocksConfirm() {
        let saved = HandCalibration.dorsalWhenSignedPositive
        HandCalibration.dorsalWhenSignedPositive = true
        defer { HandCalibration.dorsalWhenSignedPositive = saved }

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let far = CGPoint(x: affine.x + 0.25, y: affine.y)   // way past the capture radius
        let presser = presserHand(pressing: far, finger: target.pressFinger)

        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<40 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .offGuide)
        XCTAssertFalse(engine.confirmLocate(point: te3), "confirm must refuse a far press")
        XCTAssertEqual(engine.mode, .locate)
    }
}
