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
            root.addChildNode(channel(arm, dx: -s * inner, dy: frontArm))   // lung
            root.addChildNode(channel(arm, dx:  s * outer, dy: frontArm))   // large intestine
            // Leg chain: start down the thigh (0.20), knee, then just above the ankle (0.7).
            let leg = [
                mix(b(side.k("UpperLeg")), b(side.k("LowerLeg")), 0.20),
                b(side.k("LowerLeg")),
                mix(b(side.k("LowerLeg")), b(side.k("Foot")), 0.7),
            ]
            root.addChildNode(channel(leg, dx: -s * inner, dy: frontLeg))   // stomach (front-medial)
            root.addChildNode(channel(leg, dx:  s * outer * 1.6, dy: frontLeg * 0.6)) // gallbladder (lateral)
        }
        // Torso midlines: ren (front) and du (back). Flatten to the surface plane in y.
        let spine = [b("Hips"), b("Spine"), b("Chest"), b("Neck")]
        root.addChildNode(channel(spine.map { [$0.x, frontTorso, $0.z] }, dx: 0, dy: 0))  // ren
        root.addChildNode(channel(spine.map { [$0.x, backTorso,  $0.z] }, dx: 0, dy: 0))  // du
        return root
    }

    enum Side {
        case right, left
        var sign: Float { self == .right ? -1 : 1 }      // right side is −x
        var suffix: String { self == .right ? "R" : "L" }
        func k(_ base: String) -> String { base + suffix }
    }

    // One channel: offset the control points, smooth (Catmull-Rom), and lay a thin ink tube +
    // a softer, slightly wider halo along it.
    private static func channel(_ pts: [SIMD3<Float>], dx: Float, dy: Float) -> SCNNode {
        let offset = pts.map { SIMD3<Float>($0.x + dx, $0.y + dy, $0.z) }
        let path = catmullRom(offset, perSegment: 10)
        let node = SCNNode()
        for i in 0 ..< path.count - 1 {
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0075, material: haloMat))
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0030, material: coreMat))
        }
        return node
    }

    // MARK: Region anchors (for the projected SwiftUI labels)

    struct Region: Identifiable { let id: String; let zh: String; let en: String; let anchor: SIMD3<Float>; let isHand: Bool }

    // Anchors are pushed to the front (−y) so the labels read in front of the body, and nudged
    // outward (lateral +x on the LEFT side / up for head) so the small labels don't pile up on
    // the centerline. They rotate with the body and hide on the far side (see the projector).
    static let regions: [Region] = [
        Region(id: "head",    zh: "头部", en: "Head",    anchor: off(b("Head"),       0,     -0.13,  0.05), isHand: false),
        Region(id: "chest",   zh: "胸",   en: "Chest",   anchor: off(b("Chest"),     -0.02,  -0.12,  0.02), isHand: false),
        Region(id: "abdomen", zh: "腹",   en: "Abdomen", anchor: off(b("Hips"),        0.02,  -0.12, -0.02), isHand: false),
        Region(id: "arm",     zh: "臂",   en: "Arm",     anchor: off(b("LowerArmL"),   0.06,  -0.05,  0.02), isHand: false),
        Region(id: "leg",     zh: "腿",   en: "Leg",     anchor: off(b("LowerLegL"),   0.05,  -0.06,  0.00), isHand: false),
        Region(id: "foot",    zh: "足",   en: "Foot",    anchor: off(b("FootL"),       0.03,  -0.05, -0.02), isHand: false),
        Region(id: "hand",    zh: "手部", en: "Hand",    anchor: off(b("HandR"),       0,     -0.05,  0.00), isHand: true),
    ]
    private static func off(_ p: SIMD3<Float>, _ dx: Float, _ dy: Float, _ dz: Float) -> SIMD3<Float> {
        [p.x + dx, p.y + dy, p.z + dz]
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

    private static let coreMat: SCNMaterial = inkMaterial(hex: "#363c2f", opacity: 0.85)
    private static let haloMat: SCNMaterial = inkMaterial(hex: "#5b6551", opacity: 0.16)

    private static func inkMaterial(hex: String, opacity: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant            // flat ink, unaffected by scene lighting
        m.diffuse.contents = UIColor(Color(hex: hex))
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
