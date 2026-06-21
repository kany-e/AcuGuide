#!/usr/bin/env python3
"""Generate 5 fake FrameState replay fixtures for AcuGuide CV demo.
Each file = Person A's output stream (per-frame) + ground-truth labels,
so Person B can build/test the temporal+coaching layer with no camera.

v2 tightening:
- Taps START RELEASED (d=dmax at t=0) -> exact press counts (5 / 10), no +1 artifact.
- PC6 uses a larger tap amplitude so the fingertip actually CLEARS its (large) exit
  radius between fast taps -> genuine SEARCHING gaps, so the test needs no PAUSED leniency.
- Added expected_motion to each fixture's ground truth.

Run:  python generate_fixtures.py   (writes the 5 fixture_*.json files in this folder)
"""
import json, math, random

random.seed(7)
FPS = 30

# ---- base hand poses (normalized image coords: x right, y down) -------------
DORSAL = [
    (0.50,0.85,0.00),(0.40,0.80,0.01),(0.34,0.72,0.01),(0.30,0.66,0.01),(0.27,0.60,0.01),
    (0.44,0.55,0.00),(0.43,0.45,-0.01),(0.42,0.38,-0.01),(0.42,0.32,-0.01),
    (0.50,0.53,0.00),(0.50,0.42,-0.01),(0.50,0.34,-0.01),(0.50,0.28,-0.02),
    (0.56,0.55,0.00),(0.57,0.45,-0.01),(0.58,0.38,-0.01),(0.58,0.32,-0.01),
    (0.62,0.58,0.00),(0.64,0.50,-0.01),(0.65,0.44,-0.01),(0.66,0.40,-0.01)]
PALMAR = [
    (0.50,0.55,0.00),(0.60,0.50,0.01),(0.66,0.42,0.01),(0.70,0.36,0.01),(0.73,0.30,0.01),
    (0.56,0.25,0.00),(0.57,0.16,-0.01),(0.58,0.10,-0.01),(0.58,0.05,-0.01),
    (0.50,0.23,0.00),(0.50,0.13,-0.01),(0.50,0.06,-0.01),(0.50,0.02,-0.02),
    (0.44,0.25,0.00),(0.43,0.16,-0.01),(0.42,0.10,-0.01),(0.42,0.05,-0.01),
    (0.38,0.28,0.00),(0.36,0.20,-0.01),(0.35,0.14,-0.01),(0.34,0.10,-0.01)]

def dist(a,b): return math.hypot(a[0]-b[0], a[1]-b[1])
def jitter(p,s=0.004): return [round(p[0]+random.gauss(0,s),4), round(p[1]+random.gauss(0,s),4), round(p[2]+random.gauss(0,s/2),4)]
def hand_size(lm): return dist(lm[0], lm[9])

def te3_target(lm):
    x = 0.45*lm[13][0] + 0.40*lm[17][0] + 0.15*lm[0][0]
    y = 0.45*lm[13][1] + 0.40*lm[17][1] + 0.15*lm[0][1]
    return (round(x,4), round(y,4))

def pc6_target(lm):  # off-model: extrapolate from wrist along forearm axis
    ax, ay = lm[0][0]-lm[9][0], lm[0][1]-lm[9][1]
    n = math.hypot(ax,ay) or 1e-6
    ax, ay = ax/n, ay/n
    hs = hand_size(lm)
    return (round(lm[0][0] + 1.1*hs*ax, 4), round(lm[0][1] + 1.1*hs*ay, 4))

