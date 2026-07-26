import XCTest
import SceneKit
import GLTFKit2
import simd
@testable import AcuGuide

// Renders each detailed drill-down (head / arm / foot) OFF SCREEN exactly as the app builds it
// (unitMesh → euler → studio lighting → camera → screenMarker bulges) and (a) asserts the mesh is
// centred and every marker lands within the model, and (b) writes a PNG so orientation + placement
// can be eyeballed. Pull the images with:
//   xcrun simctl get_app_container booted app.acuguide.ios data   # → <container>/Documents/detail_<id>.png
final class DetailSnapshotTests: XCTestCase {

    private func loadUnitMesh(_ resource: String, nodeName: String? = nil) -> SCNNode? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "glb") else {
            XCTFail("missing \(resource).glb in bundle"); return nil
        }
        let exp = expectation(description: "load \(resource)")
        var asset: GLTFAsset?
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, _, _ in
            if status == .complete { asset = maybeAsset }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
        guard let asset else { return nil }
        return AtlasMarkers.unitMesh(from: SCNScene(gltfAsset: asset), material: AtlasMarkers.meshMaterial(), nodeName: nodeName)
    }

    // World AABB of the posed mesh, the same box screenMarker derives placement from.
    private func worldAABB(_ mesh: SCNNode) -> (SIMD3<Float>, SIMD3<Float>) {
        let (lo, hi) = mesh.boundingBox
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude); var mx = -mn
        for a in [lo.x, hi.x] { for b in [lo.y, hi.y] { for c in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(a, b, c), to: nil)
            mn = simd_min(mn, SIMD3(w.x, w.y, w.z)); mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
        } } }
        return (mn, mx)
    }

    // Same contract for the detailed HAND: every registry entry with a detailUV must land on the
    // hand mesh (dorsal near-side / palmar far-side), consumed through the SAME
    // AcupointPlacements.detailLayout rule HandModel3DView places with — the test can't drift from
    // the app. Renders detail_hand.png (+ detail_hand_palm.png) for eyeballing.
    func testHandViewPlacesMarkersOnModel() throws {
        guard let mesh = loadUnitMesh("hand_low_poly") else { XCTFail("no hand mesh"); return }
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.90, alpha: 1)
        AtlasMarkers.addStudioLighting(to: scene)
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)   // == HandModel3DView's chart pose
        scene.rootNode.addChildNode(mesh)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.position = SCNVector3(0, 0, 2.3)
        scene.rootNode.addChildNode(cam)

        let (mn, mx) = worldAABB(mesh)
        let pad: Float = 0.12
        var placed = 0
        // Consumed through the SAME detailLayout rule as HandModel3DView.placeMarkers — points
        // without a detailUV (forearm PC6/SJ5) are correctly absent.
        let d = AcupointPlacements.detailLayout(region: "hand")
        for (id, uv) in d.layout {
            guard let pt = Acupoint.byId[id] else { XCTFail("hand/\(id) not in the atlas"); continue }
            guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                    farSide: d.back.contains(id), id: id,
                                                    color: UIColor(MeridianColors.color(pt.meridian)),
                                                    core: 0.022, halo: 0.04) else {
                XCTFail("hand/\(id) produced no marker"); continue }
            // onSurface is the FLOATER assertion: a plane-fallback marker projects fine from the
            // canonical camera but hangs in space from any other angle (user-reported, twice).
            // `snapped` pins the registry uv to a DIRECT hit — the spiral snap is an in-app
            // nicety, and letting it pass here would hide a drifted entry on wrong anatomy.
            XCTAssertTrue(m.onSurface, "hand/\(id) uv \(uv) missed the mesh — floating marker")
            XCTAssertFalse(m.snapped, "hand/\(id) uv \(uv) needed a spiral snap — retune the registry entry")
            let p = SIMD3<Float>(Float(m.node.position.x), Float(m.node.position.y), Float(m.node.position.z))
            XCTAssertTrue(all(p .>= mn - pad) && all(p .<= mx + pad),
                          "hand/\(id) marker \(p) fell outside the hand box \(mn)…\(mx)")
            scene.rootNode.addChildNode(m.node)
            placed += 1
        }
        XCTAssertGreaterThanOrEqual(placed, 10, "the enlarged hand set should place ≥10 points on the mesh")

        let img = snapshotRenderer(scene, pointOfView: cam).snapshot(atTime: 0, with: CGSize(width: 660, height: 820), antialiasingMode: .multisampling4X)
        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("detail_hand.png")
        try img.pngData()!.write(to: out)
        print("SNAPSHOT wrote \(out.path)")

        // Third render from a 3/4 SIDE angle: depth errors are invisible in the two axis views (a
        // plane-fallback marker projects to the correct screen spot from the canonical camera) —
        // this is the render that shows floating markers, if any survive the onSurface assertion.
        let sideCam = SCNNode(); sideCam.camera = SCNCamera()
        sideCam.camera?.fieldOfView = 45; sideCam.camera?.zNear = 0.01; sideCam.camera?.zFar = 100
        sideCam.position = SCNVector3(1.8, 0.3, 1.5)
        sideCam.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sideCam)
        let sideImg = snapshotRenderer(scene, pointOfView: sideCam).snapshot(atTime: 0, with: CGSize(width: 660, height: 820), antialiasingMode: .multisampling4X)
        let sideOut = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("detail_hand_side.png")
        try sideImg.pngData()!.write(to: sideOut)
        print("SNAPSHOT wrote \(sideOut.path)")

        // Second render from BEHIND the hand (the palm side, mirrored on screen like flipping a
        // real hand over) so the far-side palmar markers (PC8/HT7/HT8/LU9/LU10) can be eyeballed
        // too — the frontal render hides exactly the points placed with farSide: true.
        let backCam = SCNNode(); backCam.camera = SCNCamera()
        backCam.camera?.fieldOfView = 45; backCam.camera?.zNear = 0.01; backCam.camera?.zFar = 100
        backCam.position = SCNVector3(0, 0, -2.3)
        backCam.eulerAngles = SCNVector3(0, Float.pi, 0)
        scene.rootNode.addChildNode(backCam)
        let palmImg = snapshotRenderer(scene, pointOfView: backCam).snapshot(atTime: 0, with: CGSize(width: 660, height: 820), antialiasingMode: .multisampling4X)
        let palmOut = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("detail_hand_palm.png")
        try palmImg.pngData()!.write(to: palmOut)
        print("SNAPSHOT wrote \(palmOut.path)")
    }

    func testDetailViewsPlaceMarkersOnModel() throws {
        for (id, cfg) in PartDetail.byRegion.sorted(by: { $0.key < $1.key }) {
            guard let mesh = loadUnitMesh(cfg.resource, nodeName: cfg.nodeName) else { XCTFail("no mesh for \(id)"); continue }
            let scene = SCNScene()
            scene.background.contents = UIColor(white: 0.90, alpha: 1)   // pale bg to read the silhouette
            AtlasMarkers.addStudioLighting(to: scene)
            mesh.eulerAngles = cfg.euler
            scene.rootNode.addChildNode(mesh)

            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
            cam.position = SCNVector3(0, 0, 2.4)
            scene.rootNode.addChildNode(cam)

            // unitMesh must centre the geometry at the origin (the bug that flung head/arm markers off
            // was a pivot-centred mesh whose convertPosition-derived box was off-origin). Guard it.
            let (mn, mx) = worldAABB(mesh)
            let center = (mn + mx) / 2
            XCTAssertLessThan(simd_length(center), 0.15, "\(id) mesh must be centred at the origin")

            // Every marker must land inside the model's silhouette box (small pad for the halo).
            let pad: Float = 0.12
            for pt in cfg.points {
                guard let uv = cfg.layout[pt.id] else { continue }
                guard let m = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: mesh, u: uv.x, v: uv.y,
                                                        farSide: cfg.back.contains(pt.id), id: pt.id,
                                                        color: UIColor(MeridianColors.color(pt.meridian)),
                                                        core: 0.03, halo: 0.055) else {
                    XCTFail("\(id)/\(pt.id) produced no marker"); continue }
                XCTAssertTrue(m.onSurface, "\(id)/\(pt.id) uv \(uv) missed the mesh — floating marker")
                XCTAssertFalse(m.snapped, "\(id)/\(pt.id) uv \(uv) needed a spiral snap — retune the registry entry")
                let p = SIMD3<Float>(Float(m.node.position.x), Float(m.node.position.y), Float(m.node.position.z))
                XCTAssertTrue(all(p .>= mn - pad) && all(p .<= mx + pad),
                              "\(id)/\(pt.id) marker \(p) fell outside the model box \(mn)…\(mx)")
                scene.rootNode.addChildNode(m.node)
            }

            let img = snapshotRenderer(scene, pointOfView: cam).snapshot(atTime: 0, with: CGSize(width: 660, height: 820), antialiasingMode: .multisampling4X)
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("detail_\(id).png")
            try img.pngData()!.write(to: out)
            print("SNAPSHOT wrote \(out.path)")
        }
    }
}

