import XCTest
import CoreGraphics
@testable import AcuGuide

// A calibration store on a throwaway defaults suite — hermetic: engine tests must neither read a
// real calibration saved on this device/simulator nor write junk into the app's defaults. Suites
// are tracked and purged in tearDown (purgeEphemeral) so runs don't litter orphan plists.
extension PointCalibration {
    private static var ephemeralSuites: [String] = []
    static func ephemeral() -> PointCalibration {
        let name = "test.calibration.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        ephemeralSuites.append(name)
        return PointCalibration(defaults: d)
    }
    static func purgeEphemeral() {
        for n in ephemeralSuites { UserDefaults(suiteName: n)?.removePersistentDomain(forName: n) }
        ephemeralSuites.removeAll()
    }
}

// The per-user spot correction (guided locate): store semantics, and the load-bearing invariance —
// an offset captured in one hand pose must land on the anatomically-equivalent point in ANY other
// pose (translated / PHYSICALLY rotated / scaled / mirrored / other hand). The canonical frame is
// built in ISOTROPIC width units, because landmarks are normalized per-axis and a physical
// rotation is NOT a similarity transform in that anisotropic space (a raw-coordinate frame
// re-applied an upright-captured offset at up to (H/W)² ≈ 3.2× once the hand lay sideways).
final class PointCalibrationTests: XCTestCase {

    private let aspect: CGFloat = 9.0 / 16.0   // portrait frame W/H, the engine's default

    override func tearDown() {
        PointCalibration.purgeEphemeral()
        super.tearDown()
    }

    private let base: [HandJoint: CGPoint] = HandFixture.dorsalRight

    func testStoreClampAndPersistence() {
        let name = "test.calibration.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

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
    }

    // Never destroy what we can't read: an undecodable blob under the storage key must be PARKED,
    // not silently replaced — a schema change or corrupt write would otherwise wipe every spot
    // the user confirmed by feel, unrecoverably (review-caught).
    func testUnreadableBlobIsParkedNotDestroyed() {
        let name = "test.calibration.unreadable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "pointCalibration.v2")
        let cal = PointCalibration(defaults: defaults)
        XCTAssertNil(cal.offset(for: "TE3"), "unreadable store must start empty")
        XCTAssertEqual(defaults.data(forKey: "pointCalibration.v2.unreadable"), garbage,
                       "the blob must be parked for a future build to recover")
        cal.set(PointCalibration.Offset(dx: 0.1, dy: 0), for: "TE3")   // fresh writes work
        XCTAssertNotNil(PointCalibration(defaults: defaults).offset(for: "TE3"))
    }

    // The safety clamp must hold on the LOAD path too: a decodable blob with an oversized offset
    // (restored backup, synced defaults, looser-clamp build) must not apply un-clamped.
    func testLoadReclampsOversizedOffsets() {
        let name = "test.calibration.load.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let blob = try! JSONEncoder().encode(["TE3": PointCalibration.Offset(dx: 3.0, dy: 4.0)])
        defaults.set(blob, forKey: "pointCalibration.v2")
        let cal = PointCalibration(defaults: defaults)
        XCTAssertEqual(cal.offset(for: "TE3")!.norm, PointCalibration.maxOffsetXHandSize, accuracy: 1e-9,
                       "a loaded oversized offset must be re-clamped")
    }

    // R14.10 briefly wrote raw-anisotropic offsets under the v1 key — different semantics. The v2
    // load must IGNORE v1 (not migrate, not misread) and leave the old data untouched.
    func testV1KeyIsIgnoredNotMigrated() {
        let name = "test.calibration.v1.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let v1 = try! JSONEncoder().encode(["TE3": PointCalibration.Offset(dx: 0.2, dy: 0)])
        defaults.set(v1, forKey: "pointCalibration.v1")
        let cal = PointCalibration(defaults: defaults)
        XCTAssertNil(cal.offset(for: "TE3"), "v1 data must not be read as v2")
        XCTAssertEqual(defaults.data(forKey: "pointCalibration.v1"), v1, "v1 data must be left untouched")
    }

