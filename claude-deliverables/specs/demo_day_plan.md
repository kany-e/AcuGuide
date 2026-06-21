# AcuGuide — 7-Hour Demo-Day Plan

THE RULE: **no new code after hour 6.** The last hour is rehearsal + show-stopper-only fixes.
A demo that works 100% of the time beats a fancier one that works 80%. Converge, don't widen.
Scope is locked: hero = headache → **TE3**, feedback = **position + hold-time + steadiness**
(no cadence, no PC6, no LLM endpoints).

## Schedule
| Time | Task | Done = |
|---|---|---|
| 0:00–2:30 | **TE3 core loop** — run claude_code_ar_integration_TE3_prompt.md; get ring-on-TE3 → green-on-hold → timer-complete working **on the actual demo phone** (iPhone Safari). | One full hold completes end-to-end on the demo device. |
| 2:30–3:30 | **Wire the full flow + recap honesty** — Home→Safety→Routine→Camera→Recap; confirm completing the hold **navigates to Recap and passes stats**; Recap shows position-stability + hold-time (real), safety reminder. Fix WRONG_FACE gate only if quick. | Click-through works 5× in a row, no dead ends. |
| 3:30–4:30 | **Fallback (de-risk)** — add a recorded-replay mode (see prompt below) AND screen-record one perfect live run as a backup video. | Demo can run with the camera unplugged. |
| 4:30–5:30 | **High-ROI polish** — TTS voice coaching (Web Speech API: speak the coach_copy on state change) + make the other 2 entries clickable into the same UI. | It *sounds* like a coach; 3 entries all open. |
| 5:30–6:00 | **Pitch + rehearse** — finalize the 30-sec script + Devpost; run the demo on the real device 3×. | Script memorized; run is smooth. |
| 6:00–7:00 | **FREEZE. Rehearse only.** 5+ dry runs, fix only crashes. Keep the backup video ready. | Confidence. |

If 0:00–2:30 slips, **cut the polish row (4:30–5:30), not the fallback.** The fallback is what saves the demo.

## 30-second demo script (spoken)
> "This is AcuGuide. The internet has a thousand vague acupressure tips, but none of them can tell
> if you're actually doing it right. AcuGuide can. I've got a tension headache — I pick that. First,
> a safety check: this is wellness self-care, not a medical tool, and it tells me to stop on red-flag
> symptoms. Now the coach finds the point on the back of my hand — [ring appears and tracks my hand] —
> I press and hold — [ring turns green, the timer fills] — and it confirms I held the right spot,
> steadily, for the full thirty seconds. Then a recap of how I did, and how I feel — and if I felt
> worse, it tells me to stop, not to push on. It's not an AI doctor. It's the layer that makes safe
> self-care something you can actually *do*."

Hit three beats judges remember: **"confirms you did it right," the visible safety gate, "execution layer not AI doctor."**

## Likely judge questions (prep)
- *"How accurate is the point location?"* → "We don't claim clinical precision — we locate a target
  region from hand landmarks and confirm you're on it and holding steady. It's a self-care execution
  aid, not diagnosis." (Honest + on-message.)
- *"What's the AI?"* → "Computer vision tracks the hand and the press in real time; the coaching layer
  turns a static point into guided, corrected practice with a safety boundary."
- *"Does it work for everyone/any lighting?"* → "It's tuned for a clear, framed hand; when it can't
  see well it coaches you to fix the framing rather than guessing — and it never fakes feedback."

## Recorded-fallback Claude Code prompt (paste)
```
Add a DEMO FALLBACK / replay mode to the React app so the camera loop can be shown without a live
camera. Surgical; follow /CLAUDE.md (no StrictMode, don't await video.play()). 

- Add a hidden toggle (e.g. ?demo=1 query param or a long-press on the camera page) that, instead of
  getUserMedia, plays a bundled recorded clip of a good TE3 run as the video source and feeds its
  frames through the SAME MediaPipe + feedback pipeline (so the overlay, green-on-hold, and timer all
  run exactly as live — it's real detection on a recorded video, not a fake animation).
- Bundle one short mp4 of a clean TE3 hold in public/. Loop is fine.
- Must reach COMPLETE → Recap like a live run.
- Do not change the live path; this is an additional source only. Verify both live and ?demo=1 work,
  tsc/build clean.
Deliver: the toggle + bundled clip + a one-line note on how to trigger it.
```
> Also independently screen-record one perfect live run (phone screen capture) as a non-code backup —
> if everything fails, you play the video and narrate. Belt and suspenders.

## Explicitly NOT doing (locked)
Cadence/rhythm · PC6 forearm · LLM coaching/recap endpoints · the 2nd/3rd routines' full feedback
(they just need to open). Saying no to these is what makes 7 hours enough.
