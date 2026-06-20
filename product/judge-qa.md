# Judge Q&A

## What is the core value?

AcuGuide turns static acupressure advice into a guided action. It helps users know whether they are pressing the right area, holding steady, and completing the routine safely.

## Is this a medical product?

No. It is a wellness self-care coach. It does not diagnose, treat, prescribe, or replace medical care. The product is intentionally scoped around safe, low-risk guidance and red-flag stop conditions.

## Why not just use ChatGPT?

A chatbot can explain what to do, but it cannot see whether the user is doing it correctly. AcuGuide adds the missing execution layer: camera feedback on hand visibility, target alignment, stability, and duration.

## Why not just watch a YouTube video?

Videos are one-way. They cannot adapt to the user's current hand position or tell the user when they have moved away from the target region.

## How is AI used?

AI is used in two ways: vision feedback and coaching language. The vision layer interprets hand position and feedback states. The LLM layer explains curated routines in a friendly way and handles safety responses. The LLM does not freely invent medical advice.

## How do you prevent hallucinated health advice?

The routine library is fixed and curated. The model is instructed to use only provided routine content, avoid diagnosis, avoid treatment claims, and stop when red-flag symptoms appear.

## How accurate is the acupoint detection?

The prototype provides approximate technique guidance, not clinical precision. The demo shows whether the user is in the right general hand region and holding steady. Future versions would need better calibration and expert review.

## Why start with hand-only?

Hand-only is the best hackathon scope. It is visible in a laptop camera, easier to track, safer to demo, and enough to prove the core interaction pattern.

## Why tension headache as the main demo?

It is common, easy to understand, and works well with a hand camera flow. Period discomfort is emotionally strong but requires more careful wording, so it is better as a secondary story.

## What is the business or market opportunity?

The broader opportunity is guided self-care execution. Many wellness products give users content, but few help them perform the physical routine correctly. AcuGuide could expand into hand routines, stretching, breathing, ergonomics, and guided body-based wellness.

## What would you build next?

We would add expert-reviewed routine content, improve hand-region calibration, add voice guidance, support more routines, and collect non-medical user feedback about completion and comfort.

## Judge Q&A Checklist

- [ ] 每个回答不超过 30 秒。
- [ ] 医疗问题回答先强调 non-diagnostic。
- [ ] 技术问题回答强调 constrained AI plus vision feedback。
- [ ] 商业问题回答强调 execution layer。
- [ ] 不承诺临床效果。

