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
        "TE3": Placement3D(body: [-0.370, -0.043, 0.883], detailUV: [ 0.240, -0.080]),  // 4th/5th MC groove behind the knuckles (audited: was riding the MCP heads — moved proximal)
        "TE2": Placement3D(                               detailUV: [ 0.284,  0.055]),  // 4th/5th web margin
        // SI3/SI4 pulled onto the mesh (were 0.288/-0.066 and 0.160/-0.280): both sat just off
        // the ulnar silhouette, so their rays missed and the markers survived only via the spiral
        // snap — the snapped==false test assertion now pins every registry uv to a DIRECT hit
        // (probed: the ulnar edge runs u≈0.28 at the 5th MCP and u≈0.15 at the wrist band).
        "SI3": Placement3D(body: [-0.398, -0.055, 0.848], detailUV: [ 0.278, -0.066]),  // ulnar border, behind 5th MCP
        // SI4 sits in the depression between the 5th-metacarpal BASE and the triquetral, at the
        // edge of the wrist crease (WHO; iaomai) — the retired map had it floating mid-hand
        // (user-reported; was [0.200, -0.202]).
        "SI4": Placement3D(                               detailUV: [ 0.150, -0.270]),
        "HT7": Placement3D(body: [-0.352, -0.075, 0.922], detailUV: [ 0.069, -0.341], detailFarSide: true),  // ulnar palmar wrist, pisiform
        "PC8": Placement3D(body: [-0.365, -0.088, 0.885], detailUV: [ 0.020, -0.170], detailFarSide: true),  // palm centre, 2nd/3rd MC (audited: was too ulnar — moved toward the 3rd MC)
        "HT8": Placement3D(                               detailUV: [ 0.194, -0.075], detailFarSide: true),  // where the pinky tip lands in a fist (audited: nudged distal)
        // LU9/LU10 pulled IN toward the palm centreline (was u −0.10/−0.137): their old rays fell
        // off the radial silhouette into empty space, so the far-side raycast missed and the
        // markers floated beside the wrist (user-reported two floaters). u ≈ −0.05 keeps them on
        // the thenar/radial-wrist band, over solid mesh, matching LI5's on-hand column.
        "LU10": Placement3D(                              detailUV: [-0.050, -0.235], detailFarSide: true),  // thenar, 1st MC midpoint
        "LU9": Placement3D(                               detailUV: [-0.085, -0.300], detailFarSide: true),  // radial end of palmar wrist crease (audited: v -0.35 landed on the stub CUT FACE — invisible from the palm)
        "LI5": Placement3D(                               detailUV: [-0.105, -0.300]),                       // anatomical snuffbox (audited: was mid-wrist — pulled onto the radial border)
        // ── Forearm (full-body atlas only — no detail sheet reaches them) ────────────────────
        "PC6": Placement3D(body: [-0.323, -0.050, 1.002]),  // palmar forearm, 2 cun above the crease
        "SJ5": Placement3D(body: [-0.323, -0.004, 1.002]),  // dorsal forearm, opposite PC6
        // ── Head & face (detail = frontal head sheet) ─────────────────────────────────────────
        "EX-HN3": Placement3D(body: [ 0.000, -0.085, 1.630], detailUV: [ 0.000,  0.030]),  // glabella (audited: nudged down between the brows)
        "EX-HN5": Placement3D(body: [-0.080, -0.025, 1.630], detailUV: [ 0.415,  0.075]),  // temple hollow (audited: was ON the eye corner — moved lateral/up into the temporal fossa)
        "GV20":   Placement3D(body: [ 0.000,  0.000, 1.760], detailUV: [ 0.000,  0.455]),  // vertex
        "EX-HN1": Placement3D(body: [ 0.000, -0.035, 1.748], detailUV: [ 0.000,  0.415]),  // just anterior of the vertex
        // ── Chest / abdomen (full-body atlas only) ────────────────────────────────────────────
        "CV17": Placement3D(body: [ 0.000, -0.100, 1.220]),  // mid-sternum
        "KI27": Placement3D(body: [-0.065, -0.090, 1.350]),  // under the collarbone
        "CV12": Placement3D(body: [ 0.000, -0.100, 1.080]),  // upper abdomen midline
        // ST25 drawn on the LEFT side (+x): the point is bilateral, and with KI27 on the right the
        // torso's labels were all stacking one side (user-reported crowding). Torso zooms frame
        // the whole trunk, so a left-side marker stays in view — unlike the limb regions, whose
        // zoom frames the RIGHT limb only (their markers must stay right).
        "ST25": Placement3D(body: [ 0.060, -0.100, 0.965]),  // beside the navel (left side)
        // ── Arm (detail = horizontal arm sheet, dorsum to camera) ─────────────────────────────
        "LI11": Placement3D(body: [-0.295, -0.010, 1.155], detailUV: [ 0.160,  0.040]),                       // lateral elbow crease
        "LU5":  Placement3D(body: [-0.265, -0.050, 1.150], detailUV: [ 0.130,  0.000], detailFarSide: true),  // cubital crease (far side)
        "TE4":  Placement3D(body: [-0.345,  0.005, 0.960], detailUV: [-0.230,  0.030]),                       // dorsal wrist crease
        "PC7":  Placement3D(body: [-0.350, -0.085, 0.952], detailUV: [-0.215,  0.005], detailFarSide: true),  // palmar wrist crease (audited: far-ray at the old uv exited through the THUMB)
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

    // The on-body acupoint anchors for a meridian: every point that HAS a body coordinate and belongs
    // to this meridian. Used to thread the 3D channel stroke exactly THROUGH its acupoint dots (the
    // markers snap to these same coords), so the channel reads as "----acupoint----acupoint----" rather
    // than a stick running beside a row of dots. detailUV-only hand points (TE2/SI4/HT8/LU9/LU10/LI5)
    // have no body coord and are excluded — they live on the hand drill-down, not the body figure.
    // Off-route points (e.g. the torso ST25 vs the stomach LEG channel) are filtered downstream by
    // BodyAtlas.threadThroughAnchors' distance gate, not here.
    static func bodyAnchors(meridian: String) -> [SIMD3<Float>] {
        Acupoint.all.compactMap { pt in
            guard pt.meridian == meridian, let p = table[pt.id]?.body else { return nil }
            return p
        }
    }

    // THE registry-consumption rule for detail sheets — PartDetail.byRegion, the hand sheet's
    // placeMarkers, and the snapshot test all read through here, so a change to what gets placed
    // (filtering, farSide policy) lands everywhere at once.
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
