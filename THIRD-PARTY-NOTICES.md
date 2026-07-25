# Third-party notices

AcuGuide's own source is proprietary (see [LICENSE](LICENSE)). The components below are **not** —
each keeps its own license, and several require attribution that must be preserved when the app is
distributed. The same credits are shown in-app under **Settings → Licenses & credits**.

Full license texts are in [`licenses/`](licenses/).

---

## 3D models — CC-BY 4.0 (attribution required)

All three bundled models come from Sketchfab under
[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/). Authors and
titles were read from each file's embedded `asset.extras` metadata. **CC-BY requires that these
credits accompany any distribution of the app**, which is why they also appear on the in-app
Credits screen.

| File | Title | Author | License |
|---|---|---|---|
| `AcuGuide/Resources/model.glb` | Character Mannequin Male | [muh.nurzidan](https://sketchfab.com/muh.nurzidan) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `AcuGuide/Resources/arms_hands_head_legs_and_feet__low_poly_female.glb` | Arms, hands, head, legs and feet (low poly) — Female | [pnhtuan](https://sketchfab.com/pnhtuan7) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `AcuGuide/Resources/hand_low_poly.glb` | Hand (low poly) | [scribbletoad](https://sketchfab.com/scribbletoad) | [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

**Changes made:** the models were recolored and rescaled for display. CC-BY requires that
modifications be indicated; this notice is that indication.

---

## Fonts — SIL Open Font License 1.1

Bundled in `AcuGuide/Fonts/` and embedded in the app binary. OFL 1.1 requires that the license text
travel with the fonts — it is at [`licenses/OFL-1.1.txt`](licenses/OFL-1.1.txt).

| Font | Copyright | License |
|---|---|---|
| Cormorant Garamond (Light) | Copyright 2015 The Cormorant Project Authors ([CatharsisFonts/Cormorant](https://github.com/CatharsisFonts/Cormorant)) | [OFL 1.1](licenses/OFL-1.1.txt) |
| Ma Shan Zheng | Copyright 2018 The MaShanZheng Project Authors ([googlefonts/mashanzheng](https://github.com/googlefonts/mashanzheng)) | [OFL 1.1](licenses/OFL-1.1.txt) |

Both are used unmodified. Note OFL's Reserved Font Name clause: a modified version may not be
distributed under these font names.

---

## Voice — Apache-2.0

The spoken script ships as pre-rendered audio (`AcuGuide/VoiceClips/`, 102 clips). No TTS model is
bundled or executed on device; the model was run offline to produce the clips.

| Component | Role | License |
|---|---|---|
| [Kokoro-82M v1.1](https://huggingface.co/hexgrad/Kokoro-82M) | Text-to-speech model used offline to render the clips | [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Inference runtime for the offline render | [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0) |

The render pipeline is in [`tools/voice/`](tools/voice/). We credit Kokoro in-app and here as the
source of the shipped audio.

---

## Swift packages — MIT

| Package | Author | Pinned revision | License |
|---|---|---|---|
| [GLTFKit2](https://github.com/warrenm/GLTFKit2) | Warren Moore | `be89e833aa85bde67bd27d4ecff3b7816c58ce56` | MIT |

Resolved as a binary xcframework over the network on first `make project`.

---

## Reference data

Acupoint locations and classical descriptions are drawn from published references — the WHO
Standard Acupuncture Point Locations in the Western Pacific Region (2008), the *Atlas of
Acupuncture Points*, Yin Yang House, and OCOM's AcuTrials database. These are cited as **sources**,
not redistributed as datasets: the app ships its own bilingual descriptions written for it. Full
citations are on the in-app **Sources & Evidence** screen and in
[`claude-deliverables/references/`](claude-deliverables/references/).

---

## Archived prototypes

`archive/` contains superseded pre-iOS work (a React/MediaPipe prototype, a three.js atlas, a
vanilla-JS demo). Nothing there is part of the build or the shipped app. Any third-party
dependencies referenced by that code are covered by their own manifests and are not distributed in
the app binary.
