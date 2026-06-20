# AcuGuide Hand Coach One-Pager

## Product

**AcuGuide Hand Coach** is an AI camera coach for safe, guided hand acupressure routines.

## Problem

People can find acupressure advice online, but static instructions leave a practical gap: users still do not know whether they are pressing the right place, holding long enough, or staying within safe self-care boundaries.

The real problem is not lack of information. It is lack of execution confidence.

## Solution

AcuGuide turns static hand acupressure advice into an interactive routine. A user chooses a common discomfort, sees a short safety boundary, follows a curated hand routine, and receives camera-based feedback on hand visibility, target alignment, hold stability, rhythm, and duration.

## Target Users

- Students and young professionals with everyday tension or mild discomfort.
- Wellness-curious beginners who want clearer guidance than diagrams or videos.
- Users who want a short self-care routine but do not want open-ended medical advice.

## Core Value Proposition

Static acupressure advice tells you where to press. AcuGuide shows you whether you are doing it right.

## What Makes It Different

| Alternative | Limitation | AcuGuide Difference |
|---|---|---|
| Articles and diagrams | No execution feedback | Camera-guided positioning and hold feedback |
| YouTube videos | One-way demonstration | Real-time user-specific guidance |
| Health chatbots | Text only | Visual action feedback |
| Generic pose apps | Not acupressure-specific | Routine, safety, and hand-region guidance |

## MVP Demo

The demo focuses on **Tension Headache** as the main path:

1. User selects Tension Headache.
2. App shows safety boundary.
3. App previews a 30-second hand pressure routine.
4. Camera detects whether hand is visible.
5. Overlay guides the target hand region.
6. Feedback helps the user hold steady.
7. Recap summarizes completion without medical claims.

## Safety Boundary

AcuGuide is not an AI doctor. It does not diagnose, treat, prescribe, or replace medical care. It provides wellness self-care guidance only and stops when users report concerning symptoms.

## Technical Story

The product combines:

- Curated routine data as source of truth.
- Hand tracking / visual feedback for execution.
- AI coach language and safety guardrails.
- Fallback mode so the demo works even if model or network fails.

## Winning Thesis

Most AI health demos generate more advice. AcuGuide helps users execute advice safely.