def frame(i, t, *, present=True, face="dorsal", base=DORSAL, point="TE3",
          tip_dist=None, finger_present=True, contact_part="tip",
          wrist_in_frame=True, low_light=False, conf=0.92, press_dmax=0.10):
    if not present:
        return {"t": round(t,3), "frameIndex": i, "fps": FPS,
                "receivingHand": {"present": False, "handedness": None, "face": "unknown",
                                   "handSize": None, "landmarks": None},
                "pressingFinger": {"present": False, "contactPart": None, "tipXY": None, "tipLandmark": None},
                "target": {"id": point, "xy": None, "toleranceR": None,
                           "trackable": "off_model_extrapolated" if point=="PC6" else "on_model"},
                "contact": {"onTarget": False, "offset_xHandSize": None, "depthProxy": 0.0,
                            "insideEnterRadius": False, "insideExitRadius": False},
                "quality": {"confidence": 0.0, "lowLight": low_light, "wristInFrame": False}}
    lm = [jitter(p) for p in base]
    hs = round(hand_size(lm), 4)
    tgt = pc6_target(lm) if point=="PC6" else te3_target(lm)
    tol = round((0.22 if point=="PC6" else 0.16) * hs, 4)
    fp = {"present": False, "contactPart": None, "tipXY": None, "tipLandmark": None}
    contact = {"onTarget": False, "offset_xHandSize": None, "depthProxy": 0.0,
               "insideEnterRadius": False, "insideExitRadius": False}
    if finger_present and tip_dist is not None:
        dirx, diry = 0.6, 0.8
        tipx = round(tgt[0] + dirx*tip_dist + random.gauss(0,0.003), 4)
        tipy = round(tgt[1] + diry*tip_dist + random.gauss(0,0.003), 4)
        off = round(tip_dist / hs, 4)
        enter = tip_dist < tol
        exit_ = tip_dist < tol*1.6
        depth = round(max(0.0, 1.0 - tip_dist/press_dmax), 3)
        fp = {"present": True, "contactPart": contact_part, "tipXY": [tipx, tipy], "tipLandmark": 4}
        contact = {"onTarget": bool(enter), "offset_xHandSize": off, "depthProxy": depth,
                   "insideEnterRadius": bool(enter), "insideExitRadius": bool(exit_)}
    return {"t": round(t,3), "frameIndex": i, "fps": FPS,
            "receivingHand": {"present": True, "handedness": "Right", "face": face,
                               "handSize": hs, "landmarks": lm},
            "pressingFinger": fp,
            "target": {"id": point, "name": "Zhongzhu" if point=="TE3" else "Neiguan",
                       "surface": "dorsal" if point=="TE3" else "palmar",
                       "xy": list(tgt), "toleranceR": tol,
                       "trackable": "off_model_extrapolated" if point=="PC6" else "on_model"},
            "contact": contact,
            "quality": {"confidence": round(conf+random.gauss(0,0.02),3), "lowLight": low_light,
                        "wristInFrame": wrist_in_frame}}

def tap_distance(t, freq, dmax=0.10):
    """START RELEASED: d=dmax at t=0, reaches 0 (on target) once per cycle."""
    return round(dmax * (0.5 + 0.5*math.cos(2*math.pi*freq*t)), 4)

def build(seconds, fn):
    return [fn(i, i/FPS) for i in range(int(seconds*FPS))]

def write(name, meta, frames):
    doc={"_meta": meta, "frames": frames}
    with open(name,"w") as f: json.dump(doc,f,ensure_ascii=False,indent=1)
    presses=0; prev=False; disengaged=0
    for fr in frames:
        on=fr["contact"]["insideEnterRadius"]
        if on and not prev: presses+=1
        prev=on
        if fr["contact"]["onTarget"] is False and fr["receivingHand"]["present"] and not fr["contact"]["insideExitRadius"]:
            disengaged+=1
    print(f"{name}: frames={len(frames)} presses(enter-edges)={presses} disengaged_frames={disengaged}")

# 1) TE3 correct + good rhythm (~5 taps / 10s -> freq 0.5)
write("fixture_1_te3_correct_good_rhythm.json",
  {"fixtureLabel":"A_correct_good_rhythm","point":"TE3","surface":"dorsal","durationSec":10,"fps":FPS,
   "scenario":"Hand present (back to camera), fingertip taps the TE3 zone with a steady ~0.5 Hz rhythm.",
   "groundTruth":{"expected_phase_sequence":["SEARCHING","HOLDING/tap"],"expected_pressCount":5,
                  "expected_rhythm":"rhythm_good","expected_motion":"repeated","onTarget_at_each_tap_peak":True}},
  build(10, lambda i,t: frame(i,t, point="TE3", face="dorsal", base=DORSAL,
                              tip_dist=tap_distance(t,0.5,0.10), press_dmax=0.10)))

