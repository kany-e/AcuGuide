import simd

// THE single 3D-placement registry: every representation the 3D views need for one point lives in
// ONE entry, tuned here and only here. This closes the review's two deferred altitude findings:
// (a) the same point's position used to be authored in two unrelated tables — BodyAtlas.acuMarkers
//     (full-body mesh coords) and PartDetail.layout / HandMarkerCalib (detail-sheet uv) — so a
//     placement fix had to be found and remembered twice;
// (b) the 3D hand placed markers through a linear atlas→bbox map that 6 of 10 points overrode
//     with per-point nudges — the map no longer decided anything. The detailUV values below ARE
//     the authored truth (baked from the retired map+nudge outputs, snapshot-verified identical;
//     SI4 corrected in the same step).
//
// Spaces:
//  • body      — full-body atlas, mesh-local coords (z-up, right = −x, front = −y); markers are
//                surface-snapped by Meridians.snapToSurface, so slightly-off estimates land on it.
//  • detailUV  — the point's detail sheet (hand sheet for region "hand", PartDetail sheets for
//                head/arm/foot), normalized (u,v) in [-0.5…0.5] of the model's on-screen bounding
//                box in its canonical pose (u→right, v→up); raycast onto the surface by
//                AtlasMarkers.screenMarker. detailFarSide raycasts from BEHIND (palm / sole /
//                far arm surface) so the marker sits there and reveals on rotation.
// Tune here, then eyeball via the DetailSnapshotTests renders (detail_<part>.png / detail_hand[_palm].png).
struct Placement3D {
    var body: SIMD3<Float>? = nil
    var detailUV: SIMD2<Float>? = nil
    var detailFarSide: Bool = false
}

enum AcupointPlacements {
    static let table: [String: Placement3D] = [
        // ── Hand (detail = the fingered hand sheet, dorsal pose) ─────────────────────────────
        "TE3": Placement3D(body: [-0.370, -0.043, 0.883], detailUV: [ 0.245, -0.052]),  // 4th/5th MC groove behind the knuckles
        "TE2": Placement3D(                               detailUV: [ 0.284,  0.055]),  // 4th/5th web margin
        "SI3": Placement3D(body: [-0.398, -0.055, 0.848], detailUV: [ 0.288, -0.066]),  // ulnar border, behind 5th MCP
        // SI4 sits in the depression between the 5th-metacarpal BASE and the triquetral, at the
        // edge of the wrist crease (WHO; iaomai) — the retired map had it floating mid-hand
        // (user-reported; was [0.200, -0.202]).
        "SI4": Placement3D(                               detailUV: [ 0.160, -0.280]),
        "HT7": Placement3D(body: [-0.352, -0.075, 0.922], detailUV: [ 0.069, -0.341], detailFarSide: true),  // ulnar palmar wrist, pisiform
        "PC8": Placement3D(body: [-0.365, -0.088, 0.885], detailUV: [ 0.081, -0.163], detailFarSide: true),  // palm centre, 2nd/3rd MC
        "HT8": Placement3D(                               detailUV: [ 0.194, -0.092], detailFarSide: true),  // where the pinky tip lands in a fist
        "LU10": Placement3D(                              detailUV: [-0.100, -0.233], detailFarSide: true),  // thenar, 1st MC midpoint
        "LU9": Placement3D(                               detailUV: [-0.137, -0.367], detailFarSide: true),  // radial end of palmar wrist crease
        "LI5": Placement3D(                               detailUV: [-0.062, -0.312]),                       // anatomical snuffbox
        // ── Forearm (full-body atlas only — no detail sheet reaches them) ────────────────────
        "PC6": Placement3D(body: [-0.323, -0.050, 1.002]),  // palmar forearm, 2 cun above the crease
        "SJ5": Placement3D(body: [-0.323, -0.004, 1.002]),  // dorsal forearm, opposite PC6
        // ── Head & face (detail = frontal head sheet) ─────────────────────────────────────────
        "EX-HN3": Placement3D(body: [ 0.000, -0.085, 1.630], detailUV: [ 0.000,  0.050]),  // glabella
        "EX-HN5": Placement3D(body: [-0.080, -0.025, 1.630], detailUV: [ 0.360,  0.050]),  // temple hollow
        "GV20":   Placement3D(body: [ 0.000,  0.000, 1.760], detailUV: [ 0.000,  0.455]),  // vertex
        "EX-HN1": Placement3D(body: [ 0.000, -0.035, 1.748], detailUV: [ 0.000,  0.415]),  // just anterior of the vertex
        // ── Chest / abdomen (full-body atlas only) ────────────────────────────────────────────
        "CV17": Placement3D(body: [ 0.000, -0.100, 1.220]),  // mid-sternum
        "KI27": Placement3D(body: [-0.065, -0.090, 1.350]),  // under the collarbone
        "CV12": Placement3D(body: [ 0.000, -0.100, 1.080]),  // upper abdomen midline
        "ST25": Placement3D(body: [-0.060, -0.100, 0.965]),  // beside the navel
        // ── Arm (detail = horizontal arm sheet, dorsum to camera) ─────────────────────────────
        "LI11": Placement3D(body: [-0.295, -0.010, 1.155], detailUV: [ 0.160,  0.040]),                       // lateral elbow crease
        "LU5":  Placement3D(body: [-0.265, -0.050, 1.150], detailUV: [ 0.130,  0.000], detailFarSide: true),  // cubital crease (far side)
        "TE4":  Placement3D(body: [-0.345,  0.005, 0.960], detailUV: [-0.230,  0.030]),                       // dorsal wrist crease
        "PC7":  Placement3D(body: [-0.350, -0.085, 0.952], detailUV: [-0.250, -0.050], detailFarSide: true),  // palmar wrist crease (far side)
        // ── Leg (full-body atlas only) ────────────────────────────────────────────────────────
        "ST36": Placement3D(body: [-0.115, -0.060, 0.400]),
        "GB34": Placement3D(body: [-0.135, -0.045, 0.480]),
        "SP10": Placement3D(body: [-0.075, -0.055, 0.620]),
        "ST34": Placement3D(body: [-0.135, -0.060, 0.620]),
        "ST35": Placement3D(body: [-0.125, -0.065, 0.500]),
        // ── Foot (detail = 3/4 lateral foot sheet) ────────────────────────────────────────────
        "LR3":  Placement3D(body: [-0.120, -0.100, 0.060], detailUV: [ 0.100, -0.110]),
        "ST44": Placement3D(body: [-0.130, -0.135, 0.045], detailUV: [ 0.290, -0.130]),
        "KI1":  Placement3D(body: [-0.120, -0.075, 0.025], detailUV: [ 0.140, -0.220], detailFarSide: true),  // sole
        "KI3":  Placement3D(body: [-0.105,  0.020, 0.110], detailUV: [-0.220, -0.100]),
    ]

    // Detail-sheet placements for one region, in the shapes PartDetail/the hand sheet consume.
    static func detailLayout(region: String) -> (layout: [String: SIMD2<Float>], back: Set<String>) {
        var layout: [String: SIMD2<Float>] = [:]
        var back: Set<String> = []
        for pt in Acupoint.all where pt.region == region {
            guard let p = table[pt.id], let uv = p.detailUV else { continue }
            layout[pt.id] = uv
            if p.detailFarSide { back.insert(pt.id) }
        }
        return (layout, back)
    }
}
