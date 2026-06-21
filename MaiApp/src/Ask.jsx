import { useEffect, useRef, useState } from 'react';

// ─────────────────────────────────────────────────────────────────────────────
// Ask 问询 — bilingual acupressure wellness chat.
// Uses an OpenAI-compatible chat endpoint. Leave API_KEY empty to run fully
// offline with a canned, safety-first reply (no network call).
// ─────────────────────────────────────────────────────────────────────────────

const API_KEY = '';
const API_URL = 'https://api.openai.com/v1/chat/completions';
const MODEL = 'gpt-4o-mini';

const SYSTEM_PROMPT = `You are a warm, concise acupressure wellness coach. You help people learn about gentle self-acupressure and general wellbeing.
- Reply in the language the user writes in (中文 or English); you are fully bilingual.
- Keep answers short, calm, and practical.
- You are NOT a doctor. NEVER diagnose, treat, cure, or heal. Do not promise any medical outcome.
- If the user describes a red flag (severe or sudden chest pain, trouble breathing, a serious injury, bleeding, pregnancy concerns, symptoms that are severe / worsening / persistent), gently suggest they stop and consult a qualified healthcare professional.
- Frame everything as educational and self-care oriented, never as medical advice.`;

const OFFLINE_REPLY = {
  zh: '（离线模式）我是一个用于学习的按压引导助手，不能进行诊断或处理健康问题。如果你想了解某个穴位的位置或温和的按压方式，可以告诉我。如出现剧烈、突发或持续加重的不适，请停止并咨询专业医疗人员。',
  en: '(Offline mode) I am a learning-only acupressure guide — I can\'t diagnose or address health conditions. Tell me a point you\'d like to learn about, or how to press it gently. If anything feels severe, sudden, or worsening, please stop and consult a healthcare professional.',
};

function looksChinese(s) { return /[一-鿿]/.test(s || ''); }

export default function Ask({ lang }) {
  const t = (zh, en) => (lang === 'zh' ? zh : en);
  const [messages, setMessages] = useState([
    {
      role: 'assistant',
      content: lang === 'zh'
        ? '你好，我是问询助手。可以问我关于穴位位置、温和按压方式或日常放松的小问题。这里的内容仅供学习参考。'
        : 'Hello — I\'m your Ask companion. You can ask about point locations, gentle pressing, or everyday relaxation. Everything here is for learning only.',
    },
  ]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const scrollRef = useRef(null);

  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, busy]);

  async function send() {
    const text = input.trim();
    if (!text || busy) return;
    const next = [...messages, { role: 'user', content: text }];
    setMessages(next);
    setInput('');
    setBusy(true);

    try {
      if (!API_KEY) {
        // offline canned reply, language-matched to the question
        await new Promise((r) => setTimeout(r, 400));
        const reply = looksChinese(text) ? OFFLINE_REPLY.zh : OFFLINE_REPLY.en;
        setMessages((m) => [...m, { role: 'assistant', content: reply }]);
      } else {
        const res = await fetch(API_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${API_KEY}`,
          },
          body: JSON.stringify({
            model: MODEL,
            temperature: 0.6,
            messages: [
              { role: 'system', content: SYSTEM_PROMPT },
              ...next.map((mm) => ({ role: mm.role, content: mm.content })),
            ],
          }),
        });
        const data = await res.json();
        const reply = data?.choices?.[0]?.message?.content?.trim()
          || t('抱歉，我现在无法回应。', 'Sorry, I couldn\'t respond just now.');
        setMessages((m) => [...m, { role: 'assistant', content: reply }]);
      }
    } catch (err) {
      setMessages((m) => [...m, {
        role: 'assistant',
        content: t('连接出现问题，请稍后再试。', 'Something went wrong reaching the service — please try again.'),
      }]);
    } finally {
      setBusy(false);
    }
  }

  function onKey(e) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); }
  }

  return (
    <div className="ask-wrap">
      <div className="ask-head">
        <div className="coach-kicker">{t('问询', 'Ask')}</div>
        <h2 className="coach-title">{t('按压问询', 'Acupressure companion')}</h2>
      </div>

      <div className="ask-scroll" ref={scrollRef}>
        {messages.map((m, i) => (
          <div key={i} className={`ask-row ${m.role === 'user' ? 'user' : 'bot'}`}>
            <div className={`ask-bubble ${m.role === 'user' ? 'user' : 'bot'}`}>{m.content}</div>
          </div>
        ))}
        {busy && (
          <div className="ask-row bot">
            <div className="ask-bubble bot ask-typing">…</div>
          </div>
        )}
      </div>

      <div className="ask-input-row">
        <textarea
          className="ask-input"
          rows={1}
          value={input}
          placeholder={t('输入你的问题…', 'Type your question…')}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={onKey}
        />
        <button className="ask-send" onClick={send} disabled={busy || !input.trim()}>
          {t('发送', 'Send')}
        </button>
      </div>

      <p className="ask-foot">
        {t('内容仅供学习参考，不构成医疗建议、诊断或治疗。',
           'For learning only. Not medical advice, diagnosis, or treatment.')}
      </p>
    </div>
  );
}
