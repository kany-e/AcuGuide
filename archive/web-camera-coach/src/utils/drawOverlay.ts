import type { Landmark, Acupoint, CoachingState } from '../types'
import type { PressResult } from '../hooks/usePressDetection'
import { resolvePressFinger } from './landmarks'

interface OverlayOptions {
  state: CoachingState
  targetHand: Landmark[] | null
  pressingHand: Landmark[] | null
  acupoint: Acupoint
  pressResult: PressResult
  stateColor: string
}

export function drawOverlay(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  opts: OverlayOptions
) {
  const { state, targetHand, acupoint, pressResult, stateColor } = opts

  if (!targetHand || !pressResult.targetPoint) {
    if (state === 'NO_HAND') drawNoHandHint(ctx, w, h)
    return
  }

  // Use the SMOOTHED target from usePressDetection so the ring matches the hit-test.
  const target = pressResult.targetPoint
  const tx = target.x * w
  const ty = target.y * h
  const radius = acupoint.mediapipe_target.tolerance_radius_xHandSize * pressResult.handSizeVal * w

  // Target circle
  ctx.beginPath()
  ctx.arc(tx, ty, radius, 0, 2 * Math.PI)
  ctx.strokeStyle = stateColor
  ctx.lineWidth = 3
  ctx.globalAlpha = 0.9
  ctx.stroke()

  // Inner dot
  ctx.beginPath()
  ctx.arc(tx, ty, 4, 0, 2 * Math.PI)
  ctx.fillStyle = stateColor
  ctx.globalAlpha = 0.8
  ctx.fill()

  // Pressing fingertip marker (per-point finger: INDEX_TIP for TE3, thumb otherwise)
  if (opts.pressingHand) {
    const tip = opts.pressingHand[resolvePressFinger(acupoint.mediapipe_target.press_finger)]
    if (tip) {
      ctx.beginPath()
      ctx.arc(tip.x * w, tip.y * h, 8, 0, 2 * Math.PI)
      ctx.strokeStyle = 'white'
      ctx.lineWidth = 2
      ctx.globalAlpha = 0.7
      ctx.stroke()
    }
  }

  ctx.globalAlpha = 1
}

function drawNoHandHint(ctx: CanvasRenderingContext2D, w: number, h: number) {
  ctx.save()
  ctx.globalAlpha = 0.4
  ctx.strokeStyle = 'white'
  ctx.lineWidth = 2
  ctx.setLineDash([8, 4])
  ctx.beginPath()
  ctx.roundRect(w * 0.2, h * 0.25, w * 0.6, h * 0.5, 16)
  ctx.stroke()
  ctx.restore()
}
