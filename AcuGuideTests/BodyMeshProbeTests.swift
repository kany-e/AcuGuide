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
        // DERIVED FROM HandAnatomy, not hardcoded. These bands used to be literals, which meant they
        // encoded whatever the table happened to say when they were written — so a re-SOURCING of the
        // anatomy (WHO + the classical rules, R20) failed them for being right. The band now tracks
        // the table and only asserts what this test is actually for: that the marker lands where the
        // anatomy says, within the reach of BodyAtlas's inboard surface snap.
        //
        // The tolerance is one-sided in effect because the snap walks a point TOWARD along 0.5 (it
        // steps along `toward = hand(along: 0.5, across: 0)`), so a distal point can legitimately
        // read up to ~0.4·(along − 0.5) proximal of its authored value. 0.20 covers that for every
        // point in the table and is still far tighter than "somewhere on the hand".
        var expected: [String: ClosedRange<Float>] = [
            // The two forearm points are placed by CUN, not by `along`, so they keep an explicit band.
            "PC6": (-0.70)...(-0.30), "SJ5": (-0.70)...(-0.30),
        ]
        for id in ["PC7", "TE4", "HT7", "PC8", "TE3", "SI3"] {
            guard let spot = HandAnatomy.spots[id] else { XCTFail("\(id) has no anatomy"); continue }
            expected[id] = (spot.along - 0.20)...(spot.along + 0.20)
        }
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
        // EVERY marker, with no allowance. It was 0 of 27 (hitTestWithSegment returns nothing for
        // this GLB), then 21 of 27 once the CPU intersection was adopted — the six stragglers being
        // the ones whose ray was aimed at the body's vertical axis rather than their own limb, so
        // it crossed a shin obliquely or missed it outright. Aiming at the nearest bone fixed the
        // rest, including GV20, whose ray now comes down through the top of the head instead of
        // having no radial direction at all. A miss means a marker hanging in space beside the
        // body, which is precisely the class of defect this file exists to catch.
        XCTAssertEqual(missed, [], "these markers never reached the skin — they hang at their raw estimate")
        XCTAssertEqual(fired, 27, "expected all 27 atlas markers to snap")
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


