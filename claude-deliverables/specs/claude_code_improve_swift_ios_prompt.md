# Claude Code prompt — make the native iOS (SwiftUI) port build, run, and feel right

Paste everything below the line into Claude Code, running **from the repo root on a Mac with
Xcode**. It is scoped to the Swift port only (`underdevelopment/MaiApp-iOS/`). Work in priority
order, verify each phase before moving on, and **never** weaken the safety rules in the
"Non-negotiables" section.

---

You are working on **AcuGuide**, a camera-guided hand-acupressure *wellness* coach (not a
medical tool). The validated product is the React web app at the repo root (`src/`) plus the
3D meridian atlas (`MaiApp/`). A **native SwiftUI port** was scaffolded on Windows and **never
compiled**. Your job is to make it build, run correctly on a real iPhone, match the web app's
look and flow, and then add a few native features — without changing the validated behavior or
the safety posture.

**Two things to fix that the screenshots make obvious:** the port currently shows a **capsule
(cylinder) for the body** and a **`RoundedRectangle` (square) for the hand** — it never loads the
real `MaiApp/model.glb` and never draws the real hand silhouette; those primitives are meant to
be fallbacks only. And navigation is wrong: there must be **no separate "Hand" tab** — the user
reaches the hand by **tapping a hand hotspot on the 3D body** (exactly like the web app's
`onEnterHand`), with a back button to return. Both are addressed in Phase 2 below.

## Where things are

- **Port you are improving:** `underdevelopment/MaiApp-iOS/AcuGuide/*.swift` (11 files) +
  `underdevelopment/MaiApp-iOS/README.md`.
- **Source of truth for coaching behavior (do not regress):**
  - `underdevelopment/demo-app/cv/engine.js` — the deterministic, rule-based state machine
    (enter/exit radius hysteresis, dropout debounce, pause-grace, hold confirm). This is the
    most complete reference.
  - `src/hooks/useCoachingState.ts`, `src/hooks/usePressDetection.ts`,
    `src/hooks/useHandClassifier.ts`, `src/hooks/useMediaPipe.ts` — the shipping React logic.
  - `src/utils/oneEuro.ts` — the One-Euro smoothing filter applied to the target ring.
- **Full acupoint / meridian dataset:** `MaiApp/src/data.js` (the 14 meridians in
  `MERIDIAN_COLORS` plus the acupoint list, bilingual zh/en). Use it as the source for the atlas;
  count the actual points there rather than trusting this note.
- **Body + hand visuals and the body→hand interaction (match these):**
  - `MaiApp/src/Body3D.jsx` — loads `/model.glb` (rigged GLB), sage-green material, projected
    meridian channels, region labels, and the **pulsing gold `HandHotspot`** that calls
    `onEnterHand`. The cylinders/spheres in `PlaceholderBody` are only the error-boundary fallback.
  - `MaiApp/src/HandView.jsx` — the real hand: `HAND_PTS` → a smooth closed Catmull-Rom path,
    `handSkin` radial gradient, tendon/knuckle hint strokes, glowing acupoints, and an `onBack`.
  - `MaiApp/src/MeridianAtlas.jsx` — the nav container: `view` state of body/hand/coach/ask and
    `onEnterHand={() => setView('hand')}`; the hand is a drill-down from the body, not a peer tab.
- **Replay fixtures (ground-truth frame streams):** `claude-deliverables/fixtures/*.json`.
- **3D model to convert and wire in:** `MaiApp/model.glb` → `body.usdz` (this is the real asset;
  it is currently not connected, which is why a capsule shows).

Read the port and these references before editing. Then post a short written diff of how the
Swift `CoachEngine` differs from `engine.js` before you start changing logic.

## Non-negotiables (immutable — same as the web app; do not touch)

1. **No `treat` / `cure` / `heal` / `diagnose`** language anywhere in copy, comments shown to
   users, or chatbot system prompts. It is wellness self-care, never medical.
2. The **safety gate is forced and cannot be skipped** — it must appear before the camera ever
   starts. (`SafetyGate` in `ARCoachView.swift`; keep the red-flag stop-symptom list.)
