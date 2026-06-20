# Booth And Sponsor Talk Tracks

## Mentor Ask

> We are building AcuGuide, an AI camera coach for hand acupressure routines. The product is intentionally not a diagnosis tool. We are trying to make the demo feel like a real coach: hand visible, target aligned, hold steady, complete routine. Could you give feedback on whether the product story is clear and whether the safety boundary sounds credible?

## Technical Mentor Ask

> Our main technical risk is stable hand feedback in a live demo. We do not need clinical precision; we need reliable states: no hand, hand detected, near target, hold steady. What is the simplest way to make that robust?

## Product Mentor Ask

> The core positioning is "execution layer for self-care," not "AI doctor." Does that value prop come through clearly in the flow?

## Sponsor Talk: AI/LLM Sponsor

> We are using the LLM as a constrained coach, not as a medical decision maker. Routine content is fixed, and the model turns it into friendly step-by-step guidance while respecting safety guardrails. We are interested in showing how LLMs can support bounded, high-trust workflows.

## Sponsor Talk: Vision/Infra Sponsor

> The product depends on low-latency feedback from camera state to UI state. The interesting technical challenge is making the hand tracking loop stable enough for a live guided routine.

## Sponsor Talk: Redis / Data Sponsor

> A future version could store routine templates, user completion history, and safety-checked content as structured data. The key product pattern is a curated content layer plus real-time execution feedback.

## Sponsor Talk: Observability Sponsor

> This kind of AI app needs tracing around model outputs, safety triggers, camera state transitions, and fallback usage. We need to know when the AI layer or vision layer fails silently.

## Team Formation / Collaboration Blurb

> We have a focused demo scope: hand-only AI acupressure coach. Main path is tension headache. We need to make the camera feedback loop reliable and the product story safe. If you can help with frontend polish, MediaPipe/hand tracking, or demo stability, you can plug in immediately.

## Booth Checklist

- [ ] Start with one sentence.
- [ ] Ask for one specific type of feedback.
- [ ] Do not over-explain TCM.
- [ ] Mention safety boundary before health questions.
- [ ] End by asking what would make the demo more credible.

