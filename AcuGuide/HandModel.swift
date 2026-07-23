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
    func pressTip(_ finger: HandJoint) -> (point: CGPoint, confidence: Float)? {
        if let tip = p(finger) { return (tip, confidence[finger] ?? 1) }   // fixtures: no dict → reliable
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
        // Fix: keep the DIRECTION from the projected phalanx, but stop letting its projected LENGTH
        // set the distance. Clamp the step into scale-invariant hand-size units:
        //   floor — a foreshortened phalanx still projects a real fingertip's worth past the DIP.
        //   cap   — bounded by the ANATOMICAL DIP→tip distance, so the rebuilt tip can never land
        //           beyond where a fingertip physically is. Overshooting the nail was the previous
        //           user-confirmed regression; this makes it impossible by construction rather than
        //           by picking a luckier constant.
        let v = CGPoint(x: dip.x - pip.x, y: dip.y - pip.y)
        let len = hypot(v.x, v.y)
        guard len > 1e-6 else { return nil }
        let projected = 0.6 * len
        let hs = handSize
        // handSize needs wrist + middleMCP. Fixtures that model only the index finger have none, so
        // fall back to the pure projection there — the clamp is a device-pose correction, and a
        // synthetic hand has no foreshortening to correct.
        let step = hs > 0 ? min(max(projected, HandGeom.tipFloor * hs), HandGeom.tipReach * hs) : projected
        return (CGPoint(x: dip.x + v.x / len * step, y: dip.y + v.y / len * step), 0)
    }

    // Scale unit, invariant-ish to finger spread (wrist -> middle MCP).
    var handSize: CGFloat {
        guard let w = p(.wrist), let m = p(.middleMCP) else { return 0 }
        return hypot(m.x - w.x, m.y - w.y)
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
    // The comparison is gated behind ONE flag (`HandCalibration.dorsalWhenSignedPositive`) so
    // that, if WRONG_FACE fires backwards on a device, it can be inverted in a single place
    // (a debug toggle in the coach view) rather than hunting through the geometry.
    // nil when a required MCP landmark is missing — the caller must decide what an
    // unverifiable face means rather than silently defaulting to dorsal (which would let a
    // partially-detected palm pass the TE3 dorsal gate).
    var isDorsal: Bool? {
        guard let w = p(.wrist), let i = p(.indexMCP), let pk = p(.pinkyMCP) else { return nil }
        let cross = (i.x - w.x) * (pk.y - w.y) - (i.y - w.y) * (pk.x - w.x)
        // The old front/rear-camera "cancellation" claim assumed chirality flips with the mirror —
        // it does NOT (Vision reads the un-mirrored buffer either way; only our manual x-flip
        // changes). So the parity of the coordinates must enter the sign explicitly, or the
        // back-camera (un-mirrored) mode reads dorsal/palmar BACKWARDS. The calibrated flag below
        // was tuned in the mirrored convention; `mirroredCoords` maps other parities onto it.
        let anatomical = (chirality == .right) ? cross : -cross
        let signed = mirroredCoords ? anatomical : -anatomical
        return HandCalibration.dorsalWhenSignedPositive ? signed > 0 : signed < 0
    }
}

// On-device calibration knobs, surfaced as debug toggles in the coach view so field
// calibration happens in one place.
enum HandCalibration {
    // dorsal <=> signed < 0. On-device the gate fired backwards (palm-to-camera was read as
    // dorsal / back), so the calibrated sign is inverted here. The single debug toggle in the
    // coach view re-inverts it in one place if a given device disagrees. Re-verify on hardware.
    static var dorsalWhenSignedPositive = false
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
