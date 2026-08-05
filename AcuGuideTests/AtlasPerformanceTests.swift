import XCTest
import SceneKit
import GLTFKit2
@testable import AcuGuide

// The occluded-tip reconstruction must not collapse onto the knuckle when the finger is
// foreshortened, and must never reach past where a fingertip physically is.
//
// User report: "the massage finger detection does not detect the finger tip, but around the FIRST
// KNUCKLE of the finger." Mechanism: (DIP − PIP) is the MIDDLE phalanx and its length here is an
// image PROJECTION. In the real press pose that phalanx is heavily foreshortened, so the old
// `DIP + 0.6·(DIP − PIP)` produced a near-zero step and the estimate landed on the DIP itself.
final class PressTipGeometryTests: XCTestCase {

    /// A hand with a realistic handSize whose middle phalanx is almost edge-on to the camera.
    private func foreshortenedHand(phalanxLength: CGFloat) -> Hand {
        // wrist → middleMCP = 0.30 (the handSize unit). Index DIP sits above it; PIP is only
        // `phalanxLength` away in projection because the finger points away from the lens.
        let dip = CGPoint(x: 0.50, y: 0.40)
        return Hand(points: [.wrist: CGPoint(x: 0.50, y: 0.70),
                             .middleMCP: CGPoint(x: 0.50, y: 0.40),
                             .indexDIP: dip,
                             .indexPIP: CGPoint(x: 0.50, y: 0.40 + phalanxLength)],
                    chirality: .right,
                    confidence: [.indexDIP: 0.9, .indexPIP: 0.9])
    }

    func testForeshortenedFingerDoesNotCollapseOntoTheKnuckle() throws {
        // 0.004 of projected phalanx: what a nearly edge-on finger gives. Old formula step = 0.0024.
        let hand = foreshortenedHand(phalanxLength: 0.004)
        let hs = hand.handSize
        XCTAssertEqual(hs, 0.30, accuracy: 1e-9, "handSize must be the wrist→middleMCP unit")

        let tip = try XCTUnwrap(hand.pressTip(.indexTip)).point
        let dip = try XCTUnwrap(hand.p(.indexDIP))
        let step = hypot(tip.x - dip.x, tip.y - dip.y)

        XCTAssertGreaterThanOrEqual(step, HandGeom.tipFloor * hs - 1e-9,
                                    "a foreshortened phalanx must still project a real fingertip's "
                                    + "worth past the DIP — collapsing here IS the reported knuckle bug")
        // And it must clear the tightest hit tolerance in the atlas (0.12·handSize), or the press
        // cannot register even when the real nail is on the point.
        XCTAssertGreaterThan(step, 0.12 * hs,
                             "a tip parked inside the enter radius of the DIP breaks engagement too")
    }

    func testReconstructionCanNeverOvershootTheNail() throws {
        // A long, fully in-plane phalanx: the projection is at its maximum. Overshooting the nail is
        // the previously shipped-and-reverted regression, so the cap has to hold here.
        let hand = foreshortenedHand(phalanxLength: 0.5)
        let hs = hand.handSize
        let tip = try XCTUnwrap(hand.pressTip(.indexTip)).point
        let dip = try XCTUnwrap(hand.p(.indexDIP))
        let step = hypot(tip.x - dip.x, tip.y - dip.y)

        XCTAssertLessThanOrEqual(step, HandGeom.tipReach * hs + 1e-9,
                                 "the rebuilt tip must never sit further from the DIP than a real "
                                 + "fingertip does — that overshoot was a user-confirmed regression")
    }

    /// The direction must still come from the phalanx: only the DISTANCE is clamped.
    func testReconstructionKeepsThePhalanxDirection() throws {
        let hand = foreshortenedHand(phalanxLength: 0.01)
        let tip = try XCTUnwrap(hand.pressTip(.indexTip)).point
        let dip = try XCTUnwrap(hand.p(.indexDIP))
        // PIP is directly BELOW the DIP here, so the tip must extend directly ABOVE it.
        XCTAssertEqual(tip.x, dip.x, accuracy: 1e-9, "must not drift sideways off the finger axis")
        XCTAssertLessThan(tip.y, dip.y, "must extend away from the PIP, toward the fingertip")
    }

    /// A reconstruction is still an unmeasured guess and must not be able to START an engagement.
    func testReconstructionStillReportsZeroConfidence() throws {
        let m = try XCTUnwrap(foreshortenedHand(phalanxLength: 0.01).pressTip(.indexTip))
        XCTAssertEqual(m.confidence, 0,
                       "clamping the geometry must not promote a guess into a measurement")
        XCTAssertTrue(m.reconstructed, "and it must SAY it is a guess, not leave that to be inferred "
                      + "from a confidence value fixtures default to 1")
    }

