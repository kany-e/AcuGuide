import Foundation
import Vision
import CoreGraphics

// The subset of Vision hand joints we use, with a stable mapping to Vision's names.
enum HandJoint: Hashable {
    case wrist
    case thumbTip, indexTip, middleTip, ringTip, pinkyTip
    case indexMCP, middleMCP, ringMCP, pinkyMCP
    case indexPIP, indexDIP   // distal index segment — press-tip fallback when the tip is occluded

    var vision: VNHumanHandPoseObservation.JointName {
        switch self {
        case .wrist:     return .wrist
        case .thumbTip:  return .thumbTip
        case .indexTip:  return .indexTip
        case .middleTip: return .middleTip
        case .ringTip:   return .ringTip
        case .pinkyTip:  return .littleTip
        case .indexMCP:  return .indexMCP
        case .middleMCP: return .middleMCP
        case .ringMCP:   return .ringMCP
        case .pinkyMCP:  return .littleMCP
        case .indexPIP:  return .indexPIP
        case .indexDIP:  return .indexDIP
        }
    }

    // Stable string key for serialization (M3 label records). Must stay in lockstep with train.py.
    var key: String {
        switch self {
        case .wrist: return "wrist"
        case .thumbTip: return "thumbTip"; case .indexTip: return "indexTip"; case .middleTip: return "middleTip"
        case .ringTip: return "ringTip";   case .pinkyTip: return "pinkyTip"
        case .indexMCP: return "indexMCP"; case .middleMCP: return "middleMCP"
        case .ringMCP: return "ringMCP";   case .pinkyMCP: return "pinkyMCP"
        case .indexPIP: return "indexPIP"; case .indexDIP: return "indexDIP"
        }
    }
}

// Hand proportions used to bound the occluded-tip reconstruction, expressed as fractions of
// `Hand.handSize` (wrist → middleMCP) so they hold at any distance, hand size or camera angle.
//
// These are ANATOMY, not tuning dials. The index DIP→fingertip distance is ~25 mm against a
// ~95 mm wrist→middleMCP palm, i.e. ~0.26. `tipReach` is that distance: the reconstruction is
// capped there so it can never place the tip beyond where a fingertip physically is. `tipFloor`
// is deliberately well below it — when the finger is foreshortened we would rather land short of
// the nail than past it, because overshooting is the failure mode this code has already shipped
// and reverted once.
enum HandGeom {
    static let tipFloor: CGFloat = 0.16   // minimum DIP→tip step; stops the collapse onto the knuckle
    static let tipReach: CGFloat = 0.26   // anatomical DIP→tip; hard ceiling, prevents nail overshoot
    // How long DIP→tip is RELATIVE TO the PIP→DIP segment the reconstruction measures. Both are
    // ~25 mm on an index finger — the middle phalanx joint-to-joint and the distal phalanx plus the
    // fingertip pulp — so the ratio is 1, and the same numerator gives the 0.26 tipReach above
    // against a ~95 mm palm. It is stated here because it must stay consistent with tipReach: the
    // two describe the same distance, once as a fraction of the neighbouring segment and once as a
    // fraction of the palm.
    //
    // It used to be 0.6, which quietly contradicted both constants. 0.6 × an unforeshortened
    // phalanx (~0.26·handSize) is 0.156·handSize — BELOW tipFloor — so the clamp resolved to the
    // floor on essentially every frame, tipReach was unreachable dead code, and the rebuilt tip sat
    // a permanent ~38% short of the nail, i.e. back toward the DIP. That residual is the reported
    // "the fingertip detection drifts towards the knuckle": the earlier fix stopped the estimate
    // COLLAPSING onto the knuckle but left it leaning there.
    static let tipToPhalanxRatio: CGFloat = 1.0
    // Alternate palm spans, expressed as the multiplier that converts them INTO the wrist→middleMCP
    // unit that tipFloor/tipReach are denominated in. Metacarpal ray anatomy: the 3rd (middle) ray
    // is the longest, the 2nd (index) is ≈0.97 of it and the 5th (little) ≈0.88 — so the reciprocals
    // below carry an index- or pinky-based span back onto the middle-ray scale.
    //
    // They exist because `handSize` needs middleMCP and the pressing hand frequently does not have
    // it: HandVision drops any joint under 0.3 confidence and requires only the WRIST, and the
    // massaging hand reaches in fingers-first from the top of frame, which is exactly the pose that
    // loses the middle knuckle. See Hand.pressScale.
    static let indexMCPToMiddleMCP: CGFloat = 1.03
    static let pinkyMCPToMiddleMCP: CGFloat = 1.14
}

