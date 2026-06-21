import { useMemo } from 'react'
import type { HandResult } from './useMediaPipe'
import type { Acupoint, Landmark } from '../types'
import { LANDMARKS } from '../utils/landmarks'

export interface ClassifiedHands {
  targetHand: Landmark[] | null
  pressingHand: Landmark[] | null
  wrongFaceDetected: boolean
}

function isDorsal(landmarks: Landmark[], handedness: 'Left' | 'Right'): boolean {
  const thumb = landmarks[LANDMARKS.THUMB_TIP]
  const pinky = landmarks[LANDMARKS.PINKY_MCP]
  if (!thumb || !pinky) return false
  // Empirically correct for both front and back cameras —
  // MediaPipe's handedness label already accounts for camera perspective.
  if (handedness === 'Left') return thumb.x > pinky.x
  return thumb.x < pinky.x
}

function isPalmar(landmarks: Landmark[], handedness: 'Left' | 'Right'): boolean {
  return !isDorsal(landmarks, handedness)
}

export function useHandClassifier(
  hands: HandResult[],
  acupoint: Acupoint,
): ClassifiedHands {
  return useMemo(() => {
    if (hands.length === 0) {
      return { targetHand: null, pressingHand: null, wrongFaceDetected: false }
    }

    const requiresDorsal =
      acupoint.requires_hand_face === 'back_of_hand_to_camera' ||
      acupoint.requires_hand_face === 'ulnar_edge_or_back_of_hand_to_camera'
    const requiresPalmar = acupoint.requires_hand_face === 'palm_to_camera'

    const faceOk = (h: HandResult) => {
      if (requiresDorsal) return isDorsal(h.landmarks, h.handedness)
      if (requiresPalmar) return isPalmar(h.landmarks, h.handedness)
      return true
    }

    if (hands.length === 1) {
      const hand = hands[0]
      const correct = faceOk(hand)
      return {
        targetHand: correct ? hand.landmarks : null,
        pressingHand: null,
        wrongFaceDetected: !correct,
      }
    }

    // 2 hands: target = correct face, pressing = the other
    const target = hands.find(faceOk)
    const pressing = hands.find(h => h !== target)
    return {
      targetHand: target?.landmarks ?? null,
      pressingHand: pressing?.landmarks ?? null,
      wrongFaceDetected: !target,
    }
  }, [hands, acupoint])
}