// Full-body render at the DEFAULT atlas camera, with channels + markers, exactly as Body3DView
// assembles the scene. Device report: "why does the chest meridian have two dips on it" and "the
// body should be solid, not transparent so that the front and back arm meridians are not
// simultaneously visible when you are at front angles".
extension BodyMeshProbeTests {
    func testRenderWholeBodyForAudit() throws {
        guard let gltfScene = loadScene("model"), let geometry = bodyGeometry(gltfScene) else {
            XCTFail("no body geometry"); return
        }
        for (tag, yaw) in [("front", Float(0)), ("q45", Float.pi / 4)] {
            let scene = SCNScene()
            scene.background.contents = UIColor(white: 0.97, alpha: 1)
            AtlasMarkers.addStudioLighting(to: scene)
            let geo = geometry.copy() as! SCNGeometry
            geo.materials = [BodyAtlas.auditBodyMaterial()]   // the app's own sage material
            let mesh = SCNNode(geometry: geo)
            let (lo, hi) = mesh.boundingBox
            mesh.pivot = SCNMatrix4MakeTranslation((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
            mesh.addChildNode(BodyAtlas.channels(on: mesh))
            let markers = BodyAtlas.markers(on: mesh)
            markers.enumerateHierarchy { n, _ in n.isHidden = false }
            mesh.addChildNode(markers)
            let pose = SCNNode(); pose.addChildNode(mesh)
            pose.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            let spin = SCNNode(); spin.addChildNode(pose); spin.eulerAngles = SCNVector3(0, yaw, 0)
            scene.rootNode.addChildNode(spin)

            let radius = pose.boundingSphere.radius
            let cam = SCNNode(); cam.camera = SCNCamera()
            cam.camera?.fieldOfView = 50; cam.camera?.zNear = 0.01
            cam.camera?.zFar = Double(radius) * 400 + 100
            cam.camera?.categoryBitMask = ~BodyAtlas.proxyCategory
            cam.position = SCNVector3(0, 0, radius * 3.4)
            scene.rootNode.addChildNode(cam)

            let r = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
            r.scene = scene; r.pointOfView = cam
            let img = r.snapshot(atTime: 0, with: CGSize(width: 620, height: 1000),
                                 antialiasingMode: .multisampling4X)
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("audit_body_\(tag).png")
            try img.pngData()!.write(to: out)
            print("BODY AUDIT wrote \(out.path)")
        }
    }
}

// LANDMARK DERIVATION for the DETAIL hand mesh (hand_low_poly.glb), which — unlike model.glb — has
// NO SKELETON (0 skins, 0 bones; only Sketchfab wrapper nodes). Its acupoint placements were the
// second thing the user called out as unchanged, and eyeballing a probe grid is the method this
// codebase repudiates. So derive the landmarks from the GEOMETRY: the five digits are the five
// local extremities of distance-from-the-wrist-stub, and the wrist is the flat cut face at the
// proximal end.
extension BodyMeshProbeTests {
    func testProbeDetailHandLandmarks() throws {
        guard let scene = loadScene("hand_low_poly") else { return }
        var verts: [SIMD3<Float>] = []
        scene.rootNode.enumerateHierarchy { n, _ in
            guard let g = n.geometry, let src = g.sources(for: .vertex).first,
                  src.componentsPerVector >= 3, src.bytesPerComponent == 4 else { return }
            src.data.withUnsafeBytes { raw in
                for i in 0..<src.vectorCount {
                    let b = src.dataOffset + i * src.dataStride
                    guard b + 12 <= raw.count else { break }
                    let p = SIMD3<Float>(raw.loadUnaligned(fromByteOffset: b, as: Float.self),
                                         raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                                         raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
                    let w = n.convertPosition(SCNVector3(p.x, p.y, p.z), to: nil)
                    verts.append(SIMD3(Float(w.x), Float(w.y), Float(w.z)))
                }
            }
        }
        print("=== hand_low_poly: \(verts.count) vertices ===")
        guard !verts.isEmpty else { XCTFail("no vertices — the source is GPU-backed"); return }
        var lo = verts[0], hi = verts[0]
        for v in verts { lo = simd_min(lo, v); hi = simd_max(hi, v) }
        print(String(format: "  bbox x %.3f…%.3f  y %.3f…%.3f  z %.3f…%.3f", lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        let ext = hi - lo
        let longAxis = ext.x > ext.y ? (ext.x > ext.z ? 0 : 2) : (ext.y > ext.z ? 1 : 2)
        print("  longest axis =", ["x","y","z"][longAxis], "extent", ext[longAxis])
        // Slice along the long axis and report the cross-section width + vertex count, so the wrist
        // (narrow, flat cut) and the finger fan (many small clusters) are readable from the numbers.
        let steps = 24
        for i in 0..<steps {
            let a = lo[longAxis] + ext[longAxis] * Float(i) / Float(steps)
            let b = lo[longAxis] + ext[longAxis] * Float(i + 1) / Float(steps)
            let band = verts.filter { $0[longAxis] >= a && $0[longAxis] < b }
            guard !band.isEmpty else { continue }
            let o1 = (longAxis + 1) % 3, o2 = (longAxis + 2) % 3
            let w1 = (band.map { $0[o1] }.max()! - band.map { $0[o1] }.min()!)
            let w2 = (band.map { $0[o2] }.max()! - band.map { $0[o2] }.min()!)
            print(String(format: "  %.3f…%.3f  n=%4d  width(%@)=%.3f  width(%@)=%.3f",
                         a, b, band.count, ["x","y","z"][o1] as NSString, w1, ["x","y","z"][o2] as NSString, w2))
        }
    }
}

// The DETAIL hand sheet's own anatomical frame, in the (u,v) space the registry authors in.
//
// hand_low_poly.glb has no skeleton, so the landmarks come from the GEOMETRY: slice the posed mesh
// along its long axis and read off the fingertip plane, the knuckle line (where the finger fan
// merges into a single wide mass) and the wrist crease (where the palm+thumb mass narrows into the
// forearm stub). Those three, plus the thumb's lateral extreme, give the same frame HandFrame
// derives from the body's bones — so BOTH surfaces can be placed from ONE set of anatomical
// fractions instead of two unrelated tables.
extension BodyMeshProbeTests {
    func testProbeDetailHandUVFrame() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)      // == HandModel3DView's chart pose

        // World-space vertices of the POSED mesh, and the same world AABB screenMarker maps uv onto.
        let tris = AtlasMarkers.triangles(of: mesh, in: nil, categoryMask: nil)
        XCTAssertFalse(tris.isEmpty, "no triangles — cannot derive a frame")
        var mn = tris[0], mx = tris[0]
        for v in tris { mn = simd_min(mn, v); mx = simd_max(mx, v) }
        let centre = (mn + mx) / 2, ext = mx - mn
        func uv(_ p: SIMD3<Float>) -> SIMD2<Float> {
            SIMD2((p.x - centre.x) / ext.x, (p.y - centre.y) / ext.y)
        }
        print(String(format: "=== posed AABB  x %.3f…%.3f  y %.3f…%.3f  z %.3f…%.3f", mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))

        // Slice along SCREEN-Y (v), which after the chart pose runs fingertips → wrist.
        print("  v-band      n    x-span   z-span   centroid(u,v)")
        let steps = 20
        var bands: [(v: Float, n: Int, xs: Float, cu: Float, cv: Float)] = []
        for i in 0..<steps {
            let a = mn.y + ext.y * Float(i) / Float(steps)
            let b = mn.y + ext.y * Float(i + 1) / Float(steps)
            let band = tris.filter { $0.y >= a && $0.y < b }
            guard band.count > 2 else { continue }
            let xs = band.map(\.x).max()! - band.map(\.x).min()!
            let zs = band.map(\.z).max()! - band.map(\.z).min()!
            let c = band.reduce(SIMD3<Float>.zero, +) / Float(band.count)
            let cuv = uv(c)
            bands.append((b, band.count, xs, cuv.x, cuv.y))
            let umin = uv(SIMD3(band.map(\.x).min()!, 0, 0)).x, umax = uv(SIMD3(band.map(\.x).max()!, 0, 0)).x
            print(String(format: "  %+.3f  %5d   u %+.3f…%+.3f  (span %.3f)  z-span %.3f  centroid u %+.3f",
                         cuv.y, band.count, umin, umax, xs, zs, cuv.x))
        }
    }
}

// A labelled uv GRID on the detail hand. Inferring the frame from slice statistics put the v axis
// upside down (LI5, a radial WRIST point, landed on the middle finger), so read it off a picture:
// each dot is drawn at a known (u,v), so the wrist crease, the knuckle line and the thumb side can
// be located by looking rather than by argument.
extension BodyMeshProbeTests {
    func testRenderDetailHandUVGrid() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        let out = SCNScene()
        out.background.contents = UIColor(white: 0.97, alpha: 1)
        AtlasMarkers.addStudioLighting(to: out)
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)
        out.rootNode.addChildNode(mesh)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.position = SCNVector3(0, 0, 2.3)
        out.rootNode.addChildNode(cam)

        let us: [Float] = [-0.30, -0.15, 0, 0.15, 0.30]
        let vs: [Float] = [-0.40, -0.20, 0, 0.20, 0.40]
        for v in vs {
            for u in us {
                guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: u, v: v,
                                                        farSide: false, id: "g", color: .systemRed,
                                                        core: 0.016, halo: 0.026) else { continue }
                out.rootNode.addChildNode(m.node)
                let t = SCNText(string: String(format: "%.2f,%.2f", u, v), extrusionDepth: 0.001)
                t.font = .systemFont(ofSize: 1.4); t.flatness = 0.05
                t.firstMaterial?.diffuse.contents = UIColor.systemRed
                t.firstMaterial?.lightingModel = .constant
                let tn = SCNNode(geometry: t)
                tn.scale = SCNVector3(0.030, 0.030, 0.030)
                tn.position = SCNVector3(m.node.position.x + 0.03, m.node.position.y + 0.02,
                                         m.node.position.z + 0.35)
                tn.constraints = [SCNBillboardConstraint()]
                out.rootNode.addChildNode(tn)
            }
        }
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
        r.scene = out; r.pointOfView = cam
        let img = r.snapshot(atTime: 0, with: CGSize(width: 900, height: 1100), antialiasingMode: .multisampling4X)
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uv_grid_hand.png")
        try img.pngData()!.write(to: path)
        print("UVGRID wrote \(path.path)")
    }
}

