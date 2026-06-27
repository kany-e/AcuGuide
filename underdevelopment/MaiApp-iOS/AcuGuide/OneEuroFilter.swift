import CoreGraphics

// One-Euro filter (Casiez et al. 2012) — a faithful Swift port of src/utils/oneEuro.ts.
// Speed-adaptive: heavy smoothing when the hand is still (kills the jitter that appears
// when the pressing finger occludes the ring/pinky knuckles), light smoothing on fast
// motion (so the ring tracks without visible lag). Applied to the TARGET point before
// hit-testing and drawing, exactly as usePressDetection.ts does — raw landmarks are kept
// for the press tip.

struct OneEuroOptions {
    // Tuned for normalized [0,1] image coordinates at ~30fps, matching TARGET_SMOOTH_DEFAULTS.
    var minCutoff: Double = 1.0   // Hz — cutoff at zero velocity (lower = smoother / more lag at rest)
    var beta: Double = 1.5        // speed coefficient (higher = less lag on fast moves)
    var dCutoff: Double = 1.0     // Hz — cutoff for the velocity estimate
}

private final class LowPass {
    private var s: Double?
    func filter(_ x: Double, _ alpha: Double) -> Double {
        let y = s == nil ? x : alpha * x + (1 - alpha) * s!
        s = y
        return y
    }
    func reset() { s = nil }
}

private final class OneEuroScalar {
    private let xFilter = LowPass()
    private let dxFilter = LowPass()
    private var lastTimeSec: Double?
    private var prevX: Double?

    private let minCutoff, beta, dCutoff: Double
    init(_ minCutoff: Double, _ beta: Double, _ dCutoff: Double) {
        self.minCutoff = minCutoff; self.beta = beta; self.dCutoff = dCutoff
    }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    // tSec is a monotonic timestamp in seconds (CACurrentMediaTime()).
    func filter(_ x: Double, _ tSec: Double) -> Double {
        guard let last = lastTimeSec else {
            lastTimeSec = tSec
            prevX = x
            return xFilter.filter(x, 1)
        }
        var dt = tSec - last
        lastTimeSec = tSec
        if !(dt > 0) { dt = 1.0 / 30.0 } // guard against zero/negative dt (duplicate frames)

        let dx = (x - (prevX ?? x)) / dt
        prevX = x
        let edx = dxFilter.filter(dx, alpha(dCutoff, dt))
        let cutoff = minCutoff + beta * abs(edx)
        return xFilter.filter(x, alpha(cutoff, dt))
    }

    func reset() { xFilter.reset(); dxFilter.reset(); lastTimeSec = nil; prevX = nil }
}

// Smooths a 2-D point with independent One-Euro filters on each axis.
final class OneEuroPoint {
    private let fx, fy: OneEuroScalar
    init(_ opts: OneEuroOptions = OneEuroOptions()) {
        fx = OneEuroScalar(opts.minCutoff, opts.beta, opts.dCutoff)
        fy = OneEuroScalar(opts.minCutoff, opts.beta, opts.dCutoff)
    }
    func filter(_ p: CGPoint, _ tSec: Double) -> CGPoint {
        CGPoint(x: fx.filter(Double(p.x), tSec), y: fy.filter(Double(p.y), tSec))
    }
    func reset() { fx.reset(); fy.reset() }
}
