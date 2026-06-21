import { useState, useRef, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

type Msg = { id: number; role: 'user' | 'coach'; text: string }

// Plug in an endpoint + key to go live; empty key uses the offline reply.
const ENDPOINT = 'https://api.openai.com/v1/chat/completions'
const API_KEY = '' // paste a key to enable live answers — keep it out of git
const MODEL = 'gpt-4o-mini'
const SYSTEM =
  'You are AcuGuide, a warm, concise acupressure wellness coach. You explain hand/wrist acupoints and ' +
  'how to press them as self-care, bilingual 中文/English (answer in the user’s language). You NEVER ' +
  'diagnose, treat, cure, or heal and make no medical claims. For red-flag symptoms (severe pain, ' +
  'numbness, dizziness, worsening) gently suggest stopping and seeing a professional.'

export default function AskPage() {
  const navigate = useNavigate()
  const [messages, setMessages] = useState<Msg[]>([
    { id: 0, role: 'coach', text: 'Hi — ask me about any hand acupoint, or how to press TE3 中渚. 你也可以用中文问我。' },
  ])
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const endRef = useRef<HTMLDivElement>(null)

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  async function send() {
    const q = input.trim()
    if (!q || sending) return
    const userMsg: Msg = { id: Date.now(), role: 'user', text: q }
    const history = [...messages, userMsg]
    setMessages(history)
    setInput('')
    setSending(true)

    if (!API_KEY) {
      setMessages(m => [...m, {
        id: Date.now() + 1, role: 'coach',
        text: '(offline) For TE3 中渚: on the back of the hand, in the groove behind your ring and pinky knuckles — firm, steady pressure with slow breathing, small gentle circles. Add an API key in AskPage.tsx to enable live answers.',
      }])
      setSending(false)
      return
    }
    try {
      const res = await fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${API_KEY}` },
        body: JSON.stringify({
          model: MODEL, temperature: 0.6,
          messages: [
            { role: 'system', content: SYSTEM },
            ...history.slice(-8).map(m => ({ role: m.role === 'user' ? 'user' : 'assistant', content: m.text })),
          ],
        }),
      })
      const json = await res.json()
      const reply = json?.choices?.[0]?.message?.content ?? 'Sorry, I couldn’t reach the coach.'
      setMessages(m => [...m, { id: Date.now() + 2, role: 'coach', text: reply }])
    } catch {
      setMessages(m => [...m, { id: Date.now() + 3, role: 'coach', text: 'Network error — try again.' }])
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="min-h-screen flex flex-col px-5 py-4 max-w-md mx-auto">
      <div className="flex items-center justify-between mb-3">
        <button onClick={() => navigate('/')} className="text-muted text-sm active:text-lime">← Home</button>
        <p className="text-lime text-[11px] font-black uppercase">Ask the coach</p>
        <span className="w-10" />
      </div>

      <div className="flex-1 overflow-y-auto flex flex-col gap-2.5 pb-3">
        {messages.map(m => (
          <div key={m.id} className={m.role === 'user' ? 'self-end max-w-[82%]' : 'self-start max-w-[82%]'}>
            <div className={
              m.role === 'user'
                ? 'rounded-2xl bg-lime text-paper2 px-3.5 py-2.5 text-sm leading-snug'
                : 'rounded-2xl bg-panel border border-line/25 text-ink px-3.5 py-2.5 text-sm leading-snug'
            }>
              {m.text}
            </div>
          </div>
        ))}
        {sending && <p className="text-soft text-xs self-start px-2">…thinking</p>}
        <div ref={endRef} />
      </div>

      <div className="flex gap-2 pt-2 pb-1">
        <input
          value={input}
          onChange={e => setInput(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') send() }}
          placeholder="Ask the coach…"
          className="flex-1 rounded-xl bg-panel border border-line/25 text-ink px-3.5 py-3 text-sm outline-none focus:border-lime/40"
        />
        <button
          onClick={send}
          disabled={sending || !input.trim()}
          className="rounded-xl bg-lime text-paper2 font-black px-4 disabled:opacity-40"
        >
          Send
        </button>
      </div>
      <p className="text-soft text-[11px] text-center pt-1">Wellness guidance only — never diagnosis or treatment.</p>
    </div>
  )
}
