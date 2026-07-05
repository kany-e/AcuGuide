# AcuGuide Source Upgrade — verified reference data

Consolidated, adversarially-verified data behind the July 2026 content upgrade. Sources the user
supplied: **AcuTrials** (OCOM), **Yin Yang House**, **Atlas of Acupuncture Points** (chiro.org, 2007),
**TARA** (MGB/NCCIH), and **AcuSim** (Nature *Scientific Data* 2025).

Safety rule (unchanged): no user-facing copy may contain the substrings `treat / cure / heal / diagnos`
(note `heal` ⊂ `health`, so use "wellness" / "medical professional"). Enforced by
`AcuGuideTests.testNoForbiddenMedicalClaims` (extended to the new fields).

## 1. Classical point-category labels (Yin Yang House, each cross-verified on the live page)

| id | Classical role (EN) | 中文 |
|----|--------------------|------|
| TE3 | Shu-Stream (Wood) point of the Sanjiao channel | 手少阳三焦经 输(木)穴 |
| PC6 | Luo-Connecting & Command point of Pericardium; Master of Yin Wei vessel (with SP4) | 手厥阴心包经 络穴、八脉交会穴(通阴维,配公孙) |
| SJ5 | Luo-Connecting point of Sanjiao; Master of Yang Wei vessel (with GB41) | 手少阳三焦经 络穴、八脉交会穴(通阳维,配足临泣) |
| PC8 | Ying-Spring (Fire) point of Pericardium; Exit & Ghost point | 手厥阴心包经 荥(火)穴、出穴、鬼穴 |
| HT7 | Yuan-Source & Shu-Stream (Earth) point of Heart | 手少阴心经 原穴、输(土)穴 |
| SI3 | Shu-Stream (Wood) & Tonification point of Small Intestine; Master of Governing Vessel (with BL62) | 手太阳小肠经 输(木)穴、补穴;八脉交会穴(通督脉,配申脉) |
| EX-HN3 | Yintang — extra (non-channel) point between the eyebrows | 经外奇穴 印堂 |
| EX-HN5 | Taiyang — extra (non-channel) point at the temple | 经外奇穴 太阳 |
| GV20 | Sea-of-Marrow point; intersection of Du with Bladder/Gallbladder/Sanjiao/Liver | 督脉 百会;髓海、诸阳之会 |
| EX-HN1 | Sishencong — four extra points around GV20 at the vertex | 经外奇穴 四神聪 |
| CV17 | Hui-Meeting (Influential) point of Qi; Front-Mu of the Pericardium | 任脉 气会、心包募穴 |
| CV12 | Front-Mu of the Stomach; Hui-Meeting (Influential) point of the Fu organs | 任脉 胃募穴、腑会 |
| ST25 | Front-Mu of the Large Intestine | 足阳明胃经 大肠募穴 |
| LI11 | He-Sea (Earth) & Tonification point of Large Intestine; Ghost point | 手阳明大肠经 合(土)穴、补穴、鬼穴 |
| LU5 | He-Sea (Water) point of the Lung | 手太阴肺经 合(水)穴 |
| TE4 | Yuan-Source point of the Sanjiao | 手少阳三焦经 原穴 |
| PC7 | Shu-Stream (Earth) & Yuan-Source point of Pericardium; Ghost point | 手厥阴心包经 输(土)穴、原穴、鬼穴 |
| ST36 | He-Sea (Earth) & Lower-He-Sea of Stomach; Sea of Water & Grain; Command point of the abdomen | 足阳明胃经 合(土)穴、下合穴、四总穴(肚腹) |
| GB34 | He-Sea (Earth) & Lower-He-Sea of Gallbladder; Hui-Meeting (Influential) point of the sinews | 足少阳胆经 合(土)穴、下合穴、筋会 |
| SP10 | Xuehai — Spleen channel point (no Five-Shu/special category) | 足太阴脾经 血海 |
| ST34 | Xi-Cleft (Accumulation) point of the Stomach | 足阳明胃经 郄穴 |
| LR3 | Shu-Stream (Earth) & Yuan-Source point of the Liver | 足厥阴肝经 输(土)穴、原穴 |
| ST44 | Ying-Spring (Water) point of the Stomach | 足阳明胃经 荥(水)穴 |
| KI1 | Jing-Well (Wood) point of the Kidney | 足少阴肾经 井(木)穴 |
| KI3 | Shu-Stream (Earth) & Yuan-Source point of the Kidney | 足少阴肾经 输(土)穴、原穴 |

