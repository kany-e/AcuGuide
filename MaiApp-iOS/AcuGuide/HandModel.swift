import Foundation
import Vision
import CoreGraphics

// The subset of Vision hand joints we use, with a stable mapping to Vision's names.
enum HandJoint: Hashable {
    case wrist
    case thumbTip, indexTip, middleTip, ringTip, pinkyTip
    case indexMCP, middleMCP, ringMCP, pinkyMCP

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
        }
    }
}

// One detected hand. Points are normalized 0...1 in TOP-LEFT origin (already flipped
// from Vision's bottom-left), so they map directly onto the SwiftUI overlay.
struct Hand {
    var points: [HandJoint: CGPoint]
    var chirality: VNChirality   // .left / .right (Vision's handedness)

    func p(_ j: HandJoint) -> CGPoint? { points[j] }

    // Scale unit, invariant-ish to finger spread (wrist -> middle MCP).
    var handSize: CGFloat {
        guard let w = p(.wrist), let m = p(.middleMCP) else { return 0 }
        return hypot(m.x - w.x, m.y - w.y)
    }

    // Weighted sum of named landmarks → the acupoint target (image-normalized).
    func weightedTarget(_ anchors: [AnchorWeight]) -> CGPoint? {
        var x: CGFloat = 0, y: CGFloat = 0, total: CGFloat = 0
        for a in anchors {
            guard let pt = p(a.landmark) else { return nil }
            x += pt.x * a.weight; y += pt.y * a.weight; total += a.weight
        }
        return total > 0 ? CGPoint(x: x, y: y) : nil
    }

    // Palm vs back-of-hand via the signed cross of (wrist->index_mcp) x (wrist->pinky_mcp).
    // Ported from the web app's CALIBRATED, mirror-invariant test: dorsal <=> signed > 0.
    // (`signed` = cross for a right hand, -cross for a left hand; horizontal mirroring
    //  negates cross and swaps chirality, which cancel — so it holds for front/rear camera.)
    var isDorsal: Bool {
        guard let w = p(.wrist), let i = p(.indexMCP), let pk = p(.pinkyMCP) else { return true }
        let cross = (i.x - w.x) * (pk.y - w.y) - (i.y - w.y) * (pk.x - w.x)
        let signed = (chirality == .right) ? cross : -cross
        return signed > 0
    }
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
