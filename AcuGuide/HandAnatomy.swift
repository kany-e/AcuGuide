import simd

// WHERE EVERY HAND POINT IS, stated ONCE, in anatomy rather than in any model's coordinates.
//
// The app draws the hand on two completely different meshes — the full-body figure (model.glb, which
// has a skeleton) and the fingered detail sheet (hand_low_poly.glb, which does not) — and until now
// each carried its own hand-tuned numbers. That is the "authored twice" problem Placements3D's header
// says it closed, reopened one level down: a point could be right on one surface and wrong on the
// other with nothing to notice, and that is exactly what happened. The body atlas was corrected while
// the detail sheet still stacked TE3, SI3 and SI4 on one spot — SI4 belongs at the WRIST, most of a
// palm away from the other two — which is what the user saw when they said the hand "didn't even
// change".
//
// So: one table of fractions, and each surface supplies only its own frame.
//   along  — 0 at the wrist crease, 1 at the knuckle (MCP) line; negative runs up the forearm.
//   across — fraction of the palm LENGTH, measured across the hand; + is RADIAL (thumb side).
//   dorsal — which face, and the same flag the camera coach's face gate uses (Acupoint.requiresDorsal).
//
// Scale reference for `across`: on a relaxed hand the MCP heads run from about +0.30 (index) to
// −0.36 (little finger), so adjacent metacarpals are ~0.22 apart and the ulnar border sits near
// −0.45. Sources: WHO Standard Acupuncture Point Locations in the Western Pacific Region (2008) and
// claude-deliverables/references/acuguide_source_upgrade.md.
enum HandAnatomy {
    struct Spot {
        let along: Float
        let across: Float
        /// Cross-checked against Acupoint.requiresDorsal by HandAnatomyTests, so the atlas and the
        /// coach can never disagree about which side of the hand a point is on.
        let dorsal: Bool
    }

    static let spots: [String: Spot] = [
        // ── Palmar ───────────────────────────────────────────────────────────────────────────
        // Daling: middle of the palmar wrist crease, between the two central tendons.
        "PC7":  Spot(along:  0.00, across:  0.00, dorsal: false),
        // Taiyuan: radial end of the palmar wrist crease, on the radial artery.
        "LU9":  Spot(along:  0.02, across:  0.30, dorsal: false),
        // Shenmen: ulnar end of the palmar wrist crease, at the pisiform.
        "HT7":  Spot(along:  0.03, across: -0.32, dorsal: false),
        // Yuji: thenar eminence, at the midpoint of the 1st metacarpal, on the palmar side.
        "LU10": Spot(along:  0.45, across:  0.42, dorsal: false),
        // Shaofu: between the 4th and 5th metacarpals — where the LITTLE fingertip lands in a fist.
        "HT8":  Spot(along:  0.55, across: -0.22, dorsal: false),
        // Laogong: centre of the palm, between the 2nd and 3rd metacarpals, nearer the 3rd — where
        // the MIDDLE fingertip lands. (WHO also admits a reading just proximal to the MCP joint,
        // ≈0.85; the app's own location text and find-guide both say "the centre of the palm", and
        // that is what the user expects to see.)
        "PC8":  Spot(along:  0.62, across:  0.10, dorsal: false),
        // Neiguan: palmar forearm, 2 cun proximal to the crease — placed by cun, not by `along`.
        // ── Dorsal ───────────────────────────────────────────────────────────────────────────
        // Yangxi: the anatomical snuffbox, at the radial end of the dorsal wrist crease.
        "LI5":  Spot(along:  0.02, across:  0.42, dorsal: true),
        // Yangchi: dorsal wrist crease, in the depression just ulnar of the extensor tendon.
        "TE4":  Spot(along:  0.00, across: -0.06, dorsal: true),
        // Wangu: between the base of the 5th metacarpal and the triquetral, at the ULNAR WRIST —
        // nearly a full palm proximal of TE3/SI3, which is what the detail sheet had lost.
        "SI4":  Spot(along:  0.05, across: -0.42, dorsal: true),
        // Zhongzhu: the groove proximal to the heads of the 4th and 5th metacarpals.
        "TE3":  Spot(along:  0.80, across: -0.25, dorsal: true),
        // Houxi: ulnar border, proximal to the head of the 5th metacarpal — the end of the palm
        // crease when a loose fist is made. A red-white-flesh BORDER point, so which face it is on
        // is genuinely ambiguous; placed a little inside the border so it resolves to the DORSAL
        // side, which is the side it is filed under and the side the camera coach asks to see.
        "SI3":  Spot(along:  0.86, across: -0.40, dorsal: true),
        // Yemen: the margin of the web between the ring and little fingers, just DISTAL of the MCPs.
        "TE2":  Spot(along:  1.06, across: -0.34, dorsal: true),
    ]