Verifier notes: SI3's "hyphen" and CV17's Front-Mu wording are cosmetic; LU5's "Water" element is the
standard Five-Shu designation of a Yin-channel He-Sea point (corroborated by the Atlas command-point
tables) even though the YYH page did not spell out "Water"; SP10 correctly has **no** classical category.

## 2. Per-condition evidence (AcuTrials indexed counts + flagship review; item URLs verified)

Honest framing only — "a research literature exists; individual results vary," never assured relief.

| App symptom | AcuTrials condition (count) | Flagship citation | AcuTrials item |
|-------------|-----------------------------|-------------------|----------------|
| nausea | Vomiting (44) | Cheong et al., *PLoS ONE* 2013 — PC6 acupressure ↓ nausea RR 0.71 / vomiting RR 0.62 | /item/10842 |
| headache | Headache Disorders (88) | Davis et al., *J Pain* 2008 — tension-type headache meta-analysis | /item/9402 |
| sleep | Sleep Disorders (35) | Shergis et al., *Complement Ther Med* 2016 — acupuncture & sleep quality in insomnia | /item/9086 |
| anxiety/mood | Mental Disorders (115) | Chan et al., *J Affect Disord* 2015 — acupuncture + antidepressant | /item/10788 |
| neck | Neck Pain (50) | Fu et al., *J Altern Complement Med* 2009 — neck-pain RCT review | /item/10657 |
| shoulder | Shoulder Pain (32) | Dong et al., *Medicine* 2015 — shoulder impingement network meta-analysis | /item/11011 |
| menstrual | Menstruation Disturbances (31) | Xu et al., *BMC CAM* 2017 — acupoint stim vs NSAIDs, 19 RCTs | /item/10142 |
| digestion | Gastrointestinal Diseases (65) | Kim et al., *Complement Ther Med* 2015 — functional dyspepsia | /item/10262 |

Base condition-browse URL:
`https://acutrials.ocom.edu/s/acutrials/item?property%5B0%5D%5Bproperty%5D=OCRE400032%3AOCRE900086&property%5B0%5D%5Btype%5D=eq&property%5B0%5D%5Btext%5D=<Condition>`

## 3. Meridian pathways (Atlas of Acupuncture Points, 2007 — paraphrased for descriptions)

- **Lung (LU):** chest near the armpit → anterior-medial upper arm → radial wrist → thenar → radial tip of the thumb.
- **Large Intestine (LI):** index fingertip → dorsal-radial forearm → lateral upper arm → shoulder & neck → cheek → beside the nose.
- **Stomach (ST):** face → down the front of the torso and the **front-lateral** leg → 2nd toe. *(fixes the old "inner leg" drawing.)*
- **Spleen (SP):** medial big toe → medial foot & leg (red/white skin line) → anterior-medial thigh → abdomen → side of the chest.
- **Heart (HT):** center of the axilla → posterior-medial upper arm → pisiform → palm → medial tip of the little finger.
- **Small Intestine (SI):** ulnar tip of the little finger → ulnar hand & posterolateral arm → scapula → neck & cheek → front of the ear.
- **Bladder (BL):** inner canthus → over the vertex → two lines down the back → posterior thigh & calf → behind the lateral ankle → little toe.
- **Kidney (KI):** sole of the foot → behind the medial ankle → medial leg & thigh → abdomen → depression under the clavicle.
- **Pericardium (PC):** chest beside the nipple → medial upper arm → between the two forearm tendons → palm → tip of the middle finger.
- **Sanjiao (TE/SJ):** ring fingertip → between 4th/5th metacarpals → dorsal wrist & forearm → olecranon → lateral upper arm & shoulder → neck → behind & around the ear.
- **Gallbladder (GB):** outer canthus → around the ear & temple → zig-zag over the head → side of the neck & trunk → lateral leg → 4th toe.
- **Liver (LR):** lateral big toe → dorsum of the foot → medial leg & thigh → genitals → lower abdomen → below the ribs/nipple.
- **Ren / Conception (CV):** perineum → up the front midline of the abdomen & chest → throat → mentolabial groove.
- **Du / Governing (GV):** coccyx → up the spine → nape → over the vertex → down the forehead & nose → upper lip.

