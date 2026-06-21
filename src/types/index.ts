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
  rhythmConsistency: 'steady' | 'variable'
}

export type FeelingOption = 'relief' | 'no_change' | 'worse'
