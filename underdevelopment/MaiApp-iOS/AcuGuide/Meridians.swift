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
            // The stroke threads through its acupoint dots — but only on the RIGHT, where the markers
            // live; the left limb keeps the plain bone route (no dots to thread, so no beside-the-dots
            // look to fix). Arm chain shoulder → upper arm → elbow → WRIST; the hand-ward acupoints
            // (TE3/SI3/PC8/HT7, below the wrist) EXTEND the stroke to their dots via the anchor thread,
            // while the fat tap-proxies stay on the arm so they can't blanket the Hand region label.
            let thread = side == .right
            let wristEnd = mix(b(side.k("LowerArm")), b(side.k("Hand")), 0.7)
            let arm = [b(side.k("Shoulder")), b(side.k("UpperArm")), b(side.k("LowerArm")), wristEnd]
            // Yin — anterior (palmar) surface: radial LU, middle PC, ulnar HT.
            root.addChildNode(channel(arm, dx: -s * ax, meridian: "lung",  mesh: mesh, front: true,  threadAnchors: thread))
            root.addChildNode(channel(arm, dx:  0,      meridian: "pc",    mesh: mesh, front: true,  threadAnchors: thread))
            root.addChildNode(channel(arm, dx:  s * ax, meridian: "heart", mesh: mesh, front: true,  threadAnchors: thread))
            // Yang — posterior (dorsal) surface: radial LI, middle SJ, ulnar SI.
            root.addChildNode(channel(arm, dx: -s * ax, meridian: "li",    mesh: mesh, front: false, threadAnchors: thread))
            root.addChildNode(channel(arm, dx:  0,      meridian: "sj",    mesh: mesh, front: false, threadAnchors: thread))
            root.addChildNode(channel(arm, dx:  s * ax, meridian: "si",    mesh: mesh, front: false, threadAnchors: thread))
            // Full leg chain: hip → thigh → knee → ankle.
            let leg = [b(side.k("UpperLeg")), b(side.k("LowerLeg")), mix(b(side.k("LowerLeg")), b(side.k("Foot")), 0.7)]
            root.addChildNode(channel(leg, dx: s * outer * 0.8, meridian: "stomach", mesh: mesh, front: true, threadAnchors: thread)) // front-lateral
            root.addChildNode(channel(leg, dx: s * outer * 1.5, meridian: "gb",      mesh: mesh, front: true, threadAnchors: thread)) // lateral / side
        }
        // Torso midlines: ren (front, threads CV17/CV12) and du (back, extends up to GV20) — single +
        // central, always tappable.
        let spine = [b("Hips"), b("Spine"), b("Chest"), b("Neck")]
        root.addChildNode(channel(spine, dx: 0, meridian: "ren", mesh: mesh, front: true,  threadAnchors: true))
        root.addChildNode(channel(spine, dx: 0, meridian: "du",  mesh: mesh, front: false, threadAnchors: true))
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

    // One channel, as a single flowing ink stroke that threads THROUGH its acupoint dots. Pipeline:
    // lateral-offset the skeleton control points → densify → PROJECT the coarse samples onto the body
    // surface (project BEFORE the final smoothing, so the per-facet raycast snap can't re-jag the curve
    // — the old order projected a smoothed curve and re-roughened it) → weave the meridian's acupoint
    // anchors in at their arc-length (snapped to the surface exactly like the markers) → one centripetal
    // Catmull-Rom that INTERPOLATES every control point. The result is swept as ONE continuous tube (core
    // + soft wash halo), drawn on top of the translucent body (high renderingOrder) so it never blends
    // away at grazing angles. No per-segment cylinders and no bead spheres — those were the "bunch of
    // points connected, not a single line" look.
    private static func channel(_ pts: [SIMD3<Float>], dx: Float, meridian: String,
                                mesh: SCNNode, front: Bool, threadAnchors: Bool = false,
                                tappable: Bool = true) -> SCNNode {
        let offset = pts.map { SIMD3<Float>($0.x + dx, $0.y, $0.z) }
        let bones = projectAll(densify(offset, perSegment: 4), mesh: mesh, front: front)
        let anchors = threadAnchors
            ? AcupointPlacements.bodyAnchors(meridian: meridian).map { snapToSurface($0, mesh: mesh) }
            : []
        let curve = catmullRom(threadThroughAnchors(bones, anchors), perSegment: 6)

        let mats = channelMaterials(meridian)
        let node = SCNNode()
        if tappable { node.name = "mer:" + meridian }   // tap hit-test resolves the channel → card
        // One swept tube for the soft wash halo + one for the thin ink core, both carrying the shared
        // core/halo materials so setChannelHighlight still lights the whole channel in its hue.
        if let halo = sweptTube(curve, radius: 0.0052, radialSegments: 7, material: mats.halo) { node.addChildNode(halo) }
        if let core = sweptTube(curve, radius: 0.0024, radialSegments: 7, material: mats.core) { node.addChildNode(core) }
        // Modest, fully-transparent hit-proxy tubes so a tap near the hairline channel still selects it —
        // laid along the BONE route only (not the hand/foot the anchor thread can extend the visible
        // stroke into), so they never blanket the Hand region label and swallow its drill-in tap.
        if tappable {
            let proxyPath = catmullRom(bones, perSegment: 6)
            let step = max(1, proxyPath.count / 16)
            var i = 0
            while i + step < proxyPath.count {
                node.addChildNode(tube(from: proxyPath[i], to: proxyPath[i + step], radius: 0.03, material: hitProxyMaterial()))
                i += step
            }
        }
        return node
    }

    // Weave the meridian's acupoint anchors into the (already surface-projected) bone polyline at their
    // arc-length position, so the interpolating spline passes exactly through each dot. An anchor beyond
    // a chain end (a hand/foot point below the wrist/ankle) may overshoot the end segment, so it EXTENDS
    // the stroke to its dot instead of piling onto the endpoint. Anchors sitting too far off the route
    // (e.g. the torso ST25 vs the stomach LEG channel) are dropped by the distance gate.
    private static func threadThroughAnchors(_ poly: [SIMD3<Float>], _ anchors: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !anchors.isEmpty, poly.count >= 2 else { return poly }
        var arc = [Float](repeating: 0, count: poly.count)
        for i in 1 ..< poly.count { arc[i] = arc[i - 1] + simd_length(poly[i] - poly[i - 1]) }
        var control: [(s: Float, p: SIMD3<Float>)] = zip(arc, poly).map { ($0, $1) }
        let maxOffRoute: Float = 0.13   // an anchor farther than this from the route isn't on this channel
        for a in anchors {
            var best: (s: Float, d: Float) = (0, .greatestFiniteMagnitude)
            for i in 0 ..< poly.count - 1 {
                let p0 = poly[i], p1 = poly[i + 1]
                let seg = p1 - p0
                let len2 = simd_length_squared(seg)
                guard len2 > 1e-9 else { continue }
                // Overshoot the first/last vertex generously so a hand/foot/head anchor well beyond the
                // wrist/ankle/neck (e.g. SI3 below the wrist ≈ 4-5 densified segments out, GV20 above the
                // neck) still projects to the extended limb axis and threads in. The perpendicular
                // distance to that axis is what the 0.13 gate below measures, so a truly OFF-route point
                // (torso ST25 vs the stomach LEG channel) is still rejected regardless of the overshoot.
                let tLo: Float = (i == 0) ? -6.0 : 0
                let tHi: Float = (i == poly.count - 2) ? 6.0 : 1
                let t = max(tLo, min(tHi, simd_dot(a - p0, seg) / len2))
                let d = simd_length(a - (p0 + seg * t))
                if d < best.d { best = (arc[i] + simd_length(seg) * t, d) }
            }
            if best.d <= maxOffRoute { control.append((best.s, a)) }
        }
        control.sort { $0.s < $1.s }
        return control.map { $0.p }
    }

    // Sweep a small R-gon cross-section along `path` with parallel-transport frames (no twist) as ONE
    // SCNGeometry — a single continuous tube. Double-sided material, so triangle winding is not load-bearing.
    private static func sweptTube(_ path: [SIMD3<Float>], radius: Float, radialSegments: Int,
                                  material: SCNMaterial) -> SCNNode? {
        guard path.count >= 2, radialSegments >= 3 else { return nil }
        let R = radialSegments
        var tan = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: path.count)
        for i in 0 ..< path.count {
            let d = path[min(i + 1, path.count - 1)] - path[max(i - 1, 0)]
            tan[i] = simd_length(d) > 1e-6 ? simd_normalize(d) : tan[max(i - 1, 0)]
        }
        // Initial normal perpendicular to the first tangent, then parallel-transported along the path.
        var refUp = SIMD3<Float>(0, 0, 1)
        if abs(simd_dot(refUp, tan[0])) > 0.9 { refUp = SIMD3<Float>(1, 0, 0) }
        var nrm = simd_normalize(refUp - tan[0] * simd_dot(refUp, tan[0]))
        var verts: [SCNVector3] = []; verts.reserveCapacity(path.count * R)
        var norms: [SCNVector3] = []; norms.reserveCapacity(path.count * R)
        for i in 0 ..< path.count {
            if i > 0 {
                let axis = simd_cross(tan[i - 1], tan[i])
                let sinA = simd_length(axis)
                if sinA > 1e-6 {
                    let angle = atan2(sinA, simd_dot(tan[i - 1], tan[i]))
                    nrm = simd_quatf(angle: angle, axis: axis / sinA).act(nrm)
                }
                nrm = simd_normalize(nrm - tan[i] * simd_dot(nrm, tan[i]))   // re-orthogonalize against drift
            }
            let bin = simd_normalize(simd_cross(tan[i], nrm))
            for j in 0 ..< R {
                let ang = Float(j) / Float(R) * 2 * .pi
                let dir = nrm * cos(ang) + bin * sin(ang)
                let v = path[i] + dir * radius
                verts.append(SCNVector3(v.x, v.y, v.z))
                norms.append(SCNVector3(dir.x, dir.y, dir.z))
            }
        }
        var idx: [Int32] = []; idx.reserveCapacity((path.count - 1) * R * 6)
        for i in 0 ..< path.count - 1 {
            for j in 0 ..< R {
                let j1 = (j + 1) % R
                let a = Int32(i * R + j), bb = Int32(i * R + j1)
                let c = Int32((i + 1) * R + j), d = Int32((i + 1) * R + j1)
                idx.append(contentsOf: [a, c, bb, bb, c, d])
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        geo.firstMaterial = material
        let node = SCNNode(geometry: geo)
        node.renderingOrder = 12
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

    // Acupoints as INK DOTS — slightly larger than the thin channel strokes they sit on, in the
    // same faintly-tinted ink with a soft wash halo, so a revealed point reads like the brush
    // pressed and paused there. Node names ("acu:<id>") let a tap hit-test identify the point.
    // Added to the mesh (raw coords) so they ride the body through pose + spin.
    static func markers(on mesh: SCNNode) -> SCNNode {
        let root = SCNNode()
        for m in acuMarkers {
            let col = inkTint(m.meridian, toward: 0.35)   // a touch more hue than the stroke — tappable focus
            let pos = snapToSurface(m.pos, mesh: mesh)
            let node = AtlasMarkers.node(id: m.id, color: col, coreRadius: 0.0080,
                                         haloRadius: 0.0145, at: SCNVector3(pos.x, pos.y, pos.z))
            node.isHidden = true        // revealed only for the focused region / selected meridian
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