/// Builds a snapshot renderer for `scene` seen from `pointOfView`.
///
/// This replaces a `NSObject.also { $0.scene = … }` configure-in-place helper. That helper was
/// declared `func also(_ body: (Self) -> Void) -> Self` in a non-final class extension, where `Self`
/// stays an abstract placeholder rather than binding to `SCNRenderer`: Xcode 26 inferred it fine, but
/// Xcode 16.x (what the CI runner ships) rejected `$0.scene` with "value of type 'Self' has no member
/// 'scene'", so the test target failed to compile on CI while building clean locally. A concrete
/// return type keeps it portable across toolchains.
private func snapshotRenderer(_ scene: SCNScene, pointOfView: SCNNode) -> SCNRenderer {
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
    renderer.scene = scene
    renderer.pointOfView = pointOfView
    return renderer
}

// DIAGNOSTIC (audit aid, not an invariant): renders the hand sheet with every marker LABELED by
// point id, so placement can be judged against each point's WHO location text instead of guessing
// which anonymous dot is which. Device report: "the acupoints on the detailed views are very
// inaccurate" — the existing assertions only prove a marker landed ON the mesh, which is a far
// weaker claim than landing on the right anatomy, so they pass while the placement is wrong.
extension DetailSnapshotTests {
    func testRenderLabeledHandForAudit() throws {
        guard let mesh = loadUnitMesh("hand_low_poly") else { XCTFail("no hand mesh"); return }
        // wantBack: which side's points to LABEL. Markers on the far side are hidden behind the
        // mesh, but a billboarded label still draws in front of it — so labelling both sides put
        // five palm labels over the dorsum and made the render unreadable.
        // The palm view moves the CAMERA behind the hand; it must NOT rotate the mesh. Rotating the
        // mesh also rotates what "behind" means to screenMarker's farSide raycast, so the palmar
        // points get re-projected onto the far side again and render invisible — which is exactly
        // what the first version of this diagnostic did (labels, no dots).
        for (name, backCamera, file, wantBack) in [
            ("dorsal", false, "audit_hand_dorsal.png", false),
            ("palm",   true,  "audit_hand_palm.png",   true),
        ] {
            let scene = SCNScene()
            scene.background.contents = UIColor(white: 0.97, alpha: 1)
            AtlasMarkers.addStudioLighting(to: scene)
            let m2 = mesh.clone(); m2.eulerAngles = SCNVector3(0, 0.72, Float.pi)   // canonical pose
            scene.rootNode.addChildNode(m2)
            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
            cam.position = SCNVector3(0, 0, backCamera ? -2.3 : 2.3)
            if backCamera { cam.eulerAngles = SCNVector3(0, Float.pi, 0) }
            scene.rootNode.addChildNode(cam)

            let d = AcupointPlacements.detailLayout(region: "hand")
            for (id, uv) in d.layout {
                guard d.back.contains(id) == wantBack else { continue }
                guard let pt = Acupoint.byId[id],
                      let mk = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: m2, u: uv.x, v: uv.y,
                                                         farSide: d.back.contains(id), id: id,
                                                         color: UIColor(MeridianColors.color(pt.meridian)),
                                                         core: 0.022, halo: 0.04) else { continue }
                scene.rootNode.addChildNode(mk.node)
                let t = SCNText(string: id, extrusionDepth: 0.001)
                t.font = .systemFont(ofSize: 1.4); t.flatness = 0.05
                t.firstMaterial?.diffuse.contents = UIColor.black
                t.firstMaterial?.lightingModel = .constant
                let tn = SCNNode(geometry: t)
                tn.scale = SCNVector3(0.05, 0.05, 0.05)
                // Float toward WHICHEVER camera is rendering — a fixed +z pushed labels behind the
                // hand in the palm view, leaving dots with no readable labels.
                tn.position = SCNVector3(mk.node.position.x + (backCamera ? -0.05 : 0.05),
                                         mk.node.position.y + 0.02,
                                         mk.node.position.z + (backCamera ? -0.35 : 0.35))
                tn.constraints = [SCNBillboardConstraint()]
                scene.rootNode.addChildNode(tn)
            }
            let img = snapshotRenderer(scene, pointOfView: cam)
                .snapshot(atTime: 0, with: CGSize(width: 900, height: 1100), antialiasingMode: .multisampling4X)
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(file)
            try img.pngData()!.write(to: out)
            print("AUDIT \(name) wrote \(out.path)")
        }
    }
}

