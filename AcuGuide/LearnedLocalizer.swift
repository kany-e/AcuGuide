import Foundation
import CoreML
import CoreGraphics
import QuartzCore
import os

// M1 SHADOW-MODE localizer. Runs the learned CoreML head (AcupointHead.mlpackage) ALONGSIDE the affine
// `weightedTarget`, measures the learned−affine delta + inference latency, and NEVER changes coach
// behavior (it only reads a Hand and logs). Because the head is trained by affine-imitation, the live
// delta should be ~0; a large delta means a coordinate-convention mismatch to fix before any cut-over.
// See claude-deliverables/experiments/m1-head/ + references/acuguide_localizer_research.md (§10 M1).

// Canonical hand frame — ported VERBATIM from the M0 harness Core.swift and train.py: origin = middleMCP,
// scale = |middleMCP − wrist|, rotation aligns wrist→middleMCP to +Y, chirality fold mirrors left hands.
struct CanonicalFrame {
    let ox, oy, s, c, sn, fold: Double
    init?(_ pts: [HandJoint: CGPoint], isRight: Bool) {
        guard let w = pts[.wrist], let m = pts[.middleMCP] else { return nil }
        let scale = Double(hypot(m.x - w.x, m.y - w.y)); guard scale > 1e-9 else { return nil }
        let ux = Double(m.x - w.x) / scale, uy = Double(m.y - w.y) / scale
        let phi = Double.pi / 2 - atan2(uy, ux)
        ox = Double(m.x); oy = Double(m.y); s = scale; c = cos(phi); sn = sin(phi); fold = isRight ? 1 : -1
    }
    func to(_ p: CGPoint) -> (Double, Double) {
        let dx = (Double(p.x) - ox) / s, dy = (Double(p.y) - oy) / s
        return (fold * (c * dx - sn * dy), sn * dx + c * dy)
    }
    func from(_ qx: Double, _ qy: Double) -> CGPoint {
        let rx = fold * qx, ry = qy
        return CGPoint(x: ox + (c * rx + sn * ry) * s, y: oy + (-sn * rx + c * ry) * s)
    }
}

final class ShadowLocalizer {
    static let shared = ShadowLocalizer()
    // Master switch (shadow only: logging, no behavior change). Debug builds only — release users
    // shouldn't pay the (small) inference cost for telemetry no one reads.
    #if DEBUG
    static var enabled = true
    #else
    static var enabled = false
    #endif
    static let inferEveryNFrames = 3              // throttle inference cost while still sampling

    // Feature/point order MUST match train.py exactly (JOINTS / POINTS).
    static let joints: [HandJoint] = [.wrist, .thumbTip, .indexTip, .middleTip, .ringTip, .pinkyTip,
                                      .indexMCP, .middleMCP, .ringMCP, .pinkyMCP]
    static let points = ["TE3", "SI3", "PC8", "HT7", "PC6", "SJ5", "TE4", "PC7"]

    private let model: MLModel?
    private let log = Logger(subsystem: "app.acuguide", category: "shadow")
    // Stays .utility — telemetry must never compete with the coach for CPU. The Hang Risk Xcode
    // reported ("user-interactive thread waiting on a lower QoS thread") came from the main thread
    // WAITING on the semaphore below, not from this queue's priority: a fire-and-forget async to a
    // low-QoS queue inverts nothing, because nobody blocks on it. Removing the wait is the whole
    // fix. Raising this to .userInitiated as well was a mistake — on a 2-core CI runner it put
    // CoreML inference in contention with the test thread.
    private let q = DispatchQueue(label: "app.acuguide.shadow", qos: .utility)
    // In-flight gate. Was a DispatchSemaphore the MAIN thread wait()ed on and the worker signalled —
    // the half of the inversion the checker actually names. It is now a plain Bool confined to the
    // main thread (same confinement `frame` already relies on): record() sets it, and the worker
    // clears it by hopping back to main. It bounds the queue to one in-flight inference exactly as
    // the semaphore did, but the main thread never waits on anything. No lock, no new dependency,
    // and the extra main hop happens at most once per throttled frame, in DEBUG only.
    private var inFlight = false                      // main-thread only
    private var frame = 0                             // main-thread throttle counter
    // Per (point|regime) accumulator. `regime` splits idle vs two-hand PRESS frames — the press is when
    // the massaging hand occludes the receiving hand, the exact case the localizer research flags as the
    // hard one, so its delta/σ/joint-dropout must be read apart from idle frames. Bounded recent-sample
    // windows give p50/p90 (the occlusion tail the mean hides). Touched only on `q`.
    private struct Stat {
        var n = 0, skipped = 0, jointsSum = 0
        var sumA = 0.0, sumU = 0.0, maxA = 0.0
        var sumMs = 0.0, maxMs = 0.0
        var sumSig = 0.0, minSig = Double.greatestFiniteMagnitude, maxSig = 0.0
        var recentA: [Double] = [], recentU: [Double] = []   // bounded |Δ| windows for percentiles
    }
    private var stats: [String: Stat] = [:]           // keyed "<id>|<regime>"; touched only on `q`
    private static let recentCap = 400

