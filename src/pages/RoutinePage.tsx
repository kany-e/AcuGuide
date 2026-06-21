import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import acupointsData from '../data/acupoints.json'
import type { Acupoint, SymptomId } from '../types'

const SYMPTOM_POINT: Record<string, string> = {
  tension_headache: 'TE3',
  neck_shoulder_tension: 'SI3',
  menstrual_discomfort: 'PC6',
}

const SYMPTOM_LABEL: Record<string, string> = {
  tension_headache: 'Tension Headache',
  neck_shoulder_tension: 'Neck & Shoulder',
  menstrual_discomfort: 'Menstrual Discomfort',
}

const STEPS: Record<string, string[]> = {
  tension_headache: [
    'Back of your hand faces the camera.',
    'Find the highlighted groove just behind your ring and pinky knuckles.',
    'Press gently with the opposite thumb.',
    'Hold steady for 30 seconds.',
    'Stop if symptoms feel sharp, unusual, or worse.',
  ],
  neck_shoulder_tension: [
    'Place your hand in view, ulnar edge toward the camera.',
    'Find the highlighted region near the pinky side of your palm.',
    'Use gentle, steady pressure with the opposite thumb.',
    'Hold while breathing slowly.',
    'Stop if discomfort feels severe or unusual.',
  ],
  menstrual_discomfort: [
    'Place your hand palm-up in view.',
    'Find the highlighted region near the inner wrist.',
    'Press gently near the highlighted area.',
    'Hold for 30 seconds.',
    'Stop if you feel numbness or sharp pain.',
  ],
}

export default function RoutinePage() {
  const { symptomId } = useParams<{ symptomId: SymptomId }>()
  const navigate = useNavigate()
  const [targetHand, setTargetHand] = useState<'Left' | 'Right'>('Left')

  if (!sessionStorage.getItem('safetyAcknowledged')) {
    navigate(`/safety/${symptomId}`)
    return null
  }

  const pointId = SYMPTOM_POINT[symptomId ?? '']
  const point = (acupointsData as { acupoints: Acupoint[] }).acupoints.find(
    p => p.id === pointId,
  )
  if (!point) return <div className="p-8 text-[#f5f6f1]">Point not found</div>

  const steps = STEPS[symptomId ?? ''] ?? []

  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto">
      <button
        onClick={() => navigate(`/safety/${symptomId}`)}
        className="text-muted text-sm mb-3 self-start min-h-[34px] flex items-center"
      >
        Back
      </button>

      <p className="text-lime text-[11px] font-black uppercase mb-2">
        {SYMPTOM_LABEL[symptomId ?? '']}
      </p>
      <h2 className="text-[32px] font-black leading-tight text-[#f5f6f1] mb-3">
        {point.technique.duration_s}-Second Hand Pressure
      </h2>
      <p className="text-muted text-sm leading-relaxed mb-4">{point.coach_copy.align}</p>

      {/* Metric row */}
      <div className="grid grid-cols-3 gap-2 mb-4">
        {[
          { label: 'Time', value: `${point.technique.duration_s}s` },
          { label: 'Pressure', value: 'Gentle' },
          { label: 'Mode', value: 'Coach' },
        ].map(m => (
          <div key={m.label} className="border border-white/10 rounded-lg bg-panel p-3">
            <span className="block text-soft text-[10px] font-black uppercase">{m.label}</span>
            <strong className="block text-[#f5f6f1] text-[13px] mt-1.5">{m.value}</strong>
          </div>
        ))}
      </div>

      {/* Step list */}
      <div className="flex flex-col gap-[10px] mb-3">
        {steps.map((step, i) => (
          <div
            key={i}
            className="border border-white/10 rounded-lg bg-panel p-[13px] text-sm leading-relaxed flex gap-3"
          >
            <strong className="text-[#f5f6f1] flex-shrink-0">{i + 1}</strong>
            <span className="text-muted">{step}</span>
          </div>
        ))}
      </div>

      {/* Prep card */}
      <div className="border border-white/10 rounded-lg overflow-hidden mt-1 mb-5">
        {[
          { label: 'Placement', value: 'Target region' },
          { label: 'Hold', value: '30-second timer' },
          { label: 'Safety', value: 'Stop boundary' },
        ].map((row, i) => (
          <div
            key={row.label}
            className={`flex justify-between items-center px-[14px] py-3 bg-white/[0.035] ${
              i > 0 ? 'border-t border-white/10' : ''
            }`}
          >
            <span className="text-soft text-[11px] font-black uppercase">{row.label}</span>
            <strong className="text-[#f5f6f1] text-[13px]">{row.value}</strong>
          </div>
        ))}
      </div>

      {/* Hand selector */}
      <div className="mb-4">
        <p className="text-soft text-[11px] font-black uppercase mb-2">Which hand will you press on?</p>
        <div className="grid grid-cols-2 gap-2">
          {(['Left', 'Right'] as const).map(hand => (
            <button
              key={hand}
              onClick={() => setTargetHand(hand)}
              className={`min-h-[44px] rounded-lg text-[14px] font-black transition-colors ${
                targetHand === hand
                  ? 'bg-lime text-surface'
                  : 'bg-panel border border-white/10 text-muted'
              }`}
            >
              {hand} hand
            </button>
          ))}
        </div>
      </div>

      <button
        onClick={() => {
          window.speechSynthesis?.cancel()
          sessionStorage.setItem('targetHandedness', targetHand)
          navigate(`/camera/${symptomId}`)
        }}
        className="w-full min-h-[52px] rounded-lg bg-lime text-surface font-black text-base mt-auto mb-4"
      >
        Open coach
      </button>
    </div>
  )
}
