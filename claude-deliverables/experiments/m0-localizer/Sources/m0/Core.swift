import Foundation
import CoreGraphics

// ── The AcuGuide localization contract, replicated EXACTLY (zero train/serve skew) ──────────────
// Joints (HandModel.swift), affine anchors (Acupoints.swift), handSize = |middleMCP − wrist|,
// weightedTarget = Σ wᵢ·kpᵢ in TOP-LEFT normalized image coords.

let JOINTS = ["wrist", "thumbTip", "indexTip", "middleTip", "ringTip", "pinkyTip",
              "indexMCP", "middleMCP", "ringMCP", "pinkyMCP"]

// Affine anchor weights, copied verbatim from Acupoints.swift MediaPipeTarget. All weights per
// point sum to 1.0 (verified) — i.e. these are the LINEAR special case the learned head generalizes.
let ANCHORS: [String: [(String, Double)]] = [
    "TE3": [("ringMCP", 0.46), ("pinkyMCP", 0.34), ("wrist", 0.20)],
    "SI3": [("pinkyMCP", 0.85), ("wrist", 0.35), ("ringMCP", -0.20)],
    "PC8": [("middleMCP", 0.50), ("indexMCP", 0.18), ("wrist", 0.32)],
    "HT7": [("wrist", 0.85), ("pinkyMCP", 0.15)],
    "PC6": [("wrist", 1.7), ("middleMCP", -0.7)],
    "SJ5": [("wrist", 1.7), ("middleMCP", -0.7)],   // = TE5 Waiguan, the 2nd point we share with MetaAcuPoint
    "TE4": [("wrist", 0.84), ("middleMCP", 0.09), ("ringMCP", 0.07)],
    "PC7": [("wrist", 0.90), ("middleMCP", 0.10)],
]

// weightedTarget — the exact affine map (HandModel.swift:42). nil if any anchor joint is missing.
func weightedTarget(_ pts: [String: CGPoint], _ anchors: [(String, Double)]) -> CGPoint? {
    var x = 0.0, y = 0.0, total = 0.0
    for (j, w) in anchors {
        guard let p = pts[j] else { return nil }
        x += Double(p.x) * w; y += Double(p.y) * w; total += w
    }
    return total > 0 ? CGPoint(x: x, y: y) : nil
}

func handSize(_ pts: [String: CGPoint]) -> Double {
    guard let w = pts["wrist"], let m = pts["middleMCP"] else { return 0 }
    return hypot(Double(m.x - w.x), Double(m.y - w.y))
}

func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }

// ── Canonical hand frame (the load-bearing design choice) ───────────────────────────────────────
// Origin = middleMCP (stable interior anchor; wrist jitters most). Scale = |middleMCP − wrist|.
// Rotation aligns wrist→middleMCP to canonical +Y. Chirality fold mirrors left hands onto the right
// frame so both hands + front/back-camera mirroring collapse into one frame. Similarity (no depth).
struct Canonical {
    let o: CGPoint       // origin (middleMCP)
    let s: Double        // scale (handSize)
    let c: Double        // cos φ
    let sn: Double       // sin φ
    let fold: Double     // +1 right hand, −1 left (mirror canonical x)

    // Build from a hand; nil if wrist/middleMCP missing or degenerate.
    init?(_ pts: [String: CGPoint], isRight: Bool) {
        guard let w = pts["wrist"], let m = pts["middleMCP"] else { return nil }
        let s = hypot(Double(m.x - w.x), Double(m.y - w.y))
        guard s > 1e-9 else { return nil }
        // u = unit(wrist→middleMCP); rotate by φ so u ↦ (0,1). θ = angle of u; φ = 90° − θ.
        let ux = Double(m.x - w.x) / s, uy = Double(m.y - w.y) / s
        let theta = atan2(uy, ux)
        let phi = (.pi / 2) - theta
        self.o = m; self.s = s; self.c = cos(phi); self.sn = sin(phi)
        self.fold = isRight ? 1 : -1
    }