# 2) TE3 wrong position (finger held off-target the whole time)
write("fixture_2_te3_wrong_position.json",
  {"fixtureLabel":"A_wrong_position","point":"TE3","surface":"dorsal","durationSec":8,"fps":FPS,
   "scenario":"Hand present, but pressing fingertip stays ~0.18 away from the TE3 zone (never enters).",
   "groundTruth":{"expected_phase_sequence":["WRONG_POSITION"],"expected_pressCount":0,
                  "expected_rhythm":"n/a","expected_motion":"n/a","onTarget":False}},
  build(8, lambda i,t: frame(i,t, point="TE3", face="dorsal", base=DORSAL, tip_dist=0.18)))

# 3) PC6 correct + too fast (~10 taps / 10s -> freq 1.0), off-model; dmax clears exit radius
write("fixture_3_pc6_correct_too_fast.json",
  {"fixtureLabel":"B_correct_too_fast","point":"PC6","surface":"palmar","durationSec":10,"fps":FPS,
   "scenario":"Palm-up forearm in frame; fingertip taps the extrapolated PC6 zone too quickly (~1 Hz). Taps fully clear the zone between presses.",
   "notes":"PC6 is OFF-MODEL: target extrapolated from wrist along forearm axis; wristInFrame must be true.",
   "groundTruth":{"expected_phase_sequence":["SEARCHING","HOLDING/tap"],"expected_pressCount":10,
                  "expected_rhythm":"rhythm_too_fast","expected_motion":"repeated"}},
  build(10, lambda i,t: frame(i,t, point="PC6", face="palmar", base=PALMAR,
                              tip_dist=tap_distance(t,1.0,0.16), wrist_in_frame=True, conf=0.80, press_dmax=0.16)))

# 4) no hand (background only) + brief partial hand at the end
def f4(i,t):
    if t < 7.0:
        return frame(i,t, present=False, point="TE3")
    fr = frame(i,t, point="TE3", face="unknown", base=DORSAL, tip_dist=None,
               finger_present=False, wrist_in_frame=False, conf=0.35)
    fr["quality"]["confidence"]=round(0.35+random.gauss(0,0.03),3)
    return fr
write("fixture_4_no_hand_then_partial.json",
  {"fixtureLabel":"no_hand / partial_hand","point":"TE3","durationSec":9,"fps":FPS,
   "scenario":"First 7s empty background (no hand), then a partial low-confidence hand enters.",
   "groundTruth":{"expected_phase_sequence":["NO_HAND","(partial->still NO_HAND/low_conf)"],
                  "expected_pressCount":0,"expected_rhythm":"n/a","expected_motion":"n/a"}},
  build(9, f4))

# 5) TE3 full end-to-end flow through every state (the integration 'hello world')
def f5(i,t):
    if t < 1.5:
        return frame(i,t, present=False, point="TE3")
    if t < 3.0:
        return frame(i,t, point="TE3", face="palmar", base=PALMAR, tip_dist=None, finger_present=False)
    if t < 4.5:
        return frame(i,t, point="TE3", face="dorsal", base=DORSAL, tip_dist=0.14)
    if t < 5.5:
        return frame(i,t, point="TE3", face="dorsal", base=DORSAL,
                     tip_dist=max(0.0, 0.05+0.03*math.sin(2*math.pi*2.0*t)))
    return frame(i,t, point="TE3", face="dorsal", base=DORSAL, tip_dist=tap_distance(t,0.5,0.10), press_dmax=0.10)
write("fixture_5_te3_full_flow.json",
  {"fixtureLabel":"te3_full_flow","point":"TE3","surface":"dorsal","durationSec":12,"fps":FPS,
   "scenario":"End-to-end: no_hand -> wrong_face -> searching -> on_target_unstable -> holding/tap good rhythm -> complete.",
   "groundTruth":{"expected_phase_sequence":["NO_HAND","WRONG_FACE","SEARCHING","ON_TARGET_UNSTABLE","HOLDING","COMPLETE"],
                  "expected_rhythm":"rhythm_good","expected_motion":"repeated","note":"use as the integration smoke test (A->B->UI)."}},
  build(12, f5))

print("done")
