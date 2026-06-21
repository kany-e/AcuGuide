# AcuGuide — Native iOS (SwiftUI) starter

A native port of MaiApp (the 诗词山河 meridian atlas) with three things added:
**a 3D body atlas**, an **AR coaching window** (Vision hand-pose → TE3 overlay, porting the
validated web logic), and a **themed AI chatbot** — all in the same ink-and-gold palette.

> Status: **starter scaffold, post-hackathon track.** It was authored on Windows and **not
> compiled** (Xcode is macOS-only), so budget a little fix-up time in Xcode. The structure,
> theme, and the AR coaching logic are complete and faithful to the web app.

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
1. **New project** → iOS → App → SwiftUI → name it `AcuGuide`. **Deployment target: iOS 16+.**
2. Delete the default `ContentView.swift`/`*App.swift`, then **drag in all the `AcuGuide/*.swift` files**.
3. **Camera permission:** in the target's Info, add `NSCameraUsageDescription` =
   "AcuGuide uses the camera to guide your acupressure press."
4. **3D model (optional):** convert your `MaiApp/model.glb` → `body.usdz` with **Reality Converter**
   (free) or `usdzconvert`, and add it to the app bundle as `body.usdz`. Without it you get the
   glowing placeholder body.
5. **Chatbot:** open `ChatView.swift` → set `apiKey` (and `endpoint`/`model`) in `ChatService`.
   Leave it empty to use the offline canned reply. **Do not commit the key.**
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
