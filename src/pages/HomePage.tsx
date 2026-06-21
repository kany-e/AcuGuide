import { useNavigate } from 'react-router-dom'
import type { SymptomId } from '../types'

const symptoms: { id: SymptomId; short: string; label: string; description: string }[] = [
  {
    id: 'tension_headache',
    short: 'Tension-related discomfort',
    label: 'Tension Headache',
    description: 'Gently press the highlighted region on the back of your hand.',
  },
  {
    id: 'neck_shoulder_tension',
    short: 'Everyday tension routine',
    label: 'Neck & Shoulder',
    description: 'A hand-based self-care routine for neck and upper shoulder tension.',
  },
  {
    id: 'menstrual_discomfort',
    short: 'Gentle comfort support',
    label: 'Menstrual Discomfort',
    description: 'A short comfort-support routine for mild discomfort.',
  },
]

const TAGS = ['30s', 'Coach', 'Self-care']

export default function HomePage() {
  const navigate = useNavigate()

  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto overflow-y-auto">
      <div className="mb-6">
        <p className="text-lime text-[11px] font-black uppercase mb-1.5">AcuGuide</p>
        <h2 className="text-[32px] font-black leading-none text-[#f5f6f1]">
          Today's hand coach
        </h2>
        <p className="text-muted text-sm mt-2">Choose a self-care routine to get started.</p>
      </div>

      <div className="flex flex-col gap-[11px] pb-8">
        {symptoms.map(s => (
          <button
            key={s.id}
            onClick={() => navigate(`/safety/${s.id}`)}
            className="relative w-full min-h-[112px] p-4 pr-14 rounded-xl text-left border border-white/10 bg-panel active:border-lime/40 transition-colors"
          >
            <p className="text-soft text-[11px] font-black uppercase mb-1">{s.short}</p>
            <strong className="block text-[20px] font-black text-[#f5f6f1] mb-1.5">
              {s.label}
            </strong>
            <p className="text-muted text-sm leading-snug">{s.description}</p>
            <div className="flex gap-[7px] mt-3">
              {TAGS.map(tag => (
                <span
                  key={tag}
                  className="rounded-full bg-white/[0.08] text-muted px-2 py-1 text-[11px] font-bold"
                >
                  {tag}
                </span>
              ))}
            </div>
            <span className="absolute right-4 top-[18px] w-[31px] h-[31px] rounded-full bg-lime flex items-center justify-center">
              <span
                className="block w-0 h-0"
                style={{
                  borderTop: '5px solid transparent',
                  borderBottom: '5px solid transparent',
                  borderLeft: '7px solid #101113',
                  marginLeft: '2px',
                }}
              />
            </span>
          </button>
        ))}
      </div>
    </div>
  )
}
