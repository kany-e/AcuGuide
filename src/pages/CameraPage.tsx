import { useEffect, useRef, useState, useCallback } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import type { CoachingState, SymptomId, Acupoint } from '../types'
import { useMediaPipe } from '../hooks/useMediaPipe'
import { useHandClassifier } from '../hooks/useHandClassifier'
import { usePressDetection } from '../hooks/usePressDetection'
import { useCoachingState } from '../hooks/useCoachingState'
import { drawOverlay } from '../utils/drawOverlay'
import { useTTS } from '../hooks/useTTS'
import acupointsData from '../data/acupoints.json'

const SYMPTOM_POINT: Record<string, string> = {
  tension_headache: 'TE3',
  neck_shoulder_tension: 'SI3',
  menstrual_discomfort: 'PC6',
}

const STATE_COLORS: Record<CoachingState, string> = {
  NO_HAND: '#6b7280',
  WRONG_FACE: '#f59e0b',
  SEARCHING: '#ff8a3d',
  ON_TARGET_UNSTABLE: '#82d8ff',
  HOLDING: '#c8ff3d',
  PAUSED: '#ff8a3d',
  COMPLETE: '#c8ff3d',
}

const STATE_LABELS: Record<CoachingState, string> = {
  NO_HAND: 'Looking for hand',
  WRONG_FACE: 'Wrong orientation',
  SEARCHING: 'Adjust position',
  ON_TARGET_UNSTABLE: 'Hold steady',
  HOLDING: 'Good position',
  PAUSED: 'Adjust position',
  COMPLETE: 'Complete',
}