    // A PHYSICAL similarity transform of the hand (rotate/scale/translate in real space, i.e. in
    // isotropic units — then mapped back through the anisotropic per-axis normalization): the
    // corrected target must be exactly the transformed press point. This is the transform a real
    // hand performs; a raw-coordinate canonical frame fails it (the anisotropy trap).
    func testOffsetRidesPhysicalHandPose() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let hand = Hand(points: base, chirality: .right)
        let affine = hand.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y - 0.03)   // "the spot that felt right"

        let off = PointCalibration.offset(press: press, affine: affine, hand: hand, aspect: aspect)!
        let cal = PointCalibration.ephemeral()
        cal.set(off, for: "TE3")

        // Physical similarity: rotate 90°, scale 1.3, translate — composed in ISO space.
        let th = Double.pi / 2, s = 1.3, tx = 0.10, ty = -0.06
        func T(_ p: CGPoint) -> CGPoint {
            let ix = Double(p.x), iy = Double(p.y) / Double(aspect)
            let rx = s * (cos(th) * ix - sin(th) * iy) + tx
            let ry = s * (sin(th) * ix + cos(th) * iy) + ty
            return CGPoint(x: rx, y: ry * Double(aspect))
        }
        let moved = Hand(points: base.mapValues(T), chirality: .right)
        let movedAffine = moved.weightedTarget(te3.anchors)!
        let corrected = cal.apply(movedAffine, hand: moved, pointId: "TE3", aspect: aspect)
        let expected = T(press)
        XCTAssertEqual(Double(corrected.x), Double(expected.x), accuracy: 1e-6)
        XCTAssertEqual(Double(corrected.y), Double(expected.y), accuracy: 1e-6)

        // A point with no stored offset passes through untouched.
        XCTAssertEqual(cal.apply(movedAffine, hand: moved, pointId: "SI3", aspect: aspect), movedAffine)
    }

    // Chirality invariance: the offset captured on the RIGHT hand must land on the anatomically
    // equivalent (mirror-image) spot of the LEFT hand — the canonical frame's chirality fold.
    func testOffsetTransfersToOtherHand() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let right = Hand(points: base, chirality: .right)
        let affine = right.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y - 0.03)

        let cal = PointCalibration.ephemeral()
        cal.set(PointCalibration.offset(press: press, affine: affine, hand: right, aspect: aspect)!, for: "TE3")

        // The left hand as the exact mirror image (same parity convention, mirroredCoords: true).
        func mirror(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let left = Hand(points: base.mapValues(mirror), chirality: .left)
        let leftAffine = left.weightedTarget(te3.anchors)!
        let corrected = cal.apply(leftAffine, hand: left, pointId: "TE3", aspect: aspect)
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
        cal.set(PointCalibration.offset(press: press, affine: affine, hand: mirroredHand, aspect: aspect)!,
                for: "TE3")

        // The same physical scene through the back camera: x un-mirrors, chirality stays .right.
        func unmirror(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let backHand = Hand(points: base.mapValues(unmirror), chirality: .right, mirroredCoords: false)
        let backAffine = backHand.weightedTarget(te3.anchors)!
        let corrected = cal.apply(backAffine, hand: backHand, pointId: "TE3", aspect: aspect)
        XCTAssertEqual(Double(corrected.x), Double(unmirror(press).x), accuracy: 1e-6)
        XCTAssertEqual(Double(corrected.y), Double(unmirror(press).y), accuracy: 1e-6)
    }

    // .unknown chirality must never capture or apply a correction — the fold direction would be a
    // guess, and a wrong guess mirrors the offset across the hand axis (review-caught).
    func testUnknownChiralityNeverCalibrates() {
        let te3 = Acupoint.byId["TE3"]!.mediapipeTarget!
        let hand = Hand(points: base, chirality: .unknown)
        let affine = hand.weightedTarget(te3.anchors)!
        let press = CGPoint(x: affine.x + 0.04, y: affine.y)
        XCTAssertNil(PointCalibration.offset(press: press, affine: affine, hand: hand, aspect: aspect),
                     "capture must refuse an unknown-handedness frame")

        let cal = PointCalibration.ephemeral()
        cal.set(PointCalibration.Offset(dx: 0.2, dy: 0), for: "TE3")
        XCTAssertEqual(cal.apply(affine, hand: hand, pointId: "TE3", aspect: aspect), affine,
                       "apply must fall back to the affine target on an unknown-handedness frame")
    }
}