3. **"Felt worse"** after a routine → advise stopping; never "continue."
4. **LI4 is excluded entirely** (pregnancy-contraindicated) — do not add it, even to the atlas.
5. **Honest scope: TE3 (中渚) is the only AR-coached point.** PC6/SI3/etc. stay **atlas-only**
   (display, no camera coaching). Do **not** add AR coaching for un-validated points. Keep the
   "no cadence / no BPM" stance — position + steady-hold only.
6. Keep the **ink-and-gold** visual identity (`Theme.swift`, matched to `MaiApp/styles.css`).
7. All hand tracking stays **on-device** (Vision). No video upload, no accounts, no telemetry.

## Definition of done

The app opens in Xcode, builds clean for an iOS 16+ device, passes `xcodebuild` for the unit-test
target, and runs on a real iPhone through the full flow: **3D body atlas (real model) → tap the
hand hotspot on the body → hand acupoint map → back, or → Coach safety gate → live TE3 overlay →
recap → chat**. The body and hand are the real model/silhouette (not a capsule or a rectangle),
there is **no separate Hand tab**, the new native features below work, and the four immutable
safety behaviors are intact.

---

## Phase 0 — Make it a real, buildable app (do this first)

The folder is **loose `.swift` files**: there is no `.xcodeproj`, no `Info.plist`, no
`Assets.xcassets`, no app icon, no `body.usdz`. It cannot compile as-is.

1. **Generate a project.** Prefer **XcodeGen** (`brew install xcodegen`) with a checked-in
   `project.yml`, or Swift Package + an app target — pick whichever you can drive to a green
   `xcodebuild` from the CLI. Target name `AcuGuide`, bundle id `app.acuguide.ios` (or similar),
   **deployment target iOS 16.0**, SwiftUI lifecycle. Commit the project file(s) so it is
   reproducible — no more "drag files into Xcode by hand."
2. **Info.plist:** add `NSCameraUsageDescription` =
   "AcuGuide uses the camera to guide your acupressure press." Set supported orientations
   (portrait + the two landscapes you actually handle in Phase 1; portrait-only is acceptable if
   you lock it).
3. **Assets:** add an `Assets.xcassets` with at least an `AccentColor` (ink-gold `#9a7d44`) and a
   placeholder `AppIcon`. Wire `.tint(Ink.gold)` to the asset where sensible.
4. **Resolve every compile error** across all 11 files. The code was never compiled — expect
   real issues (enum exhaustiveness in `CoachEngine.color`, `@StateObject` init ordering in
   `ARCoachView.init`, `VNChirality` availability, `axis:` TextField API on iOS 16, optional
   handling). Fix them faithfully; do not delete features to silence errors.
5. **A test target** (even empty to start) so `xcodebuild test` is wired now.

**Verify Phase 0:** `xcodebuild -scheme AcuGuide -destination 'generic/platform=iOS' build`
succeeds; `xcodebuild test` runs. Report the exact commands and output.

## Phase 1 — Correctness on real hardware (highest-value behavior work)

These are device-reality bugs the Windows scaffold could not catch. Use the web logic as the
reference for *intent*, but the fixes here are native-camera-specific.

1. **Device-orientation → Vision orientation.** `CameraCoach.captureOutput` hardcodes
   `orientation: .up`. Compute the correct `CGImagePropertyOrientation` from the active
   capture-connection / interface orientation for the front camera so landmarks aren't rotated
   (note the API split: `videoRotationAngle` is iOS 17+, `videoOrientation` on iOS 16 — handle
   the 16+ deployment target). If you lock the app to portrait, still derive it rather than
   assuming `.up`.
2. **Front-camera mirror ↔ overlay alignment.** The preview is mirrored (`isVideoMirrored = true`)
   and `buildHand` flips `x` for the front cam. Confirm on-device that the ring and the white
   press-tip dot land on the *same* knuckles the user sees. Make the mirror a single source of
   truth (one `usingFront` / `mirrored` flag that drives both the preview connection and the
   landmark x-flip) so they cannot disagree. Add a tiny debug toggle to flip it at runtime for
   field calibration.
3. **Lock the two-hand roles (stop ring flicker).** `CoachEngine.update` recomputes
   receiver vs. presser by distance **every frame**, so the ring can jump between hands. Assign
   roles once when both hands are stable, add hysteresis / a short stickiness window, and only
   re-evaluate if the assignment is confidently wrong for several frames. Preserve the existing
   "receiver = hand whose target zone is nearest the other's press tip" heuristic as the initial
   choice.
