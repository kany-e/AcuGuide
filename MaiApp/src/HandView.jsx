import { useMemo, useState } from 'react';
import { ACUPOINTS, MERIDIAN_COLORS, S } from './data';

// Catmull-Rom -> closed smooth path
function smoothClosed(pts) {
  const n = pts.length;
  if (n < 3) return '';
  let d = `M ${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)} `;
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    const c1x = p1[0] + (p2[0] - p0[0]) / 6, c1y = p1[1] + (p2[1] - p0[1]) / 6;
    const c2x = p2[0] - (p3[0] - p1[0]) / 6, c2y = p2[1] - (p3[1] - p1[1]) / 6;
    d += `C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x.toFixed(1)} ${c2y.toFixed(1)}, ${p2[0].toFixed(1)} ${p2[1].toFixed(1)} `;
  }
  return d + 'Z';
}

const HAND_PTS = [
  [140,430],[136,360],[134,300],[137,272],[141,250],
  [130,232],[114,222],[99,208],[91,196],[88,188],[95,180],[111,182],[128,189],
  [137,172],[142,150],[140,96],[143,78],[152,72],[161,78],[164,96],[166,150],
  [170,162],[172,146],[170,60],[173,50],[182,45],[191,50],[194,62],[196,146],
  [200,160],[202,143],[200,72],[203,60],[211,55],[219,60],[222,74],[224,144],
  [228,158],[230,141],[229,108],[231,98],[238,94],[244,100],[246,112],[248,150],
  [244,200],[238,250],[231,272],[226,300],[224,360],[220,430],
];

export default function HandView({ lang, onBack, selectedId, onSelect }) {
  const [hover, setHover] = useState(null);
  const handPath = useMemo(() => smoothClosed(HAND_PTS), []);
  const t = (k) => S[k]?.[lang] ?? k;

  return (
    <div className="hand-view">
      <button className="ghost-btn back-btn" onClick={onBack}>← {t('back')}</button>
      <svg viewBox="0 0 360 440" className="hand-svg" role="img" aria-label="Hand acupoints">
        <defs>
          <radialGradient id="handSkin" cx="42%" cy="34%" r="78%">
            <stop offset="0%" stopColor="#cdd8c0" />
            <stop offset="55%" stopColor="#aebd9d" />
            <stop offset="100%" stopColor="#8a9c7b" />
          </radialGradient>
          <filter id="ptGlow" x="-60%" y="-60%" width="220%" height="220%">
            <feGaussianBlur stdDeviation="3.2" result="b" />
            <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
        </defs>

        <path d={handPath} fill="url(#handSkin)" stroke="none" />

        {/* tendon + knuckle hints */}
        <g stroke="#6f7d61" strokeWidth="1" fill="none" opacity="0.45" strokeLinecap="round">
          <path d="M150 250 L156 200" /><path d="M172 250 L176 196" />
          <path d="M196 250 L196 196" /><path d="M220 250 L216 200" />
          <path d="M150 196 q24 -10 70 0" />
        </g>

        {/* acupoints */}
        {ACUPOINTS.map((p) => {
          const c = MERIDIAN_COLORS[p.mer] || '#c9a86a';
          const active = selectedId === p.id;
          return (
            <g key={p.id}
               className="acu"
               onMouseEnter={() => setHover(p.id)}
               onMouseLeave={() => setHover(null)}
               onClick={() => onSelect(p.id)}
               style={{ cursor: 'pointer' }}>
              {active && <circle cx={p.x} cy={p.y} r="13" fill="none" stroke={c} strokeWidth="1.4" opacity="0.7" className="acu-ring" />}
              <circle cx={p.x} cy={p.y} r={active ? 6.5 : 5} fill={c} filter="url(#ptGlow)" />
              <circle cx={p.x} cy={p.y} r="2" fill="#ffffff" />
              {(hover === p.id) && (
                <g pointerEvents="none">
                  <rect x={p.x + 10} y={p.y - 24} width={lang === 'zh' ? 86 : 96} height="22" rx="5"
                        fill="#f4f2ea" opacity="0.95" stroke={c} strokeWidth="0.7" />
                  <text x={p.x + 16} y={p.y - 9} fill="#33372f" fontSize="11"
                        fontFamily="'Noto Serif SC', serif">
                    {lang === 'zh' ? `${p.nameZh} ${p.id}` : `${p.nameEn} ${p.id}`}
                  </text>
                </g>
              )}
            </g>
          );
        })}
      </svg>
      <p className="hand-hint">{lang === 'zh' ? '点按穴位查看详情' : 'Tap a point for details'}</p>
    </div>
  );
}