    // image (top-left normalized) → canonical
    func to(_ p: CGPoint) -> CGPoint {
        let dx = Double(p.x - o.x) / s, dy = Double(p.y - o.y) / s
        let rx = c * dx - sn * dy
        let ry = sn * dx + c * dy
        return CGPoint(x: fold * rx, y: ry)
    }
    // canonical → image (exact inverse)
    func from(_ q: CGPoint) -> CGPoint {
        let rx = fold * Double(q.x), ry = Double(q.y)
        let dx = c * rx + sn * ry           // R⁻¹ = Rᵀ
        let dy = -sn * rx + c * ry
        return CGPoint(x: Double(o.x) + dx * s, y: Double(o.y) + dy * s)
    }
}

// ── Ridge least-squares (learned LINEAR keypoint→acupoint map; the M0 upgrade over hand-tuning) ──
// Solves (XᵀX + λI) w = Xᵀy per output dim via Gaussian elimination. Small dense systems (~21 feats).
enum LeastSquares {
    static func fit(X: [[Double]], Y: [[Double]], ridge: Double) -> [[Double]]? {
        guard let n = X.first?.count, !X.isEmpty, Y.count == X.count, let outDim = Y.first?.count else { return nil }
        // XtX (n×n) + λI, XtY (n×outDim)
        var XtX = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var XtY = Array(repeating: Array(repeating: 0.0, count: outDim), count: n)
        for row in 0..<X.count {
            let xr = X[row], yr = Y[row]
            for i in 0..<n {
                for j in 0..<n { XtX[i][j] += xr[i] * xr[j] }
                for k in 0..<outDim { XtY[i][k] += xr[i] * yr[k] }
            }
        }
        for i in 0..<n { XtX[i][i] += ridge }
        // Solve for each output column.
        var W = Array(repeating: Array(repeating: 0.0, count: outDim), count: n)
        for k in 0..<outDim {
            let b = (0..<n).map { XtY[$0][k] }
            guard let w = solve(XtX, b) else { return nil }
            for i in 0..<n { W[i][k] = w[i] }
        }
        return W   // n × outDim
    }

    static func predict(_ W: [[Double]], _ x: [Double]) -> [Double] {
        let outDim = W.first?.count ?? 0
        var out = Array(repeating: 0.0, count: outDim)
        for i in 0..<x.count { for k in 0..<outDim { out[k] += x[i] * W[i][k] } }
        return out
    }

    // Gaussian elimination with partial pivoting on a copy.
    static func solve(_ A0: [[Double]], _ b0: [Double]) -> [Double]? {
        let n = b0.count
        var A = A0, b = b0
        for col in 0..<n {
            var piv = col
            for r in (col+1)..<n where abs(A[r][col]) > abs(A[piv][col]) { piv = r }
            if abs(A[piv][col]) < 1e-12 { return nil }
            if piv != col { A.swapAt(piv, col); b.swapAt(piv, col) }
            let d = A[col][col]
            for r in 0..<n where r != col {
                let f = A[r][col] / d
                if f == 0 { continue }
                for c in col..<n { A[r][c] -= f * A[col][c] }
                b[r] -= f * b[col]
            }
        }
        return (0..<n).map { b[$0] / A[$0][$0] }
    }
}

// Feature vector for the learned map: all present joints in CANONICAL coords + bias. Missing joints
// → 0 (the mask is implicit here; M1's head adds an explicit mask channel). Deterministic order.
func canonicalFeatures(_ pts: [String: CGPoint], _ frame: Canonical) -> [Double] {
    var f: [Double] = []
    for j in JOINTS {
        if let p = pts[j] { let q = frame.to(p); f.append(Double(q.x)); f.append(Double(q.y)) }
        else { f.append(0); f.append(0) }
    }
    f.append(1.0)   // bias
    return f
}
