import { useState } from 'react';
import Body3D from './Body3D.jsx';
import HandView from './HandView.jsx';
import { ACUPOINTS, MERIDIANS, MERIDIAN_COLORS, S } from './data';

// channels drawn on the body, grouped by part so each can be isolated and fixed
const PART_IDS = { arm: ['lung', 'li'], leg: ['stomach', 'gb'], torso: ['ren', 'du'] };
const ALL_IDS = [...PART_IDS.arm, ...PART_IDS.leg, ...PART_IDS.torso];
const PARTS = [
  { id: null, zh: '全', en: 'All' },
  { id: 'arm', zh: '臂', en: 'Arm' },
  { id: 'torso', zh: '躯', en: 'Torso' },
  { id: 'leg', zh: '腿', en: 'Leg' },
];

export default function MeridianAtlas() {
  const [lang, setLang] = useState('zh');
  const [view, setView] = useState('body');
  const [selectedId, setSelectedId] = useState(null);
  const [solo, setSolo] = useState(null);
  const [part, setPart] = useState(null);
  const t = (k) => S[k]?.[lang] ?? k;
  const selected = ACUPOINTS.find((p) => p.id === selectedId) || null;
  const ids = part ? PART_IDS[part] : ALL_IDS;
  const majors = MERIDIANS.filter((m) => ids.includes(m.id));

  return (
    <div className="atlas">
      <div style={{ position: 'fixed', bottom: 6, right: 9, fontSize: 11, letterSpacing: 1, color: '#b04a2f', zIndex: 99, fontFamily: 'monospace', pointerEvents: 'none' }}>BUILD-25</div>
      <div className="ink-bg" aria-hidden="true">
        <div className="moon" />
        <svg className="mountains" viewBox="0 0 1440 700" preserveAspectRatio="xMidYMax slice">
          <path className="mtn mtn-far" d="M0,430 C160,372 320,398 470,356 C640,308 800,236 1000,300 C1160,350 1300,330 1440,360 L1440,700 L0,700 Z" />
          <path className="mtn mtn-mid" d="M0,520 C200,478 360,500 540,470 C740,436 900,402 1110,452 C1270,490 1370,476 1440,498 L1440,700 L0,700 Z" />
          <path className="mtn mtn-near" d="M0,612 C240,588 430,602 650,586 C870,570 1030,560 1250,582 C1350,592 1410,588 1440,592 L1440,700 L0,700 Z" />
        </svg>
        <div className="mist" />
      </div>

      <header className="topbar">
        <div className="brand">
          <span className="brand-zh">{lang === 'zh' ? '诗词山河 · 经络图谱' : 'Poetic Meridian Atlas'}</span>
          <span className="brand-en">{lang === 'zh' ? 'Poetic Meridian Atlas' : '诗词山河 · 经络图谱'}</span>
        </div>
        <div className="top-controls">
          <div className="seg">
            <button className={view === 'body' ? 'on' : ''} onClick={() => setView('body')}>{t('fullBody')}</button>
            <button className={view === 'hand' ? 'on' : ''} onClick={() => setView('hand')}>{t('hand')}</button>
          </div>
          <button className="lang-btn" onClick={() => setLang(lang === 'zh' ? 'en' : 'zh')}>{lang === 'zh' ? 'EN' : '中文'}</button>
        </div>
      </header>

      <div className="stage">
        <main className="figure-col">
          {view === 'body'
            ? <Body3D lang={lang} solo={solo} part={part} onEnterHand={() => setView('hand')} onPick={(mer) => setSolo(solo === mer ? null : mer)} />
            : <HandView lang={lang} onBack={() => setView('body')} selectedId={selectedId} onSelect={setSelectedId} />}
        </main>

        <aside className="ink-col">
          {/* part toggle: isolate arm / leg / torso so each can be inspected and fixed */}
          {view === 'body' && (
            <div className="part-row">
              {PARTS.map((p) => (
                <button key={p.en}
                  className={`part-tab ${part === p.id ? 'on' : ''}`}
                  onClick={() => { setPart(p.id); setSolo(null); }}>
                  {lang === 'zh' ? p.zh : p.en}
                </button>
              ))}
            </div>
          )}

          {/* vertical brush-calligraphy meridian names; click to isolate a channel */}
          {view === 'body' && (
            <nav className="mer-col">
              {majors.map((m) => (
                <button key={m.id}
                  className={`mer-name ${solo === m.id ? 'on' : ''}`}
                  style={solo === m.id ? { color: MERIDIAN_COLORS[m.id] } : undefined}
                  onClick={() => setSolo(solo === m.id ? null : m.id)}>
                  {m.zh}
                </button>
              ))}
            </nav>
          )}

          {selected && (
            <section className="detail-ink">
              <div className="d-name-v">{lang === 'zh' ? selected.nameZh : selected.nameEn}</div>
              <div className="d-meta">
                <span style={{ color: MERIDIAN_COLORS[selected.mer] }}>{selected.id}</span>
                <span>{lang === 'zh' ? selected.meridianZh : selected.meridianEn}</span>
              </div>
              <p className="d-text"><b>{t('location')}</b>　{lang === 'zh' ? selected.locationZh : selected.locationEn}</p>
              <p className="d-text"><b>{t('indications')}</b>　{lang === 'zh' ? selected.indZh : selected.indEn}</p>
              <p className="d-text subtle">{lang === 'zh' ? selected.cautZh : selected.cautEn}</p>
            </section>
          )}
        </aside>
      </div>

      <footer className="disclaimer">{t('disclaimer')}</footer>
    </div>
  );
}
