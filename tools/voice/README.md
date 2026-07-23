# Pre-rendered voice clips

The app's spoken audio (`AcuGuide/VoiceClips/*.m4a`) is **rendered offline**, not synthesized on the
device. This directory holds the pipeline that produces it.

## Why pre-rendered

Every line AcuGuide speaks is a **fixed literal string** — the coach/locate phrase tables in
`Speech.swift` and the acupoint read-aloud (`Acupoint.spokenInfo`), which comes from the dataset.
Nothing user-generated or LLM-written is ever voiced (the chat is not spoken). So the whole script can
be rendered once with a good neural voice and shipped as audio:

|                        | Pre-rendered clips        | On-device neural engine        |
|------------------------|---------------------------|--------------------------------|
| Quality                | Kokoro (neural)           | Kokoro (neural)                |
| App/disk cost          | **~4.6 MB**               | ~250 MB (runtime + model)      |
| Latency                | none (file playback)      | seconds/utterance on CPU       |
| Risk                   | none at runtime           | memory, latency, GPL phonemizer|

Apple's own "enhanced/premium" voices were the alternative, but an app **cannot** trigger their
download, and deep-linking to that Settings pane is private API (App Store guideline 2.5.1) — so the
user would have to find it themselves, and Chinese caps at "Enhanced". Pre-rendering removes that step.

## How it works

1. `VoiceScript.allLines()` (in `AcuGuide/VoiceClips.swift`) enumerates every spoken line in **both**
   languages by calling the real phrase tables — so the render list cannot drift from what's spoken.
2. `VoiceScriptTests.testDumpVoiceScriptManifest` prints that list as JSON between
   `<<<VOICE_SCRIPT_BEGIN>>>` / `<<<VOICE_SCRIPT_END>>>` markers.
3. `render_voice.py` renders each line and encodes it to AAC named `<key>.m4a`, where
   `key = sha256("<locale>|<normalized text>").digest()[:16].hex()` — the first 16 **bytes** of the
   digest, i.e. a **32-character** hex filename. Same key `VoiceClips.key(_:locale:)` computes at runtime.
4. The clips ship as a **folder reference** (`project.yml` declares `AcuGuide/VoiceClips` with
   `type: folder`) so they land in `AcuGuide.app/VoiceClips/` rather than being flattened into the
   bundle root. At runtime `CoachVoice`/`AtlasSpeaker` look the clip up and play it; **if it's missing
   they fall back to `AVSpeechSynthesizer`**, so a reworded or new line is still spoken, in the system voice.
5. `VoiceScriptTests` catches drift in **both** directions at build time:
   `testEverySpokenLineHasABundledClip` fails on a line with no clip, and
   `testNoOrphanedClipsAreShipped` fails on a clip no line can reach (re-rendering copies in but never
   prunes). `SafetyInvariantTests` additionally scans the spoken script for forbidden claim language —
   worth remembering that a bad line is baked into AUDIO and cannot be hot-fixed by editing a string.

## Re-rendering (after changing any spoken copy, or to change voice)

```bash
# 0. everything below runs from tools/voice/
cd "$(git rev-parse --show-toplevel)/tools/voice"

# 1. dump the manifest from the app's own phrase tables (make lives at the repo root)
(cd "$(git rev-parse --show-toplevel)" && make test) 2>&1 | tee /tmp/voice.log
python3 - <<'PY'
import re, json
log = open("/tmp/voice.log", errors="ignore").read()
m = re.search(r"<<<VOICE_SCRIPT_BEGIN>>>(.*?)<<<VOICE_SCRIPT_END>>>", log, re.S)
json.dump(json.loads(m.group(1)), open("voice_manifest.json", "w"), ensure_ascii=False, indent=1)
PY

# 2. get the model (Apache-2.0, ~350 MB, NOT committed) and the renderer
pip3 install sherpa-onnx
curl -L -o k.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_1.tar.bz2
tar xjf k.tar.bz2 && rm k.tar.bz2

# 3. render (~35 min for the full script) and install.
#    Start from an empty out_clips so a reworded line cannot leave its old clip behind, and REPLACE
#    the shipped directory rather than merging into it — testNoOrphanedClipsAreShipped fails on any
#    clip the script can no longer reach.
rm -rf out_clips
python3 render_voice.py
rm -f ../../AcuGuide/VoiceClips/*.m4a
cp out_clips/*.m4a ../../AcuGuide/VoiceClips/
#    voice_manifest.json stays HERE (tools/voice/) as the render record — it is deliberately not
#    shipped in the app bundle, because nothing reads it at runtime.

# voice comparison samples only (fast):
python3 render_voice.py --samples-only
```

Change the voice with `EN_SID` / `ZH_SID` (indices into the alphabetically-sorted voice list):
`0 af_maple`, `1 af_sol`, `2 bf_vale` (English), `3+` = `zf_001`… (100 Chinese voices).
Defaults are `EN_SID=0` (af_maple), `ZH_SID=3` (zf_001).

## Licensing

- **Model**: Kokoro-82M v1.1-zh — **Apache-2.0**, which permits shipping the generated audio commercially.
  Its `LICENSE` is in the downloaded model directory.
- **Runtime**: sherpa-onnx (Apache-2.0), used only as a build-time tool — it is **not** shipped in the app.
- espeak-ng (GPL) is used *build-time only* for English phonemization of out-of-vocabulary words. Using a
  GPL tool to produce output does not encumber the output, and no GPL code ships in the app.
- We deliberately do **not** render with Apple's system voices: redistributing their output as bundled app
  assets is a licensing grey area.

## Known limitation

~60 English words fall outside the model's 178k-word lexicon — mostly pinyin point names (*Zhongzhu*,
*Baihui*) and Latin anatomy (*palmaris*, *digitorum*) — and are phonemized by espeak's guesser, which can
mispronounce them. Fix by adding entries to `lexicon-us-en.txt` in the model directory before rendering.