// The guided-locate flow at engine level: settle a press near the dashed guide → .ready →
// confirm stores the correction and hands over to the coach with the ring ON the user's spot.
final class CoachEngineLocateTests: XCTestCase {
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

    func testLocateConfirmStoresCorrectionAndMovesRing() {

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
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
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

    // THE single-user physical flow (review-caught as impossible before the latch): the pressing
    // finger must LIFT to tap the confirm button. .ready must survive the lift for the latch
    // window — with the CAPTURE-TIME candidate/anchors frozen — and decay after it.
    func testConfirmLatchSurvivesPressLift() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.03, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        let cand = engine.locateCandidate!

        // The pressing hand lifts away (only the receiver stays): 2 seconds — well past the old
        // tipGraceS decay, well inside the confirm latch.
        for _ in 0..<60 { engine.update(hands: [receiver], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready, "the confirm offer must survive the lift-to-tap")
        XCTAssertNotNil(engine.locateCandidate)
        XCTAssertEqual(Double(hypot(engine.locateCandidate!.x - cand.x, engine.locateCandidate!.y - cand.y)),
                       0, accuracy: 1e-6, "with a static receiver the labeled press stays put")

        // The tap lands: the stored correction reflects the CAPTURE-time press.
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t), "confirm must succeed within the latch")
        let off = cal.offset(for: "TE3")
        XCTAssertNotNil(off)
        XCTAssertGreaterThan(off!.norm, 0.01, "a real correction was stored")