// THE uv SPACE IS NOT SQUARE, and that is the whole bug behind "the hand acupoint location is way
// off the palm". screenMarker aims a ray at (centre.x + u·ext.x, centre.y + v·ext.y) — u and v are
// fractions of DIFFERENT world extents. HandSheet builds an orthonormal frame (distal ⟂ radial,
// both unit length) inside that space, so "perpendicular in uv" is not perpendicular on the hand
// and "one palm-length" is a different distance along each axis. This prints the numbers that
// settle it, in screenMarker's OWN basis (the corner-transformed bounding box it actually uses —
// not the triangle AABB testProbeDetailHandUVFrame reports, which is a tighter and different box).
extension BodyMeshProbeTests {
    func testDetailHandUVSpaceIsAnisotropic() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)

        // Exactly screenMarker's basis: the 8 LOCAL bbox corners pushed to world.
        let (lo, hi) = mesh.boundingBox
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude); var mx = -mn
        for a in [lo.x, hi.x] { for b in [lo.y, hi.y] { for c in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(a, b, c), to: nil)
            mn = simd_min(mn, SIMD3(w.x, w.y, w.z)); mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
        } } }
        let ext = mx - mn
        print(String(format: "=== screenMarker basis: ext.x %.4f  ext.y %.4f  ext.x/ext.y %.4f",
                     ext.x, ext.y, ext.x / ext.y))
        print(String(format: "=== HandSheet.uvAspect is %.4f", HandSheet.uvAspect))

        XCTAssertEqual(HandSheet.uvAspect, ext.x / ext.y, accuracy: 0.005,
                       "HandSheet.uvAspect no longer matches the posed mesh — re-measure it")

        // END-TO-END, through the public API rather than the internals: one palm-length ALONG and
        // one palm-length ACROSS must come out perpendicular and equally long ON THE MESH.
        func world(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x * ext.x, p.y * ext.y) }
        let o = world(HandSheet.uv(along: 0, across: 0))
        let a = world(HandSheet.uv(along: 1, across: 0)) - o     // wrist crease → knuckle line
        let b = world(HandSheet.uv(along: 0, across: 1)) - o     // one palm-length across
        let deg = acos(max(-1, min(1, simd_dot(simd_normalize(a), simd_normalize(b))))) * 180 / .pi
        print(String(format: "=== along∠across on the MESH: %.1f°  (90° = square)", deg))
        // Measured at the WRIST (along 0), so the expected ratio is the wrist end of the profile.
        print(String(format: "=== |across| / |along| = %.4f  (should be wristAcrossScale %.2f)",
                     simd_length(b) / simd_length(a), HandSheet.wristAcrossScale))
        XCTAssertEqual(deg, 90, accuracy: 1.0,
                       "the hand frame is sheared on the mesh — moving across the palm also walks the point along it")
        XCTAssertEqual(simd_length(b) / simd_length(a), HandSheet.wristAcrossScale, accuracy: 0.02,
                       "one palm-length across is not one palm-length on the mesh")
    }
}

