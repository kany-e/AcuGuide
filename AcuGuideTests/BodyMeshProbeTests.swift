import XCTest
import SceneKit
import GLTFKit2
import simd
@testable import AcuGuide

// DIAGNOSTIC (audit aid, not an invariant). The full-body atlas places every acupoint from
// AcupointPlacements.table[...].body — hand-authored mesh-space coordinates whose only automated
// check was BodyAtlas.snapToSurface, which is supposed to pull a slightly-off estimate onto the
// skin. Device report: the hand points render on the wrong part (and the wrong FACE) of the hand.
//
// Two instruments, because the coordinates were authored without either:
//  • the model's own SKELETON as the ruler — Hand_R pins the wrist, Fingers01_R the knuckle line,
//    Thumb01_R/Thumb02_R the thumb — so a placement can be scored as a fraction along the palm
//    axis and as a signed distance along the palm NORMAL, instead of eyeballed off a render;
//  • testSurfaceSnapActuallyFires, which asks whether the snap does anything at all.
final class BodyMeshProbeTests: XCTestCase {

    // The frame under test is the app's own (HandFrame.right) — the test must not carry a second
    // copy of the skeleton that could drift from it. These two landmarks are extra reference points
    // the frame itself does not need; both come from testProbeBodySkeleton.
    static let fingerMidR = SIMD3<Float>(-0.3636, -0.0914, 0.7938)   // Fingers02_R — mid-finger
    static let thumb1R    = SIMD3<Float>(-0.3436, -0.0883, 0.8918)   // Thumb01_R   — thumb base

    static var frame: HandFrame { .right }

    private func loadScene(_ resource: String) -> SCNScene? {
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
        return SCNScene(gltfAsset: asset)
    }

    /// The body mesh assembled exactly as Body3DView assembles it (pivot, channels, then markers),
    /// so the marker positions read back here are the ones the atlas renders.
    private func bodyMesh() throws -> SCNNode {
        guard let scene = loadScene("model"), let geometry = bodyGeometry(scene) else {
            throw XCTSkip("no body geometry")
        }
        let mesh = SCNNode(geometry: geometry)
        let (lo, hi) = mesh.boundingBox
        mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        mesh.addChildNode(BodyAtlas.channels(on: mesh))
        mesh.addChildNode(BodyAtlas.markers(on: mesh))
        return mesh
    }

    private func snappedMarkerPositions() throws -> [String: SIMD3<Float>] {
        var out: [String: SIMD3<Float>] = [:]
        try bodyMesh().enumerateChildNodes { n, _ in
            guard let name = n.name, name.hasPrefix("acu:") else { return }
            out[String(name.dropFirst(4))] = SIMD3(Float(n.position.x), Float(n.position.y), Float(n.position.z))
        }
        return out
    }

    private func bodyGeometry(_ scene: SCNScene) -> SCNGeometry? {
        var found: SCNGeometry? = nil
        scene.rootNode.enumerateHierarchy { n, _ in if found == nil { found = n.geometry } }
        return found?.copy() as? SCNGeometry
    }

    // Dump every bind-pose bone, so the landmarks above can be re-derived if the model changes.
    func testProbeBodySkeleton() throws {
        guard let scene = loadScene("model") else { return }
        var bones: [(String, SIMD3<Float>)] = []
        scene.rootNode.enumerateHierarchy { node, _ in
            guard let name = node.name else { return }
            let w = node.convertPosition(SCNVector3Zero, to: nil)
            bones.append((name, SIMD3(Float(w.x), Float(w.y), Float(w.z))))
        }
        print("=== SKELETON — scene space (y-up); app coords are (x, −z, y) ===")
        for (n, p) in bones.sorted(by: { $0.1.y > $1.1.y }) {
            print(String(format: "  %-24@  scene(%+.4f %+.4f %+.4f)   app[%+.4f, %+.4f, %+.4f]",
                         n as NSString, p.x, p.y, p.z, p.x, -p.z, p.y))
        }
    }