// LANDMARK PROBE (audit aid). Option A of the placement rework: identify the five landmarks the
// coach's validated anchor sets need — wrist + index/middle/ring/pinky MCP — ONCE, by eye, from a
// labelled grid. A knuckle is visually unambiguous in a way an acupoint in a groove is not, which
// is exactly why reading THESE off a render is sound while reading acupoints off one was not.
// Once the five are fixed, all ten hand points derive from the same weighted-anchor formula the
// camera coach uses, instead of ten independent eyeballed bbox fractions.
extension DetailSnapshotTests {
    func testRenderLandmarkProbeGrid() throws {
        guard let mesh = loadUnitMesh("hand_low_poly") else { XCTFail("no hand mesh"); return }
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.97, alpha: 1)
        AtlasMarkers.addStudioLighting(to: scene)
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)
        scene.rootNode.addChildNode(mesh)
        // THUMB-SIDE landmark probe + the CORRECTED wrist. LU10/LU9/LI5 are all radial points and
        // the five knuckle/wrist landmarks have no radial reference beyond indexMCP, so a thumb-base
        // (1st metacarpal) landmark is needed before any of them can be derived rather than guessed.
        let probes: [(String, Float, Float, UIColor)] = [
            ("wrist-33", 0.06, -0.33, .systemPurple),      // corrected: at the crease, not the stump
            ("thumbA", -0.28, -0.06, .systemOrange),
            ("thumbB", -0.22, -0.12, .systemOrange),
            ("thumbC", -0.16, -0.18, .systemOrange),
            ("thumbD", -0.10, -0.24, .systemOrange),
        ]
        for (i, pr) in probes.enumerated() {
            guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: pr.1, v: pr.2,
                                                    farSide: false, id: pr.0, color: pr.3,
                                                    core: 0.020, halo: 0.034) else { continue }
            scene.rootNode.addChildNode(m.node)
            let t = SCNText(string: pr.0, extrusionDepth: 0.001)
            t.font = .systemFont(ofSize: 1.2); t.flatness = 0.05
            t.firstMaterial?.diffuse.contents = pr.3
            t.firstMaterial?.lightingModel = .constant
            let tn = SCNNode(geometry: t)
            tn.scale = SCNVector3(0.042, 0.042, 0.042)
            tn.position = SCNVector3(m.node.position.x - 0.30,
                                     m.node.position.y + Float(i % 2) * 0.05,
                                     m.node.position.z + 0.35)
            tn.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(tn)
            print("PROBE \(pr.0) onSurface=\(m.onSurface)")
        }
        // ORBIT. Head-on, the wrist is badly foreshortened — the hand's long axis runs almost
        // straight away from the camera there, so a landmark can sit centimetres proximal or distal
        // and project to the same pixel. That is precisely why the wrist was the least certain of
        // the five. Yaw around the model so the wrist crease is seen across the line of sight.
        for (tag, yaw) in [("front", Float(0)), ("q45", Float.pi/4),
                           ("side", Float.pi/2), ("q135", 3 * Float.pi/4)] {
            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
            cam.position = SCNVector3(2.3 * sin(yaw), 0, 2.3 * cos(yaw))
            cam.eulerAngles = SCNVector3(0, yaw, 0)
            scene.rootNode.addChildNode(cam)
            let img = snapshotRenderer(scene, pointOfView: cam)
                .snapshot(atTime: 0, with: CGSize(width: 900, height: 1100), antialiasingMode: .multisampling4X)
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("probe_\(tag).png")
            try img.pngData()!.write(to: out)
            print("PROBE wrote \(out.path)")
        }
    }
}
