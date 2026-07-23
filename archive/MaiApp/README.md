# 诗词山河 · 经络图谱 · Poetic Meridian Atlas (3D)

A bilingual (中文 / English) acupuncture meridian atlas with a rotatable **3D body**
rendered in three.js / react-three-fiber, dressed in an ink-and-gold aesthetic with
glowing meridian channels. Tap the hand to drop into a detailed 2D hand view with
verified acupoints and a bilingual panel.

It **ships with a real rigged human mesh** (a single skinned mesh + skeleton, i.e. how
game characters are actually built), so it looks like a real model out of the box. Swap
in a higher-fidelity one whenever you want by replacing one file.

## Run it

```bash
npm install
npm run dev
```

Open the URL Vite prints (usually http://localhost:5173). Drag to rotate (it also
auto-rotates). Tap the glowing hand marker to enter the hand view.

## Swapping in a more realistic body (one file)

The app loads `public/model.glb` and **auto-fits any model**: it stands it upright,
scales it to height, and grounds the feet. So you can drop in almost any rigged human
`.glb` and it just works. Good free sources for a realistic / game-quality character:

- **Mixamo** (mixamo.com, free Adobe account): pick a character, download as `.glb` (or
  FBX then convert). This is the standard pipeline for rigged game characters.
- **Ready Player Me** (readyplayer.me): generate an avatar, download the `.glb`.
- **Sketchfab** (sketchfab.com): filter Downloadable + CC0 / CC-BY for scanned realistic humans.

Save the file as `public/model.glb`, replacing the bundled sample. No code changes needed
thanks to the auto-fit. If a model faces the wrong way on load, it still reads fine because
the scene auto-rotates; to lock a facing, add a `rotation` to the `<primitive>` in
`GLBModel()` (src/Body3D.jsx).

## Tuning the meridian channels

Channels are 3D tubes routed along standing-pose landmarks at the top of `src/Body3D.jsx`
(`ARM_L`, `LEG_L`, `REN`). They assume an arms-down pose. If your model stands in a T- or
A-pose (arms out), nudge those arrays so the tubes sit on its arms. The right side mirrors
automatically. Use the legend on the right to solo a single meridian.

## Project structure

```
meridian-atlas-app/
├── index.html
├── package.json            # react, three, @react-three/fiber, drei, postprocessing, vite
├── vite.config.js
├── public/
│   └── model.glb           # bundled sample rigged human (swap for your own)
└── src/
    ├── main.jsx
    ├── MeridianAtlas.jsx   # shell: top bar, legend, detail panel, body/hand switch
    ├── Body3D.jsx          # three.js scene: model (auto-fit) + channels + hand hotspot
    ├── HandView.jsx        # detailed 2D hand with verified acupoints
    ├── data.js             # acupoints, meridians, bilingual strings
    └── styles.css          # ink / 古风 theme
```

## Attribution & license

- three.js, @react-three/fiber, @react-three/drei, @react-three/postprocessing: all MIT.
- Bundled sample model: **CesiumMan**, (c) Cesium, licensed **CC BY 4.0**, via the Khronos
  glTF Sample Assets. If you ship it, keep this attribution; or replace it with your own /
  CC0 model.
- Acupoint reference text is factual/educational, written for this project, and verified
  against standard / WHO-aligned references.

## Disclaimer

For educational and cultural reference only. Not medical advice, diagnosis, or treatment.
