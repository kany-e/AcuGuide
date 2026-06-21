import { useMemo } from 'react'
import type { HandResult } from './useMediaPipe'
import type { Acupoint, Landmark } from '../types'
import { LANDMARKS, resolvePressFinger } from '../utils/landmarks'
import { weightedTarget, handSize, euclidean } from '../utils/geometry'

export interface ClassifiedHands {
  targetHand: Landmark[] | null
  pressingHand: Landmark[] | null
  wrongFaceDetected: boolean
}

// Palm vs back-of-hand via the signed area (z of the 3D cross product) of
// (wrist->index_mcp) x (wrist->pinky_mcp). ROTATION-INVARIANT — it depends on the
// triangle's winding, which flips between the palm and the dorsum regardless of hand
// rotation (unlike the old thumb.x/pinky.x test, which only worked upright AND was
// inverted, so a palm read as dorsal and WRONG_FACE never fired).
//
// `signed` = cross for a 'Right' label, -cross for 'Left'. This quantity is INVARIANT to
// image mirroring (a horizontal flip negates `cross` and swaps the handedness label,
// which cancel), so the same sign works for the front and rear camera. The threshold was
// CALIBRATED on the labeled re-shoot clips (palmar PC6 hands signed ~ -0.05; dorsal TE3
// hands signed ~ +0.05; 7/8 correct, the miss being the degenerate 1934 clip):
//   dorsal  <=>  signed > 0 .
// Heuristic (the cross-product face test is only moderately reliable), so the gate's
// consequence is a gentle "turn your hand over" prompt, not a hard error.
const DORSAL_WHEN_SIGNED_POSITIVE = true

function handFace(landmarks: Landmark[], handedness: 'Left' | 'Right'): 'dorsal' | 'palmar' {
  const w = landmarks[LANDMARKS.WRIST]
  const i = landmarks[LANDMARKS.INDEX_MCP]
  const p = landmarks[LANDMARKS.PINKY_MCP]
  if (!w || !i || !p) return 'dorsal'
  const cross = (i.x - w.x) * (p.y - w.y) - (i.y - w.y) * (p.x - w.x)
  const signed = handedness === 'Right' ? cross : -cross
  const dorsal = DORSAL_WHEN_SIGNED_POSITIVE ? signed > 0 : signed < 0
  return dorsal ? 'dorsal' : 'palmar'
}

// Two detections are the SAME physical hand (a MediaPipe phantom duplicate) when they
// share handedness and their wrists nearly coincide relative to hand size. Such a pair
// must NOT be treated as receiver+presser — that produced a false on-target press.
function isSameHand(a: HandResult, b: HandResult): boolean {
  if (a.handedness !== b.handedness) return false
  const hs = Math.max(handSize(a.landmarks), handSize(b.landmarks), 1e-6)
  return euclidean(a.landmarks[LANDMARKS.WRIST], b.landmarks[LANDMARKS.WRIST]) < 0.5 * hs
}

export function useHandClassifier(
  hands: HandResult[],
  acupoint: Acupoint,
  facingMode: 'user' | 'environment',
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
      if (requiresDorsal) return handFace(h.landmarks, h.handedness) === 'dorsal'
      if (requiresPalmar) return handFace(h.landmarks, h.handedness) === 'palmar'
      return true
    }

    // Collapse a phantom duplicate to one hand so it can't masquerade as the presser.
    const distinct: HandResult[] =
      hands.length === 2 && isSameHand(hands[0], hands[1])
        ? [handSize(hands[0].landmarks) >= handSize(hands[1].landmarks) ? hands[0] : hands[1]]
        : hands

    // One hand = the RECEIVING hand. No separated presser yet -> pressingHand null, which
    // forces SEARCHING (capture coaching). We never treat a lone hand as the presser.
    if (distinct.length === 1) {
      const receiver = distinct[0]
      const ok = faceOk(receiver)
      return {
        targetHand: ok ? receiver.landmarks : null,
        pressingHand: null,
        wrongFaceDetected: !ok,
      }
    }

    // Two distinct hands: the RECEIVER is the hand being pressed — its target region is
    // closest to the OTHER hand's pressing fingertip. Robust to size/detection order, and
    // (unlike "first correct-face hand") it does not mis-assign when the receiver shows the
    // wrong face — so the face gate below actually fires.
    const anchors = acupoint.mediapipe_target.anchors
    const pressIdx = resolvePressFinger(acupoint.mediapipe_target.press_finger)
    const [h0, h1] = distinct
    let receiver = h0
    let presser = h1
    if (anchors) {
      const pressDist = (recv: HandResult, other: HandResult) => {
        const tip = other.landmarks[pressIdx] ?? other.landmarks[LANDMARKS.THUMB_TIP]
        return euclidean(weightedTarget(recv.landmarks, anchors), tip)
      }
      if (pressDist(h1, h0) < pressDist(h0, h1)) {
        receiver = h1
        presser = h0
      }
    } else if (handSize(h1.landmarks) > handSize(h0.landmarks)) {
      // No anchors (off-model points): fall back to the larger (presented) hand.
      receiver = h1
      presser = h0
    }

    // Gate on the RECEIVING hand's face — position alone cannot catch a wrong-face press
    // (calibration's lone false-accept was exactly a wrong-face clip).
    if (!faceOk(receiver)) {
      return { targetHand: null, pressingHand: null, wrongFaceDetected: true }
    }
    return {
      targetHand: receiver.landmarks,
      pressingHand: presser.landmarks,
      wrongFaceDetected: false,
    }
  }, [hands, acupoint, facingMode])
}