4. **Smooth the target ring (One-Euro).** Port `src/utils/oneEuro.ts` to a small Swift
   `OneEuroFilter` (2-axis) and apply it to `weightedTarget(...)` **before** hit-testing and
   drawing, exactly as `usePressDetection.ts` does. This is the difference between a jittery ring
   and a stable one when the pressing finger occludes the knuckles. Keep raw landmarks for the
   press tip.
5. **State-machine robustness (port the missing guards from `engine.js`).** The Swift
   `CoachEngine` is a simplified per-frame switch and will flicker. Bring it in line with the
   validated machine: enter-radius vs. larger exit-radius **hysteresis**, `ENTER_DROPOUT_DEBOUNCE`,
   `PAUSE_GRACE` (timer pauses, not resets, on a brief leave), and `MIN_HOLD_CONFIRM` before the
   hold timer advances. Use the same constant values as `engine.js` `CONST` and
   `useCoachingState.ts` (`GRACE_MS=1500`, `MIN_STABLE_MS=500`, `DEBOUNCE_MS=300`,
   `STABILITY_STD_THRESHOLD=0.06 × handSize`, `HOLD_TARGET_S=30`). Keep `phase`/cue names mapped
   to the existing `CoachPhase`.
6. **Face-gate calibration hook.** `HandModel.isDorsal` uses the calibrated rule
   `dorsal ⇔ signed > 0`. Keep it, but expose the comparison behind one constant / debug toggle
   so WRONG_FACE can be inverted on-device in one place if it fires backwards (per the port
   README note), rather than hunting through logic.

**Verify Phase 1:** on a real iPhone, run TE3 end-to-end. The ring sits on the correct knuckles
in portrait and landscape, doesn't jump between hands, stays steady under occlusion, and the
state transitions NO_HAND → WRONG_FACE → SEARCHING → ON_TARGET_UNSTABLE → HOLDING → (PAUSED) →
COMPLETE behave without rapid flicker. Capture a screen recording or describe the observed
behavior per state.

## Phase 2 — Real models + body→hand navigation (make it look and flow like the web app)

This is the part the user explicitly called out from the running build. The body-atlas main page
is wrong in several ways: it is **dark** (the web shanshui theme is **light**), the body is a
**shiny capsule** that **fills the screen**, and the **meridians and region labels are missing**.
Fix the whole page so it reads like the web `MeridianAtlas` + `Body3D`. **The user is the source
of truth here — implement their notes exactly.** Reference: real Chinese **shanshui (山水, ink
mountain-water) painting** — light parchment ground, soft sage ink washes, lots of empty space.

1. **Port the shanshui background (match the html — it is LIGHT, not dark).** The port forces
   `.preferredColorScheme(.dark)` with a dark `Ink.parch` ground; the web app's `body` is a warm
   parchment **radial gradient** `radial-gradient(120% 90% at 50% 0%, #f6f4ed 0%, #ece9e0 55%,
   #e1dfd4 100%)` with dark ink text (`#33372f`). On the atlas page, drop the dark scheme and build
   the layered `.ink-bg` behind the 3D body (all `pointer-events: none`, purely decorative):
   - **moon** — pale disk, `radial-gradient(circle at 42% 40%, #d8d2c2, #c3bda9 58%, transparent
     72%)`, opacity ~0.18, blur ~2pt, near top-trailing (~7% top, ~16% right), ~130pt.
   - **shanshui mountains** — three layered ridgelines from `MeridianAtlas.jsx` (the
     `viewBox="0 0 1440 700"` bezier `d` paths, `mtn-far/mid/near`) as SwiftUI `Path`s anchored to
     the bottom ~60% of the page, fills `rgba(96,110,98,0.10)`, `rgba(78,92,80,0.13)`,
     `rgba(60,74,62,0.17)`.
   - **mist** — two soft radial gradients: `radial-gradient(130% 80% at 50% 24%,
     rgba(150,165,150,0.20), transparent 58%)` and `radial-gradient(80% 55% at 50% 100%,
     rgba(120,130,112,0.18), transparent 62%)`.
   **Every page uses this one light shanshui theme** — atlas, hand map, Coach launcher, AR safety
   gate + recap, and Coach AI chat — via a single shared `ShanshuiBackground` view (Appendix B).
   **Remove `.preferredColorScheme(.dark)` globally** (in `AcuGuideApp`) and retire `Ink.parch` as a
   page background; there is no dark page anymore. (During live camera the feed fills the screen, so
   the backdrop only shows on the gate/recap; keep the feedback card a light parchment `.panel()`.)
