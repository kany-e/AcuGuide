# AcuGuide — App Store release checklist

Everything needed to submit, split into **what's done in the repo** and **what only you can do in
App Store Connect / on the developer account**. Numbers here are verified against the code, not the
old docs — see the note at the bottom.

## Verified facts to put in the listing (do not use the old doc numbers)

| Thing | Verified value | Source |
|---|---|---|
| Sourced acupoints | **33** | `Acupoint.all` (includes the 3 hyphenated extra points EX-HN1/3/5 — a regex that only matched `[A-Za-z0-9]+` silently dropped them and produced a wrong count of 30) |
| Camera-coached points | **8** — TE3, PC6, SJ5, PC8, HT7, SI3, TE4, PC7 | non-nil `mediapipeTarget`, test-pinned |
| Meridian channels drawn | **10** | `Meridian.all` — see the ⚠️ below |
| Bundled routines | **6** | `Routine.all` |
| Voice clips | **102**, two languages | `AcuGuide/VoiceClips/` |
| App size | ~20 MB uncompressed (~12–16 MB after thinning) | measured Release build |

> ⚠️ **Meridian count.** The onboarding and atlas copy say "the fourteen meridians" (the classical
> framework: 12 primary + Ren + Du), but the 3D body actually *draws* **10** channels. Decide before
> the listing whether to say "the classical meridians" (safe) or a specific number. Don't market
> "14 meridians" if only 10 are drawn.

## Done in the repo (this branch)

- **Store copy** — `store/metadata/{en-US,zh-Hans}/` holds name, subtitle, keywords, description and
  promotional text as the single source of truth. `scripts/safety_scan.py` now scans these too, so
  the merge gate catches a treat/cure/heal/diagnose slip in the listing — the one user-facing surface
  the runtime test could never reach.
- **Privacy manifest** — `AcuGuide/PrivacyInfo.xcprivacy` ships (separate branch). Required for
  submission.
- **Privacy copy** — corrected to disclose the optional voice-confirm speech fallback (separate branch).
- **Bilingual declaration** — `CFBundleLocalizations: [en, zh-Hans]` so the store lists Chinese
  (separate branch).

## You must do these — they are account / Connect actions, not code

### 1. Privacy Policy URL (mandatory field)
The policy already exists at `docs/privacy-policy.md`, and this repo is **public**, so a working URL
exists today:

```
https://github.com/kany-e/AcuGuide/blob/main/docs/privacy-policy.md
```

Nicer option: enable **GitHub Pages** (Settings → Pages → deploy from `main` / `docs`) and link a
rendered `privacy.html`. Either satisfies the field.

### 2. Support URL (mandatory field)
Connect requires a reachable support page or email. Provide one of:
- a `mailto:` you monitor, or
- a one-page `docs/support.html` (GitHub Pages) with a contact address and a short FAQ — the app's own
  `ChatService.faqs` is ready-made source material.

### 3. App Review notes — paste into *App Review Information → Notes* before submitting
> AcuGuide is a wellness self-care app. It makes no medical claims and performs no medical
> assessment. A non-skippable safety screen appears before the camera every session (Practice → any
> point → "Before you begin"). Reporting a session as "uncomfortable" shows stop-and-rest guidance and
> removes any continue option. Pregnancy-cautioned points, including LI4 (Hegu), are excluded from the
> app entirely. Point locations follow the WHO Standard Acupuncture Point Locations (2008); the in-app
> Sources & Evidence screen (Settings → Sources) states plainly which claims are established and which
> are traditional. The camera, the AI coach, and all history run on device; the only optional network
> use is Apple's speech service as a fallback for the hands-free voice confirm, disclosed in the
> privacy policy and the microphone/speech permission prompts.

### 4. Privacy nutrition label (Connect questionnaire)
Answer **"Data Not Collected"** for every category. The app has no network calls to any AcuGuide
service, no analytics, no accounts (verified: no `URLSession`/`URLRequest` in the sources). The one
required-reason API, UserDefaults (reason CA92.1), is declared in `PrivacyInfo.xcprivacy`.

### 5. Screenshots — capture these five, in this order, at 6.9" and 6.5"
1. **Camera coach mid-press** — live hand, gold guide ring on the point, white dot on the fingertip,
   green phase, hold ring counting down. *The one thing no competitor has.* Needs a real device
   (Vision hand-pose doesn't run in the Simulator).
2. **3D body atlas** — meridians drawn, gold acupoint dots, ink-and-gold theme.
3. **A point detail card** — location, "how to find it", caution, traditional-use text.
4. **Sources & Evidence** — the honesty screen; a genuine differentiator.
5. **Session recap** — the calm "nicely held / good session" close.

### 6. The ASO tension to remember
The highest-volume search terms in this category are symptom-and-relief words the safety rule forbids.
The listing wins on **specificity** ("finger on the point", "camera check", "cited sources"), not on
claim words. Store copy is also the one surface `safety_scan.py` guards but a human still edits in
Connect — re-check it against the banned list before every submission.

## Business model (from the pre-release critique)
Ship **free** with a single **$4.99 non-consumable** unlock (custom routines 1→20, multiple/per-routine
reminders, saved-spot calibration across all points). Not a subscription — no servers, no accounts, no
recurring cost to justify one. Never paywall the safety gate, stop guidance, point cautions, Sources,
or Credits (Credits is also a legal CC-BY obligation). Not built yet — see `docs/prerelease-vision.md`.