// One detected hand. Points are normalized 0...1 in TOP-LEFT origin (already flipped
// from Vision's bottom-left), so they map directly onto the SwiftUI overlay.
struct Hand {
    var points: [HandJoint: CGPoint]
    var chirality: VNChirality   // .left / .right (Vision's handedness)
    var confidence: [HandJoint: Float] = [:]   // per-joint Vision confidence (empty in fixtures/tests)
    // Whether `points` are in the x-MIRRORED (selfie-preview) convention. Vision's chirality comes
    // from the un-mirrored buffer and never flips with our manual mirror, so any handedness-signed
    // geometry (isDorsal) must know which parity the coordinates are in. Defaults to the mirrored
    // front-camera convention every fixture/test was built in.
    var mirroredCoords: Bool = true

    // Below-receiver-grade detection (whole-hand confidence 0.3–0.5): typically the foreshortened /
    // awkwardly-posed MASSAGING hand, which Vision scores low but still localizes. Weak hands may
    // only serve as the presser — their geometry is too unreliable to anchor the target ring.
    var weak: Bool = false

    // Whole-hand Vision confidence, kept so the two detection passes (primary + inverted-frame)
    // can resolve a duplicate by KEEPING THE BETTER READ of the same physical hand. Fixtures/tests
    // build hands without it → fully reliable.
    var detectionConfidence: Float = 1

    func p(_ j: HandJoint) -> CGPoint? { points[j] }

    // Press-tip estimate + its measurement confidence. The RAW fingertip wins whenever Vision
    // reports one — device testing showed it tracks the intended massage point better than any
    // reconstruction (a pressing finger is BENT at the DIP, so extending the distal segment
    // overshoots the nail — user-confirmed regression). Only when the tip is entirely absent is it
    // rebuilt from the distal index segment (DIP + k·(DIP−PIP)) — and that reconstruction reports
    // confidence 0: it is an UNMEASURED guess, so it can sustain an engagement (hysteresis) but
    // must never start one (the palm-glaze gate keys off this value).
    /// `aspect` = frame W/H, so the clamp can be applied in ISOTROPIC width units. Landmarks arrive
    /// normalized PER AXIS, so a raw `hypot` measures different physical distances along x and y —
    /// and this function compares a length along the FINGER axis against a scale along the PALM
    /// axis. Those coincide only when the two are parallel; at right angles, on a 9:16 frame, the
    /// cap was evaluated 1.78× off, clipping a cross-axis rebuild back toward the DIP by up to 44%
    /// in one orientation and letting it overshoot the nail in the other. The engine (isoDist) and
    /// PointCalibration already learned this; this was the last raw-coordinate hit-test left.
    /// Defaulted to 1 so pure-geometry callers and fixtures keep square units.
    /// `reconstructed` distinguishes a rebuilt guess from a measured tip. It used to be inferred
    /// from `confidence == 0`, which is ambiguous — fixtures default to 1, and a real Vision read of
    /// exactly 0.0 is representable — and the engine now keys its grace clock off it.
    func pressTip(_ finger: HandJoint,
                  aspect: CGFloat = 1) -> (point: CGPoint, confidence: Float, reconstructed: Bool)? {
        if let tip = p(finger) { return (tip, confidence[finger] ?? 1, false) }   // fixtures: no dict → reliable
        guard finger == .indexTip, let dip = p(.indexDIP), let pip = p(.indexPIP) else { return nil }

        // RECONSTRUCTION, and only ever when Vision reported no tip at all. (Preferring a rebuild
        // while a tip IS present was shipped in R11.1 and reverted for overshooting the nail — see
        // the note above. Do not reintroduce it, in any confidence-gated form.)
        //
        // The bug this solves (user: "it detects around the first knuckle, not the finger tip"):
        // (DIP − PIP) is the MIDDLE phalanx, and its length here is an IMAGE PROJECTION. In the real
        // press pose — phone looking down, pressing finger angled away, tip buried in skin — that
        // phalanx is heavily foreshortened, so |DIP − PIP| shrinks toward zero and `k · that` is a
        // near-zero step. The estimate therefore collapsed ONTO the DIP: exactly "the first knuckle".
        // It also broke engagement, not just the visuals — a dot parked on the DIP sits outside the
        // 0.12–0.24·handSize hit tolerance even when the real nail is dead on the point.
        //
        // Fix: keep the DIRECTION from the projected phalanx, scale its LENGTH by the anatomical
        // ratio between the two segments (HandGeom.tipToPhalanxRatio — they are the same length, so
        // the projection carries the foreshortening for free), and clamp the result into
        // scale-invariant hand-size units:
        //   floor — a foreshortened phalanx still projects a real fingertip's worth past the DIP.
        //   cap   — bounded by the ANATOMICAL DIP→tip distance, so the rebuilt tip can never land
        //           beyond where a fingertip physically is. Overshooting the nail was the previous
        //           user-confirmed regression; this makes it impossible by construction rather than
        //           by picking a luckier constant.
        // Both bounds are now REACHABLE, which is the point: with the old 0.6 the floor won every
        // frame and the cap was dead code (see HandGeom.tipToPhalanxRatio).
        // ISOTROPIC throughout: measure the phalanx, clamp, and step out all in width units, then
        // convert the y component back on the way out. For a finger parallel to the palm the whole
        // transform cancels exactly, so every axial case — including the pinned overshoot test — is
        // bit-identical to before; only the cross-axis case, which is the one that was wrong, moves.
        let a = max(aspect, 0.01)
        let v = CGPoint(x: dip.x - pip.x, y: (dip.y - pip.y) / a)
        let len = hypot(v.x, v.y)
        guard len > 1e-6 else { return nil }
        let projected = HandGeom.tipToPhalanxRatio * len
        let hs = pressScale(aspect: a)
        // pressScale falls back through the other MCPs, so a hand that has lost middleMCP still gets
        // the clamp. With NO knuckle at all there is genuinely no scale to clamp against and the
        // pure projection stands — the engine bounds that case in TIME instead (see
        // CoachConst.tipReconstructionSustainS), rather than inventing a scale.
        let step = hs > 0 ? min(max(projected, HandGeom.tipFloor * hs), HandGeom.tipReach * hs) : projected
        let out = CGPoint(x: dip.x + v.x / len * step, y: dip.y + (v.y / len * step) * a)
        return (out, 0, true)
    }

