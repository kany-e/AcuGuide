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

    // Front of the body is −y; push channels a little toward the front surface so they read as
    // lines lying ON the limb rather than through its centre.
    private static let frontArm: Float = -0.035
    private static let frontLeg: Float = -0.045
    private static let frontTorso: Float = -0.095   // front surface of the torso
    private static let backTorso: Float = 0.080     // back surface (du)

    // MARK: Channels

    // Build all six channels under one container node (added to the body mesh, raw mesh coords).
    static func channels() -> SCNNode {
        let root = SCNNode()
        let inner: Float = 0.012, outer: Float = 0.016
        for side in [Side.right, .left] {
            let s = side.sign
            // Arm chain: start a bit down the upper arm (lerp 0.24), then elbow → wrist.
            let arm = [
                mix(b(side.k("UpperArm")), b(side.k("LowerArm")), 0.24),
                b(side.k("LowerArm")), b(side.k("Hand")),
            ]
            // Lung = medial (toward midline), LI = lateral (away) — sign flips per side.
            root.addChildNode(channel(arm, dx: -s * inner, dy: frontArm, meridian: "lung"))
            root.addChildNode(channel(arm, dx:  s * outer, dy: frontArm, meridian: "li"))
            // Leg chain: start down the thigh (0.20), knee, then just above the ankle (0.7).
            let leg = [
                mix(b(side.k("UpperLeg")), b(side.k("LowerLeg")), 0.20),
                b(side.k("LowerLeg")),
                mix(b(side.k("LowerLeg")), b(side.k("Foot")), 0.7),
            ]
            root.addChildNode(channel(leg, dx: -s * inner, dy: frontLeg, meridian: "stomach"))
            root.addChildNode(channel(leg, dx:  s * outer * 1.6, dy: frontLeg * 0.6, meridian: "gb"))
        }
        // Torso midlines: ren (front) and du (back). Flatten to the surface plane in y.
        let spine = [b("Hips"), b("Spine"), b("Chest"), b("Neck")]
        root.addChildNode(channel(spine.map { [$0.x, frontTorso, $0.z] }, dx: 0, dy: 0, meridian: "ren"))
        root.addChildNode(channel(spine.map { [$0.x, backTorso,  $0.z] }, dx: 0, dy: 0, meridian: "du"))
        return root
    }

    enum Side {
        case right, left
        var sign: Float { self == .right ? -1 : 1 }      // right side is −x
        var suffix: String { self == .right ? "R" : "L" }
        func k(_ base: String) -> String { base + suffix }
    }

    // One channel: offset the control points, then densify → Laplacian-smooth → centripetal
    // Catmull-Rom so the line flows along the limb contour (not a rigid zig-zag), and lay a thin
    // meridian-colored tube + a softer, wider halo along the smoothed curve (≈70 samples).
    private static func channel(_ pts: [SIMD3<Float>], dx: Float, dy: Float, meridian: String) -> SCNNode {
        let offset = pts.map { SIMD3<Float>($0.x + dx, $0.y + dy, $0.z) }
        let dense = densify(offset, perSegment: 6)
        let smoothed = smoothPts(dense, iterations: 3)
        let path = catmullRom(smoothed, perSegment: 6)
        let mats = channelMaterials(meridian)
        let node = SCNNode()
        for i in 0 ..< path.count - 1 {
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0075, material: mats.halo))
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0032, material: mats.core))
        }
        return node
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
        Region(id: "abdomen", zh: "腹",   en: "Abdomen", anchor: off(b("Hips"),     0.02, -0.12, -0.02), center: b("Hips"),       radius: 0.17, isHand: false),
        Region(id: "arm",     zh: "臂",   en: "Arm",     anchor: off(b("LowerArmL"), 0.06, -0.05, 0.02), center: b("LowerArmL"),  radius: 0.16, isHand: false),
        Region(id: "leg",     zh: "腿",   en: "Leg",     anchor: off(b("LowerLegL"), 0.05, -0.06, 0.00), center: b("LowerLegL"),  radius: 0.20, isHand: false),
        Region(id: "foot",    zh: "足",   en: "Foot",    anchor: off(b("FootL"),     0.03, -0.05, -0.02), center: b("FootL"),     radius: 0.11, isHand: false),
        Region(id: "hand",    zh: "手部", en: "Hand",    anchor: off(b("HandR"),     0,    -0.05,  0.00), center: handCenter,     radius: 0.12, isHand: true),
    ]
    // Centre of the right hand/forearm marker cluster (between wrist and fingertips).
    private static let handCenter: SIMD3<Float> = [-0.355, -0.06, 0.86]
    private static func off(_ p: SIMD3<Float>, _ dx: Float, _ dy: Float, _ dz: Float) -> SIMD3<Float> {
        [p.x + dx, p.y + dy, p.z + dz]
    }

    // MARK: 3D acupoint markers (on the RIGHT hand / forearm)

    // Approximated from the GLB hand/forearm bones to the sourced surfaces (see Acupoints.swift):
    // dorsal points sit on the back (+y), palmar on the front (−y); forearm points (PC6/SJ5) ride
    // up toward the elbow. LI4 is excluded. Tuned visually against the small low-poly hand.
    struct AcuMarker { let id: String; let meridian: String; let pos: SIMD3<Float> }
    static let acuMarkers: [AcuMarker] = [
        AcuMarker(id: "TE3", meridian: "sj",    pos: [-0.370, -0.043, 0.883]),  // dorsal, 4th/5th MC groove
        AcuMarker(id: "SI3", meridian: "si",    pos: [-0.398, -0.055, 0.848]),  // ulnar edge, prox. 5th MC
        AcuMarker(id: "PC8", meridian: "pc",    pos: [-0.365, -0.088, 0.885]),  // palmar, centre of palm
        AcuMarker(id: "HT7", meridian: "heart", pos: [-0.352, -0.075, 0.922]),  // palmar wrist, ulnar
        AcuMarker(id: "PC6", meridian: "pc",    pos: [-0.323, -0.050, 1.002]),  // palmar forearm (2 cun up)
        AcuMarker(id: "SJ5", meridian: "sj",    pos: [-0.323, -0.004, 1.002]),  // dorsal forearm, opp. PC6
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
            node.addChildNode(SCNNode(geometry: halo))
            node.simdPosition = m.pos
            node.name = "acu:" + m.id
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
