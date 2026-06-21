import { useNavigate, useLocation } from 'react-router-dom'
import { useState } from 'react'
import type { SessionStats, FeelingOption } from '../types'

const FEELINGS: { id: FeelingOption; label: string }[] = [
  { id: 'relief', label: 'A bit better' },
  { id: 'no_change', label: 'No clear change' },
  { id: 'worse', label: 'Worse' },
]

const REPORT_TEXT: Record<FeelingOption, string> = {
  relief: 'Rest and observe how you feel. This routine is for self-care support only.',
  no_change: 'No problem. Self-care routines may not help every time.',
  worse:
    'Please stop this routine. Seek medical advice for severe, sudden, persistent, or worsening symptoms.',
}

export default function RecapPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const locState = location.state as
    | { stats: SessionStats; symptomId?: string }
    | null
  const stats = locState?.stats ?? {
    holdTimeMs: 30000,
    stabilityPct: 85,
    positionSteadiness: 'steady' as const,
  }
  const symptomId = locState?.symptomId
  const [feeling, setFeeling] = useState<FeelingOption | null>(null)

  const holdSec = Math.min(Math.round(stats.holdTimeMs / 1000), 30)
  const score = Math.min(
    100,
    Math.round(stats.stabilityPct * 0.65 + Math.min(stats.holdTimeMs / 30000, 1) * 35),
  )
  const positionLabel = stats.stabilityPct >= 75 ? 'Near target' : 'Variable'
  const stabilityLabel = stats.positionSteadiness === 'steady' ? 'Steady' : 'Variable'
  const scoreText =
    score >= 85
      ? 'Near target region with a steady hold.'
      : score >= 70
        ? 'Good effort — keep practicing.'
        : 'Keep working on your placement.'

  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto">
      <p className="text-lime text-[11px] font-black uppercase mb-2">Completion recap</p>
      <h2 className="text-[32px] font-black leading-tight text-[#f5f6f1] mb-2">
        Routine complete
      </h2>
      <p className="text-muted text-sm leading-relaxed mb-5">
        This recap summarizes execution quality, not medical outcome.
      </p>

      {/* Score card */}
      <div
        className="border border-white/10 rounded-xl p-5 text-center mb-4"
        style={{
          background:
            'radial-gradient(circle at 50% 0%, rgba(200,255,61,0.14), transparent 44%), #171a1f',
        }}
      >
        <span
          className="block text-lime font-black"
          style={{ fontSize: '78px', lineHeight: '0.95' }}
        >
          {score}
        </span>
        <span className="block text-muted text-[12px] font-black uppercase mt-1 mb-2">
          Coach score
        </span>
        <p className="text-muted text-sm">{scoreText}</p>
      </div>

      {/* Recap metrics */}
      <div className="grid grid-cols-3 gap-2 mb-5">
        {[
          { label: 'Hold time', value: `${holdSec} sec` },
          { label: 'Position', value: positionLabel },
          { label: 'Stability', value: stabilityLabel },
        ].map(m => (
          <div key={m.label} className="border border-white/10 rounded-lg bg-panel p-3">
            <span className="block text-soft text-[10px] font-black uppercase">{m.label}</span>
            <strong className="block text-[#f5f6f1] text-[13px] mt-1.5">{m.value}</strong>
          </div>
        ))}
      </div>

      {/* Self report */}
      <div className="border border-white/10 rounded-xl bg-panel p-4 mb-5">
        <p className="text-lime text-[11px] font-black uppercase mb-3">How do you feel?</p>
        <div className="grid grid-cols-3 gap-[6px] mb-3">
          {FEELINGS.map(f => (
            <button
              key={f.id}
              onClick={() => setFeeling(f.id)}
              className={`min-h-9 rounded-lg text-[13px] font-black transition-colors ${
                f.id === 'worse'
                  ? feeling === 'worse'
                    ? 'bg-[#ff6b5f]/40 text-[#ffd8d4]'
                    : 'bg-[#ff6b5f]/16 text-[#ffd8d4]'
                  : feeling === f.id
                    ? 'bg-lime text-surface'
                    : 'bg-panel-2 text-muted'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
        {feeling && (
          <p
            className={`text-sm leading-relaxed ${
              feeling === 'worse' ? 'text-[#ffd8d4]' : 'text-muted'
            }`}
          >
            {REPORT_TEXT[feeling]}
          </p>
        )}
      </div>

      {/* CTAs */}
      {feeling !== 'worse' && symptomId && (
        <button
          onClick={() => navigate(`/camera/${symptomId}`)}
          className="w-full min-h-[52px] rounded-lg bg-lime text-surface font-black text-base mb-2"
        >
          Run again
        </button>
      )}
      <button
        onClick={() => navigate('/')}
        className="w-full min-h-[46px] rounded-lg bg-transparent text-muted font-black text-base"
      >
        Choose another routine
      </button>
    </div>
  )
}