    // Scale unit, invariant-ish to finger spread (wrist -> middle MCP).
    //
    // DELIBERATELY NOT given the fallback chain that pressScale has: this value is SERIALIZED into
    // the M3 label records (LabelCapture) that must stay in lockstep with train.py, so redefining it
    // would silently skew an already-captured dataset.
    var handSize: CGFloat {
        guard let w = p(.wrist), let m = p(.middleMCP) else { return 0 }
        return hypot(m.x - w.x, m.y - w.y)
    }

    /// Palm scale for the press-tip clamp, in ISOTROPIC width units, with a fallback chain.
    ///
    /// `handSize` needs middleMCP, and the PRESSING hand routinely lacks it — HandVision requires
    /// only the wrist and drops joints under 0.3 confidence, and the massaging hand comes in
    /// fingers-first from the top of frame, foreshortened, which is precisely where knuckles go
    /// missing. The clamp was therefore switched OFF in the exact pose it was written for: with no
    /// scale, a foreshortened phalanx projecting ~0.05·palm planted the rebuilt tip ~0.05 past the
    /// DIP instead of the anatomical 0.16–0.26 — i.e. ON the knuckle, and inside the ring radius, so
    /// the press could not register either. That is the reported "detection is on the knuckle".
    ///
    /// Any MCP will do, because all we need is a palm-length unit; the constants convert the index
    /// or little ray onto the middle-ray scale the tipFloor/tipReach fractions are defined in. This
    /// can only ever ADD a scale where there was none (0), so it cannot move an existing clamp.
    func pressScale(aspect: CGFloat = 1) -> CGFloat {
        guard let w = p(.wrist) else { return 0 }
        let a = max(aspect, 0.01)
        func span(_ j: HandJoint) -> CGFloat? {
            guard let m = p(j) else { return nil }
            return hypot(m.x - w.x, (m.y - w.y) / a)
        }
        if let s = span(.middleMCP) { return s }
        if let s = span(.indexMCP)  { return s * HandGeom.indexMCPToMiddleMCP }
        if let s = span(.pinkyMCP)  { return s * HandGeom.pinkyMCPToMiddleMCP }
        return 0
    }

