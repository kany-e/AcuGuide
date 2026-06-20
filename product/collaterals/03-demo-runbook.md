# Demo Runbook

## Goal

让任何队友都能在 2 分钟内稳定演示 AcuGuide 的核心价值。

## Demo Device Setup

- Browser camera permission enabled.
- Laptop camera cleaned and unobstructed.
- Room lighting tested.
- Backup static/mock mode ready.
- Devpost/demo URL opened before judge arrives.
- One backup tab open with fallback state.

## Golden Path

1. Open app home.
2. Select **Tension Headache**.
3. Show safety screen.
4. Continue to routine preview.
5. Open camera routine.
6. Show no hand state.
7. Put hand in frame.
8. Move finger off target briefly.
9. Move finger near target.
10. Hold until progress ring advances.
11. Complete or skip to completion if time is short.
12. Show recap.

## Speaker Notes

### Home

Say:

> We support multiple common self-care contexts, but the demo path is tension headache because it is fast and easy to show with a hand camera flow.

### Safety

Say:

> The product sets a boundary before guidance starts: wellness self-care only, not medical diagnosis.

### Routine Preview

Say:

> The routine is curated. The model does not invent pressure points.

### Camera

Say:

> This is the key difference from a chatbot. AcuGuide can see whether the user is actually following the routine.

### Recap

Say:

> The recap summarizes execution, not medical outcome.

## Demo Timing

| Segment | Target Time |
|---|---:|
| Problem and product | 20s |
| Home and safety | 20s |
| Routine preview | 10s |
| Camera feedback | 40s |
| Recap and closing | 20s |

## Failure Modes

### Camera Permission Fails

Action:

1. Switch to fallback tab.
2. Show simulated camera states.
3. Say: "The live camera is failing in this environment, so we are switching to simulated states. The product logic is the same."

### Hand Tracking Is Jittery

Action:

1. Keep hand still.
2. Move to brighter background.
3. If unstable after 10 seconds, switch to mock mode.

Say:

> The prototype provides approximate technique feedback. The product value is the guided execution loop.

### LLM Fails

Action:

1. Use deterministic routine copy.
2. Continue demo.

Say:

> The routine source is curated and deterministic. The LLM layer improves coaching language and safety responses, but it is not required for the core demo.

## Hard Stop Rules

Do not say:

- It treats headaches.
- It diagnoses problems.
- It detects disease.
- It knows exactly how much pressure the user applies.
- It precisely locates clinical acupoints.

Do say:

- It guides approximate hand-region routine execution.
- It supports wellness self-care.
- It provides visual technique feedback.
- It uses safety boundaries.

## Final Pre-Demo Checklist

- [ ] Golden path ran once in the last 10 minutes.
- [ ] Backup mode is open.
- [ ] Script speaker knows the closing line.
- [ ] No page says treatment or diagnosis.
- [ ] Recap screen works.