2. **Wire in the real 3D body model via GLTFKit2, matte + slightly translucent, small & centered.**
   Load `model.glb` at runtime (no usdz): add the **GLTFKit2** SPM package
   (`https://github.com/warrenm/GLTFKit2`) to `project.yml`, copy `MaiApp/model.glb` into bundle
   resources under `underdevelopment/MaiApp-iOS/`, and load it in `SceneKitBody` (follow GLTFKit2's
   README for the load call). Keep the capsule as **fallback only** (try/catch). Then match the
   user's notes:
   - **Not shiny, slightly transparent.** Override every material to PBR matching `Body3D.jsx`:
     diffuse/`baseColor` sage `#aebd9d`, **roughness 0.85**, **metalness 0.0**, low emission
     `#2c3626` (~0.12), and **`transparency ≈ 0.85`** (a little see-through). Use soft, even
     lighting (ambient + hemisphere, like the web's `ambientLight 0.9` + `hemisphereLight`); avoid a
     hard directional light / strong specular that makes it glossy. Turn off `autoenablesDefaultLighting`
     if that is what is blowing out the highlights.
   - **Occupies ~1/5 of the page, centered, zoomable.** Set the default camera distance so the
     figure is a **small ink figure centered with generous empty space** (≈ a fifth of the view, not
     filling it). Enable **pinch zoom in/out** (`allowsCameraControl = true`) with sane min/max so
     the user can zoom to a body part. Gentle auto-rotate that **yields to** drag.
3. **Draw the meridians on the body (currently missing).** Port the channel lines from `Body3D.jsx`
   (`Channels` / `ChannelLine`): thin glowing tubes colored by `MERIDIAN_COLORS`, running along the
   limbs/torso — arm = lung/li, leg = stomach/gb, torso = ren/du. If GLTFKit2 exposes the model's
   skeleton, follow the web's approach (limb chains from bones → smoothed Catmull-Rom → tube
   geometry). If the rig isn't reachable, a **hand-placed polyline approximation** per limb (same
   meridian colors, soft opacity) anchored to the model is an acceptable first version. This is the
   most involved item — keep the channels subtle (sage ink, low opacity) so they sit *on* the body.
