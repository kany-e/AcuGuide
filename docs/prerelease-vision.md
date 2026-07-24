# AcuGuide — pre-release critique and vision

A six-lens critique of the app as it stands (UX, engineering efficiency, business model,
differentiation, marketing/ASO, release blockers), every recommendation adversarially verified
against the code. **38 recommendations were checked; 6 were refuted as wrong or generic and 2 turned
out to already exist. 32 survived.** Only those are recorded here.

Method note: this was read from the source, not imagined. Where a claim is load-bearing it carries a
`file:line`. Two things were measured rather than estimated — the built app size, and the number of
camera-coached points — and both corrected an assumption the project's own docs had baked in.

---

## 0. Corrections to what the repo believes about itself

**The app coaches 8 points with the camera, not 1.** `README.md` and `CLAUDE.md` both say TE3 is the
only AR-coached point. In the code, eight points carry a non-nil `mediapipeTarget` — TE3, PC6, SJ5,
PC8, HT7, SI3, TE4, PC7 (`Acupoints.swift:61` calls this out as "non-nil for the 8 coached points
(test-pinned)"). TE3 is only the *default demo* point (`RootView.swift:88`). The docs undersell the
single most differentiating feature by 8×, and the pitch inherits that error.

**The binary is not a size risk.** A Release build for `generic/platform=iOS` produces a 20 MB
uncompressed `.app` — MaShanZheng 5.6 MB, VoiceClips 4.8 MB, binary 4.7 MB, GLTFKit2 2.5 MB, three
GLBs 0.79 MB. After thinning that lands ~12–16 MB. The 102 pre-rendered clips are 4.8 MB and are the
right trade: studio-quality speech for a rounding error in download size.

---

## 1. What is genuinely strong — protect this

- **Per-user spot calibration is the moat.** `PointCalibration.swift` stores the delta between where
  the app computed a point and where *you* found it by feel, in a canonical hand frame (origin
  middleMCP, scale |middleMCP−wrist|, rotation wrist→middleMCP, chirality folded), so one capture
  re-applies at any hand pose, distance or side — clamped to 0.30 hand-size so a stray capture can
  never drag the ring onto different anatomy. **Nothing else in this category can personalise.**
- **Honest measurement with honest labels.** The engine reports position, jitter and hold — and
  deliberately *dropped* cadence because testing found no reliably measurable rhythm. An app that
  refuses to display a number it can't stand behind is rare.
- **The honesty infrastructure is executable, not aspirational.** `SourcesView.swift:150` tells the
  user outright that whether pressing these points is effective "is still scientifically contested".
  `SafetyInvariantTests` exists solely to make the four safety rules un-deletable — including a
  reflection test pinning that `SafetyGate` exposes exactly one stored property, so adding a
  `canSkip` flag fails the build.
- **The camera-denied path never dead-ends.** `CameraGate` offers the guided timer on both the
  not-determined and denied screens, and `PracticeSessionView` is a single dispatch point that
  carries the safety acknowledgement across the fallback — so a camera-denied user can never hit an
  unpassable routine step.
- **The coach's concurrency discipline is careful, not accidental.** `CameraCoach` keeps an explicit
  main-thread/capture-queue split with named copies of every shared flag and a scene-generation
  counter that drops frames captured under stale coordinate parity during a camera flip.
  `ShadowLocalizer` bounds itself to one in-flight inference with a non-blocking gate, so a slow
  CoreML call can never back up the capture path.

---

## 2. Release blockers — must fix before submission

| # | Issue | Why it blocks |
|---|---|---|
| B1 | **No `PrivacyInfo.xcprivacy`** | Apple requires a privacy manifest; `UserDefaults` is a required-reason API. Rejected before review starts. |
| B2 | **Privacy claims are inaccurate** | Voice confirm falls back to Apple's *servers* when the on-device model is absent (added deliberately in R14.18), yet several surfaces still say nothing leaves the device. |
| B3 | **Chat has no crisis routing** | Anxiety phrasing combined with self-harm language currently returns "press these points". This is the single most serious finding in the whole review. |
| B4 | **Safety gate unreachable at large text** | At accessibility text sizes the "I understand" button falls off-screen with no scroll — a *forced* gate becomes an *unpassable* one. |
| B5 | **No hosted privacy-policy or support URL** | Both are mandatory App Store Connect fields. `docs/privacy-policy.md` exists in the repo but is not hosted or linked in-app. |
| B6 | **App declares English only** | `knownRegions = (Base, en)`. The bilingual story — a genuine differentiator — is invisible on the store page and to Chinese-language search. |

---

## 3. UX — the gaps that cost users

- **Point-specific cautions never appear where the press happens.** `TimerSessionView` shows only
  `acupoint.location`. The bundled "Evening grounding" routine takes a user straight into pressing
  LR3 without ever showing LR3's own caution — *"Don't press hard on the pulsing artery in the
  groove."* The string exists and already passes the forbidden-term scan; it is simply not rendered.
- **25 of 33 points had no plain-language "how to find it"** (now fixed — all 33 have one). `findGuide` covers exactly the 8
  camera-coached points — i.e. precisely the ones that already *show* you. The 22 that need
  self-location get the clinical WHO string instead: *"4 cun above the navel"*. "cun" appears in 13
  user-facing strings and **is never defined anywhere in the app**.
- **The coached flow needs two free hands and never says so.** Nothing in onboarding, the safety
  gate or the spoken cues tells the user to prop the phone. A first-timer holding the phone in one
  hand can present exactly one hand and will sit in `.noHand` indefinitely, hearing only "Bring your
  hand into view."
- **The screen sleeps mid-session.** iOS locks the phone during a paced round; `isIdleTimerDisabled`
  is never set.
- **"Uncomfortable" truncates in English** on the recap — and it is the button that triggers the
  non-negotiable stop guidance. Chinese labels are short, so this is English-only and easy to miss.

---

## 4. Business model

**Recommendation: free app, one $4.99 non-consumable unlock. Not a subscription.**

A subscription is a promise of continuing service, and this architecture has no servers, no accounts
and no recurring cost — there is nothing to fund and nothing that would justify recurring payment to
a sceptical reviewer. A one-time unlock matches what the app actually is.

**Free forever** — the 3D atlas and all 33 points with locations, cautions and traditional-use text;
Sources, Credits and Privacy; the forced safety gate and the "uncomfortable → stop" branch; the
camera coach for all 8 coached points; timer practice for every point; the 6 bundled routines; one
custom routine; one daily reminder; the whole deterministic chat including red-flag screening;
voice read-aloud; unlimited local history plus export.

**Paid ("AcuGuide Complete")** — custom routines 1 → 20; multiple and per-routine reminders; saved-spot
calibration across all points.

**Never paywalled, on ethical grounds:** the safety gate, stop guidance, point cautions, Sources and
Credits. Credits is additionally a *legal* obligation (CC-BY attribution).

Two consequences the codebase must absorb: paywall copy would be the only user-facing text that
escapes the forbidden-claim test, and three absolute privacy claims stop being true the moment
StoreKit ships (the App Store receives a transaction). Both must be amended in the same PR.

---

## 5. Differentiation and pitch

> **"AcuGuide watches your hand and tells you whether your finger is actually on the point — then
> remembers where that point is on your hand."**

Everything else — bilingual, cited, private, beautiful — is proof of seriousness, not the pitch.

**The demo moment is the locate step, not the coaching.** A dashed gold ring labelled "≈ about here"
floats on your live hand; you press around by feel; the app labels *your* press; you say "this is my
spot" out loud because both hands are busy; the ring moves — and it is still there next session.
That sequence is the thing no video, chart or generic wellness app can do.

**Where it is weak:** against a YouTube video it demands setup (two free hands, propped phone) for a
benefit that isn't obvious until the calibration lands. That is exactly why the first-run experience
above matters more than any new feature.

---

## 6. Marketing / ASO

The safety rule creates a **real ASO tension worth naming**: the highest-volume search terms in this
category are symptom-and-relief words the app may not use. The listing has to win on *specificity*
("finger on the point", "camera check", "cited sources") rather than on claim words. Store metadata
is also the one user-facing surface `scripts/safety_scan.py` cannot reach — it needs a manual check
before every submission.

Screenshot order should follow the demo moment: (1) the ring on a live hand, (2) the calibration
save, (3) the 3D atlas, (4) the Sources screen, (5) the recap.

Write the App Review notes now — a short explanation of what the app does and does not claim is the
cheapest insurance against a 1.4.1 or 2.1 rejection.

---

## 7. Efficiency

- **The meridian build runs on the main thread** and blocks the first screen — 18 channels, each
  raycast-projected onto the body mesh.
- **The atlas surface-snap uses `hitTestWithSegment`**, the one SceneKit API this codebase's own
  history documents as returning zero hits before first render.
- **No capture-interruption or thermal-pressure recovery.** A phone call mid-session has no path back.
- **A failed camera input install is a permanent black screen** with no surfaced error.

---

## 8. Sequencing

1. **Blockers first** (B1–B6). Nothing else matters if the app is rejected — and B3, crisis routing,
   is a duty of care regardless of release.
2. **First-run truthfulness**: cautions at the point of press, prop-the-phone guidance, keep the
   screen awake, fix the truncated safety button.
3. **The 22 missing find-guides** — the largest single content debt, and what makes the non-coached
   two-thirds of the atlas genuinely usable.
4. **Monetisation** last, once the free experience is worth paying to extend.

Every item lands on its own branch and merges only through `merge-gate`.
