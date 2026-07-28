import XCTest
import AVFoundation
import ImageIO
@testable import AcuGuide

// THE ROTATION MATH the landscape coach rests on.
//
// The coach's whole geometry — the guide ring, the press dot, the isotropic hit test, every saved
// calibration — is measured in a normalized space shared by the camera buffer and the SwiftUI
// overlay. If the two disagree about which way is up, everything lands on the wrong pixels while
// still looking plausible, which is the failure mode that is hardest to notice and worst to ship.
final class CaptureRotationTests: XCTestCase {

    // The residual is what Vision has to apply on top of whatever the connection already did.
    // When the connection honours the request — the normal case — Vision gets `.up`, exactly as it
    // did when the app was portrait-locked.
    func testNoResidualWhenTheConnectionHonouredTheRequest() {
        for angle in [CGFloat(0), 90, 180, 270] {
            XCTAssertEqual(CaptureRotation.visionOrientation(desired: angle, actual: angle), .up,
                           "a connection already at \(angle)° needs no further rotation")
        }
    }

    // The four cases the old portrait-only table hard-coded must still come out the same, or the
    // fallback path (a platform that ignores the rotation request) silently changes behaviour.
    func testMatchesTheRetiredPortraitTable() {
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 90, actual: 90),  .up)
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 90, actual: 0),   .right)
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 90, actual: 180), .left)
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 90, actual: 270), .down)
    }

    // Wrap-around must not produce a negative modulus — the classic bug in this shape of code.
    func testResidualWrapsBothWays() {
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 0, actual: 90),   .left)   // −90 → 270
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 0, actual: 270),  .right)  //  90
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 270, actual: 0),  .left)
        XCTAssertEqual(CaptureRotation.visionOrientation(desired: 180, actual: 0),  .down)
    }

    // Every interface orientation must map to an angle AVFoundation accepts, and the two landscape
    // orientations must differ by 180° — if they collide, the picture is upside down in one of them.
    func testEveryInterfaceOrientationMapsToALegalDistinctAngle() {
        let legal: Set<CGFloat> = [0, 90, 180, 270]
        var seen: [UIInterfaceOrientation: CGFloat] = [:]
        for o in [UIInterfaceOrientation.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            let angle = CaptureRotation.angle(for: o)
            XCTAssertTrue(legal.contains(angle), "\(o.rawValue) → \(angle)° is not a legal rotation angle")
            seen[o] = angle
        }
        XCTAssertNotEqual(seen[.landscapeLeft], seen[.landscapeRight],
                          "the two landscape orientations must not share an angle — one would be upside down")
        XCTAssertEqual(abs((seen[.landscapeLeft] ?? 0) - (seen[.landscapeRight] ?? 0)), 180,
                       "the two landscape orientations are 180° apart")
        XCTAssertEqual(seen[.portrait], 90, "portrait must keep the angle the app shipped with")
    }

    // …AND WHICH LANDSCAPE GETS WHICH ANGLE, which is the assertion that was missing above.
    //
    // The test above passes just as happily with the two landscape values SWAPPED — distinct, 180°
    // apart, portrait untouched. That gap let an inversion report send the swap most of the way to
    // shipping in R17, so pin the values AND the derivation, and state the traps that make the wrong
    // answer look reasonable.
    //
    // The derivation uses no enum names, because the enum names are the trap. Portrait = 90 is
    // device-confirmed on the front camera, so that camera's sensor zero is already inside it, and
    // the landscapes follow as 90 ∓ 90. The only free parameter is the SIGN of videoRotationAngle,
    // which this repo pins independently: CameraLocator and LabelCapture both map angle 0 → Vision
    // `.right` (EXIF 6, "rotate 90° clockwise"), so 0 → 90 is 90° clockwise. Interface
    // .landscapeRight is the device turned 90° anticlockwise, hence 90 − 90 = 0.
    func testEachLandscapeGetsItsDerivedAngle() {
        XCTAssertEqual(CaptureRotation.angle(for: .landscapeRight), 0,
                       "device turned 90° anticlockwise from a device-confirmed portrait 90")
        XCTAssertEqual(CaptureRotation.angle(for: .landscapeLeft), 180,
                       "the other landscape is necessarily 180° from it")
    }

    // THE INVERSION IS CROSSED EXACTLY ONCE, in OrientationDriver. UIDeviceOrientation and
    // UIInterfaceOrientation really are opposite for landscape (the SDK writes
    // `UIInterfaceOrientationLandscapeRight = UIDeviceOrientationLandscapeLeft`), and that is the
    // driver's job. UIInterfaceOrientation and AVCaptureVideoOrientation are NOT opposite — same
    // pose, same raw value — so the capture table must not cross it a second time. Applying it twice
    // is a silent half-turn, and it is the specific mistake this pair of tests exists to block.
    func testTheInversionIsAppliedInExactlyOnePlace() {
        // The driver crosses it…
        XCTAssertEqual(OrientationDriver.target(for: .landscapeLeft), .landscapeRight)
        XCTAssertEqual(OrientationDriver.target(for: .landscapeRight), .landscapeLeft)
        // …and the capture table does not: a device turned LEFT ends up at 0°, not 180°.
        let interface = OrientationDriver.target(for: .landscapeLeft)!
        XCTAssertEqual(CaptureRotation.angle(for: interface), 0,
                       "device .landscapeLeft → interface .landscapeRight → 0°; if this reads 180 the "
                       + "device↔interface inversion has been applied twice")
    }

    // The display aspect has to be able to express landscape. It could not before: the old
    // min/max form was ≤ 1 by construction, so a landscape frame would have been scaled as if it
    // were portrait — wrong ring size, wrong hit test, wrong stored calibration.
    func testDisplayAspectExpressesBothOrientations() {
        XCTAssertLessThan(CameraCoach.displayAspect(width: 1080, height: 1920), 1, "portrait is W/H < 1")
        XCTAssertGreaterThan(CameraCoach.displayAspect(width: 1920, height: 1080), 1, "landscape is W/H > 1")
        XCTAssertEqual(CameraCoach.displayAspect(width: 1920, height: 1080),
                       1 / CameraCoach.displayAspect(width: 1080, height: 1920), accuracy: 1e-6)
        XCTAssertGreaterThan(CameraCoach.displayAspect(width: 100, height: 0), 0,
                             "a degenerate frame must not divide by zero")
    }

    // The isotropic distance the engine hit-tests with, and the calibration frame it stores in,
    // must both behave in a landscape aspect — they generalise, but nothing had ever exercised
    // them above 1.
    func testIsotropicMathHoldsForALandscapeAspect() {
        let portrait: CGFloat = 9.0 / 16.0, landscape: CGFloat = 16.0 / 9.0
        // The same PHYSICAL displacement is the same isotropic distance in either orientation:
        // a dy in a landscape frame spans proportionally less of the frame width.
        let dyPortrait = isoDist(CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.6), aspect: portrait)
        let dyLandscape = isoDist(CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.6), aspect: landscape)
        XCTAssertGreaterThan(dyPortrait, dyLandscape,
                             "a vertical offset must count for LESS of the width in a landscape frame")
        // And x is unaffected by the aspect in both.
        XCTAssertEqual(isoDist(CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.5, y: 0.5), aspect: portrait),
                       isoDist(CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.5, y: 0.5), aspect: landscape),
                       accuracy: 1e-6)
    }

    private func isoDist(_ a: CGPoint, _ b: CGPoint, aspect: CGFloat) -> CGFloat {
        let dx = a.x - b.x, dy = (a.y - b.y) / max(aspect, 0.1)
        return hypot(dx, dy)
    }
}