    // THE CLAMP WAS OFF IN THE POSE IT WAS WRITTEN FOR.
    //
    // `handSize` needs wrist AND middleMCP, and returned 0 otherwise — at which point pressTip fell
    // through to the raw projection with no floor at all. But HandVision requires only the WRIST and
    // drops any joint under 0.3 confidence, and the massaging hand comes in fingers-first from the
    // top of frame, foreshortened: precisely where the middle knuckle goes missing. So a
    // foreshortened phalanx planted the rebuilt tip a few hundredths past the DIP instead of the
    // anatomical 0.16–0.26 — on the knuckle, and inside the ring radius, so the press could not
    // register either. That is the reported "the detection is on the knuckle".
    func testClampSurvivesAMissingMiddleMCP() throws {
        let dip = CGPoint(x: 0.50, y: 0.40)
        // Same hand as foreshortenedHand, but the middle knuckle dropped and the INDEX one seen.
        let hand = Hand(points: [.wrist: CGPoint(x: 0.50, y: 0.70),
                                 .indexMCP: CGPoint(x: 0.54, y: 0.41),
                                 .indexDIP: dip,
                                 .indexPIP: CGPoint(x: 0.50, y: 0.40 + 0.004)],
                        chirality: .right)
        XCTAssertEqual(hand.handSize, 0, "precondition: no middleMCP, so the old scale is unavailable")
        let scale = hand.pressScale()
        XCTAssertGreaterThan(scale, 0, "pressScale must fall back to another metacarpal ray")

        let tip = try XCTUnwrap(hand.pressTip(.indexTip)).point
        let step = hypot(tip.x - dip.x, tip.y - dip.y)
        XCTAssertGreaterThanOrEqual(step, HandGeom.tipFloor * scale - 1e-9,
                                    "the clamp must still apply — without it this lands ~0.004 past "
                                    + "the DIP, i.e. ON the knuckle")
        XCTAssertGreaterThan(step, 0.12 * scale,
                             "and it must clear the tightest hit tolerance, or the press cannot register")
    }

    /// With no knuckle at all there is genuinely no scale, and the pure projection stands. Pinned so
    /// the residual hole is a stated limit rather than a surprise — the engine bounds this case in
    /// TIME instead (CoachConst.tipReconstructionSustainS).
    func testNoKnuckleAtAllStillFallsBackToThePureProjection() throws {
        let dip = CGPoint(x: 0.50, y: 0.40)
        let hand = Hand(points: [.wrist: CGPoint(x: 0.50, y: 0.70),
                                 .indexDIP: dip, .indexPIP: CGPoint(x: 0.50, y: 0.45)],
                        chirality: .right)
        XCTAssertEqual(hand.pressScale(), 0)
        let tip = try XCTUnwrap(hand.pressTip(.indexTip)).point
        XCTAssertEqual(hypot(tip.x - dip.x, tip.y - dip.y), 0.05, accuracy: 1e-9,
                       "unclamped projection = 1.0 × |DIP−PIP|")
    }

    // THE LAST RAW-COORDINATE HIT-TEST. Landmarks are normalized PER AXIS, so a raw hypot measures
    // different physical distances along x and y. This function compares a length along the FINGER
    // axis against a scale along the PALM axis — identical only when they are parallel. At right
    // angles on a 9:16 frame the cap was 1.78× off: it clipped a cross-axis rebuild back toward the
    // DIP in one orientation, and let it overshoot the nail in the other. The engine (isoDist) and
    // PointCalibration already learned this lesson; this was the one place left.
    func testCrossAxisReconstructionIsNotClippedByAnisotropy() throws {
        let aspect: CGFloat = 9.0 / 16.0
        // Palm VERTICAL (wrist below middleMCP), pressing finger HORIZONTAL — the normal top-down
        // pose, and the worst case for the mismatch.
        let dip = CGPoint(x: 0.50, y: 0.40)
        let hand = Hand(points: [.wrist: CGPoint(x: 0.50, y: 0.70),
                                 .middleMCP: CGPoint(x: 0.50, y: 0.52),
                                 .indexDIP: dip,
                                 .indexPIP: CGPoint(x: 0.30, y: 0.40)],   // straight out along x
                        chirality: .right)
        let scale = hand.pressScale(aspect: aspect)
        let tip = try XCTUnwrap(hand.pressTip(.indexTip, aspect: aspect)).point
        let step = hypot(tip.x - dip.x, (tip.y - dip.y) / aspect)         // measured ISOTROPICALLY
        XCTAssertLessThanOrEqual(step, HandGeom.tipReach * scale + 1e-9,
                                 "the cap must bound the ISO step, not a raw one")
        XCTAssertGreaterThanOrEqual(step, HandGeom.tipFloor * scale - 1e-9,
                                    "…and the floor must too — evaluating a palm-axis scale against "
                                    + "a finger-axis length clipped this back toward the knuckle")
    }

    /// The cancellation proof that makes the isotropic clamp safe: for a finger PARALLEL to the palm
    /// the aspect divides out exactly, so every previously-pinned case is bit-identical at any frame
    /// shape. Only the cross-axis case — the one that was wrong — moves.
    func testAxialReconstructionIsAspectInvariant() throws {
        let hand = foreshortenedHand(phalanxLength: 0.01)
        let square = try XCTUnwrap(hand.pressTip(.indexTip, aspect: 1)).point
        let portrait = try XCTUnwrap(hand.pressTip(.indexTip, aspect: 9.0 / 16.0)).point
        XCTAssertEqual(Double(square.x), Double(portrait.x), accuracy: 1e-12)
        XCTAssertEqual(Double(square.y), Double(portrait.y), accuracy: 1e-12)
    }
}

