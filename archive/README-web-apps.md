# AcuGuide

A camera-guided **hand-acupressure coach** for safe, non-diagnostic self-care. It shows you
*where* to press an acupoint, confirms your hand is in view and facing the right way, checks
your finger is on the target region, and times a steady hold — framed as wellness coaching,
never medical diagnosis or treatment.

This repo currently holds **two live web apps** plus supporting docs and exploratory work.

## The two live apps

### 1. Camera coach — repo root (`src/`)
React + Vite + TypeScript + Tailwind, with **MediaPipe Hands** for live hand tracking.
This is the camera feedback loop: target overlay on the acupoint, on-point + steady-hold
detection, a wrong-hand-face gate, a forced safety screen, and a recap.

```bash
npm install
npm run dev      # HTTPS dev server (mkcert) — needed for camera access
npm run build
npx tsc --noEmit # type-check
```

### 2. Poetic Meridian Atlas — `MaiApp/`
React + three.js (react-three-fiber). A bilingual (中文 / English) **3D meridian atlas**:
a rotatable body with glowing channels, tap the hand to drop into a 2D acupoint view.
Ink-and-gold aesthetic; self-contained with its own dependencies.

```bash
cd MaiApp
npm install
npm run dev
```

> The camera coaching (app 1) is being prepared to merge into the atlas (app 2); they are
> still separate today.

## Honest scope (what the coach actually does)
We ship only what we validated. The camera coach gives **position + steady-hold** feedback on
**TE3 (中渚)** — whether the pressing finger is on the point and held steadily — plus a
hand-face gate. We **deliberately dropped press-rhythm / cadence**: our own testing showed the
correct sustained-press technique has no reliably measurable rhythm, so we don't display a
number we can't stand behind. The app makes **no medical or efficacy claims**.

## Safety rules (non-negotiable)
- No "treat / cure / heal / diagnose" language anywhere.
- A safety screen with red-flag stop symptoms is **shown before the camera and cannot be skipped**.
- "Felt worse" after a routine → advise stopping, never "continue".
- The one pregnancy-contraindicated point (LI4) is excluded entirely — no risky screening.

## Privacy & footprint
All camera and hand-tracking runs **on the user's device** (in-browser MediaPipe) — video is
never uploaded or stored, and there are no accounts or personal-data collection. We use a
lightweight **pretrained** vision model + rule-based logic (no custom model training), keeping
the compute footprint small.

## Repository layout
```
AcuGuide/
├── src/, index.html, package.json, vite.config.ts, …   # App 1: camera coach (React + MediaPipe)
├── MaiApp/                                              # App 2: 3D meridian atlas (React + three.js)
├── product/                                             # pitch, Devpost draft, demo script, safety copy
├── hackathon/, "hackathon - md/"                        # planning & requirements docs
├── claude-deliverables/                                 # CV research, validation reports, build specs
├── underdevelopment/                                    # not in the live build (see below)
│   ├── MaiApp-iOS/                                      #   native SwiftUI port (post-hackathon)
│   └── demo-app/                                        #   early vanilla-JS prototype (superseded)
├── _archive/                                            # analysis pipeline, training videos, labeled data
├── CLAUDE.md                                            # repo working notes / key technical decisions
└── README.md
```

- **underdevelopment/** — code not part of the current live demo: the native iOS (Swift/ARKit)
  starter, and the original vanilla-JS prototype that the React apps replaced.
- **_archive/** — the Python CV analysis pipeline, raw training videos, and labeled JSON used to
  validate the coaching logic. The live apps do not depend on anything here (it's gitignored).

## Docs
- Pitch / demo script / Devpost / judge Q&A — `product/`
- Planning, requirements, team roles — `hackathon/`, `hackathon - md/`
- CV validation, calibration reports, and build prompts — `claude-deliverables/`
