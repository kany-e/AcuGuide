# AcuGuide — Native iOS (SwiftUI)

A camera-guided **acupressure coach** for safe, non-diagnostic self-care, in an ink-and-gold
palette: a **3D body atlas** of 33 sourced points across fourteen meridians, an **AR coaching
window** (Vision hand-pose, 8 camera-coached points), a **guided timer** for everything else, and a
**fully on-device AI chat coach**.

> Status: **builds, tests, and ships green.** The Xcode project is generated from `project.yml`
> (XcodeGen). `make build` (generic iOS device, unsigned) and `make test` both pass — **136 tests,
> 0 failures**. Every branch is gated by `.github/workflows/merge-gate.yml` before it may merge.
>
> **Not yet verified on real hardware:** the meridian rendering and the hand-detection feel. Camera
> and Vision hand-pose do not run in the Simulator, so no amount of test coverage speaks to them.

## Repository layout
The iOS app **is** this repository — it lives at the root.

```
AcuGuide/               # app sources (SwiftUI, Vision, SceneKit) — 51 files
AcuGuideTests/          # unit tests — 11 files, 136 tests
project.yml             # XcodeGen spec — the project is generated, never hand-assembled
Makefile                # make project / build / test
scripts/                # safety_scan.py (banned-claim scanner), pick_simulator.sh
.github/workflows/      # merge-gate.yml — the required check for anything landing on main
claude-deliverables/    # CV research, acupoint sources, and the replay fixtures the tests bundle
tools/voice/            # offline Kokoro renderer for the pre-rendered voice clips
store/metadata/         # App Store listing copy (en-US, zh-Hans) — scanned by the safety gate
licenses/               # full third-party license texts (OFL 1.1)
docs/                   # privacy policy, release checklist, pre-release vision, icon drafts
archive/                # superseded work, kept for reference — nothing here is built (see below)
CLAUDE.md               # working agreement + the traps that bite (read this before changing things)
acuguide-dashboard.html # project dashboard, regenerated from live git state
```

`archive/` holds the pre-iOS work: `web-camera-coach/` (the React + MediaPipe browser prototype
and its build config), `MaiApp/` (the three.js 诗词山河 meridian atlas the visual design came from),
`demo-app/` (the original vanilla-JS prototype), plus the `hackathon-md/` and `product/` planning
docs and the old web-era `README-web-apps.md`. **Nothing in `archive/` is part of the build.**

## What's in the app
Three tabs — **Atlas · Practice · Coach AI** (`RootView.swift`).

| Area | Files | What it does |
|---|---|---|
| **Atlas** | `Body3DView`, `HandModel3DView`, `Meridians`, `Acupoints` | SceneKit body (GLTFKit2), drill down body → hand → back; 33 bilingual points on 14 meridians, each with location, plain-language "how to find it", traditional-use text and read-aloud |
| **Camera coach** | `ARCoachView`, `CameraCoach`, `Coach`, `HandModel`, `CameraGate`, `CameraSetupCard` | Forced safety gate → first-run setup card → find-your-spot locate step → live overlay (ring / press dot / feedback) → recap. Position + hold + steadiness; **no cadence** |
| **Guided timer** | `TimerSession`, `SessionUI`, `Routines` | The camera-free path for the other 25 points, plus multi-step routines |
| **Calibration** | `PointCalibration`, "Your spots" in `RootView` | Saves *your* spot per point as a delta in the canonical hand frame; re-findable and resettable |
| **Chat coach** | `ChatView`, `ChatLLM` | Bilingual wellness Q&A over the atlas. Crisis and red-flag routing run **first**, before any answer |
| **History** | `PracticeStore`, `HistoryView` | Local-only practice log with export (ShareLink) and in-app deletion |
| **Voice** | `Speech` (incl. `AtlasSpeaker`), `VoiceClips`, `LocateVoice` | Pre-rendered clip playback, spoken cues, read-aloud, hands-free "this is my spot" |
| **Settings & reference** | `Settings`, `SourcesView`, `CreditsView` (holds `PrivacyView`), `OnboardingView` | Language, on-device AI toggle, daily reminder, sources, credits, privacy |