// Pins the draw-call/geometry budget of the 3D atlas.
//
// The user reported the atlas as "very laggy, even on my new phone when you zoom in". The cause was
// structural, not algorithmic: every ~2 mm of every meridian stroke was its own SCNNode with its own
// SCNGeometry (core + halo = two cylinders per segment), plus one FULL-RESOLUTION SCNSphere per path
// sample to fill the V-gaps at bends. SCNSphere defaults to segmentCount 24 = 1,104 triangles each,
// and there are ~109 samples per channel across 18 channels — roughly 2.0M triangles of sub-pixel
// decoration on a body mesh that is itself 1,388 triangles, submitted as ~5,700 separate draw calls.
// Every stroke material is alpha-blended, so SceneKit re-sorted all of them back-to-front on every
// frame the camera moved — i.e. every frame of a pinch-zoom.
//
// These budgets are deliberately loose (they are a regression tripwire, not a spec). They exist so
// that reverting the per-channel flattening, or dropping a raw SCNSphere back into the bead loop,
// fails here instead of on a user's phone.
final class AtlasPerformanceTests: XCTestCase {

    private func loadBodyMesh() throws -> SCNNode {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "model", withExtension: "glb"),
                                "model.glb must be bundled")
        let exp = expectation(description: "load body")
        var asset: GLTFAsset?
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
            if status == .complete { asset = maybeAsset }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        let scene = SCNScene(gltfAsset: try XCTUnwrap(asset))
        return scene.rootNode.childNodes.first ?? scene.rootNode
    }

    /// The whole channel tree must stay a couple of dozen nodes, not thousands.
    func testChannelTreeStaysWithinDrawCallBudget() throws {
        let mesh = try loadBodyMesh()
        let channels = BodyAtlas.channels(on: mesh)

        var nodes = 0
        var geometries = 0
        channels.enumerateHierarchy { n, _ in
            nodes += 1
            if n.geometry != nil { geometries += 1 }
        }
        // 18 channels x (1 flattened stroke + 1 proxy container + its proxy tubes).
        XCTAssertLessThan(nodes, 500,
                          "channel tree exploded to \(nodes) nodes — the per-channel flattenedClone "
                          + "in BodyAtlas.channel was probably removed; this was ~5,700 nodes and it "
                          + "made the atlas visibly lag on a modern iPhone")
        XCTAssertLessThan(geometries, 400,
                          "\(geometries) separate geometries = that many draw calls, all alpha-blended "
                          + "and re-sorted every frame the camera moves")
    }

    /// No full-resolution spheres in the stroke: the beads must stay low-poly.
    func testChannelGeometryTriangleBudget() throws {
        let mesh = try loadBodyMesh()
        let channels = BodyAtlas.channels(on: mesh)

        var triangles = 0
        channels.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            for element in g.elements where element.primitiveType == .triangles {
                triangles += element.primitiveCount
            }
        }
        XCTAssertGreaterThan(triangles, 0, "the channels must actually build geometry")
        // Was ~2.1M. The flattened strokes + 6-segment beads land an order of magnitude below that.
        XCTAssertLessThan(triangles, 400_000,
                          "channel geometry is \(triangles) triangles — a raw SCNSphere (segmentCount "
                          + "24 = 1,104 tris) probably crept back into the joint-bead loop in "
                          + "BodyAtlas.channel; the body mesh itself is only ~1,388 triangles")
    }

    /// The invisible tap proxies must keep their own category bit, or the camera cull silently stops
    /// working (they render again) — or, worse, they get culled from hit-testing too and taps on a
    /// channel stop selecting it.
    func testTapProxiesKeepTheirOwnCategorySoTheCameraCanCullThem() throws {
        let mesh = try loadBodyMesh()
        let channels = BodyAtlas.channels(on: mesh)

        var proxies = 0, decoration = 0
        channels.enumerateHierarchy { n, _ in
            guard n.geometry != nil else { return }
            if n.categoryBitMask == BodyAtlas.proxyCategory { proxies += 1 }
            else if n.categoryBitMask == BodyAtlas.decorationCategory { decoration += 1 }
        }
        XCTAssertGreaterThan(proxies, 0, "the wide tap proxies must be tagged proxyCategory")
        XCTAssertGreaterThan(decoration, 0, "the visible strokes must stay decorationCategory")
        // The camera hides proxyCategory; anything sharing a bit with it would vanish too.
        XCTAssertEqual(BodyAtlas.proxyCategory & BodyAtlas.decorationCategory, 0,
                       "proxy and decoration bits must not overlap or culling the proxies would "
                       + "also cull the visible meridian strokes")
        XCTAssertEqual(BodyAtlas.proxyCategory & BodyAtlas.surfaceCategory, 0,
                       "proxy and surface bits must not overlap or the surface-snap raycasts would "
                       + "start hitting the 0.03-radius proxies instead of the skin")
    }
}
