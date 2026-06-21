import { useEffect, useRef, useState } from 'react';

// ─────────────────────────────────────────────────────────────────────────────
// AR Acupressure Coach — TE3 中渚 (Sanjiao 3)
// Legacy MediaPipe Hands (window.Hands / window.Camera, loaded from CDN in index.html).
// Educational guidance only — no treat / cure / heal / diagnose language anywhere.
// ─────────────────────────────────────────────────────────────────────────────

// Mirror-invariant face gate. Legacy @mediapipe/hands reports handedness with the
// OPPOSITE convention to the Tasks API the gate was calibrated on, so the sign is
// FLIPPED here. Flip this single constant to invert the whole gate.
const DORSAL_WHEN_POSITIVE = false;

const HOLD_TARGET_S = 30;       // seconds of steady contact to complete
const STEADY_WINDOW = 15;       // frames of offset history used for steadiness
const PHASE = {
  NO_HAND: 'NO_HAND',
  WRONG_FACE: 'WRONG_FACE',
  SEARCHING: 'SEARCHING',
  UNSTABLE: 'UNSTABLE',
  ON_TARGET: 'ON_TARGET',
  PAUSED: 'PAUSED',
  HOLDING: 'HOLDING',
  COMPLETE: 'COMPLETE',
};

const COLORS = {
  jade: '#5f8a63',
  terracotta: '#b04a2f',
  gold: '#9a7d44',
};

function phaseColor(p) {
  if (p === PHASE.HOLDING || p === PHASE.COMPLETE) return COLORS.jade;
  if (p === PHASE.WRONG_FACE || p === PHASE.UNSTABLE || p === PHASE.PAUSED) return COLORS.terracotta;
  return COLORS.gold; // SEARCHING / NO_HAND
}

// bilingual coaching copy (no clinical / treatment language)
const COPY = {
  NO_HAND:    { zh: '请将手放入画面中', en: 'Bring your hand into view' },
  WRONG_FACE: { zh: '请翻转手掌，手背朝向镜头', en: 'Turn your hand — show the back of the hand' },
  SEARCHING:  { zh: '用另一只手的指尖寻找中渚穴', en: 'Use the other fingertip to find the point' },
  UNSTABLE:   { zh: '保持手部平稳', en: 'Hold your hand steady' },
  ON_TARGET:  { zh: '很好，轻轻按住', en: 'Good — rest gently on the point' },
  PAUSED:     { zh: '指尖稍稍偏离了，慢慢回到穴位', en: 'Drifted off — ease back onto the point' },
  HOLDING:    { zh: '保持轻柔的按压', en: 'Keep a gentle, steady press' },
  COMPLETE:   { zh: '完成了，放松一下', en: 'Done — relax your hands' },
};

function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }

// TE3 target landmark (in normalized hand-landmark space) for a single hand.
function te3Target(lm) {
  return {
    x: 0.45 * lm[13].x + 0.40 * lm[17].x + 0.15 * lm[0].x,
    y: 0.45 * lm[13].y + 0.40 * lm[17].y + 0.15 * lm[0].y,
  };
}

// CALIBRATED, mirror-invariant dorsal/palmar gate (sign flipped for legacy hands).
function isDorsal(lm, handed) {
  const cross =
    (lm[5].x - lm[0].x) * (lm[17].y - lm[0].y) -
    (lm[5].y - lm[0].y) * (lm[17].x - lm[0].x);
  const signed = handed === 'Right' ? cross : -cross;
  const dorsal = DORSAL_WHEN_POSITIVE ? signed > 0 : signed < 0;
  return dorsal;
}

const RED_FLAGS = {
  zh: [
    '剧烈或突发的胸痛、呼吸困难',
    '皮肤破损、感染、肿胀或近期受伤的部位',
    '怀孕期间，或患有出血性疾病、装有心脏起搏器',
    '症状持续加重、严重或反复出现',
  ],
  en: [
    'Severe or sudden chest pain, or trouble breathing',
    'Broken skin, infection, swelling, or a recent injury at the spot',
    'Pregnancy, bleeding disorders, or a pacemaker',
    'Symptoms that are severe, worsening, or recurring',
  ],
};

