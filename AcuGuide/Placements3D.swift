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
//                surface-snapped by BodyAtlas.snapToSurface, so slightly-off estimates land on it.
//                ABSENT for the eight hand/forearm points: those are derived from the model's
//                skeleton in HandFrame instead (the authored ones had seven of eight on the wrong
//                FACE of the hand — read HandFrame's header before re-authoring any of them).
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
        //
        // NOTE ON THE MISSING `body` VALUES. The eight hand/forearm points (TE3 SI3 HT7 PC8 PC6 SJ5
        // TE4 PC7) no longer carry a full-body coordinate here: BodyAtlas derives them from the
        // model's skeleton via HandFrame, because the authored ones put seven of the eight on the
        // WRONG FACE of the hand. `detailUV` is unaffected — the detail sheet is a different mesh in
        // a different pose, and its values were audited separately and are placed by a raycast that
        // always worked. Do not re-add `body:` here; change the anatomical fractions in HandFrame.
        "TE3": Placement3D(                               detailUV: [ 0.222, -0.144]),  // 4th/5th MC groove behind the knuckles (audited: was riding the MCP heads — moved proximal)
        "TE2": Placement3D(                               detailUV: [ 0.305,  0.040]),  // 4th/5th web margin
        // SI3/SI4 pulled onto the mesh (were 0.288/-0.066 and 0.160/-0.280): both sat just off
        // the ulnar silhouette, so their rays missed and the markers survived only via the spiral
        // snap — the snapped==false test assertion now pins every registry uv to a DIRECT hit
        // (probed: the ulnar edge runs u≈0.28 at the 5th MCP and u≈0.15 at the wrist band).
        "SI3": Placement3D(                               detailUV: [ 0.267, -0.105]),  // ulnar border, behind 5th MCP
        // SI4 sits in the depression between the 5th-metacarpal BASE and the triquetral, at the
        // edge of the wrist crease (WHO; iaomai) — the retired map had it floating mid-hand
        // (user-reported; was [0.200, -0.202]).
        "SI4": Placement3D(                               detailUV: [ 0.195, -0.186]),
        "HT7": Placement3D(                               detailUV: [ 0.105, -0.282], detailFarSide: true),  // ulnar palmar wrist, pisiform
        "PC8": Placement3D(                               detailUV: [ 0.095, -0.112], detailFarSide: true),  // palm centre, 2nd/3rd MC (audited: was too ulnar — moved toward the 3rd MC)
        "HT8": Placement3D(                               detailUV: [ 0.207, -0.138], detailFarSide: true),  // where the pinky tip lands in a fist (audited: nudged distal)
        // LU9/LU10 pulled IN toward the palm centreline (was u −0.10/−0.137): their old rays fell
        // off the radial silhouette into empty space, so the far-side raycast missed and the
        // markers floated beside the wrist (user-reported two floaters). u ≈ −0.05 keeps them on
        // the thenar/radial-wrist band, over solid mesh, matching LI5's on-hand column.
        "LU10": Placement3D(                              detailUV: [-0.161, -0.142], detailFarSide: true),  // thenar, 1st MC midpoint
        "LU9": Placement3D(                               detailUV: [-0.044, -0.271], detailFarSide: true),  // radial end of palmar wrist crease (audited: v -0.35 landed on the stub CUT FACE — invisible from the palm)
        "LI5": Placement3D(                               detailUV: [-0.052, -0.267]),                       // anatomical snuffbox (audited: was mid-wrist — pulled onto the radial border)
        // ── Forearm (full-body atlas only — no detail sheet reaches them) ────────────────────
        // PC6 / SJ5 carry no detail sheet and no authored body coord — HandFrame places both, 2 cun
        // proximal to the wrist crease on the palmar and dorsal forearm respectively.
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
        "TE4":  Placement3D(                               detailUV: [-0.230,  0.030]),                       // dorsal wrist crease
        "PC7":  Placement3D(                               detailUV: [-0.215,  0.005], detailFarSide: true),  // palmar wrist crease (audited: far-ray at the old uv exited through the THUMB)
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

    // THE registry-consumption rule for detail sheets — PartDetail.byRegion, the hand sheet's
    // placeMarkers, and the snapshot test all read through here, so a change to what gets placed
    // (filtering, farSide policy) lands everywhere at once.
    static func detailLayout(region: String) -> (layout: [String: SIMD2<Float>], back: Set<String>) {
        var layout: [String: SIMD2<Float>] = [:]
        var back: Set<String> = []
        // HAND: derived from HandAnatomy through HandSheet's measured frame, NOT from the authored
        // detailUV below. Those authored values were eyeballed and then nudged until the raycast
        // landed, which is how TE3, SI3 and SI4 ended up stacked on one spot when SI4 belongs a
        // whole palm away at the wrist (user-reported: the hand "didn't even change"). The body
        // atlas and this sheet now read the SAME anatomy; only the frame differs.
        if region == "hand" {
            // EVERYTHING HandAnatomy KNOWS, not everything filed under region "hand". Those are not
            // the same set: TE4 (Yangchi, the dorsal wrist crease) and PC7 (Daling, the palmar one)
            // are filed under the ARM — they also appear on the arm sheet — so the hand chart was
            // silently dropping two of its twelve points, both on the wrist crease the sheet very
            // much does draw. HandAnatomy is the app's ONE statement of where a hand point is; if a
            // point has an entry there and the mesh reaches it, the chart should show it.
            let derived = HandSheet.detailUV
            for (id, uv) in derived {
                guard let pt = Acupoint.byId[id] else { continue }
                layout[id] = uv
                if !pt.requiresDorsal { back.insert(id) }      // palmar points raycast from behind
            }
            return (layout, back)
        }
        for pt in Acupoint.all where pt.region == region {
            guard let p = table[pt.id], let uv = p.detailUV else { continue }
            layout[pt.id] = uv
            if p.detailFarSide { back.insert(pt.id) }
        }
        return (layout, back)
    }
}
