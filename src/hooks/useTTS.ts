import { useEffect, useRef } from 'react'

export function useTTS(message: string) {
  const prevRef = useRef('')

  useEffect(() => {
    if (!window.speechSynthesis) return
    if (message === prevRef.current) return
    prevRef.current = message

    // Cancel any in-progress utterance before speaking (required on iOS)
    window.speechSynthesis.cancel()

    const u = new SpeechSynthesisUtterance(message)
    u.rate = 0.9
    u.pitch = 1.0
    u.volume = 1.0
    window.speechSynthesis.speak(u)
  }, [message])

  // Cancel on unmount (e.g. when navigating away mid-utterance)
  useEffect(() => () => { window.speechSynthesis?.cancel() }, [])
}
