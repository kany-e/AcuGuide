# Claude Code Instructions — Merge the camera coach INTO MaiApp (the real app)

MaiApp ("poetic-meridian-atlas") is the app we demo. All the camera-coaching work lives in the
SEPARATE root `src/` app (MediaPipe + TE3 position detection + One-Euro smoothing + WRONG_FACE gate).
Port the coaching ENGINE into MaiApp as an ADDITIVE feature, launched from the hand view. The 3D
atlas must keep working untouched (it is the fallback). Keep changes contained to new files + minimal
wiring. Respect the immutable safety rules (no treat/cure/heal/diagnose; forced safety ack; "felt
worse"→stop; LI4 excluded — we only use TE3 anyway).

## Read first
- MaiApp/src/: main.jsx, MeridianAtlas.jsx (state nav: view 'body'|'hand', selectedId, lang),
  HandView.jsx (SVG hand + onSelect), data.js (its ACUPOINTS), styles.css (the aesthetic to match).
- root src/: hooks/{useMediaPipe,useHandClassifier,usePressDetection,useCoachingState,useTTS}.ts,
  utils/{geometry,drawOverlay,landmarks,oneEuro}.ts, types/index.ts, data/acupoints.json (the TE3
  entry with mediapipe_target anchors + tolerance + press_finger + coach_copy), pages/CameraPage.tsx
  and SafetyPage.tsx (for the flow logic + safety copy to mirror, NOT to copy wholesale).

## Do
1. PORT THE ENGINE into MaiApp/src/coach/ (copy as-is; Vite/esbuild compiles .ts from .jsx natively —
   no TS config or conversion needed): the 5 hooks, the 4 utils, types, and a coachData.(js|ts) holding
   the TE3 acupoint entry (id, mediapipe_target anchors/tolerance, press_finger=INDEX_TIP, coach_copy).
2. BUILD MINIMAL UI in MaiApp's own CSS (do NOT port Tailwind / the 5 pages):
   - SafetyGate.jsx — the red-flag list + a non-skippable "I understand" button (mirror SafetyPage copy).
   - CameraCoach.jsx — <video> + <canvas> overlay via drawOverlay; runs the ported hooks; shows the
     state label + coaching line + the target ring (green on on-target+stable) + the hold timer.
   - CoachRecap.jsx — hold-time + position-steadiness + a feeling selector (better/same/worse;
     "worse" → stop guidance, never "continue").
3. WIRE INTO MeridianAtlas.jsx: add a `view: 'coach'` (or an overlay) + a `coachPointId`. In HandView,
   when the selected point maps to TE3 (Zhongzhu), show a "Practice / 练习" button that launches
   SafetyGate → CameraCoach(TE3) → CoachRecap → back to the atlas. Only TE3 gets the camera this round;
   all other points behave exactly as today.
4. CRITICAL FIXES (or the camera will crash):
   - Remove `<React.StrictMode>` from MaiApp/src/main.jsx (StrictMode double-invoke breaks getUserMedia;
     this is why the root app removed it). 
   - Do NOT await video.play() — use `.catch(()=>{})`.
   - Camera init and MediaPipe init in separate try/catch; run the camera effect once (empty deps),
     guard MediaPipe init with a ref. (Same decisions as the root app's CLAUDE.md.)

## Do NOT
- Do not modify Body3D.jsx / the 3D atlas / the existing body+hand exploration. The atlas demo must
  still run if the camera path fails.
- Do not convert MaiApp to TypeScript or add Tailwind. Do not port the root app's 5 Tailwind pages.
- Do not ship PC6/SI3 camera coaching (only TE3 is validated). No cadence/BPM/rhythm anything.

## Verify (required)
- `cd MaiApp && npm run build` passes; `npm run dev` runs.
- The 3D atlas still loads, rotates, and the hand view still works (regression check).
- Hand view → select TE3 → Practice → safety gate (can't skip) → camera shows the ring on the dorsal
  ring/pinky-knuckle region → green on a steady on-target index press → hold completes → recap → back.
- No treat/cure/heal/diagnose copy; StrictMode removed; build clean.
- Report exactly which files were added vs the (few) MaiApp files touched (main.jsx, MeridianAtlas.jsx,
  HandView.jsx, styles.css).

## Deliver
The ported engine + 3 new UI components + the wiring, a note of what changed, and the verify results.
Work additively so the atlas remains a working fallback.
