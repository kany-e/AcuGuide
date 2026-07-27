import simd

// THE ANATOMICAL FRAME OF THE BODY MODEL'S RIGHT HAND, taken from the model's own skeleton.
//
// WHY THIS REPLACED EIGHT AUTHORED COORDINATES. The hand/forearm entries in AcupointPlacements were
// hand-tuned mesh coordinates, and nothing could check them: the only automated test asserted that
// a marker landed on SOME surface, and even that was vacuous because the surface raycast never hit
// (see BodyAtlas.Surface). Measured against the skeleton and the local skin, seven of the eight
// were defective — PC8, HT7, PC7 and PC6 (palmar) were drawn on the BACK of the hand, TE3 and SJ5
// (dorsal) on the palm, and TE4 was half a palm-length up the forearm, off the limb entirely. Only
// SI3 was where it belonged. Device report: "PC8 is supposed to be in the centre of the palm, but
// the labelling shows it near the wrist."
//
// The mistake was structural, not arithmetic. The coordinates separated palmar from dorsal along
// −y, the FRONT of the body — which would be right for a figure standing in anatomical position
// (palms forward). This model's arms hang naturally, palms facing the thighs, so its palmar normal
// is [+0.66, +0.60, −0.44]: mostly medial, partly posterior, nothing like the body's front. No
// amount of nudging individual numbers finds that; you have to write the frame down.
//
// So: derive the frame from the four bind-pose bones that pin the hand, and express each point the
// way its source describes it — a fraction ALONG the palm (wrist crease → knuckles), a fraction
// ACROSS it (radial/thumb side positive), and which face it is on. Those fractions are anatomy and
// survive a change of model; the bone positions are the only thing that would need re-reading.
struct HandFrame {
    let origin: SIMD3<Float>      // wrist crease (the Hand bone)
    let distal: SIMD3<Float>      // unit, wrist → knuckles
    let radial: SIMD3<Float>      // unit, across the palm toward the THUMB
    let palmar: SIMD3<Float>      // unit, out of the PALM
    let palmLength: Float         // wrist crease → MCP line
    let forearm: SIMD3<Float>     // unit, wrist → elbow
    let cun: Float                // proportional unit: wrist crease → cubital crease is 12 cun

    /// The right hand of `model.glb`, from its bind pose. Bone names as they appear in the GLB;
    /// values via BodyAtlas.bone plus the finger bones, which the channel routes never needed.
    /// (Mesh space: z-up, right = −x, front = −y. Dump them with BodyMeshProbeTests.)
    static let right: HandFrame = {
        let wrist    = BodyAtlas.b("HandR")                          // Hand_R
        let knuckles = SIMD3<Float>(-0.3840, -0.0701, 0.8448)        // Fingers01_R — the MCP line
        let thumbTip = SIMD3<Float>(-0.3395, -0.1174, 0.8472)        // Thumb02_R
        let elbow    = BodyAtlas.b("LowerArmR")
        return HandFrame(wrist: wrist, knuckles: knuckles, thumbTip: thumbTip, elbow: elbow)
    }()

    init(wrist: SIMD3<Float>, knuckles: SIMD3<Float>, thumbTip: SIMD3<Float>, elbow: SIMD3<Float>) {
        origin = wrist
        let d = knuckles - wrist
        palmLength = simd_length(d)
        distal = simd_normalize(d)
        // Radial = the thumb direction with its along-the-palm component removed, so the frame is
        // orthonormal and "0.30 across the palm" means the same thing at every level of the hand.
        let t = thumbTip - wrist
        radial = simd_normalize(t - simd_dot(t, distal) * distal)
        // For a RIGHT hand in this right-handed frame (right = −x, front = −y, up = +z), the palmar
        // normal is radial × distal. Sanity-check it against the model with
        // BodyMeshProbeTests.testHandPointsAgainstSkeleton, which prints the signed face distance.
        palmar = simd_normalize(simd_cross(radial, distal))
        let f = elbow - wrist
        forearm = simd_normalize(f)
        cun = simd_length(f) / 12      // the standard proportional measure for the forearm
    }

    /// A point on the hand, from anatomical fractions of the palm length.
    /// `along` 0 = wrist crease, 1 = knuckle line, negative = up the forearm.
    /// `across` + = radial (thumb) side, − = ulnar (little-finger) side.
    func hand(along: Float, across: Float) -> SIMD3<Float> {
        origin + distal * (along * palmLength) + radial * (across * palmLength)
    }

    /// A point on the forearm, `cunProximal` cun above the wrist crease. Uses the forearm axis, not
    /// the palm axis — the hand is angled off the forearm and measuring along the wrong one walks
    /// the point off the limb.
    func forearmPoint(cunProximal: Float, across: Float) -> SIMD3<Float> {
        origin + forearm * (cunProximal * cun) + radial * (across * palmLength)
    }

    // The body atlas's share of HandAnatomy: the eight points that surface carries, resolved into
    // mesh coordinates through this frame. Everything anatomical lives in HandAnatomy, so the body
    // and the detail sheet cannot drift apart. The surface offset is NOT here — BodyAtlas.markers
    // raycasts each point onto the skin along ±palmar, using the point's own requiresDorsal.
    var placements: [String: SIMD3<Float>] {
        var out: [String: SIMD3<Float>] = [:]
        // Only the points the FULL-BODY atlas draws; the rest are detail-sheet only (the low-poly
        // body hand is a mitten with no fingers to place them against).
        for id in ["PC7", "HT7", "PC8", "TE4", "TE3", "SI3"] {
            guard let s = HandAnatomy.spots[id] else { continue }
            out[id] = hand(along: s.along, across: s.across)
        }
        for (id, f) in HandAnatomy.forearmSpots {
            out[id] = forearmPoint(cunProximal: f.cun, across: f.across)
        }
        return out
    }
}
