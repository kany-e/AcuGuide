export type SymptomId = 'tension_headache' | 'neck_shoulder_tension' | 'menstrual_discomfort'

export type CoachingState =
  | 'NO_HAND'
  | 'WRONG_FACE'
  | 'SEARCHING'
  | 'ON_TARGET_UNSTABLE'
  | 'HOLDING'
  | 'PAUSED'
  | 'COMPLETE'

export interface Landmark {
  x: number
  y: number
  z: number
}

export interface AnchorDef {
  landmark: number
  weight: number
  name: string
}

export interface MediapipeTarget {
  anchors?: AnchorDef[]
  tolerance_radius_xHandSize: number
  stability_threshold_xHandSize: number
  press_finger_default: string
  /** Per-point pressing fingertip landmark name (e.g. 'INDEX_TIP'); defaults to thumb. */
  press_finger?: string
  /** Provenance note for a calibrated/indicative tolerance. */
  tolerance_note?: string
}

export interface CoachCopy {
  align: string
  drift: string
  hold: string
}

export interface Acupoint {
  id: string
  pinyin: string
  tcm_name: string
  meridian: string
  surface: string
  requires_hand_face: string
  anatomy: string
  mediapipe_target: MediapipeTarget
  technique: {
    contact: string
    pressure: string
    duration_s: number
    rhythm: string
    side: string
  }
  coach_copy: CoachCopy
  contraindications: string[]
  safety_flags: string[]
}

export interface SessionStats {
  holdTimeMs: number
  stabilityPct: number
  // Position-hold steadiness (offset variance), NOT press cadence. Cadence is NO-GO
  // and is intentionally not estimated or shown this round.
  positionSteadiness: 'steady' | 'variable'
}

export type FeelingOption = 'relief' | 'no_change' | 'worse'