// A SILHOUETTE PROBE THAT DOES NOT REBUILD THE MESH FOR EVERY RAY.
//
// The scanning probes below fire thousands of rays, and calling AtlasMarkers.screenMarker for each
// one is quadratic in disguise: screenMarker rebuilds the whole triangle soup from the geometry
// sources on EVERY call, and then allocates a node. Written that way, one probe took **2651 seconds**
// — it turned `make test`, which is the gate, into a 45-minute job. Same arithmetic as screenMarker's
// own ray construction, with the soup and the bounds hoisted out of the loop.
struct HandSilhouette {
    let tris: [SIMD3<Float>]
    let centre: SIMD3<Float>
    let ext: SIMD3<Float>
    let cameraZ: Float

    init(mesh: SCNNode, cameraZ: Float = 2.3) {
        self.cameraZ = cameraZ
        tris = AtlasMarkers.triangles(of: mesh, in: nil, categoryMask: nil)
        let (lo, hi) = mesh.boundingBox
        var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude); var mx = -mn
        for a in [lo.x, hi.x] { for b in [lo.y, hi.y] { for c in [lo.z, hi.z] {
            let w = mesh.convertPosition(SCNVector3(a, b, c), to: nil)
            mn = simd_min(mn, SIMD3(w.x, w.y, w.z)); mx = simd_max(mx, SIMD3(w.x, w.y, w.z))
        } } }
        centre = (mn + mx) / 2; ext = mx - mn
    }

    /// Does a camera ray through this (u,v) meet the mesh? Equivalent to screenMarker's DIRECT hit
    /// (no spiral snap), which is what the probes are asking about.
    func hits(_ u: Float, _ v: Float) -> Bool {
        let cam = SIMD3<Float>(0, 0, cameraZ)
        let target = SIMD3<Float>(centre.x + u * ext.x, centre.y + v * ext.y, centre.z)
        let dir = simd_normalize(target - cam)
        let reach = simd_length(target - cam) + ext.z + 1.0
        return !AtlasMarkers.rayHits(tris, origin: cam, dir: dir, maxT: reach).isEmpty
    }

    /// Widest contiguous run of surface at this height — the palm (the thumb is a separate lobe).
    func palmSpan(at v: Float, samples: Int = 80) -> (lo: Float, hi: Float)? {
        runs(at: v, samples: samples).max(by: { ($0.hi - $0.lo) < ($1.hi - $1.lo) })
    }

    func runs(at v: Float, samples: Int = 80) -> [(lo: Float, hi: Float)] {
        var out: [(lo: Float, hi: Float)] = []
        var start: Float? = nil, prev: Float = 0
        for j in 0...samples {
            let u = -0.50 + Float(j) / Float(samples) * 1.00
            if hits(u, v) { if start == nil { start = u }; prev = u }
            else if let s = start { out.append((s, prev)); start = nil }
        }
        if let s = start { out.append((s, prev)) }
        return out
    }
}

