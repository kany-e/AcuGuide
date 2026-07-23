#!/usr/bin/env python3
"""Render AcuGuide's fixed spoken script to AAC clips with Kokoro (Apache-2.0).

Input : voice_manifest.json  (dumped by VoiceScriptTests, so it matches the app exactly)
Output: out_clips/<key>.m4a  — bundled into the app as VoiceClips/
        samples/             — voice-comparison + pronunciation-check clips to listen to
"""
import json, os, sys, wave, array, subprocess, time

D = "kokoro-multi-lang-v1_1"
OUT = "out_clips"
SAMPLES = "samples"

# Voice ids are indices into the alphabetically-sorted voice list:
#   0 af_maple, 1 af_sol, 2 bf_vale (English) then 3.. zf_001... (Chinese)
EN_SID = int(os.environ.get("EN_SID", 0))    # af_maple
ZH_SID = int(os.environ.get("ZH_SID", 3))    # zf_001
SPEED = float(os.environ.get("SPEED", 1.0))

import sherpa_onnx

def make_tts():
    cfg = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=f"{D}/model.onnx", voices=f"{D}/voices.bin", tokens=f"{D}/tokens.txt",
                data_dir=f"{D}/espeak-ng-data", dict_dir=f"{D}/dict",
                lexicon=f"{D}/lexicon-us-en.txt,{D}/lexicon-zh.txt",
            ),
            num_threads=max(4, os.cpu_count() or 4), provider="cpu",
        ),
        max_num_sentences=1,
    )
    return sherpa_onnx.OfflineTts(cfg)

def write_wav(path, audio):
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(audio.sample_rate)
        pcm = array.array("h", [int(max(-1.0, min(1.0, s)) * 32767) for s in audio.samples])
        w.writeframes(pcm.tobytes())

def to_m4a(wav, m4a, bitrate="48000"):   # -b is bits/sec => 48 kbps, mono 24 kHz AAC
    # afconvert is Apple's own encoder — AAC-LC mono, ideal for short speech clips.
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac@24000", "-b", bitrate,
                    "--mix", "-c", "1", wav, m4a],
                   check=True, capture_output=True)

def main():
    tts = make_tts()
    man = json.load(open("voice_manifest.json"))
    os.makedirs(OUT, exist_ok=True); os.makedirs(SAMPLES, exist_ok=True)

    if "--samples-only" in sys.argv:
        en_line = "That's the spot — settle in gently. Keep it steady, breathe slow."
        zh_line = "就是这里 — 轻轻稳住。跟着呼吸，慢慢画小圈。"
        pron = "Zhongzhu. On the back of the hand, in the groove behind the heads of the 4th and 5th metacarpals."

        # FLUENCY A/B. The user's report was that the voice "sounds connected, not fluent enough",
        # and the cause turned out to be the punctuation handed to the model, not the model: every
        # clause was joined with an ASCII ". " in BOTH languages, so a Chinese phonemizer saw no
        # sentence boundary at all and read the whole read-aloud as one run-on — plus the source
        # strings already ended in a terminator, so 16 clips carried a doubled stop. These pairs are
        # the SAME sentence with the old and new punctuation, so the difference is audible directly.
        # (Acupoint.spokenInfo now strips each part's terminator and rejoins with 。 or ". ".)
        zh_old = "中渚. 在手背，第4、5掌骨小头后方的凹陷处（无名指与小指掌指关节后方的凹沟）。. 手背朝上。沿无名指与小指指节之间的缝向下滑，指节后方能摸到两根手骨之间的小凹陷。"
        zh_new = "中渚。在手背，第4、5掌骨小头后方的凹陷处（无名指与小指掌指关节后方的凹沟）。手背朝上。沿无名指与小指指节之间的缝向下滑，指节后方能摸到两根手骨之间的小凹陷。"
        en_old = "Zhongzhu. On the back of the hand, in the groove behind the heads of the 4th and 5th metacarpals (behind the ring- and little-finger knuckles).. Back of the hand up."
        en_new = "Zhongzhu. On the back of the hand, in the groove behind the heads of the 4th and 5th metacarpals (behind the ring- and little-finger knuckles). Back of the hand up."

        jobs = ([(f"EN-voice{n}_{nm}", en_line, s, SPEED) for n, (s, nm) in enumerate([(0,"af_maple"),(1,"af_sol"),(2,"bf_vale")])]
              + [(f"EN-pronunciation_{nm}", pron, s, SPEED) for s, nm in [(0,"af_maple")]]
              + [(f"ZH-voice{n}_{nm}", zh_line, s, SPEED) for n, (s, nm) in enumerate([(3,"zf_001"),(4,"zf_002"),(9,"zf_008")])]
              # A/B the fix itself, in the shipping voice.
              + [("FLUENCY-zh-1-BEFORE", zh_old, ZH_SID, SPEED),
                 ("FLUENCY-zh-2-AFTER",  zh_new, ZH_SID, SPEED),
                 ("FLUENCY-en-1-BEFORE", en_old, EN_SID, SPEED),
                 ("FLUENCY-en-2-AFTER",  en_new, EN_SID, SPEED)]
              # Pace: a coaching read usually wants to be slower than 1.0.
              + [(f"PACE-zh-{sp}", zh_new, ZH_SID, sp) for sp in (0.85, 0.9, 1.0)]
              + [(f"PACE-en-{sp}", en_new, EN_SID, sp) for sp in (0.85, 0.9, 1.0)])

        for tag, text, sid, speed in jobs:
            a = tts.generate(text, sid=sid, speed=speed)
            wav = f"{SAMPLES}/{tag}.wav"; write_wav(wav, a); to_m4a(wav, f"{SAMPLES}/{tag}.m4a"); os.remove(wav)
            print(f"  sample {tag}: {len(a.samples)/a.sample_rate:.1f}s", flush=True)
        return

    t0 = time.time(); total_dur = 0.0
    for i, item in enumerate(man, 1):
        key, locale, text = item["key"], item["locale"], item["text"]
        m4a = f"{OUT}/{key}.m4a"
        if os.path.exists(m4a):
            continue
        sid = EN_SID if locale == "en-US" else ZH_SID
        a = tts.generate(text, sid=sid, speed=SPEED)
        total_dur += len(a.samples) / a.sample_rate
        wav = f"{OUT}/{key}.wav"; write_wav(wav, a); to_m4a(wav, m4a); os.remove(wav)
        if i % 10 == 0 or i == len(man):
            print(f"  {i}/{len(man)}  audio {total_dur/60:.1f}min  elapsed {(time.time()-t0)/60:.1f}min", flush=True)

    size = sum(os.path.getsize(f"{OUT}/{f}") for f in os.listdir(OUT) if f.endswith(".m4a"))
    print(f"DONE: {len(os.listdir(OUT))} clips, {total_dur/60:.1f} min audio, {size/1048576:.2f} MB")

if __name__ == "__main__":
    main()