// THE DEVICE → INTERFACE MAPPING that actually turns the window.
//
// Permitting landscape was never enough on device: widening the mask requests a set that CONTAINS
// .portrait at the one moment the window is guaranteed to already BE portrait, so the system
// resolves it to "already there" and turns nothing. OrientationDriver requests a SINGLE orientation
// instead — which means this mapping is now load-bearing, and it inverts.
final class OrientationDriverMappingTests: XCTestCase {

    // UIDeviceOrientation and UIInterfaceOrientation name the landscapes from opposite ends. If this
    // ever "reads more naturally", the window turns the right way and the VIDEO comes out upside
    // down — CaptureRotation.angle puts these two 180° apart.
    func testTheLandscapesInvert() {
        XCTAssertEqual(OrientationDriver.target(for: .landscapeLeft), .landscapeRight)
        XCTAssertEqual(OrientationDriver.target(for: .landscapeRight), .landscapeLeft)
        XCTAssertEqual(OrientationDriver.target(for: .portrait), .portrait)
    }

    // A phone propped against a cup — the posture this whole screen is designed around — reports
    // faceUp/faceDown constantly. Acting on those would flip the layout while the user is pressing.
    func testFlatAndUnknownHoldTheCurrentOrientation() {
        XCTAssertNil(OrientationDriver.target(for: .faceUp))
        XCTAssertNil(OrientationDriver.target(for: .faceDown))
        XCTAssertNil(OrientationDriver.target(for: .unknown))
        // Upside-down is excluded from the app's mask, so never request it.
        XCTAssertNil(OrientationDriver.target(for: .portraitUpsideDown))
    }

    // Every orientation this driver will ever request must map to a distinct, legal capture angle —
    // otherwise a rotation the driver forces leaves the video a quarter or half turn out.
    func testEveryRequestedOrientationHasADistinctCaptureAngle() {
        let requested: [UIDeviceOrientation] = [.portrait, .landscapeLeft, .landscapeRight]
        let angles = requested.compactMap(OrientationDriver.target(for:)).map(CaptureRotation.angle(for:))
        XCTAssertEqual(angles.count, 3)
        XCTAssertEqual(Set(angles).count, 3, "two orientations share a capture angle")
    }
}
