import { useMemo } from 'react'
import type { HandResult } from './useMediaPipe'
import type { Acupoint, Landmark } from '../types'
import { LANDMARKS } from '../utils/landmarks'

export interface ClassifiedHands {
  targetHand: Landmark[] | null
  pressingHand: Landmark[] | null
  wrongFaceDetected: boolean
}

// 2D cross product of (WRIST→MIDDLE_MCP) and (INDEX_MCP→PINKY_MCP).
// Back camera, left hand, dorsal facing camera  → cross < 0
// Back camera, right hand, dorsal facing camera → cross > 0
// Front camera raw frame has x-axis mirrored vs back camera → flip result.
function isDorsalFacing(
  landmarks: Landmark[],
  userHand: 'Left' | 'Right',
  facingMode: 'user' | 'environment',
): boolean {
  const ax = landmarks[LANDMARKS.MIDDLE_MCP].x - landmarks[LANDMARKS.WRIST].x
  const ay = landmarks[LANDMARKS.MIDDLE_MCP].y - landmarks[LANDMARKS.WRIST].y
  const bx = landmarks[LANDMARKS.PINKY_MCP].x - landmarks[LANDMARKS.INDEX_MCP].x
  const by = landmarks[LANDMARKS.PINKY_MCP].y - landmarks[LANDMARKS.INDEX_MCP].y
  const cross = ax * by - ay * bx
  const dorsal = userHand === 'Left' ? cross < 0 : cross > 0
  return facingMode === 'user' ? !dorsal : dorsal
}

function faceIsCorrect(
  landmarks: Landmark[],
  userHand: 'Left' | 'Right',
  facingMode: 'user' | 'environment',
  requires: string,
): boolean {
  const dorsal = isDorsalFacing(landmarks, userHand, facingMode)
  if (requires === 'palm_to_camera') return !dorsal
  // back_of_hand_to_camera or ulnar_edge_or_back_of_hand_to_camera
  return dorsal
}

export function useHandClassifier(
  hands: HandResult[],
  acupoint: Acupoint,
  userHand: 'Left' | 'Right',
  facingMode: 'user' | 'environment',
): ClassifiedHands {
  return useMemo(() => {
    if (hands.length === 0) {
      return { targetHand: null, pressingHand: null, wrongFaceDetected: false }
    }

    if (hands.length === 1) {
      const lm = hands[0].landmarks
      const ok = faceIsCorrect(lm, userHand, facingMode, acupoint.requires_hand_face)
      return {
        targetHand: ok ? lm : null,
        pressingHand: null,
        wrongFaceDetected: !ok,
      }
    }

    // 2 hands: use face orientation to identify target rather than wrist position.
    // The target hand must have the correct face toward camera; the pressing hand
    // approaches from a different angle so its cross product sign will differ.
    const target = hands.find(h =>
      faceIsCorrect(h.landmarks, userHand, facingMode, acupoint.requires_hand_face)
    )
    const pressing = hands.find(h => h !== target) ?? null

    if (!target) {
      return { targetHand: null, pressingHand: null, wrongFaceDetected: true }
    }
    return { targetHand: target.landmarks, pressingHand: pressing?.landmarks ?? null, wrongFaceDetected: false }
  }, [hands, acupoint, userHand, facingMode])
}
