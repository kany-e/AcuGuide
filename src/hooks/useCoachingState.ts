import { useState, useEffect, useRef } from 'react'
import type { CoachingState, Acupoint, SessionStats } from '../types'
import type { PressResult } from './usePressDetection'

const DEBOUNCE_MS = 300
const GRACE_MS = 1500
const MIN_STABLE_MS = 500

export function useCoachingState(
  press: PressResult,
  acupoint: Acupoint,
  wrongFaceDetected: boolean,
): { state: CoachingState; coachingMessage: string; sessionStats: SessionStats } {
  const [state, setState] = useState<CoachingState>('NO_HAND')

  // Timestamp-based debounce — immune to per-frame resets
  const pendingRef = useRef<{ next: CoachingState; since: number } | null>(null)

  // Hold timing
  const holdStartRef = useRef<number | null>(null)
  const accumulatedHoldRef = useRef(0)

  // Grace period for leaving target
  const leftTargetAtRef = useRef<number | null>(null)

  // Stability window
  const stableStartRef = useRef<number | null>(null)

  const [sessionStats, setSessionStats] = useState<SessionStats>({
    holdTimeMs: 0,
    stabilityPct: 85,
    rhythmConsistency: 'steady',
  })

  const targetDurationMs = acupoint.technique.duration_s * 1000

  function requestTransition(next: CoachingState) {
    const now = performance.now()
    if (pendingRef.current?.next !== next) {
      pendingRef.current = { next, since: now }
      return
    }
    if (now - pendingRef.current.since >= DEBOUNCE_MS) {
      pendingRef.current = null
      setState(next)
    }
  }

  useEffect(() => {
    if (state === 'COMPLETE') return

    const now = performance.now()

    // ── No hand / wrong face ──
    if (!press.hasTarget) {
      stableStartRef.current = null
      leftTargetAtRef.current = null
      requestTransition(wrongFaceDetected ? 'WRONG_FACE' : 'NO_HAND')
      return
    }

    // Hand detected — cancel any NO_HAND pending transition
    if (pendingRef.current?.next === 'NO_HAND') pendingRef.current = null

    // ── No pressing hand ──
    if (!press.hasPressing) {
      stableStartRef.current = null
      leftTargetAtRef.current = null
      requestTransition('SEARCHING')
      return
    }

    // ── Off target ──
    if (!press.isOnTarget) {
      stableStartRef.current = null

      if (state === 'HOLDING') {
        if (!leftTargetAtRef.current) leftTargetAtRef.current = now
        if (now - leftTargetAtRef.current < GRACE_MS) return // stay HOLDING during grace
        requestTransition('PAUSED')
      } else {
        leftTargetAtRef.current = null
        requestTransition('SEARCHING')
      }
      return
    }

    // On target
    leftTargetAtRef.current = null

    // ── Unstable ──
    if (!press.isStable) {
      stableStartRef.current = null
      requestTransition('ON_TARGET_UNSTABLE')
      return
    }

    // ── Stable on target ──
    if (!stableStartRef.current) stableStartRef.current = now
    if (now - stableStartRef.current < MIN_STABLE_MS) return

    // Transition to HOLDING if not already
    if (state !== 'HOLDING') {
      requestTransition('HOLDING')
      return
    }

    // ── Accumulate hold time ──
    if (!holdStartRef.current) holdStartRef.current = now
    const elapsed = now - holdStartRef.current
    const total = accumulatedHoldRef.current + elapsed

    if (total >= targetDurationMs) {
      accumulatedHoldRef.current = targetDurationMs
      setSessionStats({ holdTimeMs: targetDurationMs, stabilityPct: 90, rhythmConsistency: 'steady' })
      setState('COMPLETE')
      return
    }

    setSessionStats(prev => ({ ...prev, holdTimeMs: total }))
  })

  // Pause/resume hold timer when state changes
  useEffect(() => {
    if (state !== 'HOLDING' && holdStartRef.current != null) {
      accumulatedHoldRef.current += performance.now() - holdStartRef.current
      holdStartRef.current = null
    }
    if (state === 'HOLDING' && holdStartRef.current == null) {
      holdStartRef.current = performance.now()
    }
  }, [state])

  const copy = acupoint.coach_copy
  const wrongFaceMsg =
    acupoint.requires_hand_face === 'palm_to_camera'
      ? 'Turn your palm toward the camera'
      : 'Turn the back of your hand toward the camera'
  const messages: Record<CoachingState, string> = {
    NO_HAND: 'Bring your hand into the frame',
    WRONG_FACE: wrongFaceMsg,
    SEARCHING: copy.drift,
    ON_TARGET_UNSTABLE: 'Hold it steady',
    HOLDING: copy.hold,
    PAUSED: copy.drift,
    COMPLETE: 'Well done! Heading to recap…',
  }

  return { state, coachingMessage: messages[state], sessionStats }
}