export default function Coach({ lang }) {
  const t = (zh, en) => (lang === 'zh' ? zh : en);

  const [acknowledged, setAcknowledged] = useState(false);
  const [agree, setAgree] = useState(false);
  const [camError, setCamError] = useState(null);
  const [phase, setPhase] = useState(PHASE.NO_HAND);
  const [progress, setProgress] = useState(0);
  const [feeling, setFeeling] = useState(null);

  const videoRef = useRef(null);
  const canvasRef = useRef(null);
  const handsRef = useRef(null);
  const cameraRef = useRef(null);

  // live coaching state kept in refs so the per-frame loop doesn't re-render churn
  const phaseRef = useRef(PHASE.NO_HAND);
  const holdRef = useRef(0);        // accumulated hold seconds
  const lastTsRef = useRef(0);      // last frame timestamp (ms)
  const offsetsRef = useRef([]);    // recent target-relative fingertip offsets

  const setPhaseBoth = (p) => { phaseRef.current = p; setPhase(p); };

  useEffect(() => {
    if (!acknowledged) return;
    let cancelled = false;

    async function start() {
      const HandsCtor = window.Hands;
      const CameraCtor = window.Camera;
      if (!HandsCtor || !CameraCtor) {
        setCamError(t('未能加载手部识别库，请检查网络连接。', 'Could not load the hand-tracking library — check your connection.'));
        return;
      }

      try {
        const hands = new HandsCtor({
          locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`,
        });
        hands.setOptions({
          maxNumHands: 2,
          modelComplexity: 1,
          minDetectionConfidence: 0.6,
          minTrackingConfidence: 0.6,
        });
        hands.onResults(onResults);
        handsRef.current = hands;

        const video = videoRef.current;
        const camera = new CameraCtor(video, {
          onFrame: async () => { if (handsRef.current) await handsRef.current.send({ image: video }); },
          width: 640,
          height: 480,
          facingMode: 'user',
        });
        cameraRef.current = camera;
        await camera.start();
        if (cancelled) camera.stop();
      } catch (err) {
        setCamError(t(
          '无法访问摄像头。请确认已授予权限，并通过 HTTPS 或 localhost 访问。',
          'Camera unavailable. Grant permission and open the app over HTTPS or localhost.'
        ));
      }
    }

    start();
    return () => {
      cancelled = true;
      try { cameraRef.current?.stop?.(); } catch (e) { /* noop */ }
      try { handsRef.current?.close?.(); } catch (e) { /* noop */ }
      const v = videoRef.current;
      if (v && v.srcObject) {
        v.srcObject.getTracks().forEach((tr) => tr.stop());
        v.srcObject = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [acknowledged]);

  function onResults(results) {
    const canvas = canvasRef.current;
    const video = videoRef.current;
    if (!canvas || !video) return;
    const W = canvas.width = video.videoWidth || 640;
    const H = canvas.height = video.videoHeight || 480;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, W, H);

    const now = performance.now();
    const lms = results.multiHandLandmarks || [];
    const handedRaw = results.multiHandedness || [];

    if (lms.length === 0) {
      holdRef.current = 0;
      offsetsRef.current = [];
      lastTsRef.current = now;
      if (phaseRef.current !== PHASE.COMPLETE) { setPhaseBoth(PHASE.NO_HAND); setProgress(0); }
      return;
    }

    // build per-hand info
    const hands = lms.map((lm, i) => ({
      lm,
      handed: handedRaw[i]?.label || 'Right',
      target: te3Target(lm),
      tip: lm[8],
      size: dist(lm[0], lm[9]) || 1e-6,
    }));

    // 2-hand assignment: receiver = the hand whose TE3 target is closest to the
    // OTHER hand's pressing fingertip; the other hand is the presser.
    let receiver, presser;
    if (hands.length >= 2) {
      const a = hands[0], b = hands[1];
      const aRecv = dist(a.target, b.tip); // a is receiver, b presses
      const bRecv = dist(b.target, a.tip); // b is receiver, a presses
      if (aRecv <= bRecv) { receiver = a; presser = b; }
      else { receiver = b; presser = a; }
    } else {
      receiver = hands[0];
      presser = null; // no presser => SEARCHING
    }

    const stateColor = phaseColor(phaseRef.current);

    // draw receiver target ring + inner dot (mirrored: x -> (1 - x) * W)
    const tx = (1 - receiver.target.x) * W;
    const ty = receiver.target.y * H;
    const tol = 0.16 * receiver.size;
    const ringR = Math.max(14, tol * W);

    drawRing(ctx, tx, ty, ringR, stateColor);
    ctx.beginPath();
    ctx.fillStyle = stateColor;
    ctx.arc(tx, ty, 5, 0, Math.PI * 2);
    ctx.fill();

    // draw the pressing fingertip as a white circle
    if (presser) {
      const px = (1 - presser.tip.x) * W;
      const py = presser.tip.y * H;
      ctx.beginPath();
      ctx.lineWidth = 3;
      ctx.strokeStyle = '#ffffff';
      ctx.arc(px, py, 9, 0, Math.PI * 2);
      ctx.stroke();
    }

    // ── phase machine ──
    const dt = lastTsRef.current ? (now - lastTsRef.current) / 1000 : 0;
    lastTsRef.current = now;

    if (phaseRef.current === PHASE.COMPLETE) return;

    // gate on the receiver's face
    if (!isDorsal(receiver.lm, receiver.handed)) {
      holdRef.current = 0; offsetsRef.current = [];
      setPhaseBoth(PHASE.WRONG_FACE); setProgress(0);
      return;
    }

    if (!presser) {
      holdRef.current = 0; offsetsRef.current = [];
      setPhaseBoth(PHASE.SEARCHING); setProgress(0);
      return;
    }

    const d = dist(presser.tip, receiver.target);
    const onTarget = d < tol;

    // steadiness: variance of last ~15 target-relative offsets < 0.06 * handSize
    const off = { x: presser.tip.x - receiver.target.x, y: presser.tip.y - receiver.target.y };
    const hist = offsetsRef.current;
    hist.push(off);
    if (hist.length > STEADY_WINDOW) hist.shift();
    let steady = false;
    if (hist.length >= STEADY_WINDOW) {
      const mx = hist.reduce((s, o) => s + o.x, 0) / hist.length;
      const my = hist.reduce((s, o) => s + o.y, 0) / hist.length;
      const variance = hist.reduce((s, o) => s + (o.x - mx) ** 2 + (o.y - my) ** 2, 0) / hist.length;
      steady = variance < 0.06 * receiver.size;
    }

    let next;
    if (!onTarget) {
      // off the point — pause hold but keep accumulated progress so brief drift is forgiving
      next = holdRef.current > 0 ? PHASE.PAUSED : PHASE.SEARCHING;
    } else if (!steady) {
      next = holdRef.current > 0 ? PHASE.ON_TARGET : PHASE.UNSTABLE;
    } else {
      next = PHASE.HOLDING;
      holdRef.current = Math.min(HOLD_TARGET_S, holdRef.current + dt);
    }

    if (holdRef.current >= HOLD_TARGET_S) {
      setProgress(1);
      setPhaseBoth(PHASE.COMPLETE);
      return;
    }

    setProgress(holdRef.current / HOLD_TARGET_S);
    setPhaseBoth(next);
  }

  function drawRing(ctx, x, y, r, color) {
    ctx.save();
    ctx.beginPath();
    ctx.lineWidth = 4;
    ctx.strokeStyle = color;
    ctx.globalAlpha = 0.9;
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  // ── safety acknowledgement gate ──
  if (!acknowledged) {
    return (
      <div className="coach-wrap">
        <div className="coach-card">
          <div className="coach-kicker">{t('安全须知', 'Before you begin')}</div>
          <h2 className="coach-title">{t('请先阅读', 'Please read first')}</h2>
          <p className="coach-lead">
            {t(
              '这是一个用于学习的轻柔按压引导，不用于诊断或处理任何健康问题。出现以下情况时，请不要继续，并咨询专业人士：',
              'This is a gentle self-guided pressure exercise for learning only. It is not for diagnosing or addressing any health condition. Do not continue, and consult a professional, if any of the following apply:'
            )}
          </p>
          <ul className="coach-flags">
            {RED_FLAGS[lang === 'zh' ? 'zh' : 'en'].map((f, i) => (
              <li key={i}>{f}</li>
            ))}
          </ul>
          <label className="coach-check">
            <input type="checkbox" checked={agree} onChange={(e) => setAgree(e.target.checked)} />
            <span>{t('我已阅读并理解上述提示。', 'I have read and understood the above.')}</span>
          </label>
          <button
            className="coach-btn"
            disabled={!agree}
            onClick={() => setAcknowledged(true)}
          >
            {t('开始引导', 'Begin')}
          </button>
        </div>
      </div>
    );
  }

  // ── completion recap ──
  if (phase === PHASE.COMPLETE) {
    return (
      <div className="coach-wrap">
        <div className="coach-card">
          <div className="coach-kicker" style={{ color: COLORS.jade }}>{t('完成', 'Complete')}</div>
          <h2 className="coach-title">{t('做得很好', 'Nicely done')}</h2>
          <p className="coach-lead">
            {t('你完成了一次约 30 秒的轻柔按压。现在感觉如何？',
               'You held a gentle press for about 30 seconds. How do you feel now?')}
          </p>
          <div className="coach-feel">
            {[
              { k: 'better', zh: '舒服一些', en: 'A little better' },
              { k: 'same',   zh: '没什么变化', en: 'No change' },
              { k: 'worse',  zh: '更不舒服', en: 'Worse' },
            ].map((o) => (
              <button
                key={o.k}
                className={`coach-feel-btn ${feeling === o.k ? 'on' : ''}`}
                onClick={() => setFeeling(o.k)}
              >
                {t(o.zh, o.en)}
              </button>
            ))}
          </div>
          {feeling === 'worse' && (
            <p className="coach-note warn">
              {t('请停止按压。如果不适持续或加重，建议咨询专业医疗人员。',
                 'Please stop. If the discomfort continues or worsens, consider speaking with a healthcare professional.')}
            </p>
          )}
          {feeling && feeling !== 'worse' && (
            <p className="coach-note">
              {t('很好。记得倾听身体的感受，温和为度。',
                 'Good. Keep listening to your body and stay gentle.')}
            </p>
          )}
          <button
            className="coach-btn ghost"
            onClick={() => {
              holdRef.current = 0; offsetsRef.current = []; lastTsRef.current = 0;
              setProgress(0); setFeeling(null); setPhaseBoth(PHASE.NO_HAND);
            }}
          >
            {t('再来一次', 'Go again')}
          </button>
        </div>
      </div>
    );
  }

  // ── live camera view ──
  const color = phaseColor(phase);
  const line = COPY[phase] ? (lang === 'zh' ? COPY[phase].zh : COPY[phase].en) : '';
  const R = 26, C = 2 * Math.PI * R;

  return (
    <div className="coach-wrap">
      <div className="coach-stage">
        {camError ? (
          <div className="coach-card coach-error">
            <div className="coach-kicker" style={{ color: COLORS.terracotta }}>{t('摄像头', 'Camera')}</div>
            <p className="coach-lead">{camError}</p>
          </div>
        ) : (
          <div className="coach-cam">
            <video ref={videoRef} className="coach-video" playsInline muted />
            <canvas ref={canvasRef} className="coach-canvas" />
            <div className="coach-tag" style={{ color }}>
              {t('中渚 · TE3', 'Zhongzhu · TE3')}
            </div>
          </div>
        )}
      </div>

      {!camError && (
        <div className="coach-feedback">
          <svg className="coach-ring" viewBox="0 0 64 64" width="64" height="64">
            <circle cx="32" cy="32" r={R} fill="none" stroke="rgba(90,80,50,0.18)" strokeWidth="5" />
            <circle
              cx="32" cy="32" r={R} fill="none" stroke={color} strokeWidth="5"
              strokeLinecap="round" strokeDasharray={C}
              strokeDashoffset={C * (1 - progress)}
              transform="rotate(-90 32 32)"
            />
            <text x="32" y="37" textAnchor="middle" fontSize="14" fill={color}
              fontFamily="'Cormorant Garamond', serif">{Math.round(progress * 100)}</text>
          </svg>
          <div className="coach-fb-text">
            <div className="coach-fb-phase" style={{ color }}>{t('状态', 'Status')}</div>
            <div className="coach-fb-line">{line}</div>
          </div>
        </div>
      )}
    </div>
  );
}
