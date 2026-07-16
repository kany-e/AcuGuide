import SceneKit
import simd
import SwiftUI   // Color(hex:) + UIColor(Color)

// Meridian channels + region anchors for the 3D body — native port of Body3D.jsx's
// Channels/ChannelLine and the region anchors. Routes are taken from the GLB's actual
// skeleton (bind-pose bone positions, precomputed in the model's local mesh space: z-up,
// 0=feet…1.78=head, x=left/right with the RIGHT side at −x, front of the body at −y).
//
// STYLE (shanshui, user-directed): channels are thin INK strokes — a dark ink core tinted just
// faintly toward each meridian's hue (so a selected channel is still tellable apart) with a
// soft, wider emissive ink WASH bleeding off it, like a brush line on damp paper. Acupoints sit
// on the strokes as slightly larger ink dots. (The earlier bright per-meridian coloring read too
// compact/synthetic against the shanshui theme; the UI cards/chips keep the full meridian
// colors — only the 3D body goes ink.)
enum BodyAtlas {

    // Hit-test categories. The body SURFACE keeps SceneKit's default category (1) and is the ONLY
    // legal target for the surface-snap raycasts below; everything decorative that gets parented
    // under the mesh — channel tubes, their invisible 0.03-radius hit-proxy cylinders, joint
    // spheres, acupoint markers — is category 2. Body3DView adds channels() to the mesh BEFORE
    // markers() snap, so without this mask a marker's snap ray could land on a tube/proxy (up to
    // ~0.03 proud of the skin) instead of the body. The mask pins the invariant regardless of
    // build order. (Tap hit-tests are unaffected: view.hitTest without a categoryBitMask option
    // matches every category.)
    static let surfaceCategory = 1
    static let decorationCategory = 2

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

    // Build the channels under one container node, routed along the FULL skeleton chains and
    // projected onto the body surface (raycast against `mesh`). Added to the body mesh (raw coords).
    //
    // Anatomy (Atlas of Acupuncture Points pathways): each arm carries three YIN channels on the
    // anterior/palmar surface (front) — Lung radial, Pericardium middle, Heart ulnar — and three
    // YANG channels on the posterior/dorsal surface (back) — Large Intestine radial, Sanjiao middle,
    // Small Intestine ulnar. This puts every coached hand point on its own drawn channel (TE3/SJ5/
    // TE4 on Sanjiao-dorsal, SI3 on Small-Intestine-dorsal, PC6/PC7/PC8 on Pericardium-palmar,
    // HT7 on Heart-palmar). Legs keep Stomach (front-LATERAL — corrected from the old inner-leg
    // routing) and Gallbladder (lateral). Torso keeps Ren (front midline) and Du (back midline).
    static func channels(on mesh: SCNNode) -> SCNNode {
        let root = SCNNode()
        let ax: Float = 0.011, outer: Float = 0.016
        for side in [Side.right, .left] {
            let s = side.sign
            // Both sides are tappable so a tap on whichever limb faces you opens the meridian; the
            // selection reveals that meridian's points (modeled on the right) regardless of side.
            // Arm chain shoulder → upper arm → elbow → WRIST (stops at 0.7 toward the hand so the arm
            // channels' tap-proxies don't blanket the Hand region label). The stroke is bone-routed and
            // smooth; the acupoint DOTS sit on/near it (drawn separately as markers). (Threading the
            // stroke THROUGH the hand dots was tried in R14.15/16 and twisted — the mitten hand's crude
            // mesh makes the depth projection unreliable there; reverted to the stable bone route.)
            let wristEnd = mix(b(side.k("LowerArm")), b(side.k("Hand")), 0.7)
            let arm = [b(side.k("Shoulder")), b(side.k("UpperArm")), b(side.k("LowerArm")), wristEnd]
            // Yin — anterior (palmar) surface: radial LU, middle PC, ulnar HT.
            root.addChildNode(channel(arm, dx: -s * ax, meridian: "lung",  mesh: mesh, front: true))
            root.addChildNode(channel(arm, dx:  0,      meridian: "pc",    mesh: mesh, front: true))
            root.addChildNode(channel(arm, dx:  s * ax, meridian: "heart", mesh: mesh, front: true))
            // Yang — posterior (dorsal) surface: radial LI, middle SJ, ulnar SI.
            root.addChildNode(channel(arm, dx: -s * ax, meridian: "li",    mesh: mesh, front: false))
            root.addChildNode(channel(arm, dx:  0,      meridian: "sj",    mesh: mesh, front: false))
            root.addChildNode(channel(arm, dx:  s * ax, meridian: "si",    mesh: mesh, front: false))
            // Full leg chain: hip → thigh → knee → ankle.
            let leg = [b(side.k("UpperLeg")), b(side.k("LowerLeg")), mix(b(side.k("LowerLeg")), b(side.k("Foot")), 0.7)]
            root.addChildNode(channel(leg, dx: s * outer * 0.8, meridian: "stomach", mesh: mesh, front: true)) // front-lateral
            root.addChildNode(channel(leg, dx: s * outer * 1.5, meridian: "gb",      mesh: mesh, front: true)) // lateral / side
        }
        // Torso midlines: ren (front) and du (back) — single + central, always tappable.
        let spine = [b("Hips"), b("Spine"), b("Chest"), b("Neck")]
        root.addChildNode(channel(spine, dx: 0, meridian: "ren", mesh: mesh, front: true))
        root.addChildNode(channel(spine, dx: 0, meridian: "du",  mesh: mesh, front: false))
        // Everything built above is decoration: exclude it from the surface-snap raycasts (see
        // surfaceCategory). categoryBitMask is NOT inherited, so stamp every node in the tree.
        root.enumerateHierarchy { n, _ in n.categoryBitMask = decorationCategory }
        return root
    }

