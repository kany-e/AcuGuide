# AR-Coach Hand/Wrist Targets — Sources & Vision-Landmark Mapping

The AR coach (`ARCoachView` → `CoachEngine`) locates an acupoint as a **weighted blend of Apple
Vision hand-pose joints** on the *receiving* hand, then watches the *pressing* hand's fingertip.
Vision tracks only hand joints (no forearm), and `handSize = dist(wrist, middleMCP)` is the scale
unit; tolerances are a fraction of `handSize`.

Each target's surface location is the **WHO Standard Acupuncture Point Locations (2008)**; the
landmark blend is an engineering approximation of that location, verified per-point (workflow
`ar-hand-targets`). Weights may be negative to extrapolate; the engine divides by Σweights.
Definitions live in `Acupoints.swift` (`mediapipeTarget`).

| Point | Surface | Blend (joint: weight) | tol×handSize | Reliability |
|---|---|---|---|---|
| **TE3** 中渚 | dorsal, between 4th/5th MC, proximal to 4th MCP | ringMCP .46 / pinkyMCP .34 / wrist .20 | 0.16 | high *(on-device validated)* |
| **SI3** 后溪 | ulnar border, proximal to 5th MCP (red/white flesh) | pinkyMCP .85 / wrist .35 / ringMCP −.20 | 0.15 | medium |
| **PC8** 劳宫 | palm centre, between 2nd/3rd MC, proximal to MCP | middleMCP .50 / indexMCP .18 / wrist .32 | 0.16 | high |
| **HT7** 神门 | palmar wrist crease, ulnar end | wrist .85 / pinkyMCP .15 | 0.13 | medium |
| **PC7** 大陵 | palmar wrist crease midpoint (PL/FCR) | wrist .90 / middleMCP .10 | 0.12 | medium |
| **TE4** 阳池 | dorsal wrist crease, ulnar to ext. digitorum | wrist .84 / middleMCP .09 / ringMCP .07 | 0.16 | medium |
| **PC6** 内关 | palmar forearm, **2 cun proximal** to wrist crease | wrist 1.85 / middleMCP −.85 *(extrapolated)* | 0.22 | **low** |
| **SJ5/TE5** 外关 | dorsal forearm, 2 cun proximal (opposite PC6) | wrist 2.6 / middleMCP −1.6 *(extrapolated)* | 0.28 | **low** |

**Reliability** = how well the WHO location can be hit from hand landmarks alone. PC6/SJ5 are on the
forearm, which Vision does not track, so they are extrapolated up the forearm axis (`wrist +
k·(wrist − middleMCP)`) with wide tolerance and a low-confidence caveat. LI4 is excluded entirely
(pregnancy-contraindicated). All copy stays wellness-only (no treat/cure/heal/diagnose).

## Citations (WHO + authoritative atlases)

- **TE3 Zhongzhu** — WHO 2008 (iris.who.int/handle/10665/206847); meandqi.com/.../zhongzhu-sj-3; tcmwiki.com/wiki/te3
- **SI3 Houxi** — evidencebasedacupuncture.org/smallintestine/si3-hou-xi; meandqi.com/.../houxi-si-3; acupoints.org/si3-acupuncture-point
- **PC8 Laogong** — meandqi.com/.../laogong-pc-8; evidencebasedacupuncture.org/pericardium/pc8-lao-gong; yinyanghouse.com/.../pc8
- **HT7 Shenmen** — meandqi.com/.../shenmen-ht-7; evidencebasedacupuncture.org/heart/ht7-shen-men; acupuncture.com/.../heart/ht7
- **PC7 Daling** — meandqi.com/.../daling-pc-7; iaomai.app/.../PC7-daling
- **TE4 Yangchi** — acupoints.org/te4-acupuncture-point; sacredlotus.com/.../sj-04-yang-chi; meandqi.com/acupuncture-points/yangchi
- **PC6 Neiguan** — WHO 2008 (who.int/publications/i/item/9789290613831); morningsideacupuncturenyc.com/blog/pc6-acupuncture-point
- **SJ5/TE5 Waiguan** — WHO 2008 (wpro.who.int/.../who_standard_acupuncture_point_locations_2008); sportsmedicineacupuncture.com/san-jiao-5-waiguan; iaomai.app/.../TE5-waiguan

See also `eight_points_citations.md` (evidence strength) and `acupoint_sources_by_type.md`.
