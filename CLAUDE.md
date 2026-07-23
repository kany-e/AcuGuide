# CLAUDE.md — AcuGuide (native iOS app)

## Working agreement

- **End every session with a short summary.** When a working session wraps up, give a brief recap:
  what changed, the current state (build/tests), and what's next. Keep it to a few lines — no need
  to re-explain everything.
- **Build and test on this machine after every change.** `xcodegen` and `xcodebuild` both work here;
  never claim otherwise. `make test` is the gate.

## What this repo is

A native **SwiftUI iOS app** — a camera-guided acupressure coach for safe, non-diagnostic self-care.
The app lives at the **repository root**; the Xcode project is generated from `project.yml`
(XcodeGen) and is never hand-assembled or committed.

```
AcuGuide/              # app sources
AcuGuideTests/         # unit tests (fixtures bundled from claude-deliverables/fixtures/)
project.yml            # XcodeGen spec  -> AcuGuide.xcodeproj (gitignored)
Makefile               # make project / build / test
claude-deliverables/   # CV research, acupoint source verification, replay fixtures
docs/                  # privacy policy, icon drafts
archive/               # superseded pre-iOS work — NOT part of the build
acuguide-dashboard.html
```

## Dev commands

```bash
make project   # xcodegen generate -> AcuGuide.xcodeproj
make build     # xcodebuild, generic iOS device, signing off
make test      # xcodebuild test on a simulator
```

CI mirrors this in `.github/workflows/ios-tests.yml`.

## Things that will bite you

1. **The test target bundles replay fixtures from outside its own directory.** `project.yml` lists
   `claude-deliverables/fixtures/fixture_*.json` as test-target resources; `CoachEngineFixtureTests`
   loads them **by bundle name**. Move or rename those files and the fixture tests break.
2. **`AcuGuide.xcodeproj/` and `AcuGuide/Info.plist` are generated and gitignored.** Info.plist is
   declared inside `project.yml` (it has to be, because `UIAppFonts` is an array). Edit the spec,
   not the generated file — `xcodegen generate` overwrites it.
3. **GLTFKit2 is a pinned binary xcframework** resolved over the network on first `make project`.
   If an SPM cleanup nukes the artifact, re-resolve before assuming the code broke.
4. **Camera and Vision hand-pose do not work in the Simulator.** Unit tests run there; anything
   involving the live coach has to be checked on a device.

## Safety rules (non-negotiable)

- Copy must **never** contain treat / cure / heal / diagnose.
- The safety gate before the camera is **forced** — it cannot be skipped.
- "Felt worse" after a routine → show stop guidance, never "continue".
- **LI4 is excluded entirely** (pregnancy-contraindicated), so no pregnancy screening is needed.
- Acupoint data is sourced and adversarially verified — see
  `claude-deliverables/references/acuguide_source_upgrade.md` and the in-app Sources screen.

## Archive

`archive/` holds the pre-iOS lineage, kept for reference and **built by nothing**:

| path | what it was |
|---|---|
| `archive/web-camera-coach/` | React + Vite + MediaPipe browser prototype (`src/`) and its build config |
| `archive/MaiApp/` | three.js 诗词山河 meridian atlas — the visual design the iOS theme came from |
| `archive/demo-app/` | original vanilla-JS prototype, superseded by the React one |
| `archive/hackathon-md/`, `archive/product/` | planning, requirements, pitch and demo docs |
| `archive/README-web-apps.md` | the old web-era root README |

Web-era decisions that only ever applied to the archived React app (kept so they aren't
rediscovered the hard way if that code is ever revived): no React `StrictMode` (double-invoked
effects caused iOS `getUserMedia` AbortError); never `await video.play()` on iOS Safari; debounce
the coaching state machine with timestamps, not `setTimeout`, because it runs every frame.