    // THE ASSERTION the hand placements never had. `along` = fraction of the palm axis (0 = wrist
    // crease, 1 = knuckle line); negative means the point sits up the FOREARM. `face` = signed
    // distance along the palm normal in palm-lengths: positive is PALMAR, negative is DORSAL.
    //
    // Before HandFrame, seven of these eight failed: PC8/HT7/PC7/PC6 (palmar) were drawn on the
    // back of the hand, TE3/SJ5 (dorsal) on the palm, and TE4 sat half a palm-length up the forearm,
    // off the limb entirely. Only SI3 was right. Nothing caught it, because the only shipping
    // assertion asked whether a marker landed on SOME surface.
    func testHandPointsSitOnTheRightAnatomy() throws {
        let f = Self.frame
        print(String(format: "=== palm axis %.4f long; palm normal [%+.3f %+.3f %+.3f]; 1 cun %.4f",
                     f.palmLength, f.palmar.x, f.palmar.y, f.palmar.z, f.cun))
        for (tag, p) in [("thumb base", Self.thumb1R), ("mid-finger", Self.fingerMidR)] {
            print(String(format: "  ref %-11@ along %+.2f", tag as NSString,
                         simd_dot(p - f.origin, f.distal) / f.palmLength))
        }
        // Measure the marker where it RENDERS, i.e. after the surface snap: HandFrame places each
        // point in the plane of the hand (face ≈ 0 by construction) and the snap is what lifts it
        // onto the correct skin. Asserting on the pre-snap value would test nothing about the face.
        let snapped = try snappedMarkerPositions()

        // Expected band along the palm axis, per point. The wrist-crease points sit at 0; the two
        // forearm points are 2 cun proximal (≈ −0.46 palm-lengths on this model); the rest are on
        // the palm or dorsum, between the crease and the knuckles.
        let expected: [String: ClosedRange<Float>] = [
            "PC6": (-0.70)...(-0.30), "SJ5": (-0.70)...(-0.30),
            "PC7": (-0.10)...(0.10),  "TE4": (-0.10)...(0.10),
            "HT7": (-0.10)...(0.15),
            "PC8": (0.45)...(0.75),
            "TE3": (0.65)...(0.95),   "SI3": (0.70)...(1.00),
        ]
        // Which face a marker is on has to be judged against the LOCAL skin, not against the plane
        // through wrist/knuckles/thumb: the low-poly limb curves away from that plane as it runs
        // distal, so a point can read "palmar side of the wrist plane" while sitting squarely on
        // the back of the hand. So at each marker, cast the palm normal clean through the limb and
        // compare the marker with the midpoint of the two skin crossings it finds.
        let surface = BodyAtlas.Surface(mesh: try bodyMesh())
        print("\n  point  surface   along   face   (− = dorsal side of the local skin)")
        for (id, band) in expected.sorted(by: { $0.key < $1.key }) {
            guard let pt = Acupoint.byId[id] else { XCTFail("\(id) missing from the atlas"); continue }
            guard let p = snapped[id] else { XCTFail("\(id) produced no atlas marker"); continue }
            let v = p - f.origin
            let along = simd_dot(v, f.distal) / f.palmLength

            // Palmar-side and dorsal-side skin crossings at this marker.
            guard let palmarSkin = surface.firstHit(from: p + f.palmar * 0.20, to: p - f.palmar * 0.20),
                  let dorsalSkin = surface.firstHit(from: p - f.palmar * 0.20, to: p + f.palmar * 0.20) else {
                XCTFail("\(id): the palm normal misses the limb — the marker is not on the hand at all")
                continue
            }
            let mid = (palmarSkin.point + dorsalSkin.point) / 2
            let face = simd_dot(p - mid, f.palmar) / f.palmLength
            print(String(format: "  %-5@  %-8@  %+.2f   %+.2f",
                         id as NSString, (pt.requiresDorsal ? "dorsal" : "palmar") as NSString, along, face))
            XCTAssertTrue(band.contains(along),
                          "\(id) sits \(along) along the palm axis, outside \(band) — wrong place on the limb")
            // requiresDorsal is the SAME flag the camera coach's face gate uses, so the atlas and
            // the coach can never disagree about which side of the hand a point is on.
            if pt.requiresDorsal {
                XCTAssertLessThan(face, 0, "\(id) is dorsal but sits on the PALM side (face \(face))")
            } else {
                XCTAssertGreaterThan(face, 0, "\(id) is palmar but sits on the BACK of the hand (face \(face))")
            }
        }
    }

    // Does the surface snap do anything? The registry promises "estimates are surface-snapped … so
    // slightly-off values still land on it" — worth nothing if the raycast misses. It missed for all
    // 27, silently: BodyAtlas used SCNNode.hitTestWithSegment, which returns nothing for either GLB
    // in this project, so the channels also kept their raw bone route. BodyAtlas now shares the CPU
    // triangle intersection that the detail sheets have always used (AtlasMarkers.triangles/rayHits).
    func testSurfaceSnapActuallyFires() throws {
        guard let scene = loadScene("model"), let geometry = bodyGeometry(scene) else {
            XCTFail("no body geometry"); return
        }
        let mesh = SCNNode(geometry: geometry)
        let (lo, hi) = mesh.boundingBox
        mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        mesh.addChildNode(BodyAtlas.markers(on: mesh))

        let placed = Dictionary(uniqueKeysWithValues: BodyAtlas.acuMarkers.map { ($0.id, $0.pos) })
        var fired = 0, missed: [String] = []
        mesh.enumerateChildNodes { n, _ in
            guard let name = n.name, name.hasPrefix("acu:") else { return }
            let id = String(name.dropFirst(4))
            guard let estimate = placed[id] else { return }
            let p = SIMD3<Float>(Float(n.position.x), Float(n.position.y), Float(n.position.z))
            if simd_length(p - estimate) < 1e-6 { missed.append(id) } else { fired += 1 }
        }
        print("=== surface snap fired for \(fired), missed for \(missed.count): \(missed.sorted())")
        // A miss means the marker hangs at its raw estimate instead of on the skin. Torso midline
        // points (CV/GV) legitimately have no radial direction and keep their estimate by design,
        // so this asserts the mechanism works at all rather than demanding a perfect score.
        XCTAssertGreaterThan(fired, 20, "the surface snap is not firing — markers float at their estimates")
        for id in ["PC8", "HT7", "TE3", "SI3", "PC7", "TE4"] {
            XCTAssertFalse(missed.contains(id), "\(id) did not reach the hand surface")
        }
    }