4. **Interactive region labels that zoom to the part and reveal its xueweis (穴位).** Port
   `RegionLabel` + `HandHotspot` from `Body3D.jsx` as **ink brush-style labels** (`brush-label`:
   serif/Ma-Shan-Zheng feel, color `#3a4234`/`#4a5340`, soft) anchored over each region —
   头/Head, 胸/Chest, 腹/Abdomen, 臂/Arm, 腿/Leg, 足/Foot, and 手部/Hand. Project each 3D anchor to
   screen, or attach billboarded SCN label nodes. Make them **tappable**:
   - **Tapping a label zooms the camera in to that body part** and **shows that region's acupoint
     (xuewei) markers** on the body (display-only dots, colored by meridian; a back/"全身" control
     returns to the full figure).
   - **Hand** is the special drill-down: tapping 手部 opens the **2D hand acupoint map** (the
     `HandView` port) with a back button — mirrors the web `onEnterHand` / `onBack`. Keep the
     existing "Practice with camera" path from a selected TE3 point into the AR coach.
   - Use the acupoint data we have; regions without point data still zoom in and show the channel +
     label (don't invent points). **Exclude LI4** everywhere.
5. **Remove the separate Hand tab.** In `RootView`, drop the `Hand` tab so the TabView is
   **Atlas · Coach · Coach AI**; the hand is reached only via the 手部 label/hotspot on the body
   (item 4).
6. **Replace the square hand with the real hand silhouette.** In the hand map, `HandAtlasView`
   currently fills a `RoundedRectangle`. Port the real outline from `HandView.jsx`: `HAND_PTS` → a
   smooth **closed Catmull-Rom path** (`Shape`/`Path`) in the same `360 × 440` box, with the
   `handSkin` radial gradient and faint tendon/knuckle hint strokes.
7. **Full acupoint atlas (display-only).** Port the dataset from `MaiApp/src/data.js` into
   `Acupoints.swift` (+ meridian metadata) so the hand map shows the real set with bilingual labels
   and `MERIDIAN_COLORS`, not the 3 placeholders. **Only TE3 keeps a `mediapipeTarget`; all others
   stay AR-disabled.** The hand subset in `data.js` is **PC6, SJ5, PC8, HT7, SI3** (no TE3 — the
   iOS app added 中渚/TE3 as its AR point), so the atlas = **TE3 + those five**. Keep TE/SJ naming
   consistent: TE3 and SJ5/TE5 are the same Sanjiao/三焦 channel — pick one prefix and map both to
   `MERIDIAN_COLORS["sj"]`.

**Verify Phase 2:** on device, the atlas page is the **light shanshui theme** (parchment ground,
ink mountains, moon, mist) matching the html; the body is the **real model**, **matte and slightly
translucent** (not shiny), **small and centered (~1/5)** with working pinch-zoom; **meridians are
visible** on the limbs/torso; **region labels show and are tappable**, zooming to a part and
revealing its xueweis, with 手部 opening the hand map; there is **no Hand tab**; the hand is the
real silhouette. Capture a screen recording: full figure → tap a region label → zoom-in with
xueweis → tap 手部 → hand map → back.

## Phase 3 — Native features (after Phase 0–2 are solid)

1. **Voice cues — `AVSpeechSynthesizer`.** Speak the coaching cue on **phase change only**
   (debounced; never every frame), mirroring the web `useTTS.ts`. Bilingual: pick the utterance
   language from the device locale (zh-Hans / en) and keep copy within the non-negotiables.
   Add a mute toggle; respect the silent switch / `AVAudioSession` category appropriately.
2. **Haptics — `CoreHaptics` (with `UIFeedbackGenerator` fallback).** A light tick when the
   finger first enters the target, a success pattern at COMPLETE. No haptics in WRONG_FACE spam.
3. **Real chatbot, securely.** `ChatView.swift` hardcodes an OpenAI endpoint and an in-source
   `apiKey = ""`. Replace with: key read from `Info.plist`/xcconfig/Keychain (never committed;
   add to `.gitignore`), graceful offline canned reply when absent, streamed responses if
   feasible, and proper error states. Keep the bilingual, wellness-only **system prompt** intact
   (it already forbids diagnosis — keep it that way).

**Verify Phase 3:** each feature works on-device; muting/locale/haptic toggles behave; the app
still builds clean and tests pass; no API key is committed (`git grep` for the key returns
nothing).

## Phase 4 — Optional hardening (stretch, only if time remains)

- Port the JSON **fixtures** (`claude-deliverables/fixtures/*.json`) into Swift unit tests that
  drive `CoachEngine` frame-by-frame and assert the phase timeline / hold time, mirroring
  `underdevelopment/demo-app/cv/engine.test.js`. This locks the validated behavior against
  regressions.
- Accessibility pass: Dynamic Type on cards, VoiceOver labels on the coaching overlay and the
  recap buttons, sufficient contrast on the parchment panels.

---

## Constraints & working style

- **Touch only `underdevelopment/MaiApp-iOS/`** plus, if you must, adding read-only references.
  Do not modify the live React apps (`src/`, `MaiApp/`).
- Make **small, reviewable commits per numbered item** with clear messages; update
  `underdevelopment/MaiApp-iOS/README.md` as setup steps change (e.g., the project is now
  generated, not hand-assembled).
- After each phase, **stop and report**: what changed, the exact build/test command + result,
  and anything that needs a real device to confirm.
- If a fix would require violating a non-negotiable, **stop and ask** instead.
- Prefer faithfully porting the validated web behavior over inventing new logic. When the web
  references disagree, `engine.js` wins for the state machine; `usePressDetection.ts` wins for
  smoothing/geometry.

---

## Appendix A — Shanshui theme tokens for `Theme.swift` (paste-ready)

The dark page background is the main reason the app "doesn't match the html." Add these named
tokens to `Theme.swift` (matched 1:1 to `MaiApp/styles.css`) and **use `Ink.ground` for every
page background instead of the dark `Ink.parch`**. `Ink.parch` is retired as a page background
(every page is light now); on the light ground use `Ink.text` (`#33372f`) for foreground.
`EllipticalGradient` (iOS 15+) matches the web's `radial-gradient(120% 90% at 50% 0%, …)` and
scales to the view, so `Ink.ground` works both as `.background(Ink.ground)` and
`Ink.ground.ignoresSafeArea()`.

```swift
extension Ink {
    // ---- Shanshui (山水) light theme — MaiApp styles.css ----

    // Page ground: parchment radial gradient (styles.css `body`)
    static let groundTop  = Color(hex: "#f6f4ed")   // 0%
    static let groundMid  = Color(hex: "#ece9e0")   // 55%  (== Ink.paper / --ink)
    static let groundEdge = Color(hex: "#e1dfd4")   // 100%
    static var ground: EllipticalGradient {         // ≈ radial 120% 90% at 50% 0%
        EllipticalGradient(
            stops: [
                .init(color: groundTop,  location: 0.00),
                .init(color: groundMid,  location: 0.55),
                .init(color: groundEdge, location: 1.00),
            ],
            center: .top,                 // "at 50% 0%"
            startRadiusFraction: 0.0,
            endRadiusFraction: 1.0)       // tune ~0.95–1.1 to taste
    }

    // Moon (.ink-bg .moon): radial #d8d2c2 → #c3bda9 58% → clear 72%, opacity ~0.18, blur ~2pt
    static let moonCore = Color(hex: "#d8d2c2")
    static let moonEdge = Color(hex: "#c3bda9")

    // Shanshui ink mountains (.mtn-far/mid/near) — already include their alpha
    static let mtnFar  = Color(hex: "#606e62").opacity(0.10)   // rgba(96,110,98,.10)
    static let mtnMid  = Color(hex: "#4e5c50").opacity(0.13)   // rgba(78,92,80,.13)
    static let mtnNear = Color(hex: "#3c4a3e").opacity(0.17)   // rgba(60,74,62,.17)

    // Mist (.ink-bg .mist), two soft washes
    static let mist1 = Color(hex: "#96a596").opacity(0.20)     // rgba(150,165,150,.20)
    static let mist2 = Color(hex: "#788270").opacity(0.18)     // rgba(120,130,112,.18)

    // Ink brush region labels (.brush-label / .sm / .soft)
    static let brush     = Color(hex: "#3a4234")
    static let brushSoft = Color(hex: "#4a5340")

    // 3D body material (Body3D.jsx MeshStandardMaterial: sage diffuse + low emissive)
    static let bodySage     = Color(hex: "#aebd9d")
    static let bodyEmission = Color(hex: "#2c3626")
}
```

Then sweep **every** view to the shared backdrop (Appendix B) so the page background is `Ink.ground`
and text uses `Ink.text` — not the dark `Ink.parch` + `Ink.paper` pairing. Hex values above are
exact; verify each against `styles.css` if you tweak.

---

## Appendix B — One shared `ShanshuiBackground` for every page

The user wants **all pages** on the same light shanshui theme. Build it once as a reusable view and
put it behind every screen, matching the web app's fixed `.ink-bg` (which sits behind all views).
This keeps the theme identical everywhere and DRY.

```swift
// Decorative shanshui backdrop — place behind EVERY page.
// Mirrors styles.css `body` + `.ink-bg` (moon, mountains, mist).
struct ShanshuiBackground: View {
    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()                              // parchment ground

            GeometryReader { geo in                                   // moon, top-trailing
                Circle()
                    .fill(RadialGradient(
                        stops: [
                            .init(color: Ink.moonCore,            location: 0.00),
                            .init(color: Ink.moonEdge,            location: 0.58),
                            .init(color: Ink.moonEdge.opacity(0), location: 0.72),
                        ],
                        center: UnitPoint(x: 0.42, y: 0.40), startRadius: 0, endRadius: 65))
                    .frame(width: 130, height: 130)
                    .blur(radius: 2).opacity(0.18)
                    .position(x: geo.size.width * 0.84, y: geo.size.height * 0.10)
            }
            .ignoresSafeArea()

            GeometryReader { geo in                                   // mountains, bottom 60%
                let bandH = geo.size.height * 0.60
                ZStack(alignment: .bottom) {
                    MountainsShape(ridge: .far ).fill(Ink.mtnFar ).frame(height: bandH)
                    MountainsShape(ridge: .mid ).fill(Ink.mtnMid ).frame(height: bandH)
                    MountainsShape(ridge: .near).fill(Ink.mtnNear).frame(height: bandH)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .ignoresSafeArea()

            EllipticalGradient(                                       // mist wash, upper
                stops: [.init(color: Ink.mist1, location: 0), .init(color: Ink.mist1.opacity(0), location: 0.58)],
                center: UnitPoint(x: 0.5, y: 0.24)).ignoresSafeArea()
            EllipticalGradient(                                       // mist wash, lower
                stops: [.init(color: Ink.mist2, location: 0), .init(color: Ink.mist2.opacity(0), location: 0.62)],
                center: UnitPoint(x: 0.5, y: 1.0)).ignoresSafeArea()
        }
        .allowsHitTesting(false)                                      // purely decorative
    }
}

// Three ink ridgelines, ported verbatim from MeridianAtlas.jsx (viewBox 0 0 1440 700).
struct MountainsShape: Shape {
    enum Ridge { case far, mid, near }
    let ridge: Ridge
    func path(in rect: CGRect) -> Path {
        let vbW: CGFloat = 1440, vbH: CGFloat = 700
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / vbW * rect.width, y: y / vbH * rect.height) }
        var p = Path()
        switch ridge {
        case .far:
            p.move(to: P(0, 430))
            p.addCurve(to: P(470, 356),  control1: P(160, 372),  control2: P(320, 398))
            p.addCurve(to: P(1000, 300), control1: P(640, 308),  control2: P(800, 236))
            p.addCurve(to: P(1440, 360), control1: P(1160, 350), control2: P(1300, 330))
        case .mid:
            p.move(to: P(0, 520))
            p.addCurve(to: P(540, 470),  control1: P(200, 478),  control2: P(360, 500))
            p.addCurve(to: P(1110, 452), control1: P(740, 436),  control2: P(900, 402))
            p.addCurve(to: P(1440, 498), control1: P(1270, 490), control2: P(1370, 476))
        case .near:
            p.move(to: P(0, 612))
            p.addCurve(to: P(650, 586),  control1: P(240, 588),  control2: P(430, 602))
            p.addCurve(to: P(1250, 582), control1: P(870, 570),  control2: P(1030, 560))
            p.addCurve(to: P(1440, 592), control1: P(1350, 592), control2: P(1410, 588))
        }
        p.addLine(to: P(1440, 700)); p.addLine(to: P(0, 700)); p.closeSubpath()
        return p
    }
}
```

**Apply it to every page** — replace each page's `Ink.parch.ignoresSafeArea()` / `Ink.paper`
background with `ShanshuiBackground()` as the bottom layer of the `ZStack`, and switch foreground
text from `Ink.paper` to `Ink.text`:

- `AcuGuideApp.swift` — remove `.preferredColorScheme(.dark)`.
- `Body3DView.swift` — `ShanshuiBackground()` behind the SceneKit view (which is already
  `backgroundColor = .clear`, so the backdrop shows through).
- `RootView.swift` `ARCoachLauncher` (Coach tab) — `ShanshuiBackground()` + `Ink.text` copy.
- `HandAtlasView.swift` — `ShanshuiBackground()` behind the hand map.
- `ARCoachView.swift` — `ShanshuiBackground()` behind the **SafetyGate** and the **recap**; the
  live `coachLayer` keeps the camera preview full-bleed with the light parchment feedback card.
- `ChatView.swift` — `ShanshuiBackground()` behind the message list; keep the jade user bubbles and
  parchment coach bubbles (both already read on the light ground).

**Verify (theme):** every screen — atlas, hand, Coach launcher, safety gate, recap, chat — shows
the same parchment-and-ink-mountains backdrop with dark ink text; no screen is dark; `git grep
'preferredColorScheme'` and `git grep 'Ink.parch'` return nothing used as a page background.

Start with Phase 0. Before editing, give me the `CoachEngine` ↔ `engine.js` behavior diff and the
list of compile errors you expect to fix.
