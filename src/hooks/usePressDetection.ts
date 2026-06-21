import { useMemo, useRef } from 'react'
import type { Acupoint, Landmark } from '../types'
import { LANDMARKS } from '../utils/landmarks'
import { euclidean, handSize, weightedTarget, offsetVariance } from '../utils/geometry'

const OFFSET_BUFFER_FRAMES = 15 // ~0.5s at 30fps

export interface PressResult {
  targetPoint: Landmark | null
  handSizeVal: number
  isOnTarget: boolean
  isStable: boolean
  hasTarget: boolean
  hasPressing: boolean
}

export function usePressDetection(
  targetHand: Landmark[] | null,
  pressingHand: Landmark[] | null,
  acupoint: Acupoint
): PressResult {
  const offsetHistory = useRef<{ dx: number; dy: number }[]>([])

  return useMemo(() => {
    if (!targetHand) {
      offsetHistory.current = []
      return { targetPoint: null, handSizeVal: 0, isOnTarget: false, isStable: false, hasTarget: false, hasPressing: false }
    }

    const hs = handSize(targetHand)
    if (hs === 0) {
      return { targetPoint: null, handSizeVal: 0, isOnTarget: false, isStable: false, hasTarget: true, hasPressing: !!pressingHand }
    }

    const anchors = acupoint.mediapipe_target.anchors
    if (!anchors) {
      return { targetPoint: null, handSizeVal: hs, isOnTarget: false, isStable: false, hasTarget: true, hasPressing: !!pressingHand }
    }

    const target = weightedTarget(targetHand, anchors)
    const tolerance = acupoint.mediapipe_target.tolerance_radius_xHandSize * hs
    const stabilityThreshold = acupoint.mediapipe_target.stability_threshold_xHandSize * hs

    const pressingTip = pressingHand
      ? pressingHand[LANDMARKS.THUMB_TIP]
      : null

    let isOnTarget = false
    let isStable = false

    if (pressingTip) {
      const dist = euclidean(pressingTip, target)
      isOnTarget = dist < tolerance

      const offset = { dx: pressingTip.x - target.x, dy: pressingTip.y - target.y }
      offsetHistory.current = [...offsetHistory.current.slice(-(OFFSET_BUFFER_FRAMES - 1)), offset]

      if (offsetHistory.current.length >= 5) {
        const variance = offsetVariance(offsetHistory.current)
        isStable = variance < stabilityThreshold
      }
    } else {
      offsetHistory.current = []
    }

    return { targetPoint: target, handSizeVal: hs, isOnTarget, isStable, hasTarget: true, hasPressing: !!pressingHand }
  }, [targetHand, pressingHand, acupoint])
}
