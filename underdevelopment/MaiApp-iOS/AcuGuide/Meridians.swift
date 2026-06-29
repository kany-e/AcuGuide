import SceneKit
import simd
import SwiftUI   // Color(hex:) + UIColor(Color)

// Meridian channels + region anchors for the 3D body — native port of Body3D.jsx's
// Channels/ChannelLine and the region anchors. Routes are taken from the GLB's actual
// skeleton (bind-pose bone positions, precomputed in the model's local mesh space: z-up,
// 0=feet…1.78=head, x=left/right with the RIGHT side at −x, front of the body at −y).
//
// Per the web, the channels are NOT drawn in per-meridian colors — every channel is a single
// subtle ink line (core #363c2f, soft halo #5b6551) so it "sits on the body". We keep that.
enum BodyAtlas {

    // ---- Bind-pose bone positions in mesh space (from model.glb inverseBindMatrices) ----
    static let bone: [String: SIMD3<Float>] = [
        "Head":  [0,  0.0115, 1.5631], "Neck": [0, 0.0300, 1.4869], "Chest": [0, 0.0000, 1.2792],
        "Spine": [0, -0.0161, 1.0531], "Hips": [0, 0.0000, 0.8838],
        "ShoulderR": [-0.0669, 0.0300, 1.4523], "UpperArmR": [-0.1800, 0.0115, 1.3761],
        "LowerArmR": [-0.2801, 0.0236, 1.1508], "HandR": [-0.3460, -0.0552, 0.9217],
        "ShoulderL": [ 0.0669, 0.0300, 1.4523], "UpperArmL": [ 0.1800, 0.0115, 1.3761],
        "LowerArmL": [ 0.2802, 0.0236, 1.1508], "HandL": [ 0.3460, -0.0552, 0.9217],
        "UpperLegR": [-0.0877, -0.0161, 0.9077], "LowerLegR": [-0.1104, 0.0050, 0.5216], "FootR": [-0.1361, 0.0438, 0.0747],
        "UpperLegL": [ 0.0877, -0.0162, 0.9077], "LowerLegL": [ 0.1104, 0.0050, 0.5216], "FootL": [ 0.1361, 0.0438, 0.0747],
    ]
    static func b(_ k: String) -> SIMD3<Float> { bone[k] ?? .zero }

    // MARK: Channels

    // Build all six channels under one container node, routed along the FULL skeleton chains and
    // projected onto the body surface (raycast against `mesh`). Added to the body mesh (raw coords).
    static func channels(on mesh: SCNNode) -> SCNNode {
        let root = SCNNode()
        let inner: Float = 0.012, outer: Float = 0.016
        for side in [Side.right, .left] {
            let s = side.sign
            // Full arm chain off the skeleton: shoulder → upper arm → elbow → wrist.
            let arm = [b(side.k("Shoulder")), b(side.k("UpperArm")), b(side.k("LowerArm")), b(side.k("Hand"))]
            root.addChildNode(channel(arm, dx: -s * inner, meridian: "lung",    mesh: mesh, front: true))
            root.addChildNode(channel(arm, dx:  s * outer, meridian: "li",      mesh: mesh, front: true))
            // Full leg chain: hip → thigh → knee → ankle.
            let leg = [b(side.k("UpperLeg")), b(side.k("LowerLeg")), mix(b(side.k("LowerLeg")), b(side.k("Foot")), 0.7)]
            root.addChildNode(channel(leg, dx: -s * inner, meridian: "stomach", mesh: mesh, front: true))
            root.addChildNode(channel(leg, dx:  s * outer * 1.3, meridian: "gb", mesh: mesh, front: true))
        }
        // Torso midlines: ren (front) and du (back).
        let spine = [b("Hips"), b("Spine"), b("Chest"), b("Neck")]
        root.addChildNode(channel(spine, dx: 0, meridian: "ren", mesh: mesh, front: true))
        root.addChildNode(channel(spine, dx: 0, meridian: "du",  mesh: mesh, front: false))
        return root
    }

    enum Side {
        case right, left
        var sign: Float { self == .right ? -1 : 1 }      // right side is −x
        var suffix: String { self == .right ? "R" : "L" }
        func k(_ base: String) -> String { base + suffix }
    }