// MEASURE THE CENTRELINE, don't eyeball it. Reading marker positions off a render means comparing
// them to a silhouette I judge by eye, in a perspective view, on a hand whose thumb occludes the
// radial border — and the dorsal and palm renders are NOT mirror images of each other, so the two
// estimates disagree and there is no way to tell which is lying.
//
// So sample the silhouette in the SAME uv space the markers are placed in: probe a grid of (u,v)
// with screenMarker's own direct-hit test, and for each v take the WIDEST CONTIGUOUS run of hits.
// At palm heights the thumb is a separate lobe with a gap between, so the widest run is the palm.
// Its midpoint is the centreline and its half-width is how far `across` can reach — both measured,
// not judged.
extension BodyMeshProbeTests {
    func testMeasureDetailHandCentreline() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)

        let sil = HandSilhouette(mesh: mesh)          // triangle soup built ONCE — see HandSilhouette

        print("     v      palm u-span        centre   half-width")
        var samples: [(v: Float, c: Float, hw: Float)] = []
        for i in 0...24 {
            let v = -0.45 + Float(i) / 24 * 0.60          // wrist stub → past the knuckle line
            let runs = sil.runs(at: v)
            guard let widest = runs.max(by: { ($0.hi - $0.lo) < ($1.hi - $1.lo) }) else { continue }
            let c = (widest.lo + widest.hi) / 2, hw = (widest.hi - widest.lo) / 2
            samples.append((v, c, hw))
            print(String(format: "  %+.3f   %+.3f…%+.3f   %+.3f    %.3f   (%d lobe%@)",
                         v, widest.lo, widest.hi, c, hw, runs.count, runs.count == 1 ? "" : "s"))
        }

        // FIT ONLY THE ROWS WHERE THE THUMB IS NOT MERGED INTO THE PALM'S OUTLINE. It is absent below
        // v ≈ −0.175 and a SEPARATE lobe above v ≈ +0.02 (so the widest run is the palm either way);
        // in between it fuses and drags the measured midpoint radially. Above +0.15 the digits split
        // and the widest run stops being the palm at all. Fitting only the low band is not enough —
        // that band is mostly the constant-width forearm stub, whose lean differs from the palm's,
        // and extrapolating it up to the knuckles is what put the knuckle end 0.1 too far radial.
        let clean = samples.filter { $0.v <= -0.175 || ($0.v >= 0.02 && $0.v <= 0.15) }
        let n = Float(clean.count)
        let sv = clean.reduce(0) { $0 + $1.v }, sc = clean.reduce(0) { $0 + $1.c }
        let svv = clean.reduce(0) { $0 + $1.v * $1.v }, svc = clean.reduce(0) { $0 + $1.v * $1.c }
        let m = (n * svc - sv * sc) / (n * svv - sv * sv)
        let b = (sc - m * sv) / n
        print(String(format: "=== measured centreline: u = %.4f·v + %.4f  (from %d clean rows)", m, b, clean.count))
        print(String(format: "=== HandSheet says wrist u %+.3f (measured %+.3f), knuckles u %+.3f (measured %+.3f)",
                     HandSheet.wrist.x, m * HandSheet.wrist.y + b,
                     HandSheet.knuckles.x, m * HandSheet.knuckles.y + b))

        // THE INVARIANT. Both landmarks must sit on the hand's own midline, or every point inherits
        // the lean — which is exactly what "the hand acupoint location is way off the palm" was.
        XCTAssertEqual(HandSheet.wrist.x, m * HandSheet.wrist.y + b, accuracy: 0.03,
                       "the frame's wrist end is off the measured centreline")
        XCTAssertEqual(HandSheet.knuckles.x, m * HandSheet.knuckles.y + b, accuracy: 0.03,
                       "the frame's knuckle end is off the measured centreline")

        // …and the knuckle line must be where the FINGERS actually separate.
        //
        // "First v with more than one lobe" is NOT that: scanning up from the wrist, the first break
        // is the THUMB peeling off the palm outline (it is a lobe on the far radial side, around
        // u −0.25…−0.08, while the palm and all four fingers are still one mass). Counting it put the
        // MCP line at v +0.025 when the digits do not actually separate until v +0.15 — a whole third
        // of the hand — and an assertion built on it happily pinned the wrong anatomy. So ignore any
        // lobe lying entirely radial of u −0.10; by the height the digits split, the palm's own
        // radial edge is well inside that.
        var split: Float? = nil
        for i in 0...60 where split == nil {
            let v = -0.10 + Float(i) / 60 * 0.40
            let digits = sil.runs(at: v).filter { $0.hi > -0.10 }   // drop the thumb lobe
            if digits.count > 1 { split = v }
        }
        XCTAssertNotNil(split, "the finger lobes never separate — the pose or the mesh changed")
        if let split {
            print(String(format: "=== digits separate at v %+.3f; HandSheet.knuckles.y %+.3f",
                         split, HandSheet.knuckles.y))
        }

        // Where the PALM stops narrowing and the amputated forearm stub begins: scanning down, the
        // half-width falls until it hits the stub's constant-width plateau. That knee is the wrist
        // crease. (Placing the wrist below it puts the frame's origin on the stub, which shifts every
        // marker proximally by a near-uniform offset instead of scaling them.)
        var knee: Float? = nil
        for i in stride(from: samples.count - 2, through: 1, by: -1) where knee == nil {
            let s = samples[i]
            guard s.v < -0.15 else { continue }
            if samples[i + 1].hw - s.hw < 0.004 { knee = s.v }   // stopped widening going up = plateau
        }
        if let knee {
            print(String(format: "=== palm/stub taper knee at v %+.3f; HandSheet.wrist.y %+.3f",
                         knee, HandSheet.wrist.y))
            XCTAssertGreaterThan(HandSheet.wrist.y, knee - 0.03,
                                 "the frame's origin is down the amputated forearm stub, not at the wrist crease")
        }
    }
}

