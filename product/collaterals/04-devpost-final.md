# Devpost Final Copy

## Project Title

AcuGuide Hand Coach

## Tagline

AI camera coach for safe, guided hand acupressure routines.

## Inspiration

People can find acupressure advice everywhere online, but static instructions leave a practical gap: users still do not know whether they are pressing the right place, holding long enough, or staying within safe self-care boundaries.

We wanted to build the missing execution layer between wellness knowledge and real user action.

## What It Does

AcuGuide lets users choose a common self-care context such as tension headache, period discomfort, or neck and shoulder tension. The app shows a short safety boundary, presents a curated hand acupressure routine, and opens a camera-guided flow.

During the routine, AcuGuide checks whether the hand is visible, overlays an approximate target region, gives real-time feedback, starts a timer when the user is aligned, and ends with a non-diagnostic completion recap.

## How We Built It

We structured AcuGuide around three layers:

1. **Curated routine library**: fixed routine content acts as the source of truth, so the model does not invent medical guidance.
2. **Camera feedback layer**: hand visibility, approximate target alignment, hold stability, and duration drive the live coaching experience.
3. **AI coaching layer**: AI helps turn routine content into friendly, step-by-step guidance and supports safety responses.

The product is intentionally hand-only for the hackathon so the experience is focused, visible, and demoable.

## What Makes It Different

Most health AI demos are chatbots. AcuGuide is not trying to diagnose the user. It focuses on execution: can the user follow a safe self-care routine correctly?

Articles and videos tell users what to do. Chatbots can explain instructions. AcuGuide adds real-time action feedback.

## Safety

AcuGuide is wellness self-care guidance only. It does not diagnose, treat, prescribe, or replace medical care. The app tells users to stop if they feel sharp pain, numbness, dizziness, unusual symptoms, or worsening discomfort. The routine content is curated, and the AI layer is constrained so it does not freely invent health advice.

## Challenges

The biggest product challenge was scope control. A full TCM diagnosis app, full-body AR model, or symptom diagnosis tool would be too broad and risky for a hackathon. We narrowed the experience to hand-only guidance and focused on a single high-quality demo loop.

The biggest engineering challenge was making the visual feedback stable and understandable enough for a live demo. We designed fallback states so the story still works if camera tracking or network calls fail.

## Accomplishments

- Built a focused wellness product instead of a broad medical chatbot.
- Designed a hand-only demo flow with real-time execution feedback.
- Created a safety-first content strategy around curated routines.
- Separated routine data, visual feedback, and AI coaching language.
- Prepared a demo path that works even when live AI is unavailable.

## What We Learned

The strongest AI product idea was not generating more advice. It was helping users execute advice safely. By combining constrained AI with camera feedback, AcuGuide moves from advice generation to action guidance.

## What's Next

Next steps include expert review of routine content, better hand-region calibration, voice-guided coaching, more self-care routines, and longitudinal completion tracking. Any expansion into stronger health claims would require clinical review and stricter validation.

## Built With

Replace with final stack:

- React / Next.js
- MediaPipe / hand tracking
- LLM API for coaching language
- Curated routine JSON

## Devpost Submission Checklist

- [ ] Replace "Built With" with actual stack.
- [ ] Add GitHub URL.
- [ ] Add demo URL.
- [ ] Add screenshots.
- [ ] Add video.
- [ ] Confirm no treatment or diagnosis claims.

