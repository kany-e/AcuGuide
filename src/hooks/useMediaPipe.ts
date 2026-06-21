import { useState, useCallback, useRef, RefObject } from 'react'
import type { Landmark } from '../types'

export interface HandResult {
  landmarks: Landmark[]
  handedness: 'Left' | 'Right'
  score: number
}

const WASM_CDN = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm'

export function useMediaPipe(videoRef: RefObject<HTMLVideoElement | null>) {
  const [hands, setHands] = useState<HandResult[]>([])
  const [isReady, setIsReady] = useState(false)
  const detectorRef = useRef<{
    detectForVideo: (video: HTMLVideoElement, ts: number) => {
      handednesses: { categoryName: string; score: number }[][]
      landmarks: Landmark[][]
    }
    close: () => void
  } | null>(null)
  const rafRef = useRef<number>(0)

  const initMediaPipe = useCallback(async () => {
    const { FilesetResolver, HandLandmarker } = await import('@mediapipe/tasks-vision')
    const vision = await FilesetResolver.forVisionTasks(WASM_CDN)
    const detector = await HandLandmarker.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath:
          'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task',
        delegate: 'GPU',
      },
      numHands: 2,
      runningMode: 'VIDEO',
    })

    detectorRef.current = detector
    setIsReady(true)

    function detect() {
      if (!videoRef.current || !detectorRef.current) return
      if (videoRef.current.readyState < 2) {
        rafRef.current = requestAnimationFrame(detect)
        return
      }

      const result = detectorRef.current.detectForVideo(videoRef.current, performance.now())
      const parsed: HandResult[] = result.landmarks.map((lms, i) => ({
        landmarks: lms,
        handedness: result.handednesses[i]?.[0]?.categoryName as 'Left' | 'Right',
        score: result.handednesses[i]?.[0]?.score ?? 0,
      }))
      setHands(parsed)
      rafRef.current = requestAnimationFrame(detect)
    }

    rafRef.current = requestAnimationFrame(detect)

    return () => {
      cancelAnimationFrame(rafRef.current)
      detector.close()
    }
  }, [videoRef])

  return { hands, isReady, initMediaPipe }
}