export default function CameraPage() {
  const { symptomId } = useParams<{ symptomId: SymptomId }>()
  const navigate = useNavigate()
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const animFrameRef = useRef<number>(0)

  const pointId = SYMPTOM_POINT[symptomId ?? ''] ?? 'TE3'
  const acupoint = (acupointsData as unknown as { acupoints: Acupoint[] }).acupoints.find(
    p => p.id === pointId,
  )!

  // State declarations first — facingMode is needed by useHandClassifier below
  const [cameraError, setCameraError] = useState<string | null>(null)
  const [mediaPipeError, setMediaPipeError] = useState<string | null>(null)
  const [facingMode, setFacingMode] = useState<'environment' | 'user'>('environment')
  const { hands, initMediaPipe, isReady } = useMediaPipe(videoRef)
  const { targetHand, pressingHand, wrongFaceDetected } = useHandClassifier(hands, acupoint)
  const pressResult = usePressDetection(targetHand, pressingHand, acupoint)
  const { state, coachingMessage, sessionStats } = useCoachingState(
    pressResult,
    acupoint,
    wrongFaceDetected,
  )

  useTTS(coachingMessage)

  const progress = Math.min(
    sessionStats.holdTimeMs / (acupoint.technique.duration_s * 1000),
    1,
  )
  const streamRef = useRef<MediaStream | null>(null)
  const mediaPipeStarted = useRef(false)

  const startStream = useCallback(async (facing: 'environment' | 'user') => {
    streamRef.current?.getTracks().forEach(t => t.stop())
    setCameraError(null)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: facing } },
      })
      streamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        videoRef.current.play().catch(() => {})
      }
    } catch (e) {
      setCameraError(e instanceof Error ? `${e.name}: ${e.message}` : String(e))
    }
  }, [])

  useEffect(() => {
    async function init() {
      await startStream(facingMode)
      if (!mediaPipeStarted.current) {
        mediaPipeStarted.current = true
        try {
          await initMediaPipe()
        } catch (e) {
          setMediaPipeError(
            e instanceof Error ? e.message : 'Failed to load hand tracking',
          )
        }
      }
    }
    init()
    return () => {
      streamRef.current?.getTracks().forEach(t => t.stop())
      cancelAnimationFrame(animFrameRef.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const flipCamera = useCallback(() => {
    const next = facingMode === 'environment' ? 'user' : 'environment'
    setFacingMode(next)
    startStream(next)
  }, [facingMode, startStream])

  const drawLoop = useCallback(() => {
    const canvas = canvasRef.current
    const video = videoRef.current
    if (!canvas || !video) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    canvas.width = video.videoWidth || video.clientWidth
    canvas.height = video.videoHeight || video.clientHeight

    ctx.clearRect(0, 0, canvas.width, canvas.height)

    drawOverlay(ctx, canvas.width, canvas.height, {
      state,
      targetHand,
      pressingHand,
      acupoint,
      pressResult,
      stateColor: STATE_COLORS[state],
    })

    animFrameRef.current = requestAnimationFrame(drawLoop)
  }, [state, targetHand, pressingHand, acupoint, pressResult])

  useEffect(() => {
    animFrameRef.current = requestAnimationFrame(drawLoop)
    return () => cancelAnimationFrame(animFrameRef.current)
  }, [drawLoop])

  useEffect(() => {
    if (state === 'COMPLETE') {
      setTimeout(() => {
        navigate('/recap', { state: { stats: sessionStats, symptomId } })
      }, 1500)
    }
  }, [state, sessionStats, navigate, symptomId])

  if (mediaPipeError) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center px-6 text-center bg-surface">
        <p className="text-lime text-[11px] font-black uppercase mb-3">Error</p>
        <h2 className="text-[#f5f6f1] text-2xl font-black mb-2">Hand tracking failed</h2>
        <p className="text-muted text-sm mb-2">
          Could not load the AI model. Check your internet connection.
        </p>
        <p className="text-soft text-xs mb-8 font-mono break-all px-2">{mediaPipeError}</p>
        <button
          onClick={() => window.location.reload()}
          className="w-full max-w-xs min-h-[52px] rounded-lg bg-lime text-surface font-black"
        >
          Try again
        </button>
      </div>
    )
  }

  if (cameraError) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center px-6 text-center bg-surface">
        <p className="text-lime text-[11px] font-black uppercase mb-3">Camera needed</p>
        <h2 className="text-[#f5f6f1] text-2xl font-black mb-2">Camera access needed</h2>
        <p className="text-muted text-sm mb-2">
          On iPhone: Settings → Safari → Camera → Allow
        </p>
        <p className="text-soft text-xs font-mono mb-8 px-2 break-all">{cameraError}</p>
        <button
          onClick={() => {
            setCameraError(null)
            window.location.reload()
          }}
          className="w-full max-w-xs min-h-[52px] rounded-lg bg-lime text-surface font-black"
        >
          Try again
        </button>
      </div>
    )
  }

  const ringColor = STATE_COLORS[state]
  const r = 18
  const circ = 2 * Math.PI * r

  return (
    <div className="relative w-full h-screen bg-black overflow-hidden">
      {/* Camera feed — mirror only for front camera */}
      <video
        ref={videoRef}
        className="absolute inset-0 w-full h-full object-cover"
        style={{ transform: facingMode === 'user' ? 'scaleX(-1)' : 'none' }}
        playsInline
        muted
      />

      {/* Canvas overlay */}
      <canvas
        ref={canvasRef}
        className="absolute inset-0 w-full h-full"
        style={{ transform: facingMode === 'user' ? 'scaleX(-1)' : 'none' }}
      />

      {/* Loading indicator */}
      {!isReady && (
        <div className="absolute inset-0 flex items-center justify-center bg-black/60">
          <p className="text-[#f5f6f1] text-sm animate-pulse">Loading hand tracking…</p>
        </div>
      )}

      {/* Back button */}
      <button
        onClick={() => navigate(`/routine/${symptomId}`)}
        className="absolute top-4 left-4 w-10 h-10 rounded-full flex items-center justify-center backdrop-blur-sm"
        style={{ background: 'rgba(23,26,31,0.82)' }}
        aria-label="Back"
      >
        <svg
          width="18"
          height="18"
          viewBox="0 0 18 18"
          fill="none"
          stroke="#f5f6f1"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M11 14L6 9l5-5" />
        </svg>
      </button>

      {/* Flip camera button */}
      <button
        onClick={flipCamera}
        className="absolute top-4 right-4 w-10 h-10 rounded-full flex items-center justify-center backdrop-blur-sm"
        style={{ background: 'rgba(23,26,31,0.82)' }}
        aria-label="Flip camera"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="#f5f6f1"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M20 7h-3a2 2 0 0 1-2-2V2" />
          <path d="M9 2H5a2 2 0 0 0-2 2v4" />
          <path d="M4 17v2a2 2 0 0 0 2 2h3" />
          <path d="M15 22h3a2 2 0 0 0 2-2v-3" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </button>

      {/* Feedback card */}
      <div className="absolute bottom-0 left-0 right-0 px-3 pb-4">
        <div
          className="border border-white/10 rounded-2xl p-4 flex items-center gap-3 backdrop-blur-sm"
          style={{ background: 'rgba(23,26,31,0.9)' }}
        >
          <div className="flex-1 min-w-0">
            <p className="text-lime text-[11px] font-black uppercase mb-1.5">
              {STATE_LABELS[state]}
            </p>
            <p className="text-[#f5f6f1] text-[19px] font-semibold leading-tight">
              {coachingMessage}
            </p>
          </div>
          {/* Progress ring */}
          <div className="relative w-[62px] h-[62px] flex-shrink-0">
            <svg
              viewBox="0 0 44 44"
              width="62"
              height="62"
              style={{ transform: 'rotate(-90deg)' }}
            >
              <circle
                cx="22"
                cy="22"
                r={r}
                fill="none"
                stroke="rgba(255,255,255,0.12)"
                strokeWidth="4"
              />
              <circle
                cx="22"
                cy="22"
                r={r}
                fill="none"
                stroke={ringColor}
                strokeWidth="4"
                strokeLinecap="round"
                strokeDasharray={circ}
                strokeDashoffset={circ * (1 - progress)}
                style={{ transition: 'stroke-dashoffset 0.18s linear' }}
              />
            </svg>
            <span className="absolute inset-0 flex items-center justify-center text-[13px] font-black text-[#f5f6f1]">
              {Math.round(progress * acupoint.technique.duration_s)}s
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}