    // Labelled render of the ATLAS HAND ZOOM, built exactly the way Body3DView builds it (same
    // mesh, same channels+markers children, same −90°X pose, same region-focus camera), with
    // orange skeleton reference dots so the numbers above can be checked against a picture.
    func testRenderBodyHandZoomForAudit() throws {
        guard let gltfScene = loadScene("model"), let geometry = bodyGeometry(gltfScene) else {
            XCTFail("no body geometry"); return
        }
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.97, alpha: 1)
        AtlasMarkers.addStudioLighting(to: scene)

        let mesh = SCNNode(geometry: geometry)
        let (lo, hi) = mesh.boundingBox
        mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        mesh.addChildNode(BodyAtlas.channels(on: mesh))
        mesh.addChildNode(BodyAtlas.markers(on: mesh))
        let pose = SCNNode()
        pose.addChildNode(mesh)
        pose.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)   // == Body3DView
        scene.rootNode.addChildNode(pose)

        let f = Self.frame
        for (tag, p) in [("wrist", f.origin), ("knuckles", f.hand(along: 1, across: 0)),
                         ("thumbBase", Self.thumb1R), ("fingerMid", Self.fingerMidR)] {
            let n = SCNNode(geometry: SCNSphere(radius: 0.010))
            n.geometry?.firstMaterial?.diffuse.contents = UIColor.systemOrange
            n.geometry?.firstMaterial?.lightingModel = .constant
            n.position = SCNVector3(p.x, p.y, p.z)
            mesh.addChildNode(n)
            addLabel(tag, at: n.position, in: mesh, color: .systemOrange, dx: -0.055)
        }
        // markers(on:) ships them hidden (the live view reveals them per frame) — unhide to render.
        mesh.enumerateChildNodes { n, _ in
            guard let name = n.name, name.hasPrefix("acu:") else { return }
            let id = String(name.dropFirst(4))
            guard ["PC6", "SJ5", "TE4", "PC7", "HT7", "PC8", "TE3", "SI3"].contains(id) else { return }
            n.isHidden = false
            n.enumerateHierarchy { c, _ in c.isHidden = false }
            addLabel(id, at: n.position, in: mesh, color: .black, dx: 0.014)
        }

        guard let hand = BodyAtlas.regions.first(where: { $0.id == "hand" }) else {
            XCTFail("no hand region"); return
        }
        let target = mesh.convertPosition(SCNVector3(hand.center.x, hand.center.y, hand.center.z), to: nil)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 50; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.camera?.categoryBitMask = ~BodyAtlas.proxyCategory
        // 1.3 is the app's margin; 2.1 here so the whole hand + labels fit the audit frame.
        let dist = hand.radius / tan(Float(25.0 * Double.pi / 180.0)) * 2.1
        cam.position = SCNVector3(target.x, target.y, target.z + dist)
        scene.rootNode.addChildNode(cam)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        let img = renderer.snapshot(atTime: 0, with: CGSize(width: 760, height: 1000),
                                    antialiasingMode: .multisampling4X)
        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audit_body_hand.png")
        try img.pngData()!.write(to: out)
        print("AUDIT wrote \(out.path)")
    }

    private func addLabel(_ s: String, at p: SCNVector3, in parent: SCNNode, color: UIColor, dx: Float) {
        let t = SCNText(string: s, extrusionDepth: 0.001)
        t.font = .systemFont(ofSize: 1.4); t.flatness = 0.05
        t.firstMaterial?.diffuse.contents = color
        t.firstMaterial?.lightingModel = .constant
        let n = SCNNode(geometry: t)
        n.scale = SCNVector3(0.0045, 0.0045, 0.0045)
        n.position = SCNVector3(p.x + dx, p.y - 0.06, p.z)
        n.constraints = [SCNBillboardConstraint()]
        n.categoryBitMask = BodyAtlas.decorationCategory
        parent.addChildNode(n)
    }
}

