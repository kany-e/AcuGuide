# Judge Q&A Cards

## Q1: What is the core value?

AcuGuide turns static acupressure advice into guided action. It helps users know whether their hand is visible, whether they are near the target region, and whether they held long enough.

## Q2: Is this a medical product?

No. It is a wellness self-care coach. It does not diagnose, treat, prescribe, or replace medical care. We intentionally scoped it around safe guidance and red-flag stop conditions.

## Q3: Why not just use ChatGPT?

ChatGPT can explain what to do, but it cannot see whether the user is doing it correctly. AcuGuide adds the missing execution layer with camera feedback.

## Q4: Why not just watch a video?

Videos are one-way. They cannot adapt to the user's current hand position or tell the user when they moved away from the target region.

## Q5: How is AI used?

AI is used for visual feedback and coaching language. The vision layer interprets hand position and feedback states. The LLM layer explains curated routines in a friendly way and handles safety responses.

## Q6: How do you prevent hallucinated health advice?

The routine library is fixed and curated. The model can only rewrite or explain provided routine content. It is instructed not to diagnose, not to make treatment claims, and not to invent new pressure points.

## Q7: How accurate is the pressure point detection?

This prototype provides approximate hand-region guidance, not clinical precision. The demo proves the interaction loop: visibility, target alignment, hold stability, and completion.

## Q8: Why start with hand-only?

Hand-only is the right hackathon scope. It is visible in a laptop camera, easier to track, safer to demo, and enough to prove the core product interaction.

## Q9: Why tension headache as the main demo?

It is common, easy to understand, and works well with a hand camera flow. Period discomfort is emotionally strong but needs more careful wording, so it works better as a secondary story.

## Q10: What is the market opportunity?

The broader opportunity is guided self-care execution. Many wellness products give users content; fewer help users perform the physical routine correctly. AcuGuide can expand into hand routines, stretching, breathing, ergonomics, and guided body-based wellness.

## Q11: What would you build next?

Expert-reviewed routine content, better hand-region calibration, voice guidance, more self-care routines, and non-medical progress tracking.

## Q12: What is the main risk?

The main risk is being mistaken for diagnosis or treatment. That is why we constrained the scope, fixed the routine library, added safety copy, and designed red-flag stop conditions.