    enum Side {
        case right, left
        var sign: Float { self == .right ? -1 : 1 }      // right side is −x
        var suffix: String { self == .right ? "R" : "L" }
        func k(_ base: String) -> String { base + suffix }
    }

    // One channel: lateral-offset the skeleton control points, densify → Laplacian-smooth → Catmull-Rom,
    // PROJECT each sample onto the body surface (so it lies ON the limb), then lay a thin meridian-tinted
    // ink tube + soft wash halo + gap-filling joint beads, drawn on top of the translucent body (high
    // renderingOrder) so it never blends away at grazing angles. Bone-routed and SMOOTH — this is the
    // known-good R14.14 stroke. (R14.15/16 tried threading it through the acupoint dots and it twisted:
    // extending the stroke into the crude mitten hand made the depth projection unreliable. The dots are
    // drawn as separate markers; making the line pass exactly through them is a screenshot-verified TODO.)
    private static func channel(_ pts: [SIMD3<Float>], dx: Float, meridian: String,
                                mesh: SCNNode, front: Bool, tappable: Bool = true) -> SCNNode {
        let offset = pts.map { SIMD3<Float>($0.x + dx, $0.y, $0.z) }
        let dense = densify(offset, perSegment: 6)
        let smoothed = smoothPts(dense, iterations: 3)
        let curve = catmullRom(smoothed, perSegment: 6)
        let path = projectAll(curve, mesh: mesh, front: front)
        let mats = channelMaterials(meridian)
        let node = SCNNode()
        if tappable { node.name = "mer:" + meridian }   // tap hit-test resolves the channel → card
        // Thin ink stroke (core) + a wider soft wash bleeding off it (halo) — brush on damp paper.
        for i in 0 ..< path.count - 1 {
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0052, material: mats.halo))
            node.addChildNode(tube(from: path[i], to: path[i + 1], radius: 0.0022, material: mats.core))
        }
        // Small joint spheres fill the V-gaps where straight segments meet at bends.
        for p in path {
            let s = SCNNode(geometry: SCNSphere(radius: 0.0022))
            s.geometry?.firstMaterial = mats.core
            s.simdPosition = p
            s.renderingOrder = 12
            node.addChildNode(s)
        }
        // Modest, fully-transparent hit-proxy tubes (children of the named node) so a tap near the
        // hairline channel still selects it — but small enough not to swallow taps meant for the
        // region labels / empty body. Only added when the channel is tappable.
        if tappable {
            let step = max(1, path.count / 16)
            var i = 0
            while i + step < path.count {
                node.addChildNode(tube(from: path[i], to: path[i + step], radius: 0.03, material: hitProxyMaterial()))
                i += step
            }
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
            SCNHitTestOption.categoryBitMask.rawValue: surfaceCategory,   // body only, never tubes/markers
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
    // Equatable so AtlasModel.Label can be Equatable — the 30 Hz projector republishes its label
    // arrays only when they actually change.
    struct Region: Identifiable, Equatable {
        let id: String; let zh: String; let en: String
        let anchor: SIMD3<Float>; let center: SIMD3<Float>; let radius: Float; let isHand: Bool
    }

    static let regions: [Region] = [
        Region(id: "head",    zh: "头",   en: "Head",    anchor: off(b("Head"),     0,    -0.13,  0.05), center: b("Head"),       radius: 0.13, isHand: false),
        Region(id: "chest",   zh: "胸",   en: "Chest",   anchor: off(b("Chest"),   -0.02, -0.12,  0.02), center: b("Chest"),      radius: 0.17, isHand: false),
        // Belly sits ABOVE the hip bone (between Hips 0.884 and Spine 1.053); the label previously
        // rode the hip joint and read low, so anchor it on the navel level (~0.965) and nudge up.
        Region(id: "abdomen", zh: "腹",   en: "Abdomen", anchor: off(belly,          0.02, -0.12,  0.03), center: belly,           radius: 0.18, isHand: false),
        // Arm/leg/foot frame the RIGHT limb (−x) to match the right-side acupoint markers — zooming
        // the left limb would show an empty part. The outward label nudge is mirrored (−dx).
        Region(id: "arm",     zh: "臂",   en: "Arm",     anchor: off(b("LowerArmR"), -0.06, -0.05, 0.02), center: b("LowerArmR"),  radius: 0.16, isHand: false),
        Region(id: "leg",     zh: "腿",   en: "Leg",     anchor: off(b("LowerLegR"), -0.05, -0.06, 0.00), center: b("LowerLegR"),  radius: 0.20, isHand: false),
        Region(id: "foot",    zh: "足",   en: "Foot",    anchor: off(b("FootR"),     -0.03, -0.05, -0.02), center: b("FootR"),     radius: 0.11, isHand: false),
        Region(id: "hand",    zh: "手",   en: "Hand",    anchor: off(b("HandR"),     0,    -0.05,  0.00), center: handCenter,     radius: 0.12, isHand: true),
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

    // Positions come from the ONE placement registry (AcupointPlacements — Placements3D.swift);
    // the meridian (for marker colour) comes from the point data itself. Mesh space is z-up,
    // right=−x, front=−y; estimates are surface-snapped below, so slightly-off values still land
    // on the body. LI4 is excluded (never in Acupoint.all).
    struct AcuMarker { let id: String; let meridian: String; let pos: SIMD3<Float> }
    static var acuMarkers: [AcuMarker] {
        Acupoint.all.compactMap { pt in
            guard let pos = AcupointPlacements.table[pt.id]?.body else { return nil }
            return AcuMarker(id: pt.id, meridian: pt.meridian, pos: pos)
        }
    }

    // Acupoints as BLACK ink DOTS on the channels (user-directed aesthetic — like a classic meridian
    // chart, not the meridian-tinted markers we had). Node names ("acu:<id>") let a tap hit-test identify
    // the point. Added to the mesh (raw coords) so they ride the body through pose + spin.
    static let markerBlack = UIColor(white: 0.08, alpha: 1)   // near-black, softer than pure black on parchment
    static func markers(on mesh: SCNNode) -> SCNNode {
        let root = SCNNode()
        for m in acuMarkers {
            let pos = snapToSurface(m.pos, mesh: mesh)
            let node = AtlasMarkers.node(id: m.id, color: markerBlack, coreRadius: 0.0080,
                                         haloRadius: 0.0145, at: SCNVector3(pos.x, pos.y, pos.z))
            node.isHidden = true        // revealed by the body view's per-frame loop (now: always shown)
            root.addChildNode(node)
        }
        // Markers are decoration too: a later surface-snap raycast must never land on a marker
        // sphere (see surfaceCategory). Stamped per-node — categoryBitMask is not inherited.
        root.enumerateHierarchy { n, _ in n.categoryBitMask = decorationCategory }
        return root
    }

    // Snap a first-pass marker estimate onto the body surface: raycast radially inward (in the x-y
    // cross-section at the marker's height z) from outside the body toward the central axis, and place
    // the marker just proud of the first surface hit — so an estimate that floated off the mesh lands
    // on it. Points near the vertical axis (vertex/sole) have no radial direction, so keep the estimate.
    // The raycast is category-masked to the body surface: by the time markers snap, the channel tubes
    // and their fat invisible hit-proxies are already children of `mesh` and would otherwise be hit.
    private static func snapToSurface(_ p: SIMD3<Float>, mesh: SCNNode) -> SIMD3<Float> {
        let radial = SIMD3<Float>(p.x, p.y, 0)
        let r = simd_length(radial)
        guard r > 0.02 else { return p }
        let dir = radial / r
        let axisPt = SIMD3<Float>(0, 0, p.z)
        let start = axisPt + dir * 0.45
        let hits = mesh.hitTestWithSegment(from: SCNVector3(start), to: SCNVector3(axisPt), options: [
            SCNHitTestOption.backFaceCulling.rawValue: false,
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue,
            SCNHitTestOption.categoryBitMask.rawValue: surfaceCategory,   // body only, never tubes/markers
        ])
        guard let h = hits.first else { return p }
        let hit = SIMD3<Float>(Float(h.localCoordinates.x), Float(h.localCoordinates.y), Float(h.localCoordinates.z))
        return hit + dir * 0.006
    }

    // MARK: helpers

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * t }

    // CENTRIPETAL Catmull-Rom (alpha = 0.5, Barry-Goldman form): knot spacing = sqrt(distance). This
    // prevents the cusps / self-intersections uniform Catmull-Rom produces when control points are
    // unevenly spaced — exactly our case now that clustered acupoint anchors are woven between the far-
    // apart bone joints. Still interpolates every control point, so the stroke passes through each dot.
    private static func catmullRom(_ p: [SIMD3<Float>], perSegment: Int) -> [SIMD3<Float>] {
        guard p.count >= 2 else { return p }
        var out: [SIMD3<Float>] = []
        let n = p.count
        for i in 0 ..< n - 1 {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, n - 1)]
            let t0: Float = 0
            let t1 = t0 + knot(p0, p1)
            let t2 = t1 + knot(p1, p2)
            let t3 = t2 + knot(p2, p3)
            for s in 0 ..< perSegment {
                let t = t1 + (t2 - t1) * Float(s) / Float(perSegment)
                out.append(catmullRomPoint(p0, p1, p2, p3, t0, t1, t2, t3, t))
            }
        }
        out.append(p[n - 1])
        return out
    }

    private static func knot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        max(simd_length(b - a).squareRoot(), 1e-4)   // sqrt spacing (alpha=0.5); floor avoids a zero knot
    }

    // Barry-Goldman recursive evaluation of the segment p1→p2 at parameter t ∈ [t1, t2].
    private static func catmullRomPoint(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                                        _ t0: Float, _ t1: Float, _ t2: Float, _ t3: Float, _ t: Float) -> SIMD3<Float> {
        let a1 = lerpT(p0, p1, t0, t1, t)
        let a2 = lerpT(p1, p2, t1, t2, t)
        let a3 = lerpT(p2, p3, t2, t3, t)
        let b1 = lerpT(a1, a2, t0, t2, t)
        let b2 = lerpT(a2, a3, t1, t3, t)
        return lerpT(b1, b2, t1, t2, t)
    }

    // Linear interpolation between a (at ta) and b (at tb), evaluated at t; guards a zero interval.
    private static func lerpT(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ ta: Float, _ tb: Float, _ t: Float) -> SIMD3<Float> {
        let d = tb - ta
        guard abs(d) > 1e-6 else { return a }
        return a + (b - a) * ((t - ta) / d)
    }

    // The resting stroke ink — deep pine, #2c3227. Exposed so the legend swatch reads the SAME ink
    // the channels render in (they can't drift apart).
    static let inkBase: (r: CGFloat, g: CGFloat, b: CGFloat) = (0.173, 0.196, 0.153)
    static var inkSwatch: Color { Color(red: inkBase.r, green: inkBase.g, blue: inkBase.b) }

    // Deep ink faintly tinted toward the meridian's hue — `toward` is the blend fraction (0 =
    // pure ink). Enough to tell a selected channel apart up close, never enough to read as color.
    private static func inkTint(_ meridian: String, toward t: CGFloat = 0.18) -> UIColor {
        let mer = UIColor(MeridianColors.color(meridian))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        mer.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ink = inkBase
        return UIColor(red: ink.r + (r - ink.r) * t, green: ink.g + (g - ink.g) * t,
                       blue: ink.b + (b - ink.b) * t, alpha: 1)
    }

    // Brighten (or reset) a channel's strokes to its full meridian hue — the on-body IDENTITY of a
    // SELECTED channel. The ink restyle made every channel a near-identical dark stroke, so a tap
    // had no visible answer near the finger (the revealed markers sit only on the right limb);
    // now the tapped channel lights up in its meridian color on BOTH sides (review-caught). Mutates
    // the shared per-channel materials in place — transparency/geometry untouched, so it's cheap;
    // skips the invisible hit-proxy tubes (colorBufferWriteMask empty).
    static func setChannelHighlight(_ nodes: [SCNNode], meridian: String, on: Bool) {
        let hue = UIColor(MeridianColors.color(meridian))
        let ink = inkTint(meridian)
        for node in nodes {
            node.enumerateHierarchy { n, _ in
                guard let mat = n.geometry?.firstMaterial, mat.colorBufferWriteMask != [] else { return }
                mat.diffuse.contents = on ? hue : ink
                if mat.emission.contents != nil {          // the soft wash halo
                    mat.emission.contents = on ? hue : ink
                    mat.emission.intensity = on ? 1.1 : 0.6
                }
            }
        }
    }

    // Ink stroke materials: a near-opaque dark core, and the emissive WASH — the same ink at low
    // opacity with a soft self-glow, so the stroke reads as ink bleeding into the paper rather
    // than a plastic tube. Created once per channel and shared across its segments.
    private static func channelMaterials(_ meridian: String) -> (core: SCNMaterial, halo: SCNMaterial) {
        let ink = inkTint(meridian)
        let core = lineMaterial(ink, 0.92)
        let halo = lineMaterial(ink, 0.16)
        halo.emission.contents = ink
        halo.emission.intensity = 0.6
        return (core, halo)
    }

    // Invisible material for the wide tap-proxy tubes: never drawn, but still returned by hitTest.
    private static func hitProxyMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.colorBufferWriteMask = []        // invisible (writes no color) but still hit-testable
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