    // One channel: lateral-offset the skeleton control points, densify → Laplacian-smooth →
    // centripetal Catmull-Rom, PROJECT each sample onto the body surface (so it lies ON the limb,
    // not beside it), then lay a thin meridian-colored tube + halo + gap-filling joints, drawn on
    // top of the translucent body (high renderingOrder) so it never blends away at grazing angles.
    private static func channel(_ pts: [SIMD3<Float>], dx: Float, meridian: String,
                                mesh: SCNNode, front: Bool) -> SCNNode {
        let offset = pts.map { SIMD3<Float>($0.x + dx, $0.y, $0.z) }
        let dense = densify(offset, perSegment: 6)
        let smoothed = smoothPts(dense, iterations: 3)
        let curve = catmullRom(smoothed, perSegment: 6)
        let path = projectAll(curve, mesh: mesh, front: front)
        let mats = channelMaterials(meridian)
        let node = SCNNode()
        node.name = "mer:" + meridian              // tap hit-test resolves the channel → meridian card
        for i in 0 ..< path.count - 1 {
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0075, material: mats.halo))
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0032, material: mats.core))
        }
        // Small joint spheres fill the V-gaps where straight segments meet at bends.
        for p in path {
            let s = SCNNode(geometry: SCNSphere(radius: 0.0032))
            s.geometry?.firstMaterial = mats.core
            s.simdPosition = p
            s.renderingOrder = 12
            node.addChildNode(s)
        }
        // Wide, fully-transparent hit-proxy tubes (children of the named node) so a tap NEAR the
        // hairline channel still selects the meridian — the visible tube alone is too thin to hit.
        let step = max(1, path.count / 16)
        var i = 0
        while i + step < path.count {
            node.addChildNode(tube(from: path[i], to: path[i + step], radius: 0.022, material: hitProxyMaterial()))
            i += step
        }
        return node
    }

    // Project a whole path onto the body surface (raycast each sample along the depth axis). For
    // samples that MISS the thin limb, interpolate the surface depth from the neighbours that hit
    // (clamped at the ends), so a single miss never injects an off-surface vertex beside the limb.
    private static func projectAll(_ pts: [SIMD3<Float>], mesh: SCNNode, front: Bool) -> [SIMD3<Float>] {
        let ys = pts.map { projectY($0, mesh: mesh, front: front) }
        guard ys.contains(where: { $0 != nil }) else { return pts }   // no hit anywhere → keep raw
        let filled = fillGaps(ys)
        return zip(pts, filled).map { SIMD3<Float>($0.x, $1, $0.z) }
    }

    // The surface depth (y) at a sample, or nil if the ray misses the limb at that (x,z).
    private static func projectY(_ p: SIMD3<Float>, mesh: SCNNode, front: Bool) -> Float? {
        let depth: Float = 0.18
        let a = SCNVector3(p.x, front ? p.y - depth : p.y + depth, p.z)   // start outside the body
        let bb = SCNVector3(p.x, front ? p.y + depth : p.y - depth, p.z)  // through to the far side
        let hits = mesh.hitTestWithSegment(from: a, to: bb, options: [
            SCNHitTestOption.backFaceCulling.rawValue: false,
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
        ])
        guard let h = hits.first else { return nil }
        return Float(h.localCoordinates.y) + (front ? -0.006 : 0.006)
    }

    // Linear-interpolate the nil (missed) entries between known values; clamp leading/trailing nils.
    private static func fillGaps(_ ys: [Float?]) -> [Float] {
        let n = ys.count
        var out = [Float](repeating: 0, count: n)
        var lastIdx = -1
        var lastVal: Float = 0
        for i in 0 ..< n {
            guard let v = ys[i] else { continue }
            if lastIdx < 0 {
                for j in 0 ..< i { out[j] = v }                      // leading nils → first value
            } else if i - lastIdx > 1 {
                for j in (lastIdx + 1) ..< i {                       // interior nils → interpolate
                    let t = Float(j - lastIdx) / Float(i - lastIdx)
                    out[j] = lastVal + (v - lastVal) * t
                }
            }
            out[i] = v; lastIdx = i; lastVal = v
        }
        if lastIdx < n - 1 { for j in (lastIdx + 1) ..< n { out[j] = lastVal } }  // trailing nils
        return out
    }

    // Linear subdivision — more control points before smoothing.
    private static func densify(_ p: [SIMD3<Float>], perSegment: Int) -> [SIMD3<Float>] {
        guard p.count >= 2 else { return p }
        var out: [SIMD3<Float>] = []
        for i in 0 ..< p.count - 1 {
            for s in 0 ..< perSegment {
                let t = Float(s) / Float(perSegment)
                out.append(p[i] + (p[i + 1] - p[i]) * t)
            }
        }
        out.append(p[p.count - 1])
        return out
    }

    // Laplacian smoothing (web smoothPts): average each interior point with its neighbors, keeping
    // the endpoints pinned so the channel still starts/ends on the limb.
    private static func smoothPts(_ p: [SIMD3<Float>], iterations: Int) -> [SIMD3<Float>] {
        guard p.count >= 3 else { return p }
        var pts = p
        for _ in 0 ..< iterations {
            var next = pts
            for i in 1 ..< pts.count - 1 {
                next[i] = (pts[i - 1] + pts[i] * 2 + pts[i + 1]) * 0.25
            }
            pts = next
        }
        return pts
    }

    // MARK: Region anchors (for the projected SwiftUI labels)

    // `center` is the body point the camera frames on zoom; `radius` is that part's extent (so the
    // dolly distance fills the view with the PART, not the whole figure). `anchor` is where the
    // label floats (pushed to the front −y and nudged outward so the small labels don't pile up).
    struct Region: Identifiable {
        let id: String; let zh: String; let en: String
        let anchor: SIMD3<Float>; let center: SIMD3<Float>; let radius: Float; let isHand: Bool
    }

    static let regions: [Region] = [
        Region(id: "head",    zh: "头部", en: "Head",    anchor: off(b("Head"),     0,    -0.13,  0.05), center: b("Head"),       radius: 0.13, isHand: false),
        Region(id: "chest",   zh: "胸",   en: "Chest",   anchor: off(b("Chest"),   -0.02, -0.12,  0.02), center: b("Chest"),      radius: 0.17, isHand: false),
        // Belly sits ABOVE the hip bone (between Hips 0.884 and Spine 1.053); the label previously
        // rode the hip joint and read low, so anchor it on the navel level (~0.965) and nudge up.
        Region(id: "abdomen", zh: "腹",   en: "Abdomen", anchor: off(belly,          0.02, -0.12,  0.03), center: belly,           radius: 0.18, isHand: false),
        Region(id: "arm",     zh: "臂",   en: "Arm",     anchor: off(b("LowerArmL"), 0.06, -0.05, 0.02), center: b("LowerArmL"),  radius: 0.16, isHand: false),
        Region(id: "leg",     zh: "腿",   en: "Leg",     anchor: off(b("LowerLegL"), 0.05, -0.06, 0.00), center: b("LowerLegL"),  radius: 0.20, isHand: false),
        Region(id: "foot",    zh: "足",   en: "Foot",    anchor: off(b("FootL"),     0.03, -0.05, -0.02), center: b("FootL"),     radius: 0.11, isHand: false),
        Region(id: "hand",    zh: "手部", en: "Hand",    anchor: off(b("HandR"),     0,    -0.05,  0.00), center: handCenter,     radius: 0.12, isHand: true),
    ]
    // Centre of the right hand/forearm marker cluster (between wrist and fingertips).
    // Centroid of the four hand markers (TE3/SI3/PC8/HT7) so the hand zoom frames the hand itself.
    private static let handCenter: SIMD3<Float> = [-0.371, -0.065, 0.884]
    // Navel-level belly point (between Hips 0.884 and Spine 1.053), front of the torso.
    private static let belly: SIMD3<Float> = [0, -0.005, 0.965]
    private static func off(_ p: SIMD3<Float>, _ dx: Float, _ dy: Float, _ dz: Float) -> SIMD3<Float> {
        [p.x + dx, p.y + dy, p.z + dz]
    }

    // MARK: 3D acupoint markers (on the RIGHT hand / forearm)

    // Approximated from the GLB hand/forearm bones to the sourced surfaces (see Acupoints.swift):
    // dorsal points sit on the back (+y), palmar on the front (−y); forearm points (PC6/SJ5) ride
    // up toward the elbow. LI4 is excluded. Tuned visually against the small low-poly hand.
    struct AcuMarker { let id: String; let meridian: String; let pos: SIMD3<Float> }
    static let acuMarkers: [AcuMarker] = [
        // Hand / forearm (right hand). ──────────────────────────────────────────────────────────
        AcuMarker(id: "TE3", meridian: "sj",    pos: [-0.370, -0.043, 0.883]),  // dorsal, 4th/5th MC groove
        AcuMarker(id: "SI3", meridian: "si",    pos: [-0.398, -0.055, 0.848]),  // ulnar edge, prox. 5th MC
        AcuMarker(id: "PC8", meridian: "pc",    pos: [-0.365, -0.088, 0.885]),  // palmar, centre of palm
        AcuMarker(id: "HT7", meridian: "heart", pos: [-0.352, -0.075, 0.922]),  // palmar wrist, ulnar
        AcuMarker(id: "PC6", meridian: "pc",    pos: [-0.323, -0.050, 1.002]),  // palmar forearm (2 cun up)
        AcuMarker(id: "SJ5", meridian: "sj",    pos: [-0.323, -0.004, 1.002]),  // dorsal forearm, opp. PC6
        // Body-region points — first-pass anatomical estimates in mesh space (z-up, right=−x,
        // front=−y), placed off the GLB skeleton + WHO surface hints. Markers draw on top of the
        // body, so they read even when slightly off-surface; fine-tune visually like TE3 if needed.
        // Head & face ─────────────────────────────────────────────────────────────────────────
        AcuMarker(id: "EX-HN3", meridian: "extra", pos: [ 0.000, -0.085, 1.630]), // glabella, front midline
        AcuMarker(id: "EX-HN5", meridian: "extra", pos: [-0.080, -0.025, 1.630]), // right temple (lateral)
        AcuMarker(id: "GV20",   meridian: "du",    pos: [ 0.000,  0.000, 1.760]), // vertex (top of head)
        AcuMarker(id: "EX-HN1", meridian: "extra", pos: [ 0.000, -0.035, 1.748]), // around the vertex
        // Chest ───────────────────────────────────────────────────────────────────────────────
        AcuMarker(id: "CV17",   meridian: "ren",    pos: [ 0.000, -0.100, 1.220]), // mid-sternum
        AcuMarker(id: "KI27",   meridian: "kidney", pos: [-0.065, -0.090, 1.350]), // under right collarbone
        // Abdomen ───────────────────────────────────────────────────────────────────────────────
        AcuMarker(id: "CV12",   meridian: "ren",     pos: [ 0.000, -0.100, 1.080]), // upper abdomen midline
        AcuMarker(id: "ST25",   meridian: "stomach", pos: [-0.060, -0.100, 0.965]), // right of navel
        // Arm (right elbow + wrist) ─────────────────────────────────────────────────────────────
        AcuMarker(id: "LI11",   meridian: "li",    pos: [-0.295, -0.010, 1.155]), // lateral elbow crease
        AcuMarker(id: "LU5",    meridian: "lung",  pos: [-0.265, -0.050, 1.150]), // anterior elbow crease
        AcuMarker(id: "TE4",    meridian: "sj",    pos: [-0.345,  0.005, 0.960]), // dorsal wrist
        AcuMarker(id: "PC7",    meridian: "pc",    pos: [-0.350, -0.085, 0.952]), // palmar wrist crease
        // Leg (right knee + lower leg) ──────────────────────────────────────────────────────────
        AcuMarker(id: "ST36",   meridian: "stomach", pos: [-0.115, -0.060, 0.400]), // below knee, front-lat
        AcuMarker(id: "GB34",   meridian: "gb",      pos: [-0.135, -0.045, 0.480]), // below knee, lateral
        AcuMarker(id: "SP10",   meridian: "spleen",  pos: [-0.075, -0.055, 0.620]), // inner thigh, above knee
        AcuMarker(id: "ST34",   meridian: "stomach", pos: [-0.135, -0.060, 0.620]), // outer thigh, above knee
        AcuMarker(id: "ST35",   meridian: "stomach", pos: [-0.125, -0.065, 0.500]), // outer knee eye
        // Foot & ankle (right) ──────────────────────────────────────────────────────────────────
        AcuMarker(id: "LR3",    meridian: "liver",   pos: [-0.120, -0.100, 0.060]), // dorsum, 1st/2nd MT
        AcuMarker(id: "ST44",   meridian: "stomach", pos: [-0.130, -0.135, 0.045]), // dorsum, 2nd/3rd toe
        AcuMarker(id: "KI1",    meridian: "kidney",  pos: [-0.120, -0.075, 0.025]), // sole, anterior third
        AcuMarker(id: "KI3",    meridian: "kidney",  pos: [-0.105,  0.020, 0.110]), // inner ankle
    ]

    // Small glowing meridian-colored spheres; node names ("acu:<id>") let a tap hit-test identify
    // the point. Added to the mesh (raw coords) so they ride the body through pose + spin.
    static func markers() -> SCNNode {
        let root = SCNNode()
        for m in acuMarkers {
            let col = UIColor(MeridianColors.color(m.meridian))
            let halo = SCNSphere(radius: 0.014); halo.firstMaterial = glowMat(col, 0.22)
            let core = SCNSphere(radius: 0.0075); core.firstMaterial = glowMat(col, 1.0)
            let node = SCNNode(geometry: core)
            let h = SCNNode(geometry: halo); h.renderingOrder = 14
            node.addChildNode(h)
            node.simdPosition = m.pos
            node.name = "acu:" + m.id
            node.renderingOrder = 15            // markers pop above the body + channels, so the hand
                                                // is always readable even when it overlaps the torso
            root.addChildNode(node)
        }
        return root
    }

    private static func glowMat(_ color: UIColor, _ opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.transparency = opacity
        m.readsFromDepthBuffer = false        // always visible on top of the body
        m.writesToDepthBuffer = false
        return m
    }

    // MARK: helpers

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    private static func catmullRom(_ p: [SIMD3<Float>], perSegment: Int) -> [SIMD3<Float>] {
        guard p.count >= 2 else { return p }
        var out: [SIMD3<Float>] = []
        let n = p.count
        for i in 0 ..< n - 1 {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, n - 1)]
            for s in 0 ..< perSegment {
                let t = Float(s) / Float(perSegment)
                let t2 = t * t, t3 = t2 * t
                let c0 = p1 * 2
                let c1 = p2 - p0
                let c2 = p0 * 2 - p1 * 5 + p2 * 4 - p3
                let c3 = p3 - p0 + p1 * 3 - p2 * 3
                var v = c0
                v += c1 * t
                v += c2 * t2
                v += c3 * t3
                out.append(v * 0.5)
            }
        }
        out.append(p[n - 1])
        return out
    }

    // One colored core + a softer wider halo per meridian (MERIDIAN_COLORS). Created once per
    // channel and shared across its segments.
    private static func channelMaterials(_ meridian: String) -> (core: SCNMaterial, halo: SCNMaterial) {
        let col = UIColor(MeridianColors.color(meridian))
        return (lineMaterial(col, 0.90), lineMaterial(col, 0.22))
    }

    // Invisible material for the wide tap-proxy tubes: never drawn, but still returned by hitTest.
    private static func hitProxyMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.transparency = 0.0
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    private static func lineMaterial(_ color: UIColor, _ opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant            // flat color, unaffected by scene lighting
        m.diffuse.contents = color
        m.transparency = opacity
        m.isDoubleSided = true
        m.writesToDepthBuffer = false          // sits on top of the translucent body cleanly
        m.readsFromDepthBuffer = false
        return m
    }

    private static func tube(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, material: SCNMaterial) -> SCNNode {
        let d = b - a
        let h = simd_length(d)
        guard h > 1e-6 else { return SCNNode() }
        let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(h))
        cyl.radialSegmentCount = 6
        cyl.firstMaterial = material
        let node = SCNNode(geometry: cyl)
        node.renderingOrder = 12               // draw on top of the translucent body
        node.simdPosition = (a + b) / 2
        let dir = d / h
        let yAxis = SIMD3<Float>(0, 1, 0)
        // Quaternion rotating +Y onto the segment direction (guard the antiparallel case).
        if simd_dot(yAxis, dir) < -0.9999 {
            node.simdOrientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        } else {
            node.simdOrientation = simd_quatf(from: yAxis, to: dir)
        }
        return node
    }
}