    /// Points placed by proportional cun up the forearm rather than by palm fraction. The forearm
    /// is 12 cun from the wrist crease to the cubital crease, so 2 cun is a sixth of the way.
    static let forearmSpots: [String: (cun: Float, across: Float, dorsal: Bool)] = [
        "PC6": (2, 0.00, false),   // Neiguan — palmar, between the tendons
        "SJ5": (2, 0.00, true),    // Waiguan — dorsal, directly opposite Neiguan
    ]
}

// THE DETAIL HAND SHEET'S FRAME, in the (u,v) space AcupointPlacements.detailUV authors in.
//
// hand_low_poly.glb has no skeleton (0 skins, 0 bones — only Sketchfab wrapper nodes), so the frame
// is READ OFF A LABELLED uv GRID rendered on the posed mesh
// (BodyMeshProbeTests.testRenderDetailHandUVGrid), not inferred. Inferring it from slice statistics
// is what I tried first and it put the v axis UPSIDE DOWN — LI5, a radial WRIST point, landed on the
// middle finger. On a mesh whose vertex density is not uniform, "which end has more vertices" is not
// evidence about which end is the wrist; a picture is.
//
// From that grid: v increases toward the FINGERTIPS and the THUMB is at NEGATIVE u.
//
// TWO THINGS WERE STILL WRONG, and together they are the "way off the palm" device report.
//
// 1. THE uv SPACE IS NOT SQUARE. AtlasMarkers.screenMarker aims its ray at
//    (centre.x + u·ext.x, centre.y + v·ext.y) — u is a fraction of the posed mesh's world WIDTH and
//    v a fraction of its HEIGHT (0.888 : 1.000 here). So a frame built with plain 2-D vector algebra
//    on (u,v) — normalize, rotate 90° by (−y, x) — is orthonormal in uv and SHEARED on the hand:
//    `across` came out 9° off square and 7% short, so moving across the palm also walked the point
//    toward the fingers. Fixed by doing the frame arithmetic in an ISOTROPIC space (u scaled by the
//    aspect so one unit is the same distance on both axes) and converting back only at the end.
//
// 2. THE PALM WAS MODELLED FAR TOO SHORT, which was the bigger half. Read off the grid picture by
//    eye, the frame ran up the 4th/5th metacarpal instead of the midline and stopped a third of the
//    way short: the MCP line was placed at v 0.00 when the digits do not separate until v +0.160.
//    Since `across` is measured in palm-LENGTHS, a short palm shrinks the lateral spread too, so the
//    whole set collapsed toward one another — PC8 (the CENTRE of the palm) rendered crowded against
//    the thumb on top of LU10, and TE3/SI3/TE2 piled onto the ulnar border.
//
// So the landmarks are no longer eyeballed off a render.
// BodyMeshProbeTests.testMeasureDetailHandCentreline probes the silhouette with screenMarker's OWN
// direct-hit test and, per v, takes the widest contiguous run of hits; the run's midpoint is the
// centreline. Three traps it has to step around, each of which produced a wrong answer first:
//
//   • The first lobe break going up is the THUMB peeling off (a lobe out around u −0.25…−0.08 while
//     the palm and all four fingers are still one mass), NOT the fingers separating. Counting it put
//     the MCP line at v +0.025 instead of +0.160 — and an assertion written on it cheerfully pinned
//     the wrong anatomy. Lobes lying entirely radial of u −0.10 are ignored.
//   • The wrist end is not the bottom of the mesh: this hand is an amputation, and below the palm is
//     a CONSTANT-WIDTH forearm stub. The wrist crease is the taper knee where the palm stops
//     narrowing (v ≈ −0.26). Placing the origin further down the stub does not scale the layout, it
//     offsets every marker proximally by the same amount.
//   • The centreline fit must skip v −0.175…+0.02, where the thumb fuses into the palm's outline and
//     drags the midpoint radially, and must NOT be fitted on the low band alone — that band is mostly
//     stub, whose lean differs from the palm's, and extrapolating it upward misplaces the knuckles.
//
// Comparing a dorsal render against a palm render cannot settle any of this — they are not mirror
// images (the palm view moves the camera, not the mesh), so the two eyeball estimates disagree with
// each other by more than the error being chased.
enum HandSheet {
    /// ext.x / ext.y of the mesh in its chart pose, in screenMarker's own basis (the corner-
    /// transformed bounding box, not the tighter triangle AABB). Pinned against the real mesh by
    /// BodyMeshProbeTests.testDetailHandUVSpaceIsAnisotropic, so re-posing or replacing the model
    /// fails a test instead of silently re-shearing every marker.
    static let uvAspect: Float = 0.8879

