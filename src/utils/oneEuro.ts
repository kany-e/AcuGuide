// One-Euro filter (Casiez et al. 2012) for smoothing the target point.
// Speed-adaptive: heavy smoothing when the hand is still (kills the jitter that
// appears when the pressing finger occludes the ring/pinky knuckles), light
// smoothing when the hand moves fast (so the ring tracks without visible lag).
//
// The calibration GO rested on the MEDIAN target position, not per-frame precision,
// so this just matches the on-screen feedback to what is actually reliable.

export interface OneEuroOptions {
  minCutoff?: number // Hz — cutoff at zero velocity (lower = smoother / more lag at rest)
  beta?: number // speed coefficient (higher = less lag on fast moves)
  dCutoff?: number // Hz — cutoff for the velocity estimate
}

// Tuned for normalized [0,1] image coordinates at ~30fps. Tunable if the ring
// drags behind fast motion (raise beta) or still jitters under occlusion (lower minCutoff).
export const TARGET_SMOOTH_DEFAULTS: Required<OneEuroOptions> = {
  minCutoff: 1.0,
  beta: 1.5,
  dCutoff: 1.0,
}

class LowPass {
  private s: number | null = null

  filter(x: number, alpha: number): number {
    this.s = this.s === null ? x : alpha * x + (1 - alpha) * this.s
    return this.s
  }

  reset(): void {
    this.s = null
  }
}

class OneEuroScalar {
  private readonly xFilter = new LowPass()
  private readonly dxFilter = new LowPass()
  private lastTimeMs: number | null = null
  private prevX: number | null = null

  constructor(
    private readonly minCutoff: number,
    private readonly beta: number,
    private readonly dCutoff: number,
  ) {}

  private alpha(cutoff: number, dt: number): number {
    const tau = 1 / (2 * Math.PI * cutoff)
    return 1 / (1 + tau / dt)
  }

  filter(x: number, tMs: number): number {
    if (this.lastTimeMs === null) {
      this.lastTimeMs = tMs
      this.prevX = x
      return this.xFilter.filter(x, 1)
    }
    let dt = (tMs - this.lastTimeMs) / 1000
    this.lastTimeMs = tMs
    if (!(dt > 0)) dt = 1 / 30 // guard against zero/negative dt (e.g. duplicate frames)

    const dx = (x - (this.prevX ?? x)) / dt
    this.prevX = x
    const edx = this.dxFilter.filter(dx, this.alpha(this.dCutoff, dt))
    const cutoff = this.minCutoff + this.beta * Math.abs(edx)
    return this.xFilter.filter(x, this.alpha(cutoff, dt))
  }

  reset(): void {
    this.xFilter.reset()
    this.dxFilter.reset()
    this.lastTimeMs = null
    this.prevX = null
  }
}

export interface Point2D {
  x: number
  y: number
  z: number
}

// Smooths a 2-D point (x,y) with independent One-Euro filters; z passes through.
export class OneEuroPoint {
  private readonly fx: OneEuroScalar
  private readonly fy: OneEuroScalar

  constructor(opts: OneEuroOptions = {}) {
    const { minCutoff, beta, dCutoff } = { ...TARGET_SMOOTH_DEFAULTS, ...opts }
    this.fx = new OneEuroScalar(minCutoff, beta, dCutoff)
    this.fy = new OneEuroScalar(minCutoff, beta, dCutoff)
  }

  filter(p: Point2D, tMs: number): Point2D {
    return { x: this.fx.filter(p.x, tMs), y: this.fy.filter(p.y, tMs), z: p.z }
  }

  reset(): void {
    this.fx.reset()
    this.fy.reset()
  }
}
