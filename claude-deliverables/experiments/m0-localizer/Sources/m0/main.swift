import Foundation
import CoreGraphics

// ── M0: does a keypoint-conditioned map match MetaAcuPoint's MDE on the shared points (TE3, TE5)? ──
// Usage:
//   swift run m0 --selftest                         # validate geometry + fit pipeline (no data)
//   swift run m0 --images DIR --labels coco.json     # real eval once MetaAcuPoint access is granted
//        [--points TE3,SJ5] [--folds 5]
// See claude-deliverables/references/acuguide_localizer_research.md (§9 Day-1 experiment).

// Reproducible RNG (Math.random-free; seeded LCG) so splits/self-test are deterministic.
struct LCG: RandomNumberGenerator { var s: UInt64; init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s } }

let args = CommandLine.arguments
func opt(_ k: String) -> String? { guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }; return args[i + 1] }

// MDE in PIXELS for one sample (normalized top-left err scaled by the image's real pixel dims).
func pxError(_ predN: CGPoint, _ labelN: CGPoint, w: Double, h: Double) -> Double {
    hypot(Double(predN.x - labelN.x) * w, Double(predN.y - labelN.y) * h)
}
func meanStd(_ v: [Double]) -> (Double, Double) {
    guard !v.isEmpty else { return (0, 0) }
    let m = v.reduce(0, +) / Double(v.count)
    let sd = (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    return (m, sd)
}

// ── Real evaluation over a MetaAcuPoint-style image folder + COCO labels ─────────────────────────
func runEval(imagesDir: String, labelsPath: String, points: [String], folds: Int) {
    guard let labels = loadCOCO(labelsPath) else { print("ERROR: could not read COCO labels at \(labelsPath)"); exit(2) }
    let fm = FileManager.default
    let files = (try? fm.contentsOfDirectory(atPath: imagesDir))?.filter {
        let l = $0.lowercased(); return l.hasSuffix(".png") || l.hasSuffix(".jpg") || l.hasSuffix(".jpeg")
    }.sorted() ?? []
    print("images on disk: \(files.count) · labeled records: \(labels.count) · target points: \(points.joined(separator: ","))")

    // Per point: collect samples {feature vec, canonical label, image-space label, w, h, affinePred}.
    struct Sample { var feat: [Double]; var canonLabel: CGPoint; var frame: Canonical; var labelN: CGPoint; var w: Double; var h: Double; var affineN: CGPoint? }
    var samples: [String: [Sample]] = [:]; points.forEach { samples[$0] = [] }
    var considered = 0, handOK = 0

    for f in files {
        guard let rec = labels[f], rec.width > 0, rec.height > 0 else { continue }
        // Only images that carry at least one of our target labels.
        guard points.contains(where: { rec.points[$0] != nil }) else { continue }
        considered += 1
        guard let cg = loadCGImage(imagesDir + "/" + f) else { continue }
        let hands = detectHands(cg)
        guard !hands.isEmpty else { continue }
        // Associate the hand: pick the one whose affine TE3 (fallback: wrist) lands nearest the labeled
        // TE3 (fallback: label centroid) — robust hand-to-label matching when both hands are present.
        let labelN: (String) -> CGPoint? = { name in rec.points[name].map { CGPoint(x: Double($0.x) / rec.width, y: Double($0.y) / rec.height) } }
        let anchorLabel = labelN("TE3") ?? points.compactMap(labelN).first
        func score(_ h: DetHand) -> Double {
            let pred = weightedTarget(h.points, ANCHORS["TE3"]!) ?? h.points["wrist"]!
            return anchorLabel.map { dist(pred, $0) } ?? -Double(h.confidence)
        }
        guard let hand = hands.min(by: { score($0) < score($1) }),
              let frame = Canonical(hand.points, isRight: hand.isRight), handSize(hand.points) > 1e-6 else { continue }
        handOK += 1
        let feat = canonicalFeatures(hand.points, frame)
        for pt in points {
            guard let ln = labelN(pt) else { continue }
            // Round-trip / detector-agreement guard: need the anchor joints present (affine computable).
            let affine = weightedTarget(hand.points, ANCHORS[pt] ?? [])
            samples[pt]!.append(Sample(feat: feat, canonLabel: frame.to(ln), frame: frame, labelN: ln, w: rec.width, h: rec.height, affineN: affine))
        }
    }

    print(String(format: "associated hands: %d/%d considered (%.0f%% retained)\n", handOK, considered, considered > 0 ? 100.0 * Double(handOK) / Double(considered) : 0))
    let paper: [String: String] = ["TE3": "MetaAcuPoint TE3: 3.78px(real)/5.01px(synth)",
                                   "SJ5": "MetaAcuPoint TE5: 5.68px(real)/5.81px(synth)"]
    print("point |  n  | affine-anchor MDE px | learned-linear MDE px (\(folds)-fold) | reference")
    print("------+-----+----------------------+--------------------------------+----------")
    for pt in points {
        let s = samples[pt] ?? []
        guard s.count >= folds else { print("\(pt.padding(toLength: 5, withPad: " ", startingAt: 0)) | \(s.count) | (too few samples)"); continue }
        // Affine baseline: no training — error on every sample with an affine prediction.
        let affErr = s.compactMap { smp in smp.affineN.map { pxError($0, smp.labelN, w: smp.w, h: smp.h) } }
        // Learned linear map: k-fold CV, predicting the image-normalized label from canonical features
        // (equivalent to canonical target + un-projection, without storing per-sample frames).
        let learnErr = kfoldLearnedMDE(s.map { (feat: $0.feat, canon: $0.canonLabel, frame: $0.frame, labelN: $0.labelN, w: $0.w, h: $0.h) }, folds: folds)
        let (am, asd) = meanStd(affErr); let (lm, lsd) = meanStd(learnErr)
        print(String(format: "%-5@ | %3d | %8.2f ± %-6.2f    | %8.2f ± %-6.2f              | %@",
                     pt as NSString, s.count, am, asd, lm, lsd, (paper[pt] ?? "—") as NSString))
    }
    print("\nNOTE: 'learned-linear' is the M0 falsification probe (a least-squares refit of the affine map).")
    print("A learned MDE ≲ affine MDE and ≲ MetaAcuPoint's px on TE3/SJ5 supports the hypothesis (see design doc §9).")
}

// k-fold CV of the learned KEYPOINT-CONDITIONED map: fit canonical features → CANONICAL acupoint,
// then un-project per-sample frame back to image space and measure px error vs the label. This is
// the correct formulation — canonical features are frame-invariant, so the target must be canonical.
func kfoldLearnedMDE(_ data: [(feat: [Double], canon: CGPoint, frame: Canonical, labelN: CGPoint, w: Double, h: Double)], folds: Int) -> [Double] {
    var idx = Array(0..<data.count); var rng = LCG(1234); idx.shuffle(using: &rng)
    var errs: [Double] = []
    for k in 0..<folds {
        let testIdx = Set(stride(from: k, to: data.count, by: folds).map { idx[$0] })
        let train = (0..<data.count).filter { !testIdx.contains($0) }
        let X = train.map { data[$0].feat }, Y = train.map { [Double(data[$0].canon.x), Double(data[$0].canon.y)] }
        guard let W = LeastSquares.fit(X: X, Y: Y, ridge: 1e-4) else { continue }
        for t in testIdx {
            let pc = LeastSquares.predict(W, data[t].feat)
            let pimg = data[t].frame.from(CGPoint(x: pc[0], y: pc[1]))
            errs.append(pxError(pimg, data[t].labelN, w: data[t].w, h: data[t].h))
        }
    }
    return errs
}

// ── Self-test: validate the geometry + fit pipeline with NO images (data is access-restricted) ───
func runSelfTest() {
    var pass = true
    func check(_ name: String, _ ok: Bool, _ detail: String = "") { print("[\(ok ? "PASS" : "FAIL")] \(name) \(detail)"); if !ok { pass = false } }

    // A synthetic right hand (top-left normalized-ish layout): wrist below, MCPs above, tips higher.
    let hand: [String: CGPoint] = [
        "wrist": CGPoint(x: 0.50, y: 0.80), "indexMCP": CGPoint(x: 0.44, y: 0.55),
        "middleMCP": CGPoint(x: 0.50, y: 0.52), "ringMCP": CGPoint(x: 0.56, y: 0.54),
        "pinkyMCP": CGPoint(x: 0.62, y: 0.58), "indexTip": CGPoint(x: 0.42, y: 0.30),
        "middleTip": CGPoint(x: 0.50, y: 0.27), "ringTip": CGPoint(x: 0.58, y: 0.30),
        "pinkyTip": CGPoint(x: 0.66, y: 0.36), "thumbTip": CGPoint(x: 0.34, y: 0.62),
    ]
    guard let frame = Canonical(hand, isRight: true) else { check("frame builds", false); print("ABORT"); exit(1) }

    // 1) Canonical round-trip: to(from(·)) ≈ identity for every joint.
    var rt = 0.0; for p in hand.values { let q = frame.from(frame.to(p)); rt = max(rt, dist(p, q)) }
    check("canonical round-trip", rt < 1e-9, String(format: "max err %.2e", rt))

    // 2) Similarity invariance: apply a rotation+scale+translation to ALL joints; canonical coords
    //    (recomputed from the transformed wrist/middleMCP) must be unchanged. This is the property that
    //    buys cross-viewpoint stability BY CONSTRUCTION (design doc hypothesis (c)).
    let ang = 0.7, sc = 1.8, tx = -0.2, ty = 0.35
    func xf(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        return CGPoint(x: sc * (cos(ang) * x - sin(ang) * y) + tx, y: sc * (sin(ang) * x + cos(ang) * y) + ty)
    }
    let hand2 = hand.mapValues(xf)
    guard let frame2 = Canonical(hand2, isRight: true) else { check("frame2 builds", false); exit(1) }
    var inv = 0.0; for j in JOINTS { if let a = hand[j], let b = hand2[j] { inv = max(inv, dist(frame.to(a), frame2.to(b))) } }
    check("similarity (view/scale/translation) invariance", inv < 1e-9, String(format: "max canonical drift %.2e", inv))

    // 3) Affine anchors reproduce a hand-computed weighted sum (the map we must not regress).
    let te3 = weightedTarget(hand, ANCHORS["TE3"]!)!
    let manual = CGPoint(x: 0.46 * Double(hand["ringMCP"]!.x) + 0.34 * Double(hand["pinkyMCP"]!.x) + 0.20 * Double(hand["wrist"]!.x),
                         y: 0.46 * Double(hand["ringMCP"]!.y) + 0.34 * Double(hand["pinkyMCP"]!.y) + 0.20 * Double(hand["wrist"]!.y))
    check("affine anchor (TE3) matches manual weighted sum", dist(te3, manual) < 1e-12)

    // 4) Least-squares recovers a planted LINEAR keypoint→acupoint map (the M0 learning step).
    //    Plant a random-but-fixed W over canonical features; generate many synthetic hands; fit; the
    //    held-out image-space MDE must be ~0 (clean) and small under joint noise.
    var rng = LCG(7)
    let nFeat = JOINTS.count * 2 + 1
    // Planted GROUND-TRUTH keypoint→acupoint map: wTrue maps canonical features → a 2D canonical point.
    let wTrue: [[Double]] = (0..<nFeat).map { _ in [Double.random(in: -0.3...0.3, using: &rng), Double.random(in: -0.3...0.3, using: &rng)] }
    func randHand() -> [String: CGPoint] {
        let a = Double.random(in: -0.6...0.6, using: &rng), s = Double.random(in: 0.6...1.6, using: &rng)
        let tx = Double.random(in: 0.1...0.9, using: &rng), ty = Double.random(in: 0.1...0.9, using: &rng)
        func t(_ p: CGPoint) -> CGPoint {                       // per-joint ARTICULATION jitter + random similarity
            let jx = Double(p.x) + Double.random(in: -0.03...0.03, using: &rng)
            let jy = Double(p.y) + Double.random(in: -0.03...0.03, using: &rng)
            return CGPoint(x: s * (cos(a) * jx - sin(a) * jy) + tx, y: s * (sin(a) * jx + cos(a) * jy) + ty)
        }
        return hand.mapValues(t)
    }
    var X4: [[Double]] = [], Y4: [[Double]] = [], test4: [([String: CGPoint], CGPoint)] = []
    for i in 0..<500 {
        let h = randHand(); guard let fr = Canonical(h, isRight: true) else { continue }
        let feat = canonicalFeatures(h, fr)
        let canon = LeastSquares.predict(wTrue, feat)          // planted keypoint-DEPENDENT canonical acupoint
        let canonPt = CGPoint(x: canon[0], y: canon[1])
        let img = fr.from(canonPt)                              // its image-space "label" for this hand
        if i % 5 == 0 { test4.append((h, img)) }
        else {
            let noisy = CGPoint(x: Double(canonPt.x) + Double.random(in: -0.003...0.003, using: &rng),
                                y: Double(canonPt.y) + Double.random(in: -0.003...0.003, using: &rng))
            X4.append(feat); Y4.append([Double(noisy.x), Double(noisy.y)])
        }
    }
    guard let W4 = LeastSquares.fit(X: X4, Y: Y4, ridge: 1e-6) else { check("least-squares fit", false); exit(1) }
    var mde = 0.0; for (h, label) in test4 { guard let fr = Canonical(h, isRight: true) else { continue }
        let pc = LeastSquares.predict(W4, canonicalFeatures(h, fr))
        mde += dist(fr.from(CGPoint(x: pc[0], y: pc[1])), label) }
    mde /= Double(max(1, test4.count))
    check("learned linear map recovers a planted keypoint→acupoint map", mde < 0.02, String(format: "held-out image MDE %.4f (normalized)", mde))

    print(pass ? "\nSELF-TEST: all checks passed — geometry + learned-fit pipeline are correct." :
                 "\nSELF-TEST: FAILURES above.")
    exit(pass ? 0 : 1)
}

// ── entry ────────────────────────────────────────────────────────────────────────────────────────
if args.contains("--selftest") || (opt("--images") == nil && opt("--labels") == nil) {
    runSelfTest()
} else if let dir = opt("--images"), let lab = opt("--labels") {
    let pts = (opt("--points") ?? "TE3,SJ5").split(separator: ",").map(String.init)
    runEval(imagesDir: dir, labelsPath: lab, points: pts, folds: Int(opt("--folds") ?? "5") ?? 5)
} else {
    print("usage: m0 --selftest | m0 --images DIR --labels coco.json [--points TE3,SJ5] [--folds 5]")
    exit(64)
}
