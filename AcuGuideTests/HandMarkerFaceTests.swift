import XCTest
import SceneKit
import GLTFKit2
import simd
@testable import AcuGuide

// WHICH DOT ANSWERS A TAP — the face-culling rule, checked against the real hand mesh.
//
// The device report was "the labels are attached to the wrong dots" on the 3D hand. There are no
// text labels in that view: the label is the detail card a tapped dot opens, so a wrong label IS a
// wrong tap resolution. The cause is measured in testOppositeFacePairsReallyDoOverlap below — four
// pairs sit back-to-back through the hand within one halo diameter of each other in the viewing
// plane, so a tap in the overlap used to be decided by camera DISTANCE, which says nothing about
// which dot the user aimed at.
//
// These tests cover the decision, not the pixels. Rendering cannot be checked on a build machine,
// but "is this marker facing the camera" is pure geometry and is exactly the thing that used to be
// left to per-pixel depth at the silhouette.
final class HandMarkerFaceTests: XCTestCase {

    // MARK: - The overlap that makes culling necessary

    // If this ever comes back empty, the culling has no job left and the comments in SceneKitAtlas
    // that justify it are stale. It is here so a future anatomy change cannot quietly remove the
    // reason without the reason being re-read.
    func testOppositeFacePairsReallyDoOverlap() {
        let d = AcupointPlacements.detailLayout(region: "hand")
        let haloDiameter: Float = 0.08          // HandModel3DView places halo: 0.04
        var opposite: [(String, String, Float)] = []
        let ids = d.layout.keys.sorted()
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let sep = simd_length(d.layout[ids[i]]! - d.layout[ids[j]]!)
                guard sep < haloDiameter,
                      d.back.contains(ids[i]) != d.back.contains(ids[j]) else { continue }
                opposite.append((ids[i], ids[j], sep))
            }
        }
        XCTAssertFalse(opposite.isEmpty,
                       "no back-to-back overlaps left — re-read why face culling exists before deleting it")
        // The wrist creases are the worst case and the one the report was about: PC7 (palmar) and
        // TE4 (dorsal) are the SAME anatomy on two faces.
        XCTAssertTrue(opposite.contains { ($0.0 == "PC7" && $0.1 == "TE4") || ($0.0 == "TE4" && $0.1 == "PC7") },
                      "PC7/TE4 must be one of the overlapping pairs — got \(opposite.map { "\($0.0)/\($0.1)" })")
    }

    // MARK: - The rule itself

    func testFacesCameraIsTrueOnlyForSurfacesTurnedTowardTheViewer() {
        let lookingDownNegativeZ = SIMD3<Float>(0, 0, -1)        // a camera's world −Z
        XCTAssertTrue(AtlasMarkers.facesCamera(face: SIMD3(0, 0, 1), cameraForward: lookingDownNegativeZ),
                      "a face turned back toward the camera is aimable")
        XCTAssertFalse(AtlasMarkers.facesCamera(face: SIMD3(0, 0, -1), cameraForward: lookingDownNegativeZ),
                       "a face turned away is not")
    }

    // THE FACE IS THE `farSide` INPUT, NOT THE FACET NORMAL THE RAY LANDED ON. The first cut of this
    // fix culled on the surface normal and this suite caught it immediately: LU9 and PC7, both
    // PALMAR, came back camera-facing from the dorsal pose. Both sit at the wrist, where the surface
    // is nearly edge-on to the view and "outward from the model centre" points along the forearm
    // rather than out of the palm — so the normal simply does not carry the palmar/dorsal fact. The
    // two it got wrong were the wrist creases, which is precisely the pair the report was about.
    func testTheFaceVectorFollowsFarSideNotTheLocalSurface() throws {
        let mesh = try XCTUnwrap(handMesh())
        let d = AcupointPlacements.detailLayout(region: "hand")
        let cameraForward = SIMD3<Float>(0, 0, -1)
        for id in ["PC7", "LU9"] {                     // the two the facet normal got wrong
            let uv = try XCTUnwrap(d.layout[id], "\(id) must be on the hand sheet")
            let m = try XCTUnwrap(AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                            farSide: true, id: id, color: .red,
                                                            core: 0.022, halo: 0.04))
            XCTAssertFalse(AtlasMarkers.facesCamera(face: m.face, cameraForward: cameraForward),
                           "\(id) is palmar — it must not be aimable from the dorsal pose")
        }
    }

    // MARK: - Against the real mesh, in the sheet's canonical pose

    // THE ONE THAT WOULD HAVE CAUGHT THE BUG. Built off the actual hand GLB at the actual camera
    // distance the sheet uses: from the canonical dorsal pose every DORSAL point must be selectable
    // and every PALMAR point must not, so the palmar dots can no longer answer for the dorsal ones
    // they sit behind.
    func testFromTheDorsalPoseOnlyDorsalMarkersAreSelectable() throws {
        let mesh = try XCTUnwrap(handMesh(), "hand_low_poly must load for this test to mean anything")
        let d = AcupointPlacements.detailLayout(region: "hand")
        let cameraForward = SIMD3<Float>(0, 0, -1)   // installDetailMesh puts the camera on +Z looking back

        var checked = 0
        for (id, uv) in d.layout {
            let farSide = d.back.contains(id)
            guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                    farSide: farSide, id: id, color: .red,
                                                    core: 0.022, halo: 0.04) else { continue }
            checked += 1
            let faces = AtlasMarkers.facesCamera(face: m.face, cameraForward: cameraForward)
            XCTAssertEqual(faces, !farSide,
                           "\(id) is on the \(farSide ? "palmar" : "dorsal") face and should "
                           + "\(farSide ? "NOT " : "")be selectable from the dorsal pose")
        }
        XCTAssertGreaterThan(checked, 8, "too few markers resolved for this to be a real check")
    }

    // updateMarkerVisibility is what the renderer delegate calls; hitTest skips hidden nodes, so
    // this is the step that couples what is drawn to what can be tapped.
    func testUpdateMarkerVisibilityHidesTheAwayFacingOnes() {
        let toward = AtlasMarkers.domeMarker(id: "TE4", color: .red, radius: 0.02, halo: 0.04,
                                             at: SCNVector3(0, 0, 0.1), normal: SCNVector3(0, 0, 1))
        let away = AtlasMarkers.domeMarker(id: "PC7", color: .red, radius: 0.02, halo: 0.04,
                                           at: SCNVector3(0, 0, -0.1), normal: SCNVector3(0, 0, -1))
        AtlasMarkers.updateMarkerVisibility([(toward, SIMD3(0, 0, 1)), (away, SIMD3(0, 0, -1))],
                                            cameraForward: SIMD3(0, 0, -1))
        XCTAssertFalse(toward.isHidden, "the dot facing the camera stays selectable")
        XCTAssertTrue(away.isHidden, "the dot on the far face is hidden, so it cannot take the tap")
    }

    // The hand mesh, posed exactly as HandModel3DView poses it — the pose is load-bearing for
    // placement, so a test that used a different one would be checking a different hand.
    // A .glb needs GLTFKit2 to decode — SCNScene(url:) cannot read one. Same async load the mesh
    // probe suite uses.
    private func handMesh() -> SCNNode? {
        guard let url = Bundle.main.url(forResource: "hand_low_poly", withExtension: "glb") else { return nil }
        let exp = expectation(description: "load hand_low_poly")
        var asset: GLTFAsset?
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
            if status == .complete { asset = maybeAsset }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        guard let asset,
              let mesh = AtlasMarkers.unitMesh(from: SCNScene(gltfAsset: asset),
                                               material: AtlasMarkers.meshMaterial()) else { return nil }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)     // HandModel3DView's chart pose
        return mesh
    }
}
