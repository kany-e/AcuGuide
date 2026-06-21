import { useNavigate, useParams } from 'react-router-dom'
import type { SymptomId } from '../types'

const SAFETY_ITEMS = [
  'Use gentle pressure only.',
  'Stop if you feel sharp pain, numbness, dizziness, unusual symptoms, or worsening discomfort.',
  'Do not press on broken, irritated, swollen, or infected skin.',
  'If pregnant or possibly pregnant, avoid certain pressure points unless advised by a clinician.',
]

export default function SafetyPage() {
  const { symptomId } = useParams<{ symptomId: SymptomId }>()
  const navigate = useNavigate()

  function handleAcknowledge() {
    sessionStorage.setItem('safetyAcknowledged', 'true')
    navigate(`/routine/${symptomId}`)
  }

  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto">
      <button
        onClick={() => navigate('/')}
        className="text-muted text-sm mb-3 self-start min-h-[34px] flex items-center"
      >
        Back
      </button>

      <p className="text-lime text-[11px] font-black uppercase mb-2">Before you start</p>
      <h2 className="text-[32px] font-black leading-tight text-ink mb-3">
        Safety boundary
      </h2>
      <p className="text-muted text-sm leading-relaxed mb-5">
        AcuGuide provides wellness self-care guidance only. It does not diagnose, treat, or
        replace medical care.
      </p>

      <div className="flex flex-col gap-[10px] mb-6">
        {SAFETY_ITEMS.map((item, i) => (
          <div
            key={i}
            className="border border-line/25 rounded-lg bg-panel p-[13px] text-muted text-sm leading-relaxed"
          >
            {item}
          </div>
        ))}
      </div>

      <button
        onClick={handleAcknowledge}
        className="w-full min-h-[52px] rounded-lg bg-lime text-surface font-black text-base mt-auto"
      >
        I understand
      </button>
    </div>
  )
}