// WHERE EACH POINT SITS ACROSS THE HAND, as a number rather than an impression. Device report:
// "PC8 looks right, the others look maybe slightly off" — and the labelled render cannot settle that,
// because on the dorsal side TE2/TE3/SI3 land close enough together that their billboarded labels
// overlap and hide the very dots being judged.
//
// So report, per point: its uv, the palm's measured u-span at that height, and its position as a
// FRACTION OF THE HALF-WIDTH (0 = centreline, -1 = ulnar border, +1 = radial border). That makes
// "too far ulnar" a number. Also reports which points the chart actually draws — a point whose
// region is not "hand" is silently absent from the sheet no matter what anatomy it has.
extension BodyMeshProbeTests {
    func testReportHandPointsAcrossThePalm() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)

        let sil = HandSilhouette(mesh: mesh)          // triangle soup built ONCE — see HandSilhouette
        func palmSpan(at v: Float) -> (lo: Float, hi: Float)? { sil.palmSpan(at: v) }

        let drawn = Set(AcupointPlacements.detailLayout(region: "hand").layout.keys)
        print("  id    along  across |    u       v    | palm u-span      | across/half-width | drawn")
        for id in HandAnatomy.spots.keys.sorted() {
            guard let s = HandAnatomy.spots[id] else { continue }
            let uv = HandSheet.uv(along: s.along, across: s.across)
            guard let span = palmSpan(at: uv.y) else {
                print(String(format: "  %-5@  %+.2f  %+.2f  | %+.3f %+.3f | OFF THE MESH", id as NSString,
                             s.along, s.across, uv.x, uv.y))
                continue
            }
            let c = (span.lo + span.hi) / 2, hw = (span.hi - span.lo) / 2
            let frac = hw > 1e-4 ? (uv.x - c) / hw : 0
            print(String(format: "  %-5@  %+.2f  %+.2f  | %+.3f %+.3f | %+.3f…%+.3f | %+.2f %@ | %@",
                         id as NSString, s.along, s.across, uv.x, uv.y, span.lo, span.hi, frac,
                         (abs(frac) > 0.95 ? "OFF EDGE" : abs(frac) > 0.8 ? "at border" : "        ") as NSString,
                         (drawn.contains(id) ? "yes" : "NO — region is not \"hand\"") as NSString))
        }
        let missing = HandAnatomy.spots.keys.filter { !drawn.contains($0) }.sorted()
        print("=== in HandAnatomy but NOT drawn on the chart: \(missing.isEmpty ? "none" : missing.joined(separator: " "))")
    }
}

