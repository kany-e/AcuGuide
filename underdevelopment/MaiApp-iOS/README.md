# AcuGuide — Native iOS (SwiftUI) starter

A native port of MaiApp (the 诗词山河 meridian atlas) with three things added:
**a 3D body atlas**, an **AR coaching window** (Vision hand-pose → TE3 overlay, porting the
validated web logic), and a **themed AI chatbot** — all in the same ink-and-gold palette.

> Status: **builds & runs (Phase 0 done).** Originally authored on Windows and never compiled;
> it is now a reproducible Xcode project generated from `project.yml` (XcodeGen), with an asset
> catalog, camera usage string, and a wired unit-test target. `xcodebuild build` and
> `xcodebuild test` both pass. The structure, theme, and AR coaching logic are faithful to the web app.

## Files (all under `AcuGuide/`)
| File | Role |
|---|---|
| `AcuGuideApp.swift` | App entry. |
| `RootView.swift` | Tab nav: **Atlas · Coach · Coach AI**; Atlas drills body → hand → back; launches the AR coach. |
| `Theme.swift` | Ink-and-gold palette (1:1 with MaiApp's `styles.css` tokens) + panel/button styles. |
| `Acupoints.swift` | Full bilingual hand atlas from `data.js` (TE3 + PC6/SJ5/PC8/HT7/SI3; TE3 only AR; no LI4). |
| `Body3DView.swift` | SceneKit body — loads `model.glb` via **GLTFKit2** (sage material), capsule fallback; pulsing hand hotspot. |
| `HandAtlasView.swift` | Hand acupoint map — real `HAND_PTS` Catmull-Rom silhouette + radial skin gradient + tendon hints. |
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
   cd underdevelopment/MaiApp-iOS
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
4. **3D model:** loaded at runtime from the bundled `AcuGuide/Resources/model.glb` (a copy of
   `MaiApp/model.glb`) via the **GLTFKit2** Swift package — no usdz conversion, same asset as the
   web app. `make project` resolves the package (network needed once). Capsule shows only if the
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
  text from `MaiApp/src/data.js`. **TE3 is the only AR-coached point**; LI4 is excluded.

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
- **`AcuGuide/Resources/model.glb`** — body model (same asset as the web `MaiApp/`).
- Bundled fonts (`AcuGuide/Fonts/`): **Ma Shan Zheng** and **Cormorant Garamond**, both SIL OFL.