        // And a fresh session's latch EXPIRES when never confirmed: past locateConfirmLatchS with
        // no press, the offer decays instead of staying confirmable forever.
        let engine2 = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t2 = 0.0
        for _ in 0..<30 { engine2.update(hands: [receiver, presser], point: te3, now: t2); t2 += dt }
        XCTAssertEqual(engine2.locateState, .ready)
        let expiry = Int((CoachConst.locateConfirmLatchS + 0.5) / dt)
        for _ in 0..<expiry { engine2.update(hands: [receiver], point: te3, now: t2); t2 += dt }
        XCTAssertNotEqual(engine2.locateState, .ready, "an unconfirmed offer must expire")
        XCTAssertFalse(engine2.confirmLocate(point: te3, now: t2))
    }

    func testLocateSkipKeepsStandardSpot() {

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

    // A press outside the OUTER capture radius must read as off-guide and never unlock confirm.
    // The inner radius no longer refuses — a user whose point genuinely isn't where the affine
    // estimate puts it can confirm out to locateFarCaptureRadiusXHandSize with an honest note
    // (device-reported: "what if the acupoint is outside the dashed circle? it doesn't even allow
    // you to press"). This pins the OUTER limit that still exists, so a stray press or a hand
    // resting elsewhere cannot become a permanent calibration.
    // Distances are derived from the constants, not hard-coded: this test previously used a fixed
    // offset chosen against the old 0.30 gate and silently became a no-op when the gate widened.
    func testFarPressNeverUnlocksConfirm() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        // Past the OUTER radius but still inside presserAcquireXHandSize (0.65), so the tip is
        // tracked and the verdict is a real "off-guide", not "no press at all".
        // Same iso hand size the sibling boundary test uses (wrist→middleMCP, y in width units).
        let hsIsoLocal = CGFloat(hypot(0.0, 0.28 / (9.0 / 16.0)))
        let beyond = CGFloat(CoachConst.locateFarCaptureRadiusXHandSize + 0.08) * hsIsoLocal
        let far = CGPoint(x: affine.x + beyond, y: affine.y)
        let presser = presserHand(pressing: far, finger: target.pressFinger)

        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<40 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .offGuide)
        XCTAssertFalse(engine.confirmLocate(point: te3, now: t), "confirm must refuse a far press")
        XCTAssertEqual(engine.mode, .locate)
    }

    // Re-locate with an EXISTING correction (the review-caught datum-split class): the dashed
    // guide must sit on the STANDARD spot (one datum with gate + clamp), the old correction shows
    // as the savedSpot dot, and a fresh confirm REPLACES the offset un-clamped.
    func testRecalibrateGuidesFromStandardSpotAndReplaces() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!

        let cal = PointCalibration.ephemeral()
        cal.set(PointCalibration.Offset(dx: 0.22, dy: 0), for: "TE3")   // near-clamp prior offset
        let engine = CoachEngine(startLocating: true, calibration: cal)

        var t = 0.0
        for _ in 0..<10 { engine.update(hands: [receiver], point: te3, now: t); t += dt }
        // Guide ring = pure affine, NOT the corrected spot; the correction shows as savedSpot.
        let ring = engine.ringCenter!
        XCTAssertEqual(Double(hypot(ring.x - affine.x, ring.y - affine.y)), 0, accuracy: 0.01,
                       "the locate guide must sit on the STANDARD spot")
        let dot = engine.overlay.savedSpot
        XCTAssertNotNil(dot, "the stored correction must stay visible as the saved-spot dot")
        XCTAssertGreaterThan(Double(hypot(dot!.x - affine.x, dot!.y - affine.y)), 0.02,
                             "savedSpot sits at the corrected position, away from the guide")

        // Press slightly off the standard spot and confirm: the stored offset is REPLACED by the
        // new small one — no accumulation, no silent clamp.
        let press = CGPoint(x: affine.x + 0.025, y: affine.y)
        let presser = presserHand(pressing: press, finger: target.pressFinger)
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
        let off = cal.offset(for: "TE3")!
        XCTAssertLessThan(off.norm, 0.15, "the old near-clamp offset must be REPLACED, not kept/accumulated")
        XCTAssertGreaterThan(off.norm, 0.01, "a real (small) correction was stored")
    }

    // Latch BREAK paths — the safety half of the latch design (only expiry was tested).
    func testLatchBreaksWhenReceiverLeavesOrFlips() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.03, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        // (1) Receiver leaves the frame: offer + candidate void immediately; a return needs a
        // FULL fresh settle window, not a resumed one.
        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        for _ in 0..<3 { engine.update(hands: [], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .noHand)
        XCTAssertNil(engine.locateCandidate, "hand gone voids the labeled press")
        XCTAssertFalse(engine.confirmLocate(point: te3, now: t), "confirm must refuse after the hand left")
        for _ in 0..<10 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertNotEqual(engine.locateState, .ready,
                          "a returning hand must re-settle a full window before confirm re-unlocks")

        // (2) Face flips mid-offer: same voiding via the wrong-face break. The flip is the user
        // TURNING THEIR HAND OVER — the mirrored landmark set — not a toggle of the calibration
        // global, which is what this used to do. Toggling the global exercised the toggle; this
        // exercises the gate. (The hold on the receiver's handedness debounces a flickering LABEL,
        // not a change of geometry, so a real flip still lands within a frame or two.)
        let engine2 = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t2 = 0.0
        for _ in 0..<30 { engine2.update(hands: [receiver, presser], point: te3, now: t2); t2 += dt }
        XCTAssertEqual(engine2.locateState, .ready)
        let turnedOver = Hand(points: HandFixture.palmarRight, chirality: .right)
        for _ in 0..<3 { engine2.update(hands: [turnedOver, presser], point: te3, now: t2); t2 += dt }
        XCTAssertEqual(engine2.locateState, .wrongFace)
        XCTAssertFalse(engine2.confirmLocate(point: te3, now: t2), "confirm must refuse on a flipped face")
    }

    // A camera flip mid-locate is a coordinate-parity discontinuity: window/candidate/anchors are
    // void; a confirm must refuse; re-settling in the NEW parity works and stores a sane offset.
    func testCameraFlipMidLocateVoidsCaptureAndRecovers() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let press = CGPoint(x: affine.x + 0.03, y: affine.y + 0.01)
        let presser = presserHand(pressing: press, finger: target.pressFinger)

        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)

        engine.cameraFlipped()
        XCTAssertEqual(engine.locateState, .noPress, "flip voids the offer")
        XCTAssertNil(engine.locateCandidate)
        XCTAssertFalse(engine.confirmLocate(point: te3, now: t), "confirm must refuse across a parity flip")

        // Re-settle in the new (un-mirrored) parity: mirrored fixtures, mirroredCoords false.
        // (Same physical scene → same dorsal verdict: mirroredCoords folds the parity in, so the
        // calibration flag stays put.)
        func um(_ p: CGPoint) -> CGPoint { CGPoint(x: 1 - p.x, y: p.y) }
        let receiverB = Hand(points: base.mapValues(um), chirality: .right, mirroredCoords: false)
        let affineB = receiverB.weightedTarget(target.anchors)!
        let pressB = CGPoint(x: affineB.x - 0.03, y: affineB.y + 0.01)
        var presserPtsB: [HandJoint: CGPoint] = [.wrist: CGPoint(x: pressB.x - 0.20, y: pressB.y + 0.28),
                                                 .middleMCP: CGPoint(x: pressB.x - 0.16, y: pressB.y + 0.20)]
        presserPtsB[target.pressFinger] = pressB
        let presserB = Hand(points: presserPtsB, chirality: .left, mirroredCoords: false)
        for _ in 0..<30 { engine.update(hands: [receiverB, presserB], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready, "locate must recover in the new parity")
        XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
        XCTAssertNotNil(cal.offset(for: "TE3"))
        XCTAssertLessThanOrEqual(cal.offset(for: "TE3")!.norm, PointCalibration.maxOffsetXHandSize + 1e-9)
    }

    // A pause stops frames and the latch is frame-clocked: suspendLocate must void the offer so a
    // stale .ready is never confirmable behind the pause overlay / after resume.
    func testSuspendLocateVoidsPendingConfirm() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let presser = presserHand(pressing: CGPoint(x: affine.x + 0.03, y: affine.y),
                                  finger: target.pressFinger)

        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        var t = 0.0
        for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .ready)
        engine.suspendLocate()
        XCTAssertEqual(engine.locateState, .noPress)
        XCTAssertNil(engine.locateCandidate)
        XCTAssertFalse(engine.confirmLocate(point: te3, now: t), "a suspended offer must not confirm")
    }

    // Gate-unit / clamp-unit equivalence as a PROPERTY: any gate-accepted press stores its own
    // iso distance (never clamp-truncated); past the gate it never stores at all.
    func testGateAcceptedPressStoresUnclamped() {

        let te3 = Acupoint.byId["TE3"]!
        let target = te3.mediapipeTarget!
        let receiver = Hand(points: base, chirality: .right)
        let affine = receiver.weightedTarget(target.anchors)!
        let aspect = 9.0 / 16.0
        // iso hand size of the fixture receiver (wrist→middleMCP, y in width units)
        let hsIso = hypot(0.0, 0.28 / aspect)

        for r in [0.06, 0.16, 0.28] {
            for deg in [0.0, 130.0, 250.0] {
                let a = deg * .pi / 180
                let press = CGPoint(x: affine.x + r * hsIso * cos(a),
                                    y: affine.y + r * hsIso * sin(a) * aspect)
                let presser = presserHand(pressing: press, finger: target.pressFinger)
                let cal = PointCalibration.ephemeral()
                let engine = CoachEngine(startLocating: true, calibration: cal)
                var t = 0.0
                for _ in 0..<30 { engine.update(hands: [receiver, presser], point: te3, now: t); t += dt }
                XCTAssertEqual(engine.locateState, .ready, "r=\(r) deg=\(deg) should settle")
                XCTAssertTrue(engine.confirmLocate(point: te3, now: t))
                let stored = cal.offset(for: "TE3")!
                XCTAssertEqual(stored.norm, r, accuracy: 0.02,
                               "stored norm must equal the press's iso distance (r=\(r) deg=\(deg))")
            }
        }
        // Boundary: past the OUTER gate → offGuide, nothing stored. Derived from the constant so
        // it tracks the gate instead of quietly falling inside it when the gate widens.
        let far = CGPoint(x: affine.x + CGFloat(CoachConst.locateFarCaptureRadiusXHandSize + 0.08) * hsIso,
                          y: affine.y)
        let farPresser = presserHand(pressing: far, finger: target.pressFinger)
        let cal = PointCalibration.ephemeral()
        let engine = CoachEngine(startLocating: true, calibration: cal)
        var t = 0.0
        for _ in 0..<40 { engine.update(hands: [receiver, farPresser], point: te3, now: t); t += dt }
        XCTAssertEqual(engine.locateState, .offGuide)
        XCTAssertFalse(engine.confirmLocate(point: te3, now: t))
        XCTAssertNil(cal.offset(for: "TE3"))
    }
}