// DRAW THE FRAME, not the points. The labelled-point audit is too cluttered to answer the only
// question that matters — does the hand frame's CENTRELINE run down the middle of the palm, and is
// "across" actually across? So render the frame itself: the along-axis as a ladder of dots at
// across = 0, and two rungs at across = ±0.30. If the ladder leans off the palm's midline, every
// point inherits that lean, which is what "way off the palm" looks like.
extension BodyMeshProbeTests {
    func testRenderHandFrameLadder() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        let out = SCNScene()
        out.background.contents = UIColor(white: 0.97, alpha: 1)
        AtlasMarkers.addStudioLighting(to: out)
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)
        out.rootNode.addChildNode(mesh)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 45; cam.camera?.zNear = 0.01; cam.camera?.zFar = 100
        cam.position = SCNVector3(0, 0, 2.3)
        out.rootNode.addChildNode(cam)

        // Centreline in WHITE, across-rungs in BLUE (radial/thumb) and RED (ulnar).
        var dots: [(Float, Float, UIColor)] = []
        for i in 0...8 { dots.append((Float(i) / 8 * 1.1 - 0.05, 0, .white)) }
        for a in [Float(0.0), 0.3, 0.6, 0.9] {
            dots.append((a,  0.30, .systemBlue))
            dots.append((a, -0.30, .systemRed))
        }
        for (along, across, color) in dots {
            let uv = HandSheet.uv(along: along, across: across)
            guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                    farSide: false, id: "f", color: color,
                                                    core: 0.018, halo: 0.03) else { continue }
            out.rootNode.addChildNode(m.node)
        }
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice()!, options: nil)
        r.scene = out; r.pointOfView = cam
        let img = r.snapshot(atTime: 0, with: CGSize(width: 900, height: 1100), antialiasingMode: .multisampling4X)
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("frame_ladder_hand.png")
        try img.pngData()!.write(to: path)
        print("LADDER wrote \(path.path)")
    }
}

// FIT THE ACROSS-SCALE BY SEARCH, not by eye.
//
// The anatomy says the ulnar border sits ~0.45 palm-lengths off the centreline. This mesh is a
// stylised hand: its fingers are splayed (so its knuckle line is far WIDER than a real hand's) while
// its wrist stub is far NARROWER, so no single stretch puts every point on the silhouette. Pick the
// largest scale at which every hand point still lands DIRECTLY on the mesh — measured once, here,
// rather than nudged per point until a render looks acceptable (the method that produced the
// placements this replaced).
extension BodyMeshProbeTests {
    func testFitDetailHandAcrossScale() throws {
        guard let scene = loadScene("hand_low_poly"),
              let mesh = AtlasMarkers.unitMesh(from: scene, material: AtlasMarkers.meshMaterial()) else {
            XCTFail("no hand mesh"); return
        }
        mesh.eulerAngles = SCNVector3(0, 0.72, Float.pi)
        let ids = HandAnatomy.spots.keys.sorted()

        print("  scale   direct hits / \(ids.count)   misses")
        var best: Float? = nil
        for i in stride(from: 40, through: 210, by: 5) {
            let scale = Float(i) / 100
            var direct = 0, bad: [String] = []
            for id in ids {
                guard let sp = HandAnatomy.spots[id] else { continue }
                let uv = HandSheet.uv(along: sp.along, across: sp.across, boost: scale)
                guard let m = AtlasMarkers.screenMarker(cameraZ: 2.3, mesh: mesh, u: uv.x, v: uv.y,
                                                        farSide: !sp.dorsal, id: id, color: .white,
                                                        core: 0.02, halo: 0.03) else { bad.append(id); continue }
                if m.onSurface && !m.snapped { direct += 1 } else { bad.append(id) }
            }
            print(String(format: "  %.2f     %2d              %@", scale, direct, bad.joined(separator: " ") as NSString))
            if direct == ids.count { best = scale }
        }
        if let best { print("=== largest all-direct across-scale: \(best)") }
        else { print("=== no scale puts every point directly on the mesh") }
    }
}

// The shared anatomy table is the app's ONE statement of where a hand point is. These pin the two
// things that made it necessary: that it agrees with the coach's face gate, and that the detail
// sheet it now feeds still puts every point on the mesh.
final class HandAnatomyTests: XCTestCase {

