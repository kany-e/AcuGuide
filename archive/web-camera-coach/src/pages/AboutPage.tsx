import { useNavigate } from 'react-router-dom'

const PILLS = ['find the point', 'on-target check', 'steady-hold timer', 'on-device · private', '中文 / EN']

const STEPS = [
  'Pick a concern — the coach maps it to a hand acupoint (e.g. TE3 · 中渚).',
  'Hold your hand up: the camera tracks it and shows a target ring on the point.',
  'Press and hold — the ring turns green when you’re on the spot and steady.',
  'Get a recap of how you did, and how you feel.',
]

export default function AboutPage() {
  const navigate = useNavigate()
  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto overflow-y-auto">
      <button onClick={() => navigate('/')} className="text-muted text-sm mb-4 self-start active:text-lime">
        ← Home
      </button>

      <p className="text-lime text-[11px] font-black uppercase mb-1.5">What it does</p>
      <h2 className="text-[30px] font-black leading-[1.05] text-ink">
        A camera that watches you do acupressure — safely.
      </h2>
      <p className="text-muted text-sm mt-3">
        The internet has endless acupressure tips, but none can tell whether you’re doing it right.
        AcuGuide can. It shows <span className="text-ink font-semibold">where</span> to press,
        confirms you’re <span className="text-ink font-semibold">on the point</span>, and times a
        <span className="text-ink font-semibold"> steady hold</span> — as guided self-care, never
        medical diagnosis or treatment.
      </p>

      <div className="flex flex-wrap gap-[7px] mt-4">
        {PILLS.map(p => (
          <span key={p} className="rounded-full bg-gold/10 text-muted px-2.5 py-1 text-[11px] font-bold">
            {p}
          </span>
        ))}
      </div>

      <div className="mt-6 p-4 rounded-xl bg-panel border border-line/25">
        <p className="text-soft text-[11px] font-black uppercase mb-2">How it works</p>
        <ol className="list-decimal list-inside flex flex-col gap-2">
          {STEPS.map((s, i) => (
            <li key={i} className="text-muted text-sm leading-snug">{s}</li>
          ))}
        </ol>
      </div>

      <div className="mt-4 p-3 rounded-xl bg-c-red/10 border border-c-red/30">
        <p className="text-c-red text-[12px] leading-snug">
          Wellness self-care only — not medical advice. Stop and seek care for red-flag symptoms (sudden
          severe pain, numbness, dizziness, worsening). If pregnant or managing a condition, check with a
          professional first.
        </p>
      </div>

      <div className="flex gap-3 mt-6 pb-8">
        <button
          onClick={() => navigate('/')}
          className="flex-1 rounded-xl bg-lime text-paper2 font-black py-3"
        >
          Choose a routine
        </button>
        <button
          onClick={() => navigate('/ask')}
          className="rounded-xl bg-panel border border-line/25 text-ink font-bold py-3 px-4"
        >
          Ask AI
        </button>
      </div>
    </div>
  )
}