// MARK: - Calibration as a first-class, reachable feature

// The per-user spot is the app's most defensible capability, but it used to be reachable only by
// starting a full session and tapping an unlabeled glyph in the camera overlay. These pin the
// entry points so a refactor cannot quietly make it unreachable again.
final class CalibrationDiscoverabilityTests: XCTestCase {

    /// "Find my spot" must be offered for exactly the points where the locate step can actually run:
    /// camera-coached (there is a ring to correct) AND carrying a find-by-feel guide.
    func testEveryCameraCoachedPointCanBeCalibrated() {
        let coached = Acupoint.all.filter { $0.mediapipeTarget != nil }
        XCTAssertFalse(coached.isEmpty, "the coached set must not be empty")
        for pt in coached {
            XCTAssertTrue(pt.hasFindGuide,
                          "\(pt.id) is camera-coached but has no find guide, so the locate step "
                          + "cannot teach it — Find my spot would be a dead button")
        }
    }

    /// A locate launch is identity-distinct from a practice launch of the same point, or the
    /// fullScreenCover would refuse to swap between them (Identifiable dedupe).
    func testLocateLaunchHasItsOwnIdentity() throws {
        let te3 = try XCTUnwrap(Acupoint.byId["TE3"])
        let practice = PracticeLaunch.point(te3, rounds: 1, timerOnly: false)
        let locate = PracticeLaunch.locate(te3)
        XCTAssertNotEqual(practice.id, locate.id,
                          "a locate launch must not collide with a practice launch of the same point")
        XCTAssertEqual(locate.id, PracticeLaunch.locate(te3).id, "locate identity must be stable")
    }

    /// Saving and clearing a spot is what the "Your spots" list and its reset action depend on.
    func testSavedSpotRoundTripsAndResets() {
        let cal = PointCalibration.ephemeral()
        defer { PointCalibration.purgeEphemeral() }
        XCTAssertFalse(cal.hasCalibration("TE3"))
        cal.set(PointCalibration.Offset(dx: 0.02, dy: -0.01), for: "TE3")
        XCTAssertTrue(cal.hasCalibration("TE3"), "a saved spot must be listable in Your spots")
        cal.clear("TE3")
        XCTAssertFalse(cal.hasCalibration("TE3"), "reset-to-standard must remove the saved spot")
    }
}