    // Every spot's `dorsal` must equal the point's own requiresDorsal — the flag the camera coach
    // uses to decide "turn your hand over". If these disagree, the atlas draws a point on one face
    // while the coach asks the user to show the other.
    func testAnatomyAgreesWithTheCoachFaceGate() {
        for (id, spot) in HandAnatomy.spots.sorted(by: { $0.key < $1.key }) {
            guard let pt = Acupoint.byId[id] else { XCTFail("\(id) is not in the atlas"); continue }
            XCTAssertEqual(spot.dorsal, pt.requiresDorsal,
                           "\(id): HandAnatomy says dorsal=\(spot.dorsal) but requiresDorsal=\(pt.requiresDorsal)")
        }
        for (id, f) in HandAnatomy.forearmSpots {
            guard let pt = Acupoint.byId[id] else { XCTFail("\(id) is not in the atlas"); continue }
            XCTAssertEqual(f.dorsal, pt.requiresDorsal, "\(id): forearm spot disagrees with requiresDorsal")
        }
    }

    // Every hand-region point must have anatomy SOMEWHERE, or it silently vanishes from the chart
    // (detailLayout skips ids it cannot resolve). PC6 and SJ5 are filed under region "hand" but are
    // FOREARM points — 2 cun above the wrist crease, past the end of the hand sheet's mesh — so
    // they belong to forearmSpots and are correctly absent from the chart, as they always were.
    func testEveryHandRegionPointHasAnatomy() {
        for pt in Acupoint.all where pt.region == "hand" {
            let placed = HandAnatomy.spots[pt.id] != nil || HandAnatomy.forearmSpots[pt.id] != nil
            XCTAssertTrue(placed, "\(pt.id) is a hand-region point with no entry in HandAnatomy")
        }
        // …and the two forearm ones must stay OFF the sheet rather than being drawn at its edge.
        XCTAssertNil(HandSheet.detailUV["PC6"], "PC6 is on the forearm — the hand sheet does not reach it")
        XCTAssertNil(HandSheet.detailUV["SJ5"], "SJ5 is on the forearm — the hand sheet does not reach it")
    }

    // THE DEFECT THIS ROUND FIXED, as an assertion. SI4 is at the ulnar WRIST and TE3/SI3 are up by
    // the knuckles; the detail sheet had all three within a few percent of one spot. Anything that
    // collapses them again — a bad frame, a bad scale — fails here.
    func testWristAndKnucklePointsAreNotOnTopOfEachOther() {
        let uv = HandSheet.detailUV
        guard let si4 = uv["SI4"], let te3 = uv["TE3"], let si3 = uv["SI3"] else {
            XCTFail("missing derived uv"); return
        }
        // MEASURED AGAINST THE ANATOMY, not against a literal. The old form asserted a bare 0.20 uv,
        // which encoded the spacing the table happened to have when it was written — so re-sourcing
        // SI4 (0.05 → 0.24) and TE3/SI3 (0.80/0.86 → 0.70/0.76) failed it for being right, even
        // though the points are still half a palm apart. What this test is FOR is catching a bad
        // frame or a bad scale collapsing the layout, so compare the rendered separation with the
        // separation the anatomy asks for, and require most of it to survive the mapping.
        func anatomySeparation(_ a: String, _ b: String) -> Float {
            guard let x = HandAnatomy.spots[a], let y = HandAnatomy.spots[b] else { return 0 }
            // In palm-lengths, with `across` on the sheet's own lateral scale so the comparison is
            // like for like.
            let dAlong = x.along - y.along
            let dAcross = (x.across - y.across) * HandSheet.acrossScale(atAlong: (x.along + y.along) / 2)
            return (dAlong * dAlong + dAcross * dAcross).squareRoot() * HandSheet.palmLength
        }
        for (a, b) in [("SI4", "TE3"), ("SI4", "SI3")] {
            let want = anatomySeparation(a, b), got = simd_distance(uv[a]!, uv[b]!)
            XCTAssertGreaterThan(got, want * 0.75,
                                 "\(a) and \(b) render \(got) apart but the anatomy asks for \(want) — the layout is collapsing")
        }
        // TE3 and SI3 ARE genuinely close (both proximal to the 4th/5th MCP heads) — but not equal.
        XCTAssertGreaterThan(simd_distance(te3, si3), 0.02, "TE3 and SI3 are the same point")
        // …and SI4 must stay PROXIMAL of both, which is the ordering the original defect destroyed.
        XCTAssertLessThan(HandAnatomy.spots["SI4"]!.along, HandAnatomy.spots["SI3"]!.along - 0.3,
                          "SI4 is at the 5th metacarpal BASE; SI3 is at its neck, half a palm distal")
    }
}
