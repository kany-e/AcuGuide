# Devpost Draft

## Project Title

AcuGuide Hand Coach

## Tagline

AI camera coach for safe, guided hand acupressure routines.

## Inspiration

People can find acupressure advice everywhere online, but static instructions leave a practical gap: users still do not know whether they are pressing the right place, holding long enough, or staying within safe self-care boundaries. We wanted to build the missing execution layer between wellness knowledge and real user action.

## What It Does

AcuGuide lets users choose a common discomfort such as tension headache, period discomfort, or neck and shoulder tension. The app shows a short safety boundary, presents a curated hand acupressure routine, and opens a camera-guided flow. It detects whether the hand is visible, overlays an approximate target region, gives real-time feedback, starts a guided timer when the user is aligned, and ends with a non-diagnostic completion recap.

## What Makes It Different

Most health AI demos are chatbots. AcuGuide is not trying to diagnose the user. It focuses on execution: can the user follow a safe self-care routine correctly? The combination of curated routine content, camera-based feedback, and AI coaching language makes it more useful than a static article and safer than an open-ended medical chatbot.

## How We Built It

The product is structured around a small routine library, a camera feedback layer, and an AI coaching layer. The routine library acts as the source of truth so the model does not invent medical advice. The camera layer estimates hand visibility and target alignment. The AI layer is used for friendly coaching language and safety responses rather than diagnosis.

## Challenges

The hardest product challenge was scope control. A full TCM diagnosis app or AR body model would be too large and risky for a hackathon. We narrowed the product to hand-only guidance and designed clear safety boundaries. The hardest engineering challenge was making visual feedback stable enough for a live demo while keeping the experience understandable.

## Accomplishments

- Built a focused wellness product instead of a broad medical chatbot.
- Created a hand-only demo flow that can show real-time execution feedback.
- Designed safety guardrails around red flags and non-diagnostic language.
- Structured the app so routine content is curated rather than hallucinated.

## What We Learned

We learned that the strongest AI product idea was not “generate more advice.” It was helping users execute advice safely. Combining vision feedback with a constrained AI coach creates a clearer product than a generic health assistant.

## What's Next

Next steps would include expert review of the routine library, better hand-region calibration, voice-guided coaching, more personalization, and longitudinal routine tracking. Any expansion into stronger health claims would require clinical review and much stricter validation.

## Devpost Checklist

- [ ] Project title final.
- [ ] Tagline final.
- [ ] Screenshots prepared.
- [ ] Demo video recorded.
- [ ] Safety boundary included.
- [ ] Tech stack listed.
- [ ] No treatment or diagnosis claim.

