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
| `RootView.swift` | Tab nav: **Atlas · Hand · Coach · Coach AI**; launches the AR coach. |
| `Theme.swift` | Ink-and-gold palette (1:1 with MaiApp's `styles.css` tokens) + panel/button styles. |
| `Acupoints.swift` | Data model + TE3 (validated AR point) + examples + meridian colors. Paste the full `data.js` list here. |
| `Body3DView.swift` | SceneKit rotatable 3D body (loads `body.usdz`, glowing placeholder otherwise). |
| `HandAtlasView.swift` | 2D tappable hand acupoint map. |
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
4. **3D model (optional):** convert `MaiApp/model.glb` → `body.usdz` (**Reality Converter** or
   `usdzconvert`) and add it to the bundle. Without it you get the glowing placeholder body.
5. **Chatbot:** key is read from `Secrets.xcconfig` / Keychain (git-ignored), **never committed**.
   Absent → offline canned reply. *(Wiring lands in Phase 2.)*
6. **Run on a real device** (camera + Vision hand-pose don't work in the Simulator).

## Notes / things to tune on-device
- **Front camera** is used (selfie); the preview is mirrored and landmark x is flipped to match.
  If the overlay sits on the wrong side, flip `usingFront`/the mirror in `CameraCoach.swift`.
- **Face gate sign:** `HandModel.isDorsal` uses the empirically-calibrated rule `dorsal ⇔ signed > 0`
  (mirror-invariant). If WRONG_FACE fires backwards on your device, invert that one comparison.
- **Vision orientation:** the request uses `.up`; if landmarks look rotated, adjust the
  `VNImageRequestHandler` orientation for the device orientation.
- **Scope this build ships:** TE3 camera coaching (validated). PC6/SI3 are atlas-only (no AR),
  matching the web app's honest scope — **no cadence/BPM**, position + hold + steadiness only.

## Safety (immutable, same as web)
No treat/cure/heal/diagnose copy anywhere; the safety gate before the camera is **not skippable**;
"Felt worse" → stop guidance; pregnancy → "check with a professional" (no contraindicated points used).
