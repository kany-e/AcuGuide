# Acupoint Massage Video Extractor

This subproject extracts numeric JSON features from short acupoint massage videos.
It is the first-stage extractor only: it does not train the downstream neural
network.

## Inputs

- Videos live in `drive-download-20260620T234210Z-3-001/`.
- Metadata labels live in `data/labels.csv`.
- Video names are `IMG_<id>.MOV`, matching the `video_id` in the label file.

## Outputs

Running the extractor creates one JSON per video in `outputs/json/` and an
aggregate `outputs/json/index.csv`.

Each JSON includes:

- manual labels copied from `data/labels.csv`
- target-hand-relative `u/v` samples at 0.5 second intervals
- fingertip-derived press/rub events
- `frequency_curve`
- summary fields: mean frequency, frequency std, cycle count, mean `u/v`
- quality flags and detection coverage ratios

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
.venv/bin/python src/extract_acupoint_features.py --video-id 3852 --video-id 3859 --write-overlays
```

## Notes

Frequency and `u/v` are computed from the same heuristic fingertip/nail point.
The current lightweight workaround uses MediaPipe hand/person detection only to
gate candidate regions and build the target-hand coordinate system.

It does not use target-hand vibration, target-region motion, or background/camera
motion as a fallback.
