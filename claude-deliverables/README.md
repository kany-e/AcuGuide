# Claude Deliverables — AcuGuide Hand Coach

Generated for the CV / data-acquisition + safety workstreams. Placed in a subfolder so nothing in your existing repo (Citations.md, PointLandmark.json, demo-app/, experiment.md) is overwritten — merge as you like.

## data/
- **acuguide_hand_points.json** — the core CV dataset. Maps each hand/wrist acupoint to MediaPipe Hands landmarks (target geometry, tolerances, technique, coach copy), plus the feedback state machine and safety layer. Pregnancy-safe (LI4 excluded). Compare against your `PointLandmark.json`.

## specs/
- **min_cv_demo_scope_v2.md** — the minimum CV experiment scope (v2.1). Points: A = TE3 (中渚, headache), B = PC6 (内关, nausea/stress). Includes tap-rhythm proxy + hysteresis, frontal recording, recording table, acceptance criteria.
- **cv_two_person_split.md** / **cv_two_person_split_zh.md** — how to split the CV work across two people (FrameState / CoachState contract), EN + 中文.

## references/
- **eight_points_citations.md** — citations for the 8 points, split into Location / Evidence / Safety.
- **hand_wrist_8_acupoints_map.md** — quick map of the 8 points + massage technique.
- **acupoint_sources_by_type.md** — sources tagged SPOT / PROVE / VALIDATION / SAFETY.
- **hand_wrist_acupoints_research_links.md** — full annotated link library (~40 links, authority-tagged).

## fixtures/
- **fixture_1..5_*.json** — fake FrameState replay streams (30fps) with ground-truth labels, for building/testing the temporal+coaching layer with no camera. Start with fixture_5 (full flow) as the integration smoke test.
- **generate_fixtures.py** — the generator; tweak tap frequency / noise / scenarios.

> Note: fixtures are synthetic (approximate landmark poses). Swap in real MediaPipe recordings once available.
