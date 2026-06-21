<<<<<<< HEAD
# AcuGuide

## Working Docs

- [Demo WebApp](./demo-app/README.md)
- [Hackathon planning](./hackathon/README.md)
- [Product owner workspace](./product/README.md)

## Current Demo Thesis

AcuGuide is a camera-guided hand acupressure coach. It helps users perform safe, non-diagnostic self-care routines by showing where to press, whether the hand is visible, whether the finger is near the target region, and whether the hold is steady long enough.
=======
# Acupoint Massage Video Extractor

This project extracts numeric JSON features from short acupoint massage videos.
It is the first-stage extractor only: it does not train the downstream neural
network.

## Inputs

- Videos live in `drive-download-20260620T234210Z-3-001/`.
- Metadata labels live in `data/labels.csv`.
- Video names are `IMG_<id>.MOV`, matching the `video_id` in the label file.

## Output

Running the extractor creates one JSON per video in `outputs/json/` and an
aggregate `outputs/json/index.csv`.

Each JSON includes:

- manual labels copied from `data/labels.csv`
- quality flags for target hand visibility and heuristic fingertip/nail detection
- `relative_location_samples` at 0.5 second intervals
- cycle events and `frequency_curve`
- summary fields: mean frequency, frequency std, cycle count, mean `u/v`

The coordinate system is target-hand relative:

- `u`: wrist to middle knuckle, positive toward fingers and negative toward the forearm
- `v`: index knuckle to pinky knuckle, normalized by hand scale
- units: normalized by target hand palm length/width, so different hand sizes are comparable

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Run

Run all videos:

```bash
.venv/bin/python src/extract_acupoint_features.py
```

Run selected videos and write visual overlays:

```bash
.venv/bin/python src/extract_acupoint_features.py --video-id 3852 --video-id 3865 --write-overlays
```

## Notes

This is a baseline built with MediaPipe Hands and simple signal processing. It
does not use custom training yet. The manual labels are kept in the JSON, but
the numeric `u/v` and frequency values are measured by the extractor.

The `orientation_score_heuristic` is only a weak geometric signal. For
front/back hand orientation, the manual label remains the reliable source until
we add a dedicated classifier or more labeled examples.

If the target hand/region is not visible, the extractor marks
`quality.frequency_reliable=false` and leaves frequency summary values as
`null`.

Frequency and `u/v` are computed from the same heuristic fingertip/nail point.
MediaPipe is used to establish the target hand coordinate system; it is not used
to pick the pressing hand fingertip. When the heuristic fingertip detector cannot
find enough samples near the target region, the extractor leaves
`mean_frequency_hz`, `frequency_std_hz`, `frequency_curve`, and cycle events
empty/null. It does not use target-hand vibration, target-region motion, or
background/camera motion as a fallback.

The CSV/JSON field `frequency_source` makes this explicit:

- `heuristic_fingertip`: frequency is based on the heuristic fingertip/nail
  detector.
- `null`: no reliable frequency was produced.

Use `quality.frequency_reliable=true` when the downstream model requires a
frequency value.
>>>>>>> 5434261 (added code)
