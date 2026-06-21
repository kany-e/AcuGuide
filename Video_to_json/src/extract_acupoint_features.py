#!/usr/bin/env python3
"""Extract body-relative acupoint massage features from short videos.

This baseline intentionally avoids custom neural-network training. It uses
MediaPipe Hands for landmarks, OpenCV for video IO, and simple signal processing
to produce one JSON file per video.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
from scipy.signal import find_peaks


Point = Tuple[float, float]


TIP_IDS = [4, 8, 12, 16, 20]
PALM_IDS = [0, 5, 9, 13, 17]
HEURISTIC_SOURCE_PREFIX = "heuristic_"


@dataclass
class LabelRow:
    video_id: str
    file: str
    target: str
    region_hint: str
    position_label: Optional[str]
    frequency_label: Optional[str]
    issue_label: Optional[str]


@dataclass
class HandObservation:
    landmarks: np.ndarray
    handedness: str
    score: float
    bbox: Tuple[float, float, float, float]
    bbox_area: float
    edge_touch: bool


def nullable(value: str) -> Optional[str]:
    value = value.strip()
    return value or None


def load_labels(path: Path) -> List[LabelRow]:
    rows: List[LabelRow] = []
    with path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(
                LabelRow(
                    video_id=row["video_id"].strip(),
                    file=row["file"].strip(),
                    target=row["target"].strip(),
                    region_hint=row["region_hint"].strip(),
                    position_label=nullable(row.get("position_label", "")),
                    frequency_label=nullable(row.get("frequency_label", "")),
                    issue_label=nullable(row.get("issue_label", "")),
                )
            )
    return rows


def landmark_array(hand_landmarks: Any) -> np.ndarray:
    return np.array([(lm.x, lm.y, lm.z) for lm in hand_landmarks.landmark], dtype=np.float32)


def bbox_for_landmarks(landmarks: np.ndarray) -> Tuple[float, float, float, float]:
    xs = landmarks[:, 0]
    ys = landmarks[:, 1]
    return float(xs.min()), float(ys.min()), float(xs.max()), float(ys.max())


def is_edge_touching(bbox: Tuple[float, float, float, float], margin: float = 0.025) -> bool:
    x0, y0, x1, y1 = bbox
    return x0 <= margin or y0 <= margin or x1 >= 1.0 - margin or y1 >= 1.0 - margin


def collect_hands(results: Any) -> List[HandObservation]:
    if not results.multi_hand_landmarks:
        return []

    handedness_items = results.multi_handedness or []
    hands: List[HandObservation] = []
    for idx, hand_landmarks in enumerate(results.multi_hand_landmarks):
        arr = landmark_array(hand_landmarks)
        bbox = bbox_for_landmarks(arr)
        x0, y0, x1, y1 = bbox
        area = max(0.0, x1 - x0) * max(0.0, y1 - y0)
        handedness = "unknown"
        score = 0.0
        if idx < len(handedness_items):
            cls = handedness_items[idx].classification[0]
            handedness = cls.label
            score = float(cls.score)
        hands.append(
            HandObservation(
                landmarks=arr,
                handedness=handedness,
                score=score,
                bbox=bbox,
                bbox_area=area,
                edge_touch=is_edge_touching(bbox),
            )
        )
    return hands


def target_hand_score(hand: HandObservation) -> float:
    # The target hand is usually the larger, less clipped hand. The pressing hand
    # is often partial or at an image edge.
    clip_penalty = 0.55 if hand.edge_touch else 1.0
    return hand.bbox_area * clip_penalty * (0.5 + hand.score)


def choose_target_hand(hands: List[HandObservation]) -> Optional[int]:
    if not hands:
        return None
    scores = [target_hand_score(hand) for hand in hands]
    return int(np.argmax(scores))


def normalize2(v: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(v))
    if norm < 1e-6:
        return np.array([1.0, 0.0], dtype=np.float32)
    return v / norm


def hand_local_basis(target: HandObservation) -> Dict[str, Any]:
    lm = target.landmarks
    wrist = lm[0, :2]
    middle_mcp = lm[9, :2]
    index_mcp = lm[5, :2]
    pinky_mcp = lm[17, :2]

    y_axis = normalize2(middle_mcp - wrist)
    x_axis_raw = pinky_mcp - index_mcp
    x_axis = normalize2(x_axis_raw)
    # Make the axes roughly orthogonal. Keep x sign from index->pinky.
    x_axis = normalize2(x_axis - np.dot(x_axis, y_axis) * y_axis)
    if float(np.linalg.norm(x_axis)) < 1e-6:
        x_axis = np.array([-y_axis[1], y_axis[0]], dtype=np.float32)

    palm_len = float(np.linalg.norm(middle_mcp - wrist))
    palm_width = float(np.linalg.norm(pinky_mcp - index_mcp))
    scale = max(palm_len, palm_width, 1e-4)

    return {
        "origin": wrist,
        "x_axis": x_axis,
        "y_axis": y_axis,
        "scale": scale,
        "palm_length": palm_len,
        "palm_width": palm_width,
        "anchors": {
            "wrist": [float(wrist[0]), float(wrist[1])],
            "middle_mcp": [float(middle_mcp[0]), float(middle_mcp[1])],
            "index_mcp": [float(index_mcp[0]), float(index_mcp[1])],
            "pinky_mcp": [float(pinky_mcp[0]), float(pinky_mcp[1])],
        },
    }


def to_local_uv(point_xy: np.ndarray, basis: Dict[str, Any]) -> Tuple[float, float]:
    delta = point_xy - basis["origin"]
    scale = basis["scale"]
    u = float(np.dot(delta, basis["y_axis"]) / scale)
    v = float(np.dot(delta, basis["x_axis"]) / scale)
    return u, v


def point_distance_to_bbox(point: np.ndarray, bbox: Tuple[float, float, float, float]) -> float:
    x0, y0, x1, y1 = bbox
    x, y = float(point[0]), float(point[1])
    dx = max(x0 - x, 0.0, x - x1)
    dy = max(y0 - y, 0.0, y - y1)
    return math.hypot(dx, dy)


def clip_bounds(
    x0: float, y0: float, x1: float, y1: float, width: int, height: int
) -> Tuple[int, int, int, int]:
    ix0 = int(max(0, min(width - 1, round(x0))))
    iy0 = int(max(0, min(height - 1, round(y0))))
    ix1 = int(max(ix0 + 1, min(width, round(x1))))
    iy1 = int(max(iy0 + 1, min(height, round(y1))))
    return ix0, iy0, ix1, iy1


def local_point_to_frame(point_uv: Tuple[float, float], basis: Dict[str, Any]) -> np.ndarray:
    u, v = point_uv
    return basis["origin"] + basis["y_axis"] * (u * basis["scale"]) + basis["x_axis"] * (v * basis["scale"])


def target_roi_bounds(
    target: HandObservation, basis: Dict[str, Any], frame_shape: Tuple[int, int, int]
) -> Tuple[int, int, int, int]:
    height, width = frame_shape[:2]
    x0, y0, x1, y1 = target.bbox

    local_points = [
        local_point_to_frame((-1.35, -1.15), basis),
        local_point_to_frame((2.65, 1.15), basis),
        local_point_to_frame((-1.35, 1.15), basis),
        local_point_to_frame((2.65, -1.15), basis),
    ]
    xs = [x0, x1] + [float(p[0]) for p in local_points]
    ys = [y0, y1] + [float(p[1]) for p in local_points]

    return clip_bounds(
        min(xs) * width,
        min(ys) * height,
        max(xs) * width,
        max(ys) * height,
        width,
        height,
    )


def normalized_target_distance(point_xy: np.ndarray, target: HandObservation) -> float:
    target_points = target.landmarks[:, :2]
    return float(np.min(np.linalg.norm(target_points - point_xy, axis=1)))


def target_landmark_exclusion_mask(
    shape: Tuple[int, int], target: HandObservation, radius_px: int
) -> np.ndarray:
    mask = np.zeros(shape, dtype=np.uint8)
    height, width = shape[:2]
    hull_points = np.array(
        [[int(point[0] * width), int(point[1] * height)] for point in target.landmarks[:, :2]],
        dtype=np.int32,
    )
    for point in target.landmarks[:, :2]:
        cv2.circle(mask, (int(point[0] * width), int(point[1] * height)), radius_px, 255, -1)
    mask = cv2.dilate(mask, np.ones((radius_px, radius_px), dtype=np.uint8), iterations=1)
    return mask


def find_heuristic_fingertip(
    frame_bgr: np.ndarray,
    target: HandObservation,
    basis: Dict[str, Any],
    strict_target_band: bool,
    person_mask: Optional[np.ndarray],
    allowed_bboxes: Optional[List[Tuple[float, float, float, float]]],
    allowed_tip_points: Optional[np.ndarray],
) -> Tuple[Optional[np.ndarray], float, Optional[str]]:
    """Find a visible pressing fingertip/nail near the target region.

    This lightweight detector searches only near the target hand/arm coordinate
    frame, prioritizes nail-like blobs, and uses the detected fingertip/nail
    point itself for u/v.
    """

    height, width = frame_bgr.shape[:2]
    x0, y0, x1, y1 = target_roi_bounds(target, basis, frame_bgr.shape)
    roi = frame_bgr[y0:y1, x0:x1]
    if roi.size == 0:
        return None, 0.0, None

    roi_h, roi_w = roi.shape[:2]
    hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
    ycrcb = cv2.cvtColor(roi, cv2.COLOR_BGR2YCrCb)

    skin_hsv = cv2.inRange(hsv, np.array([0, 18, 45]), np.array([35, 190, 255]))
    skin_ycrcb = cv2.inRange(ycrcb, np.array([0, 135, 80]), np.array([255, 180, 138]))
    cr = ycrcb[:, :, 1].astype(np.int16)
    cb = ycrcb[:, :, 2].astype(np.int16)
    skin_chroma = np.where(cr > cb + 8, 255, 0).astype(np.uint8)
    skin = cv2.bitwise_and(cv2.bitwise_and(skin_hsv, skin_ycrcb), skin_chroma)

    if person_mask is not None:
        person_roi = np.where(person_mask[y0:y1, x0:x1] > 0.20, 255, 0).astype(np.uint8)
        person_roi = cv2.dilate(person_roi, np.ones((5, 5), np.uint8), iterations=1)
        skin = cv2.bitwise_and(skin, person_roi)
    else:
        person_roi = None

    # Fingernails are usually less saturated and brighter than surrounding skin.
    nail = cv2.inRange(hsv, np.array([0, 0, 95]), np.array([35, 95, 255]))
    nail = cv2.bitwise_and(nail, cv2.dilate(skin, np.ones((5, 5), np.uint8), iterations=1))
    if person_roi is not None:
        nail = cv2.bitwise_and(nail, person_roi)

    exclude_full = target_landmark_exclusion_mask(
        (height, width), target, radius_px=max(8, int(round(basis["scale"] * width * 0.18)))
    )
    exclude = exclude_full[y0:y1, x0:x1]
    nail = cv2.bitwise_and(nail, cv2.bitwise_not(exclude))

    kernel = np.ones((5, 5), np.uint8)
    nail = cv2.morphologyEx(nail, cv2.MORPH_OPEN, kernel, iterations=1)
    nail = cv2.morphologyEx(nail, cv2.MORPH_CLOSE, kernel, iterations=1)

    def contour_candidates(mask: np.ndarray, source: str) -> List[Tuple[float, np.ndarray, float, str]]:
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        candidates: List[Tuple[float, np.ndarray, float, str]] = []
        frame_area = float(width * height)
        for contour in contours:
            area = float(cv2.contourArea(contour))
            if area < frame_area * 0.000012 or area > frame_area * 0.010:
                continue
            bx, by, bw, bh = cv2.boundingRect(contour)
            if bw <= 1 or bh <= 1:
                continue
            aspect = max(bw / bh, bh / bw)
            if source == "heuristic_nail" and aspect > 4.8:
                continue
            if source == "heuristic_skin_fingertip" and aspect < 1.35:
                continue

            moments = cv2.moments(contour)
            if abs(moments["m00"]) < 1e-6:
                continue
            cx = (moments["m10"] / moments["m00"] + x0) / width
            cy = (moments["m01"] / moments["m00"] + y0) / height
            point_xy = np.array([cx, cy], dtype=np.float32)
            if allowed_bboxes is not None:
                bbox_pad = 0.03
                if not any(
                    bx0 - bbox_pad <= cx <= bx1 + bbox_pad and by0 - bbox_pad <= cy <= by1 + bbox_pad
                    for bx0, by0, bx1, by1 in allowed_bboxes
                ):
                    continue
            tip_closeness = 0.0
            if allowed_tip_points is not None and allowed_tip_points.size:
                tip_d = float(np.min(np.linalg.norm(allowed_tip_points - point_xy, axis=1)))
                if tip_d > 0.16:
                    continue
                tip_closeness = max(0.0, 1.0 - tip_d / 0.16)
            if strict_target_band:
                tx0, ty0, tx1, ty1 = target.bbox
                bbox_pad = 0.0
                if not (tx0 - bbox_pad <= cx <= tx1 + bbox_pad and ty0 - bbox_pad <= cy <= ty1 + bbox_pad):
                    continue
            d = normalized_target_distance(point_xy, target)
            if d > 0.35:
                continue
            area_score = min(1.0, area / (frame_area * 0.0012))
            shape_score = min(1.0, aspect / 3.0)
            closeness = max(0.0, 1.0 - d / 0.35)
            if source == "heuristic_nail":
                score = 0.38 * closeness + 0.22 * area_score + 0.12 * (1.0 - min(1.0, abs(aspect - 1.8) / 3.0)) + 0.28 * tip_closeness
                confidence = 0.45 + 0.50 * score
            else:
                score = 0.42 * closeness + 0.18 * shape_score + 0.12 * area_score + 0.28 * tip_closeness
                confidence = 0.25 + 0.45 * score
            candidates.append((score, np.array([cx, cy], dtype=np.float32), confidence, source))
        return candidates

    candidates = contour_candidates(nail, "heuristic_nail")
    if not candidates:
        skin = cv2.bitwise_and(skin, cv2.bitwise_not(exclude))
        skin = cv2.morphologyEx(skin, cv2.MORPH_OPEN, kernel, iterations=1)
        skin = cv2.morphologyEx(skin, cv2.MORPH_CLOSE, kernel, iterations=2)
        candidates = contour_candidates(skin, "heuristic_skin_fingertip")

    if not candidates:
        return None, 0.0, None

    _, point, confidence, source = max(candidates, key=lambda item: item[0])
    return point, float(confidence), source


def finite_median(values: Iterable[Optional[float]]) -> Optional[float]:
    arr = np.array([v for v in values if v is not None and np.isfinite(v)], dtype=np.float32)
    if arr.size == 0:
        return None
    return float(np.median(arr))


def finite_mean(values: Iterable[Optional[float]]) -> Optional[float]:
    arr = np.array([v for v in values if v is not None and np.isfinite(v)], dtype=np.float32)
    if arr.size == 0:
        return None
    return float(np.mean(arr))


def finite_std(values: Iterable[Optional[float]]) -> Optional[float]:
    arr = np.array([v for v in values if v is not None and np.isfinite(v)], dtype=np.float32)
    if arr.size <= 1:
        return None
    return float(np.std(arr))


def smooth_signal(values: np.ndarray, window: int) -> np.ndarray:
    if values.size == 0 or window <= 1:
        return values
    window = min(window, values.size)
    kernel = np.ones(window, dtype=np.float32) / window
    return np.convolve(values, kernel, mode="same")


def compute_frequency(
    frame_records: List[Dict[str, Any]], duration_sec: float, process_fps: float
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Optional[float]]]:
    if not frame_records:
        return [], [], {
            "mean_frequency_hz": None,
            "frequency_std_hz": None,
            "cycle_count": 0,
        }

    times = np.array([r["time_sec"] for r in frame_records], dtype=np.float32)
    points = np.array(
        [
            [
                r["u"] if r.get("u") is not None else np.nan,
                r["v"] if r.get("v") is not None else np.nan,
            ]
            for r in frame_records
        ],
        dtype=np.float32,
    )
    valid = np.array(
        [
            bool(r.get("finger_contact_detected"))
            and r.get("u") is not None
            and r.get("v") is not None
            for r in frame_records
        ],
        dtype=bool,
    )

    speed = np.zeros(len(frame_records), dtype=np.float32)
    for i in range(1, len(frame_records)):
        dt = max(1e-3, float(times[i] - times[i - 1]))
        if valid[i] and valid[i - 1] and np.all(np.isfinite(points[i])) and np.all(np.isfinite(points[i - 1])):
            speed[i] = float(np.linalg.norm(points[i] - points[i - 1]) / dt)

    def normalize(arr: np.ndarray) -> np.ndarray:
        if arr.size == 0:
            return arr
        p95 = float(np.percentile(arr, 95))
        if p95 <= 1e-6:
            return np.zeros_like(arr)
        return np.clip(arr / p95, 0.0, 1.0)

    activity = normalize(speed)
    activity = smooth_signal(activity, max(1, int(round(process_fps * 0.20))))

    if activity.size < 4 or float(np.max(activity)) < 0.05:
        peaks = np.array([], dtype=np.int64)
    else:
        min_distance = max(1, int(round(process_fps * 0.28)))
        prominence = max(0.05, float(np.std(activity)) * 0.55)
        peaks, _ = find_peaks(activity, distance=min_distance, prominence=prominence)

    events: List[Dict[str, Any]] = []
    for peak_idx in peaks:
        rec = frame_records[int(peak_idx)]
        events.append(
            {
                "time_sec": round(float(rec["time_sec"]), 3),
                "u": round(float(rec["u"]), 4) if rec.get("u") is not None else None,
                "v": round(float(rec["v"]), 4) if rec.get("v") is not None else None,
                "type": "cycle_peak",
                "confidence": round(float(activity[int(peak_idx)]), 3),
            }
        )

    peak_times = times[peaks] if peaks.size else np.array([], dtype=np.float32)
    intervals = np.diff(peak_times)
    interval_freqs = 1.0 / intervals if intervals.size else np.array([], dtype=np.float32)
    mean_hz = float(np.median(interval_freqs)) if interval_freqs.size else (
        float(len(peaks) / duration_sec) if duration_sec > 0 and len(peaks) > 1 else None
    )
    std_hz = float(np.std(interval_freqs)) if interval_freqs.size > 1 else None

    curve: List[Dict[str, Any]] = []
    if duration_sec > 0:
        t = 0.5
        while t <= duration_sec + 1e-6:
            window_start = t - 1.0
            window_end = t + 1.0
            local = peak_times[(peak_times >= window_start) & (peak_times <= window_end)]
            window_len = min(duration_sec, window_end) - max(0.0, window_start)
            hz: Optional[float]
            if local.size >= 2:
                local_intervals = np.diff(local)
                hz = float(np.median(1.0 / local_intervals))
            elif window_len > 0 and local.size == 1:
                hz = float(local.size / window_len)
            else:
                hz = 0.0
            confidence = float(np.mean(activity[(times >= window_start) & (times <= window_end)])) if times.size else 0.0
            curve.append(
                {
                    "time_sec": round(t, 3),
                    "hz": round(hz, 4) if hz is not None else None,
                    "confidence": round(max(0.0, min(1.0, confidence)), 3),
                }
            )
            t += 0.5

    summary = {
        "mean_frequency_hz": round(mean_hz, 4) if mean_hz is not None else None,
        "frequency_std_hz": round(std_hz, 4) if std_hz is not None else None,
        "cycle_count": int(len(peaks)),
    }
    return curve, events, summary


def prepare_frequency_records(
    frame_records: List[Dict[str, Any]], process_fps: float
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    records = [dict(record) for record in frame_records]
    if not records:
        return records, {
            "raw_valid_ratio": 0.0,
            "filtered_valid_ratio": 0.0,
            "filled_valid_ratio": 0.0,
            "outlier_count": 0,
            "interpolated_count": 0,
        }

    points = np.array(
        [
            [
                record["u"] if record.get("u") is not None else np.nan,
                record["v"] if record.get("v") is not None else np.nan,
            ]
            for record in records
        ],
        dtype=np.float32,
    )
    valid = np.array(
        [
            bool(record.get("finger_contact_detected"))
            and record.get("u") is not None
            and record.get("v") is not None
            and np.all(np.isfinite(points[idx]))
            for idx, record in enumerate(records)
        ],
        dtype=bool,
    )
    raw_valid_ratio = float(np.mean(valid)) if valid.size else 0.0
    outlier_count = 0
    interpolated_count = 0

    valid_indices = np.flatnonzero(valid)
    if valid_indices.size >= 4:
        valid_points = points[valid]
        center = np.median(valid_points, axis=0)
        distances = np.linalg.norm(valid_points - center, axis=1)
        median_distance = float(np.median(distances))
        mad = float(np.median(np.abs(distances - median_distance)))
        outlier_threshold = max(0.9, median_distance + 3.5 * max(mad, 0.03))
        for idx, distance in zip(valid_indices, distances):
            if float(distance) > outlier_threshold:
                records[int(idx)]["u"] = None
                records[int(idx)]["v"] = None
                records[int(idx)]["contact_score"] = 0.0
                records[int(idx)]["contact_source"] = None
                records[int(idx)]["finger_contact_detected"] = False
                valid[int(idx)] = False
                outlier_count += 1

    filtered_valid_ratio = float(np.mean(valid)) if valid.size else 0.0
    valid_indices = np.flatnonzero(valid)
    max_gap_frames = max(1, int(round(process_fps * 2.0)))
    for left, right in zip(valid_indices[:-1], valid_indices[1:]):
        gap = int(right - left)
        if gap <= 1 or gap > max_gap_frames:
            continue
        left_point = points[int(left)]
        right_point = points[int(right)]
        if not np.all(np.isfinite(left_point)) or not np.all(np.isfinite(right_point)):
            continue
        for idx in range(int(left) + 1, int(right)):
            alpha = float(idx - left) / float(gap)
            point = left_point * (1.0 - alpha) + right_point * alpha
            records[idx]["u"] = float(point[0])
            records[idx]["v"] = float(point[1])
            records[idx]["contact_score"] = max(float(records[idx].get("contact_score") or 0.0), 0.35)
            records[idx]["contact_source"] = "heuristic_interpolated"
            records[idx]["finger_contact_detected"] = True
            interpolated_count += 1

    filled_valid = np.array(
        [
            bool(record.get("finger_contact_detected"))
            and record.get("u") is not None
            and record.get("v") is not None
            for record in records
        ],
        dtype=bool,
    )
    return records, {
        "raw_valid_ratio": raw_valid_ratio,
        "filtered_valid_ratio": filtered_valid_ratio,
        "filled_valid_ratio": float(np.mean(filled_valid)) if filled_valid.size else 0.0,
        "outlier_count": outlier_count,
        "interpolated_count": interpolated_count,
    }


def downscale_for_processing(frame: np.ndarray, max_width: int) -> np.ndarray:
    h, w = frame.shape[:2]
    if w <= max_width:
        return frame
    scale = max_width / float(w)
    return cv2.resize(frame, (max_width, int(round(h * scale))), interpolation=cv2.INTER_AREA)


def maybe_write_overlay(
    path: Optional[Path],
    frame: np.ndarray,
    hands: List[HandObservation],
    target_idx: Optional[int],
    contact_point: Optional[np.ndarray],
    sample: Dict[str, Any],
) -> None:
    if path is None:
        return
    out = frame.copy()
    h, w = out.shape[:2]
    for idx, hand in enumerate(hands):
        color = (40, 220, 40) if idx == target_idx else (40, 130, 255)
        x0, y0, x1, y1 = hand.bbox
        cv2.rectangle(out, (int(x0 * w), int(y0 * h)), (int(x1 * w), int(y1 * h)), color, 2)
        for point in hand.landmarks[:, :2]:
            cv2.circle(out, (int(point[0] * w), int(point[1] * h)), 3, color, -1)

    if contact_point is not None:
        cv2.circle(out, (int(contact_point[0] * w), int(contact_point[1] * h)), 12, (0, 0, 255), 3)

    text = f"t={sample['time_sec']:.1f}s u={sample.get('u')} v={sample.get('v')}"
    cv2.putText(out, text, (24, 42), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 4)
    cv2.putText(out, text, (24, 42), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), out)


def extract_video(
    row: LabelRow,
    video_path: Path,
    output_dir: Path,
    hands_model: Any,
    segmentation_model: Any,
    process_fps: float,
    sample_interval_sec: float,
    max_width: int,
    overlay_dir: Optional[Path],
) -> Dict[str, Any]:
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video: {video_path}")

    source_fps = float(cap.get(cv2.CAP_PROP_FPS) or 30.0)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration_sec = frame_count / source_fps if source_fps > 0 and frame_count else 0.0
    frame_step = max(1, int(round(source_fps / process_fps)))
    actual_process_fps = source_fps / frame_step if frame_step else source_fps

    frame_records: List[Dict[str, Any]] = []
    sample_records: List[Dict[str, Any]] = []
    hand_counts: List[int] = []
    target_detected: List[bool] = []
    other_hand_detected: List[bool] = []
    other_hand_edge_touch: List[bool] = []
    target_orientation_scores: List[float] = []
    next_sample_time = 0.0

    frame_index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % frame_step != 0:
            frame_index += 1
            continue

        time_sec = frame_index / source_fps if source_fps > 0 else 0.0
        frame_small = downscale_for_processing(frame, max_width=max_width)
        rgb = cv2.cvtColor(frame_small, cv2.COLOR_BGR2RGB)

        results = hands_model.process(rgb)
        segmentation = segmentation_model.process(rgb) if segmentation_model is not None else None
        person_mask = segmentation.segmentation_mask if segmentation is not None else None
        hands = collect_hands(results)
        target_idx = choose_target_hand(hands)
        target = hands[target_idx] if target_idx is not None else None
        hand_counts.append(len(hands))
        target_detected.append(target is not None)
        other_indices = [i for i in range(len(hands)) if i != target_idx]
        other_hand_detected.append(bool(other_indices))
        other_hand_edge_touch.append(any(hands[i].edge_touch for i in other_indices))

        basis: Optional[Dict[str, Any]] = None
        contact_point: Optional[np.ndarray] = None
        landmark_conf = 0.0
        contact_source: Optional[str] = None
        if target is not None:
            basis = hand_local_basis(target)
            allowed_bboxes = [hands[i].bbox for i in other_indices]
            if other_indices:
                allowed_tip_points = np.vstack([hands[i].landmarks[TIP_IDS, :2] for i in other_indices])
            else:
                allowed_tip_points = np.empty((0, 2), dtype=np.float32)
            contact_point, landmark_conf, contact_source = find_heuristic_fingertip(
                frame_small,
                target,
                basis,
                strict_target_band=False,
                person_mask=person_mask,
                allowed_bboxes=allowed_bboxes,
                allowed_tip_points=allowed_tip_points,
            )
            # Heuristic only: z separation between palm center and fingertips tends
            # to change when the visible side flips. Keep it as a score, not a verdict.
            z_tip = float(np.mean(target.landmarks[TIP_IDS, 2]))
            z_palm = float(np.mean(target.landmarks[PALM_IDS, 2]))
            target_orientation_scores.append(z_tip - z_palm)

        u: Optional[float] = None
        v: Optional[float] = None
        contact_score = 0.0
        if basis is not None and contact_point is not None:
            u, v = to_local_uv(contact_point, basis)
            contact_score = landmark_conf

        record = {
            "time_sec": float(time_sec),
            "u": float(u) if u is not None and np.isfinite(u) else None,
            "v": float(v) if v is not None and np.isfinite(v) else None,
            "contact_score": float(contact_score),
            "contact_source": contact_source,
            "finger_contact_detected": bool(contact_source and contact_source.startswith(HEURISTIC_SOURCE_PREFIX)),
            "hand_count": len(hands),
            "target_hand_detected": target is not None,
            "pressing_hand_detected": bool(other_indices),
        }
        frame_records.append(record)

        while time_sec + 1e-6 >= next_sample_time:
            sample = {
                    "time_sec": round(next_sample_time, 3),
                    "u": round(float(u), 4) if u is not None and np.isfinite(u) else None,
                    "v": round(float(v), 4) if v is not None and np.isfinite(v) else None,
                    "contact_score": round(float(contact_score), 3),
                    "contact_source": contact_source,
                    "finger_contact_detected": bool(contact_source and contact_source.startswith(HEURISTIC_SOURCE_PREFIX)),
                    "hand_count": len(hands),
                    "target_hand_detected": target is not None,
                    "pressing_hand_detected": bool(other_indices),
            }
            sample_records.append(sample)
            if overlay_dir is not None and abs((next_sample_time / sample_interval_sec) % 2) < 1e-6:
                maybe_write_overlay(
                    overlay_dir / f"{row.video_id}_{next_sample_time:.1f}.jpg",
                    frame_small,
                    hands,
                    target_idx,
                    contact_point,
                    sample,
                )
            next_sample_time += sample_interval_sec

        frame_index += 1

    cap.release()

    frequency_records, trajectory_stats = prepare_frequency_records(frame_records, actual_process_fps)
    frequency_curve, events, freq_summary = compute_frequency(
        frequency_records, duration_sec, actual_process_fps
    )

    target_ratio = float(np.mean(target_detected)) if target_detected else 0.0
    other_ratio = float(np.mean(other_hand_detected)) if other_hand_detected else 0.0
    other_edge_ratio = float(np.mean(other_hand_edge_touch)) if other_hand_edge_touch else 0.0
    contact_mean = finite_mean([r.get("contact_score") for r in frame_records]) or 0.0
    raw_finger_contact_ratio = (
        float(np.mean([bool(r.get("finger_contact_detected")) for r in frame_records]))
        if frame_records
        else 0.0
    )
    finger_contact_ratio = float(trajectory_stats["filled_valid_ratio"])

    target_visible = target_ratio >= 0.50
    landmark_pressing_present = other_ratio >= 0.18
    pressing_present = landmark_pressing_present
    # A normal pressing hand can touch the image edge because the wrist/forearm
    # enters from outside the frame. Treat it as usable when it is consistently
    # detected; keep edge_touch_ratio as the stricter diagnostic.
    pressing_in_frame: Optional[bool]
    if landmark_pressing_present:
        pressing_in_frame = other_ratio >= 0.45 or other_edge_ratio < 0.75
    else:
        pressing_in_frame = None
    orientation_score = finite_median(target_orientation_scores)
    frequency_reliable = target_visible and finger_contact_ratio >= 0.35
    if not frequency_reliable:
        frequency_curve = []
        events = []
        freq_summary = {
            "mean_frequency_hz": None,
            "frequency_std_hz": None,
            "cycle_count": 0,
        }

    frequency_source = None
    if frequency_reliable:
        frequency_source = (
            "heuristic_fingertip_interpolated"
            if trajectory_stats["interpolated_count"]
            else "heuristic_fingertip"
        )

    mean_u = finite_mean([r.get("u") for r in frequency_records])
    mean_v = finite_mean([r.get("v") for r in frequency_records])
    std_u = finite_std([r.get("u") for r in frequency_records])
    std_v = finite_std([r.get("v") for r in frequency_records])

    result: Dict[str, Any] = {
        "video_id": row.video_id,
        "file": row.file,
        "target": row.target,
        "region_hint": row.region_hint,
        "duration_sec": round(duration_sec, 4),
        "source_fps": round(source_fps, 4),
        "process_fps": round(actual_process_fps, 4),
        "sample_interval_sec": sample_interval_sec,
        "manual_label": {
            "position": row.position_label,
            "frequency": row.frequency_label,
            "issue": row.issue_label,
        },
        "quality": {
            "target_region_visible": target_visible,
            "target_hand_detected_ratio": round(target_ratio, 4),
            "pressing_hand_present": bool(pressing_present),
            "pressing_hand_landmark_present": bool(landmark_pressing_present),
            "pressing_hand_detected_ratio": round(other_ratio, 4),
            "finger_contact_raw_ratio": round(raw_finger_contact_ratio, 4),
            "finger_contact_sample_ratio": round(finger_contact_ratio, 4),
            "finger_contact_filtered_ratio": round(float(trajectory_stats["filtered_valid_ratio"]), 4),
            "finger_contact_interpolated_count": int(trajectory_stats["interpolated_count"]),
            "finger_contact_outlier_count": int(trajectory_stats["outlier_count"]),
            "pressing_hand_in_frame": pressing_in_frame,
            "pressing_hand_edge_touch_ratio": round(other_edge_ratio, 4),
            "frequency_reliable": bool(frequency_reliable),
            "frequency_source": frequency_source,
            "orientation_issue_from_manual": row.issue_label == "orientation_wrong",
            "orientation_score_heuristic": round(orientation_score, 5) if orientation_score is not None else None,
            "mean_contact_score": round(contact_mean, 4),
            "confidence": round(float(np.mean([target_ratio, finger_contact_ratio, min(1.0, contact_mean), 1.0 - min(1.0, other_edge_ratio)])), 4),
        },
        "coordinate_system": {
            "type": "target_hand_local_2d",
            "u_axis": "wrist_to_middle_mcp; positive toward fingers, negative toward forearm",
            "v_axis": "index_mcp_to_pinky_mcp, orthogonalized to u_axis",
            "scale": "max(distance(wrist,middle_mcp), distance(index_mcp,pinky_mcp)) per frame",
            "units": "target-hand-scale-normalized",
        },
        "relative_location_samples": sample_records,
        "press_or_rub_events": events,
        "frequency_curve": frequency_curve,
        "summary": {
            **freq_summary,
            "mean_u": round(mean_u, 4) if mean_u is not None else None,
            "mean_v": round(mean_v, 4) if mean_v is not None else None,
            "std_u": round(std_u, 4) if std_u is not None else None,
            "std_v": round(std_v, 4) if std_v is not None else None,
        },
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{row.video_id}.json"
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def write_index(results: List[Dict[str, Any]], output_dir: Path) -> None:
    rows = []
    for result in results:
        summary = result["summary"]
        quality = result["quality"]
        rows.append(
            {
                "video_id": result["video_id"],
                "target": result["target"],
                "region_hint": result["region_hint"],
                "manual_position": result["manual_label"]["position"],
                "manual_frequency": result["manual_label"]["frequency"],
                "manual_issue": result["manual_label"]["issue"],
                "mean_frequency_hz": summary["mean_frequency_hz"],
                "frequency_std_hz": summary["frequency_std_hz"],
                "cycle_count": summary["cycle_count"],
                "mean_u": summary["mean_u"],
                "mean_v": summary["mean_v"],
                "std_u": summary["std_u"],
                "std_v": summary["std_v"],
                "target_hand_detected_ratio": quality["target_hand_detected_ratio"],
                "pressing_hand_detected_ratio": quality["pressing_hand_detected_ratio"],
                "finger_contact_sample_ratio": quality["finger_contact_sample_ratio"],
                "pressing_hand_in_frame": quality["pressing_hand_in_frame"],
                "frequency_source": quality["frequency_source"],
                "frequency_reliable": quality["frequency_reliable"],
                "confidence": quality["confidence"],
            }
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / "index.csv"
    if not rows:
        csv_path.write_text("", encoding="utf-8")
        return
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video-dir", type=Path, default=Path("drive-download-20260620T234210Z-3-001"))
    parser.add_argument("--labels", type=Path, default=Path("data/labels.csv"))
    parser.add_argument("--output-dir", type=Path, default=Path("outputs/json"))
    parser.add_argument("--process-fps", type=float, default=12.0)
    parser.add_argument("--sample-interval-sec", type=float, default=0.5)
    parser.add_argument("--max-width", type=int, default=960)
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--video-id", action="append", help="Run only this video id. Can be repeated.")
    parser.add_argument("--write-overlays", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = load_labels(args.labels)
    if args.video_id:
        wanted = set(args.video_id)
        rows = [row for row in rows if row.video_id in wanted]
    if args.limit is not None:
        rows = rows[: args.limit]

    overlay_dir = Path("diagnostics/overlays") if args.write_overlays else None
    results: List[Dict[str, Any]] = []
    mp_hands = mp.solutions.hands
    mp_selfie_segmentation = mp.solutions.selfie_segmentation
    for row in rows:
        video_path = args.video_dir / row.file
        if not video_path.exists():
            print(f"SKIP missing {video_path}", flush=True)
            continue
        print(f"extract {row.video_id} {video_path}", flush=True)
        with mp_hands.Hands(
            static_image_mode=True,
            max_num_hands=4,
            model_complexity=1,
            min_detection_confidence=0.35,
            min_tracking_confidence=0.35,
        ) as hands_model, mp_selfie_segmentation.SelfieSegmentation(
            model_selection=1
        ) as segmentation_model:
            result = extract_video(
                row=row,
                video_path=video_path,
                output_dir=args.output_dir,
                hands_model=hands_model,
                segmentation_model=segmentation_model,
                process_fps=args.process_fps,
                sample_interval_sec=args.sample_interval_sec,
                max_width=args.max_width,
                overlay_dir=overlay_dir,
            )
            results.append(result)
            print(
                "  mean_hz={hz} cycles={cycles} mean_uv=({u},{v}) confidence={conf}".format(
                    hz=result["summary"]["mean_frequency_hz"],
                    cycles=result["summary"]["cycle_count"],
                    u=result["summary"]["mean_u"],
                    v=result["summary"]["mean_v"],
                    conf=result["quality"]["confidence"],
                ),
                flush=True,
            )

    write_index(results, args.output_dir)
    print(f"wrote {len(results)} json files to {args.output_dir}", flush=True)


if __name__ == "__main__":
    main()
