import { useEffect, useRef, useState } from 'react';
import { ACUPOINTS } from './data';

// ─────────────────────────────────────────────────────────────────────────────
// Ask 问询 — bilingual acupressure wellness chat.
// Works fully offline: it matches what the user types against the acupoint data
// in data.js and returns relevant points (location + gentle-press note + safety
// caveat). If an API_KEY is provided it instead calls an OpenAI-compatible model,
// grounded on the same point data. Educational only — no diagnose / treat / cure.
// ─────────────────────────────────────────────────────────────────────────────

const API_KEY = '';
const API_URL = 'https://api.openai.com/v1/chat/completions';
const MODEL = 'gpt-4o-mini';

// LI4 (合谷) is excluded everywhere in the app (pregnancy caution), so it is never
// recommended here either.
const SAFE_POINTS = ACUPOINTS.filter((p) => p.id !== 'LI4');
const byId = (id) => SAFE_POINTS.find((p) => p.id === id);

// symptom / keyword -> safe point ids (bilingual keys). Educational associations,
// not diagnoses.
const SYMPTOM_HINTS = [
  { keys: ['headache', 'head', 'migraine', '头痛', '头疼', '头', '偏头痛'], ids: ['SJ5', 'SI3'] },
  { keys: ['neck', 'shoulder', 'stiff', 'stiffness', '颈', '脖', '肩', '落枕', '僵'], ids: ['SI3'] },
  { keys: ['nausea', 'nauseous', 'queasy', 'motion', 'sick', 'vomit', 'travel', 'car', '恶心', '想吐', '反胃', '晕车', '晕船', '孕吐'], ids: ['PC6'] },
  { keys: ['chest', 'tight', 'tightness', 'palpitation', '胸闷', '胸', '心悸'], ids: ['PC6'] },
  { keys: ['sleep', 'insomnia', 'restless', 'anxious', 'anxiety', 'stress', 'stressed', 'calm', 'nervous', 'worry', '失眠', '睡不', '睡不好', '入睡', '心神', '焦虑', '紧张', '安神', '心烦'], ids: ['HT7', 'PC8'] },
  { keys: ['palm', 'sweaty', 'sweat', 'flush', 'heat', '手心', '手心热', '烦热'], ids: ['PC8'] },
  { keys: ['ear', 'tinnitus', 'ringing', 'arm', 'forearm', 'elbow', '耳', '耳鸣', '上肢', '手臂', '前臂'], ids: ['SJ5'] },
];

function looksChinese(s) { return /[一-鿿]/.test(s || ''); }

// find matching safe points for a free-text query
function matchPoints(text) {
  const q = (text || '').toLowerCase();
  const ids = [];
  // 1) symptom keyword map
  for (const h of SYMPTOM_HINTS) {
    if (h.keys.some((k) => q.includes(k.toLowerCase()))) {
      for (const id of h.ids) if (!ids.includes(id)) ids.push(id);
    }
  }
  // 2) direct point name / id mentions (e.g. "内关", "PC6", "neiguan")
  for (const p of SAFE_POINTS) {
    const hit = [p.id, p.nameZh, p.nameEn, p.pinyin].some(
      (v) => v && q.includes(String(v).toLowerCase()),
    );
    if (hit && !ids.includes(p.id)) ids.push(p.id);
  }
  return ids.map(byId).filter(Boolean).slice(0, 3);
}

// build an offline, data-grounded reply for the matched points
function buildPointReply(points, zh) {
  if (zh) {
    const blocks = points.map((p) =>
      `· ${p.nameZh}（${p.id}）\n  位置：${p.locationZh}\n  传统用途：${p.indZh}\n  温和按压：用拇指或食指指腹轻柔按压约 30 秒，配合缓慢呼吸。`,
    );
    return (
      '可以了解以下常用穴位（仅供学习参考，并非诊断或治疗）：\n\n' +
      blocks.join('\n\n') +
      '\n\n如出现刺痛、麻木，或剧烈、突发、持续加重的不适，请停止并咨询专业医疗人员。'
    );
  }
  const blocks = points.map((p) =>
    `· ${p.nameEn} (${p.id})\n  Location: ${p.locationEn}\n  Traditional use: ${p.indEn}\n  Gentle press: rest your thumb or fingertip on the spot for about 30 seconds while breathing slowly.`,
  );
  return (
    'Here are some commonly used points you can learn about (for learning only — not a diagnosis or treatment):\n\n' +
    blocks.join('\n\n') +
    '\n\nIf you feel sharp pain or numbness, or anything severe, sudden, or worsening, please stop and consult a healthcare professional.'
  );
}

const OFFLINE_FALLBACK = {
  zh: '（离线模式）我可以介绍一些常用的手部穴位。你可以告诉我想了解的穴位名称，或简单描述你的不适，例如「头痛」「恶心」「睡不好」「肩颈僵硬」。如出现剧烈、突发或持续加重的不适，请停止并咨询专业医疗人员。',
  en: "(Offline mode) I can introduce some commonly used hand points. Tell me a point by name, or describe what's bothering you — for example \"headache\", \"nausea\", \"trouble sleeping\", or \"stiff neck\". If anything feels severe, sudden, or worsening, please stop and consult a healthcare professional.",
};

// compact point context to ground the online model on the app's own data
const POINTS_CONTEXT = SAFE_POINTS.map(
  (p) => `${p.id} ${p.nameZh}/${p.nameEn}: location ${p.locationEn}; traditional use ${p.indEn}`,
).join('\n');

const SYSTEM_PROMPT = `You are a warm, concise acupressure wellness coach. You help people learn about gentle self-acupressure and general wellbeing.
- Reply in the language the user writes in (中文 or English); you are fully bilingual.
- Keep answers short, calm, and practical.
- Prefer the points in the reference list below; do NOT recommend LI4 / 合谷.
- You are NOT a doctor. NEVER diagnose, treat, cure, or heal. Do not promise any medical outcome.
- If the user describes a red flag (severe or sudden chest pain, trouble breathing, a serious injury, bleeding, pregnancy concerns, symptoms that are severe / worsening / persistent), gently suggest they stop and consult a qualified healthcare professional.
- Frame everything as educational and self-care oriented, never as medical advice.

Reference points (use these locations and traditional associations):
${POINTS_CONTEXT}`;

export default function Ask({ lang }) {
  const t = (zh, en) => (lang === 'zh' ? zh : en);
  const [messages, setMessages] = useState([
    {
      role: 'assistant',
      content: lang === 'zh'
        ? '你好，我是问询助手。告诉我你想了解的穴位，或简单描述你的不适（如「头痛」「恶心」「睡不好」），我可以介绍相关的常用手部穴位。内容仅供学习参考。'
        : "Hello — I'm your Ask companion. Tell me a point you'd like to learn about, or describe what's bothering you (like \"headache\", \"nausea\", or \"trouble sleeping\"), and I'll introduce relevant hand points. Everything here is for learning only.",
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
        // offline: match against the app's own acupoint data
        await new Promise((r) => setTimeout(r, 350));
        const zh = looksChinese(text);
        const points = matchPoints(text);
        const reply = points.length
          ? buildPointReply(points, zh)
          : (zh ? OFFLINE_FALLBACK.zh : OFFLINE_FALLBACK.en);
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
          || t('抱歉，我现在无法回应。', "Sorry, I couldn't respond just now.");
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
          placeholder={t('描述不适或穴位名称…', 'Describe a symptom or point…')}
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