    var isAvailable: Bool { model != nil }

    private init() {
        let b = Bundle(for: ShadowLocalizer.self)
        if let u = b.url(forResource: "AcupointHead", withExtension: "mlmodelc"), let m = try? MLModel(contentsOf: u) {
            model = m
        } else if let p = b.url(forResource: "AcupointHead", withExtension: "mlpackage"),
                  let comp = try? MLModel.compileModel(at: p), let m = try? MLModel(contentsOf: comp) {
            model = m                              // fallback: compile an uncompiled .mlpackage at runtime
        } else {
            model = nil                            // model not bundled → shadow silently disabled
        }
    }

    // Learned acupoint target in the SAME coordinate space as `hand.points`, + mean σ, or nil (nil when
    // wrist/middleMCP are absent — the frame can't be built). Joints Vision missed become 0 features (OOD).
    // `mirrorInput`: run the head on x-mirrored coords and mirror the result back — a control to test
    // whether the live selfie x-mirror is the cause of a delta (train.py coupled the mirror WITH the fold,
    // so live mirrored-points + true-chirality is out-of-distribution; this isolates that convention).
    func predict(hand: Hand, pointId pid: Int, mirrorInput: Bool = false) -> (target: CGPoint, sigma: CGFloat)? {
        let pts = mirrorInput ? hand.points.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) } : hand.points
        guard let model, let cf = CanonicalFrame(pts, isRight: hand.chirality == .right),
              let feats = try? MLMultiArray(shape: [1, 20], dataType: .float32),
              let pidArr = try? MLMultiArray(shape: [1], dataType: .int32) else { return nil }
        for (i, j) in Self.joints.enumerated() {
            if let p = pts[j] { let (qx, qy) = cf.to(p)
                feats[2 * i] = NSNumber(value: Float(qx)); feats[2 * i + 1] = NSNumber(value: Float(qy))
            } else { feats[2 * i] = 0; feats[2 * i + 1] = 0 }
        }
        pidArr[0] = NSNumber(value: Int32(pid))
        guard let prov = try? MLDictionaryFeatureProvider(dictionary: [
                "features": MLFeatureValue(multiArray: feats), "pointId": MLFeatureValue(multiArray: pidArr)]),
              let out = try? model.prediction(from: prov),
              let coord = out.featureValue(for: "coord")?.multiArrayValue else { return nil }
        var img = cf.from(coord[0].doubleValue, coord[1].doubleValue)
        if mirrorInput { img = CGPoint(x: 1 - img.x, y: img.y) }   // back into the input coordinate space
        let sig = out.featureValue(for: "sigma")?.multiArrayValue
        let sigma = sig != nil ? CGFloat((sig![0].doubleValue + sig![1].doubleValue) / 2) : 0
        return (img, sigma)
    }

    // SHADOW: compute the learned target next to the affine one, log the delta + latency. The coach path
    // only does a cheap throttle + non-blocking semaphore try + a value-type Hand copy — inference and all
    // mutable stats run on the serial `q`. Throttle is at ENQUEUE and the semaphore bounds the queue to ONE
    // in-flight block, so a slow inference can NEVER back the queue up (it just drops frames). Never races
    // with or adds latency to the coach.
    // `pressing` = a second (massaging) hand is present → the occlusion-prone PRESS regime; splits stats.
    func record(hand: Hand, point: Acupoint, affine: CGPoint, handSize: CGFloat, pressing: Bool) {
        guard Self.enabled, model != nil, handSize > 0, Self.points.contains(point.id) else { return }
        frame += 1                                                    // main-thread serial → no lock needed
        guard frame % Self.inferEveryNFrames == 0 else { return }     // throttle BEFORE enqueue
        guard !inFlight else { return }                               // drop the frame if one is in flight
        inFlight = true                                               // main-thread confined; no wait
        let id = point.id
        q.async { [weak self] in
            self?.doRecord(hand, id: id, affine: affine, handSize: handSize, pressing: pressing)
            // Clear on MAIN, where the flag lives — never signal a main-thread waiter from here.
            DispatchQueue.main.async { self?.inFlight = false }
        }
    }

    private func doRecord(_ hand: Hand, id: String, affine: CGPoint, handSize: CGFloat, pressing: Bool) {  // `q` only
        guard let pid = Self.points.firstIndex(of: id) else { return }
        let key = "\(id)|\(pressing ? "press" : "idle")"
        var s = stats[key] ?? Stat()
        let t0 = CACurrentMediaTime()
        guard let asis = predict(hand: hand, pointId: pid, mirrorInput: false) else {   // no middleMCP → skip
            s.skipped += 1; stats[key] = s; return
        }
        let ms = (CACurrentMediaTime() - t0) * 1000
        let unmir = predict(hand: hand, pointId: pid, mirrorInput: true)?.target
        let dA = Double(hypot(asis.target.x - affine.x, asis.target.y - affine.y)) / Double(handSize)
        let dU = unmir.map { Double(hypot($0.x - affine.x, $0.y - affine.y)) / Double(handSize) } ?? dA
        let sig = Double(asis.sigma)
        // Count only the TRAINED joints (Self.joints): HandVision now extracts indexPIP/indexDIP
        // too, and hand.points.count silently inflated this "/10" feature-coverage metric by up to
        // 2 joints — masking the fingertip-dropout regime the shadow analysis exists to expose.
        s.n += 1; s.jointsSum += Self.joints.filter { hand.points[$0] != nil }.count
        s.sumA += dA; s.sumU += dU; s.maxA = max(s.maxA, dA)
        s.sumMs += ms; s.maxMs = max(s.maxMs, ms)
        s.sumSig += sig; s.minSig = min(s.minSig, sig); s.maxSig = max(s.maxSig, sig)
        Self.push(&s.recentA, dA); Self.push(&s.recentU, dU)
        stats[key] = s
        if s.n % 30 == 0 { logStat(key, s) }   // periodic; `logSummary()` dumps every key on teardown
    }

    // Nearest-rank percentile of a bounded sample window (small arrays → the sort is negligible).
    private func pct(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted(); return s[Int((Double(s.count - 1) * p).rounded())]
    }
    private static func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v); if arr.count > recentCap { arr.removeFirst(arr.count - recentCap) }
    }

    // One consolidated line per (point|regime). asis = naive live (mirrored) delta; unmir = mirror-undone
    // (the cut-over convention) — the one whose p50/p90 must trend to ~0. σ + mean joint count expose
    // whether uncertainty tracks detector dropout (the basis for a future σ-driven adaptive ring).
    private func logStat(_ key: String, _ s: Stat) {
        // `.notice` level so the lines show in Console.app WITHOUT toggling "Include Info Messages".
        if s.n == 0 { log.notice("shadow \(key, privacy: .public): n=0 skip=\(s.skipped) (no usable frames)"); return }
        let n = Double(s.n)
        let line = String(format:
            "shadow %@: n=%ld skip=%ld joints=%.1f/10 | Δhs asis[mean=%.4f p90=%.4f max=%.4f] unmir[mean=%.4f p50=%.4f p90=%.4f] | σ[mean=%.4f %.4f..%.4f] | infer[mean=%.2f max=%.2f]ms",
            key, s.n, s.skipped, Double(s.jointsSum) / n,
            s.sumA / n, pct(s.recentA, 0.9), s.maxA,
            s.sumU / n, pct(s.recentU, 0.5), pct(s.recentU, 0.9),
            s.sumSig / n, s.minSig, s.maxSig, s.sumMs / n, s.maxMs)
        log.notice("\(line, privacy: .public)")
    }

    // Dump every (point|regime) accumulator at once — call on coach teardown so a device session's full
    // picture lands in one place instead of scraping interleaved periodic lines.
    func logSummary() {
        q.async { [weak self] in
            guard let self else { return }
            if self.stats.isEmpty {
                // Visible even when the head never ran (model not bundled/loaded, or no usable hand).
                self.log.notice("shadow summary: no samples this session (model available=\(self.model != nil))")
                return
            }
            self.log.notice("── shadow summary ──")
            for key in self.stats.keys.sorted() { self.logStat(key, self.stats[key]!) }
        }
    }
}
