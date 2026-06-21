# AcuGuide Hand Coach

## Inspiration

AcuGuide was inspired by a real self-care problem from our team: someone wanted to try hand acupressure for period discomfort, but did not know whether the position, rhythm, or movement was correct. Static diagrams and videos were not enough. We wanted to build a system that gives immediate visual feedback while keeping clear safety boundaries.

## What It Does

AcuGuide uses AR to guide users toward the correct hand acupressure area, then uses computer vision to analyze pressing rhythm, accuracy, and stability in real time. Instead of only showing where to press, it helps users understand whether they are doing the routine correctly.

## How We Built It

We built a web-based demo with React, camera input, MediaPipe hand tracking, AR-style overlays, and computer vision logic for hand position and pressing frequency. We also created a video-to-JSON pipeline to extract fingertip position and rhythm features from training videos, which can support future model training.

## Challenges We Ran Into

1. Fine-tuning a CV model to recognize exact acupressure position was too large for the hackathon scope. Our workaround was to use AR target circles to mark the intended area, so the software does not need to fully identify the acupoint from scratch. It only needs to check whether the user's finger reaches the marked region.
2. Overlapping fingers made fingertip-level tracking noisy. Since AR handles position guidance, we simplified frequency detection by measuring motion around the target region, such as centroid motion frequency, instead of requiring perfect fingertip landmark detection every frame.

## Accomplishments That We're Proud Of

We are proud that we kept the idea small enough to actually demo. Instead of trying to build a huge health AI product, we focused on one simple user pain point: people can read acupressure instructions online, but they still do not know if they are pressing in the right area.

We are also proud of the workaround we found for the vision problem. Exact acupoint detection is hard, especially in a hackathon, so we used hand landmarks and rough target regions to make the guidance understandable enough for a working demo.

## What We Learned

We learned that the hardest part is not explaining acupressure; it is helping users perform it correctly. We also learned that computer vision for hands becomes much harder when fingers overlap, move quickly, or leave the frame.

## What's Next for AcuGuide

- Expand from one-time pressing feedback into guided course-style sessions, where users complete structured routines over time instead of a single action.
- Add an LLM assistant with RAG over curated TCM and safety content, so users can ask self-care questions while the system stays grounded in reviewed sources.
- Support more acupressure points and routines, with AR guidance and computer vision feedback for different hand and wrist regions.
- Build a full routine feedback system that summarizes position accuracy, pressing rhythm, stability, completion, and progress across sessions.