Five-element command points (Atlas) corroborate the YinYangHouse categories (e.g. Pericardium: Water P3,
Metal P5, Earth P7, Fire P8, Wood P9; Luo P6; Xi-Cleft P4; Source P7).

## 4. Coach-identification verdict (Yin Yang House vs the 8 WHO-2008 AR anchors)

YinYangHouse locations **corroborate all 8** AR-coachable placements — no contradictions, so the anchor
math is unchanged. It only sharpens the human cue text:
- **TE3 / SI3** — a loose fist opens the depression; SI3 sits at the very end of the palm crease on the pinky side, at the red/white skin border.
- **PC8** — curl the middle finger to the palm; the point is where the tip lands.
- **HT7** — find the pisiform (small round bone at the pinky-side base of the palm); the point is just inside it on the crease.
- **PC6 / SJ5** — three finger-widths above the wrist crease between the two central tendons (PC6 palmar; SJ5 directly opposite on the back).
- **PC7** — middle of the wrist crease between the same two tendons. **TE4** — dorsal wrist crease, ulnar to the extensor tendon.

## 5. Camera-localization sources — feasibility note (cited, not embedded)

Ranked by how usable they are for a future **on-device RGB** point-finder (all need a CNN ported to
CoreML, so none is a drop-in for this content build):

- **MetaAcuPoint** (Guruge et al., *Healthcare* 13(23):3093, 2025; PMC12691809) — synthetic **RGB** hand/forearm dataset (900 MetaHuman/UE5 images), 5 points incl. **TE3 & TE5**; HRNet-W48, ~5 mm error, generalizes across viewpoints. **CC BY 4.0** (commercial + derivatives OK), dataset on Zenodo (DOI 10.5281/zenodo.17713204). → **Best future path**: RGB-only, on-region, our hero points, permissive license. A CoreML port could power a learned hand point-finder or cross-check our anchors — a separate ML project, not this build.
- **FAcupoint** (Zhang et al., *Expert Systems with Applications* 272:126683, 2025) — first dense **RGB facial** acupoint dataset (654 real face images, 43 points, 5 licensed physicians); migrates facial-landmark models. Validates the RGB-landmark approach our face locator uses, but data is **request-only under ethical restrictions** (real faces). → cited; not embeddable as-is.
- **AcuSim** (Nature *Sci Data* 12:625, 2025; PMC12000350) — synthetic **RGB-D** cervicocranial dataset (63,936 images, 174 points; 92.86% within 5 mm). Needs **depth** (we're RGB-only), **no trained model** released (Dryad render scripts only), **CC BY-NC-ND 4.0** (non-commercial + no-derivatives). → validates the approach; not usable in a product.
- **TARA** (`tara-repository.mgb.org/visual_search`, MGB, NCCIH U24AT012560) — a **Unity WebGL 3D acupoint/meridian atlas** ("visual search" = type a point → highlight on a 3D model). Browse/visualization only (overlaps our own atlas), beta + login-gated, **no public API/model/dataset**. → institutional cross-reference; nothing to integrate.

**Bottom line:** MetaAcuPoint is the first of these that is RGB-only, hand-region, covers our points, and
is openly licensed — so a learned on-device hand point-finder (or an anchor cross-check) is now a
realistic *future* upgrade, distinct from the current WHO-anchored + Vision-landmark coach.