    // Both are MEASURED silhouette centres at the two v the mesh itself marks out — the palm/stub
    // taper knee and the digit-separation (web) line. The straight line between them reproduces the
    // measured centre at every clean row in between to within 0.008 uv, which is the check that this
    // is the hand's real long axis and not a fit through one end of it.
    static let wrist    = SIMD2<Float>( 0.019, -0.275)   // wrist-crease centre
    // The digits separate at v +0.160, but that is the WEB line, and HandAnatomy puts the web at
    // along 1.06 (TE2), not 1.00 — so the MCP line is 1/1.06 of the way there.
    static let knuckles = SIMD2<Float>( 0.196,  0.131)   // MCP-line centre
    // Only the SIGN of `radial` depends on this, so it needs to be roughly thumb-ward, nothing more.
    static let thumbRef = SIMD2<Float>(-0.350,  0.130)   // out along the abducted thumb

    /// uv → a space where one unit is the same distance horizontally and vertically, and back.
    private static func iso(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x * uvAspect, p.y) }
    private static func unIso(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x / uvAspect, p.y) }

    /// Unit vectors of the sheet's hand frame, IN ISOTROPIC SPACE — they are only perpendicular on
    /// the hand there, so never add them to a raw uv coordinate. Go through `uv(along:across:)`.
    static var distal: SIMD2<Float> { simd_normalize(iso(knuckles) - iso(wrist)) }
    static var radial: SIMD2<Float> {
        let p = SIMD2<Float>(-distal.y, distal.x)
        return simd_dot(p, iso(thumbRef) - iso(wrist)) > 0 ? p : -p
    }
    static var palmLength: Float { simd_length(iso(knuckles) - iso(wrist)) }

    /// How far the anatomy's `across` fractions stretch on THIS mesh. Fitted by search, not by eye:
    /// BodyMeshProbeTests.testFitDetailHandAcrossScale walks the scale and reports the largest value
    /// at which all twelve hand points still land DIRECTLY on the silhouette (no spiral snap). 0.60
    /// is that value; SI4 — the most ulnar, at the narrow wrist — is the first to fall off above it.
    ///
    /// Why it is BELOW 1 when the fingers are splayed WIDER than a real hand's: the constraint is
    /// the wrist, not the knuckles. This model's stub is much narrower than a real wrist, and the
    /// camera-ray placement grazes off the silhouette near the edges, so the widest scale the whole
    /// set survives is set by its narrowest part. Points therefore sit slightly inboard of their
    /// true anatomy — a measured, uniform concession to the model, made once, instead of twelve
    /// per-point nudges. The RELATIVE arrangement, which is what was broken, is preserved exactly.
    ///
    /// It dropped 0.90 → 0.60 when the landmarks above were corrected, and that is a CONSISTENCY
    /// CHECK rather than a new concession: `across` is measured in palm-lengths, and the corrected
    /// frame is 1.50× longer, so 0.90/1.50 = 0.60 leaves the absolute width of the hand's point
    /// spread almost exactly where the old fit had put it. The old numbers had the right span drawn
    /// along the wrong line.
    static let acrossScale: Float = 0.60

    /// `scale` is the across-scale to apply; it is a parameter only so the fitting probe
    /// (BodyMeshProbeTests.testFitDetailHandAcrossScale) can sweep it through the SAME arithmetic
    /// the app uses instead of re-deriving the frame and drifting from it.
    static func uv(along: Float, across: Float, scale: Float = acrossScale) -> SIMD2<Float> {
        unIso(iso(wrist) + distal * (along * palmLength) + radial * (across * scale * palmLength))
    }

    /// Every hand-sheet point, resolved from the shared anatomy. Consumed by AcupointPlacements.
    static var detailUV: [String: SIMD2<Float>] {
        HandAnatomy.spots.mapValues { uv(along: $0.along, across: $0.across) }
    }
}