## Setup (Xcode, on your Mac)
The project is **generated from `project.yml`** — no hand-assembly. You need
[XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

1. **Generate + open:**
   ```bash
   make project          # = xcodegen generate  → AcuGuide.xcodeproj (git-ignored)
   open AcuGuide.xcodeproj
   ```
   Bundle id `app.acuguide.ios`, deployment target **iOS 16.0**, SwiftUI lifecycle,
   portrait-locked. The camera usage string and `AccentColor`/`AppIcon` assets are baked in.
2. **Build / test from the CLI** (no Xcode UI needed):
   ```bash
   make build            # xcodebuild build for a generic iOS device (signing off)
   make test             # xcodebuild test (auto-picks a simulator; override with SIM="iPhone 16")
   ```
   `make test` is the gate — CI re-runs it on a different toolchain plus a device build, the stress
   suite five times, and the whole suite twice to catch `UserDefaults` state leaks.
3. **Signing:** set your team on the `AcuGuide` target to run on a physical device.
4. **3D models:** loaded at runtime from `AcuGuide/Resources/*.glb` via the **GLTFKit2** Swift
   package — no usdz conversion. `make project` resolves the package (network needed once); if an
   SPM cleanup nukes the artifact, re-resolve before assuming the code broke. A capsule fallback
   shows only if an asset is missing.
5. **Chat coach:** fully **offline**. On iOS 26+ with Apple Intelligence it answers free-form
   questions using Apple's on-device `FoundationModels`; elsewhere it falls back to the built-in
   bilingual atlas helper. No API key, no network, no accounts. Red-flag symptoms → stop-and-seek
   care; crisis messages route to real help and never to acupressure.
6. **Run on a real device** — camera and Vision hand-pose don't work in the Simulator.

## Voice
Every spoken line is a fixed string, so the whole script is **pre-rendered offline** into **102
bilingual AAC clips** (`AcuGuide/VoiceClips/`, ~5.3 MB, Kokoro / Apache-2.0; pipeline in
`tools/voice/`). Playback is the primary path; `AVSpeechSynthesizer` is the fallback for any line
that has drifted from its clip.

> **The clip key is `sha256("<locale>|<normalized text>")`** — so *rewording any spoken string
> orphans its clip* and silently drops that line to the robotic fallback. `VoiceScriptTests` fails
> in both directions (missing clip / orphaned clip); when it does, re-render with
> `tools/voice/render_voice.py`. See `CLAUDE.md` before touching spoken copy.

Cues fire on phase change only; there's a mute toggle. `.ambient` session for coach cues (respects
the silent switch), `.playback` for read-aloud. **Haptics** (`CoreHaptics`, `UIFeedbackGenerator`
fallback): a tick on first entering the target, a success pattern at COMPLETE; nothing during
NO_HAND / WRONG_FACE.

## Safety (immutable — enforced by tests and CI, not convention)
- No **treat / cure / heal / diagnose** copy anywhere, in either language. `scripts/safety_scan.py`
  scans Swift string literals *and* the store metadata; it runs in CI and locally.
- The safety gate before the camera is **forced** — it cannot be skipped, and it stays scrollable so
  large Dynamic Type can never push its only exit off-screen.
- "Felt worse" after a routine → **stop guidance, never "continue"** (including for legacy stored
  keys).
- Each point's own caution is shown **where the press happens**, not only on the atlas card.
- **LI4 is excluded entirely** (pregnancy-contraindicated) — which is *why* the app needs no
  pregnancy screening. CI fails if it reappears.
- Crisis and red-flag routing run before any chat answer.
- Acupoint data is sourced and adversarially verified — see `claude-deliverables/references/` and
  the in-app Sources screen.

## Licensing
AcuGuide's own source is **proprietary — all rights reserved** ([LICENSE](LICENSE)). The repo is
public so the source can be read and reviewed; it is not open-source, and redistribution or reuse
in another product needs written permission.

The bundled third-party components keep their own licenses, several of which **require attribution
that must be preserved when the app is distributed** — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and [`licenses/`](licenses/).

## Third-party assets / credits
All three bundled models are **CC-BY 4.0** from Sketchfab and their attribution is a **licence
obligation**. The same credits are shown in-app under Settings → Licenses & credits.

| Asset | Title | Author | Licence |
|---|---|---|---|
| `Resources/model.glb` | Character Mannequin Male | [muh.nurzidan](https://sketchfab.com/muh.nurzidan) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Resources/arms_hands_head_legs_and_feet__low_poly_female.glb` | Arms, hands, head, legs and feet (low poly) — Female | [pnhtuan](https://sketchfab.com/pnhtuan7) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Resources/hand_low_poly.glb` | Hand (low poly) | [scribbletoad](https://sketchfab.com/scribbletoad) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

Models were recolored and rescaled for display.

- **Voice:** [Kokoro-82M v1.1](https://huggingface.co/hexgrad/Kokoro-82M) (Apache-2.0), rendered
  offline via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx).
- **Fonts** (`AcuGuide/Fonts/`): **Ma Shan Zheng** and **Cormorant Garamond**, both
  [SIL OFL 1.1](licenses/OFL-1.1.txt) (the license text ships with them, as OFL requires).
- **GLTFKit2** by [Warren Moore](https://github.com/warrenm/GLTFKit2), MIT.

## Notes / things to tune on-device
- **Mirror / face gate:** a calibration menu (slider icon) in the coach view flips the preview
  mirror and inverts the face gate at runtime, so no code edit is needed for field calibration.
- **Vision orientation:** derived from the capture connection (portrait-locked), not hardcoded.
- **Two-person mode:** the back camera coaches someone else's hand.
- **Scope this build ships:** camera coaching for 8 hand/wrist points — **TE3, PC6, SJ5, PC8, HT7,
  SI3, TE4, PC7** (TE3 is the default demo point). Every other point is atlas + guided timer.
