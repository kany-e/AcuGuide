# AcuGuide — Native iOS (SwiftUI)

A camera-guided **acupressure coach** for safe, non-diagnostic self-care, in an ink-and-gold
palette: **a 3D body atlas**, an **AR coaching window** (Vision hand-pose → TE3 overlay), and a
**themed offline AI chatbot**.

> Status: **builds & runs.** The Xcode project is generated from `project.yml` (XcodeGen), with an
> asset catalog, camera usage string, and a wired unit-test target. `xcodebuild build` and
> `xcodebuild test` both pass.

## Repository layout
The iOS app **is** this repository — it lives at the root.

```
AcuGuide/              # app sources (SwiftUI, Vision, SceneKit)
AcuGuideTests/         # unit tests
project.yml            # XcodeGen spec — the project is generated, never hand-assembled
Makefile               # make project / build / test
claude-deliverables/   # CV research, acupoint sources, and the replay fixtures the tests bundle
docs/                  # privacy policy, icon drafts
archive/               # superseded work, kept for reference — nothing here is built (see below)
```

`archive/` holds the pre-iOS work: `web-camera-coach/` (the React + MediaPipe browser prototype
and its build config), `MaiApp/` (the three.js 诗词山河 meridian atlas the visual design came from),
`demo-app/` (the original vanilla-JS prototype), plus the `hackathon-md/` and `product/` planning
docs and the old web-era `README-web-apps.md`. **Nothing in `archive/` is part of the build.**

## Files (all under `AcuGuide/`)
| File | Role |
|---|---|
| `AcuGuideApp.swift` | App entry. |
| `RootView.swift` | Tab nav: **Atlas · Coach · Coach AI**; Atlas drills body → hand → back; launches the AR coach. |
| `Theme.swift` | Ink-and-gold palette (1:1 with the archived web app's `styles.css` tokens) + panel/button styles. |
| `Acupoints.swift` | Full bilingual hand atlas (TE3 + PC6/SJ5/PC8/HT7/SI3; TE3 only AR; no LI4). |
| `Body3DView.swift` | SceneKit body — loads `model.glb` via **GLTFKit2** (sage material), capsule fallback; pulsing hand hotspot. |
| `HandModel3DView.swift` | Detailed 3D hand drill-down (scribbletoad's CC-BY model) with raycast acupoint markers. |
| `HandModel.swift` | Vision joints + geometry: `weightedTarget`, `handSize`, **calibrated dorsal/palmar test**. |
| `Coach.swift` | `CoachEngine` — position + hold + steadiness state machine (no cadence; correct technique). |
| `CameraCoach.swift` | AVCapture + `VNDetectHumanHandPoseRequest` → drives `CoachEngine`; camera preview. |
| `ARCoachView.swift` | Safety gate (forced) → live overlay (ring/finger/feedback) → recap. |
| `ChatView.swift` | Themed bilingual coach chat + `ChatService` (plug in your LLM key). |

## Setup (Xcode, on your Mac)
The project is **generated from `project.yml`** — no hand-assembly. You need
[XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

1. **Generate + open:**
   ```bash
   # from the repository root
   make project          # = xcodegen generate  → AcuGuide.xcodeproj (git-ignored)
   open AcuGuide.xcodeproj
   ```
   Bundle id `app.acuguide.ios`, deployment target **iOS 16.0**, SwiftUI lifecycle,
   portrait-locked. The camera usage string and `AccentColor`/`AppIcon` assets are baked in.
2. **Build / test from the CLI** (no Xcode UI needed):
   ```bash
   make build            # xcodebuild build for a generic iOS device (signing off)
   make test             # xcodebuild test on the iPhone 17 simulator
   ```
3. **Signing:** set your team on the `AcuGuide` target to run on a physical device.
4. **3D model:** loaded at runtime from the bundled `AcuGuide/Resources/model.glb` via the
   **GLTFKit2** Swift package — no usdz conversion. (Same asset as the archived web atlas,
   `archive/MaiApp/model.glb`.) `make project` resolves the package (network needed once). Capsule shows only if the
   asset is missing. The body auto-rotates and pauses while you drag.
5. **Chatbot:** fully **offline** — a local bilingual wellness helper over the acupoint atlas. No
   API key, no network, no accounts, nothing to secure. Red-flag symptoms → stop-and-seek-care.
6. **Run on a real device** (camera + Vision hand-pose don't work in the Simulator).

## Native features (Phase 2)
- **Voice cues** (`AVSpeechSynthesizer`) on phase change only; bilingual by device locale; mute
  toggle (speaker button); `.ambient` audio session (respects the silent switch).
- **Haptics** (`CoreHaptics`, `UIFeedbackGenerator` fallback): a tick on first entering the target,
  a success pattern at COMPLETE; nothing during NO_HAND / WRONG_FACE.
- **Atlas:** TE3 + PC6 / SJ5 / PC8 / HT7 / SI3 with bilingual labels, location, and traditional-use
  text carried over from the archived web atlas. **TE3 is the only AR-coached point**; LI4 is excluded.

## Notes / things to tune on-device
- **Mirror / face gate:** a calibration menu (slider icon) in the coach view flips the preview
  mirror and inverts the face gate at runtime, so no code edit is needed for field calibration.
- **Vision orientation:** derived from the capture connection (portrait-locked), not hardcoded.
- **Scope this build ships:** TE3 camera coaching (validated). Every other point is atlas-only
  (no AR), matching the web app's honest scope — **no cadence/BPM**, position + hold + steadiness.

## Safety (immutable, same as web)
No treat/cure/heal/diagnose copy anywhere; the safety gate before the camera is **not skippable**;
"Felt worse" → stop guidance; pregnancy → "check with a professional" (no contraindicated points used).

## Third-party assets / credits
- **`AcuGuide/Resources/hand_low_poly.glb`** — "Hand Low Poly" by **scribbletoad**, licensed
  **CC-BY 4.0** (https://creativecommons.org/licenses/by/4.0/), from Sketchfab. Used for the
  detailed 3D hand in the hand drill-down. Attribution is also shown in-app on that screen.
  Required attribution: *"Hand Low Poly" by scribbletoad — CC-BY 4.0.*
- **`AcuGuide/Resources/model.glb`** — body model (same asset as `archive/MaiApp/`).
- Bundled fonts (`AcuGuide/Fonts/`): **Ma Shan Zheng** and **Cormorant Garamond**, both SIL OFL.