    // Weighted MEAN of named landmarks → the acupoint target (image-normalized). Normalizing by the
    // weight total matters: every shipped anchor set happens to sum to 1.0, so raw-sum and mean are
    // identical today — but a future set that doesn't sum to 1 would silently scale the point toward
    // or away from the origin. (Review-caught latent trap.)
    func weightedTarget(_ anchors: [AnchorWeight]) -> CGPoint? {
        var x: CGFloat = 0, y: CGFloat = 0, total: CGFloat = 0
        for a in anchors {
            guard let pt = p(a.landmark) else { return nil }
            x += pt.x * a.weight; y += pt.y * a.weight; total += a.weight
        }
        return total > 0 ? CGPoint(x: x / total, y: y / total) : nil
    }

    // Palm vs back-of-hand via the signed cross of (wrist->index_mcp) x (wrist->pinky_mcp).
    // Ported from the web app's CALIBRATED, mirror-invariant test: dorsal <=> signed > 0.
    // (`signed` = cross for a right hand, -cross for a left hand; horizontal mirroring
    //  negates cross and swaps chirality, which cancel — so it holds for front/rear camera.)
    //
    // The comparison is gated behind ONE flag (`HandCalibration.dorsalWhenSignedPositive`) so that
    // the convention lives in a single place rather than being spread through the geometry. It is a
    // BUILD-TIME constant, not a user-reachable switch: the coach's debug menu that used to flip it
    // in the field is gone, because the value is device-verified (see the flag) and a live toggle
    // over the camera was only ever a way to invert a correct gate by accident.
    // nil when a required MCP landmark is missing — the caller must decide what an
    // unverifiable face means rather than silently defaulting to dorsal (which would let a
    // partially-detected palm pass the TE3 dorsal gate).
    var isDorsal: Bool? { isDorsal(assuming: chirality) }

    // Same test, but against a CALLER-SUPPLIED handedness — so the coach can feed a label that has
    // been held steady across frames instead of this frame's raw read. Vision's chirality is a
    // per-hand image-side estimate, not an anatomical guarantee: it is least reliable exactly where
    // this app looks (a close-up of two overlapping hands, no forearm or body in frame), and it is
    // the ONLY handedness-dependent term in the whole coach, so a single misread frame inverts
    // palm-vs-back and tells the user to turn over a hand that is already the right way up.
    // Device report: "the hand orientation detection is reversed for the right and left hand."
    func isDorsal(assuming hand: VNChirality) -> Bool? {
        // UNKNOWN IS NOT LEFT. This used to be `(chirality == .right) ? cross : -cross`, whose else
        // arm swallowed .unknown and silently returned the LEFT answer — a coin flip that reads as
        // a confident verdict. Every other consumer of chirality refuses to guess (PointCalibration
        // .canonicalFrame bails, settleVerdict reports .chiralityBlocked); this one now does too,
        // and nil routes to the caller's "reuse the last verdict we could compute" path.
        guard hand != .unknown else { return nil }
        guard let w = p(.wrist), let i = p(.indexMCP), let pk = p(.pinkyMCP) else { return nil }
        let cross = (i.x - w.x) * (pk.y - w.y) - (i.y - w.y) * (pk.x - w.x)
        // The old front/rear-camera "cancellation" claim assumed chirality flips with the mirror —
        // it does NOT (Vision reads the un-mirrored buffer either way; only our manual x-flip
        // changes). So the parity of the coordinates must enter the sign explicitly, or the
        // back-camera (un-mirrored) mode reads dorsal/palmar BACKWARDS. The calibrated flag below
        // was tuned in the mirrored convention; `mirroredCoords` maps other parities onto it.
        let anatomical = (hand == .right) ? cross : -cross
        let signed = mirroredCoords ? anatomical : -anatomical
        return HandCalibration.dorsalWhenSignedPositive ? signed > 0 : signed < 0
    }
}

// On-device calibration knobs, surfaced as debug toggles in the coach view so field
// calibration happens in one place.
enum HandCalibration {
    // dorsal <=> signed < 0.
    //
    // THIS VALUE IS CORRECT — DO NOT FLIP IT to chase a wrong-face report. It is confirmed against
    // real device captures, not derived on paper: all nine labels in
    // claude-deliverables/data/te3_labels_2026-07-07.jsonl are TE3 (a DORSAL point), captured on
    // device through this exact pipeline, five read .right and four .left — and every one of the
    // nine yields signed < 0. The convention therefore holds for BOTH hands, which also rules out
    // any systematic left/right inversion here. Flipping it would break the hand that works today.
    //
    // A wrong-face report is a bad chirality LABEL, not a bad sign convention; see
    // Hand.isDorsal(assuming:) and CoachEngine's held handedness.
    static var dorsalWhenSignedPositive = false
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
