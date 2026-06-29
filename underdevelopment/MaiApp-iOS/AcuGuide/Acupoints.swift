import SwiftUI

// Hand acupoint dataset, ported from MaiApp/src/data.js (the validated atlas). x,y are in the
// 360 x 440 hand-SVG coordinate box used by HandAtlasView. `mediapipeTarget` drives the AR coach
// and is non-nil for TE3 ONLY (the single validated AR-coached point); every other point is
// atlas-only (display, no camera coaching). LI4 (合谷) is excluded entirely — it is
// pregnancy-contraindicated and must never appear, not even in the atlas.

struct AnchorWeight: Hashable {
    let landmark: HandJoint   // which Vision joint
    let weight: Double
}

struct MediaPipeTarget: Hashable {
    let anchors: [AnchorWeight]          // weighted sum of landmarks
    let toleranceXHandSize: Double       // hit radius as a fraction of hand size
    let pressFinger: HandJoint           // which fingertip presses (INDEX_TIP for TE3)
}

// Picks the active-language string from the in-app setting (defaults to the device locale on
// first launch; toggled in Settings). Observe AppSettings.shared in a view to re-render on change.
enum AppLocale {
    static var isChinese: Bool { AppSettings.shared.lang == .zh }
    static func pick(_ zh: String, _ en: String) -> String { isChinese ? zh : en }
}

struct Acupoint: Identifiable, Hashable {
    let id: String          // "TE3"
    let zh: String          // 中渚
    let en: String          // Zhongzhu (romanized name)
    let pinyin: String      // Zhōngzhǔ (toned)
    let meridian: String    // "sj" — key into MeridianColors
    let meridianZh: String
    let meridianEn: String
    let x: Double           // hand-SVG x (0...360)
    let y: Double           // hand-SVG y (0...440)
    let requiresDorsal: Bool
    let locationZh: String
    let locationEn: String
    let indicationsZh: String
    let indicationsEn: String
    let coachAlign: String  // AR cue (used live for TE3 only)
    let coachHold: String   // AR cue (used live for TE3 only)
    var coachAlignZh: String = ""   // zh AR cue (TE3 only; en stays in coachAlign)
    var coachHoldZh: String = ""
    let mediapipeTarget: MediaPipeTarget?   // non-nil for TE3 only
    var region: String = "hand"     // head/chest/abdomen/arm/leg/foot/hand — groups the body atlas
    var cautionZh: String = ""      // per-point safety note (shown in the detail card); empty = none
    var cautionEn: String = ""

    // Localized accessors for the atlas UI + the AR coach card.
    var location: String     { AppLocale.pick(locationZh, locationEn) }
    var indications: String  { AppLocale.pick(indicationsZh, indicationsEn) }
    var caution: String      { AppLocale.pick(cautionZh, cautionEn) }
    var meridianName: String { AppLocale.pick(meridianZh, meridianEn) }
    var coachAlignL: String  { AppLocale.pick(coachAlignZh.isEmpty ? coachAlign : coachAlignZh, coachAlign) }
    var coachHoldL: String   { AppLocale.pick(coachHoldZh.isEmpty ? coachHold : coachHoldZh, coachHold) }

    static let all: [Acupoint] = [
        // ── The one validated AR-coached point. ──────────────────────────────────────────────
        Acupoint(
            id: "TE3", zh: "中渚", en: "Zhongzhu", pinyin: "Zhōngzhǔ",
            meridian: "sj", meridianZh: "手少阳三焦经", meridianEn: "Sanjiao Meridian",
            x: 232, y: 150, requiresDorsal: true,
            locationZh: "在手背，第4、5掌骨小头后方的凹陷处（无名指与小指掌指关节后方的凹沟）。",
            locationEn: "On the back of the hand, in the groove behind the heads of the 4th and 5th metacarpals (behind the ring- and little-finger knuckles).",
            indicationsZh: "传统上常用于头侧紧张、耳部不适，以及手背与腕部紧张等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for side-of-head tension, ear discomfort, and tension across the back of the hand and wrist.",
            coachAlign: "Back of the hand up. Find the groove behind your ring and pinky knuckles.",
            coachHold: "Good — firm, steady pressure with slow breathing, small gentle circles.",
            coachAlignZh: "手背朝上。找到无名指与小指掌指关节后方的凹沟。",
            coachHoldZh: "很好 — 稳定用力，配合缓慢呼吸，可做小幅轻柔画圈。",
            // TE3 = centre of the 4th/5th metacarpal gap, stepped ~20% proximally into the
            // depression just behind the 4th MCP. Per the WHO Standard (WPRO 2008) + a sourced
            // landmark study: 0.5·(ringMCP+pinkyMCP) + 0.20·(wrist−gap) ⇒ ring 0.40 / pinky 0.40 /
            // wrist 0.20, ring-biased to 0.46/0.34 toward the 4th MCP. NO middleMCP (it pulls the
            // point radially out of the gap). 0.20 wrist sits it behind the knuckle, not on it.
            mediapipeTarget: MediaPipeTarget(
                anchors: [
                    AnchorWeight(landmark: .ringMCP, weight: 0.46),
                    AnchorWeight(landmark: .pinkyMCP, weight: 0.34),
                    AnchorWeight(landmark: .wrist, weight: 0.20),
                ],
                toleranceXHandSize: 0.16,
                pressFinger: .indexTip
            )
        ),

        // ── Atlas-only points (display, no AR coaching this build). ──────────────────────────
        Acupoint(
            id: "PC6", zh: "内关", en: "Neiguan", pinyin: "Nèiguān",
            meridian: "pc", meridianZh: "手厥阴心包经", meridianEn: "Pericardium Meridian",
            x: 200, y: 344, requiresDorsal: false,
            locationZh: "在前臂掌侧，腕横纹上约2寸，两筋之间。",
            locationEn: "On the palmar side of the forearm, about two cun above the wrist crease, between the two tendons.",
            indicationsZh: "传统上常与恶心、胸闷、心神不宁、晕动不适等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with nausea, chest tightness, an unsettled spirit, and motion-related discomfort.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil
        ),
        Acupoint(
            id: "SJ5", zh: "外关", en: "Waiguan", pinyin: "Wàiguān",
            meridian: "sj", meridianZh: "手少阳三焦经", meridianEn: "Sanjiao Meridian",
            x: 174, y: 320, requiresDorsal: true,
            locationZh: "在前臂背侧，腕背横纹上约2寸，与内关相对。",
            locationEn: "On the dorsal side of the forearm, about two cun above the dorsal wrist crease, opposite Neiguan.",
            indicationsZh: "传统上常用于头侧不适、耳部不适、上肢酸楚等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for side-of-head discomfort, ear discomfort, and aching of the arm.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil
        ),
        Acupoint(
            id: "PC8", zh: "劳宫", en: "Laogong", pinyin: "Láogōng",
            meridian: "pc", meridianZh: "手厥阴心包经", meridianEn: "Pericardium Meridian",
            x: 186, y: 214, requiresDorsal: false,
            locationZh: "在手掌中央，约当第2、3掌骨之间偏于第3掌骨处。",
            locationEn: "At the center of the palm, between the second and third metacarpal bones, nearer the third.",
            indicationsZh: "传统上常与心烦、口部不适、手心热等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with restlessness, mouth discomfort, and warmth of the palms.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil
        ),
        Acupoint(
            id: "HT7", zh: "神门", en: "Shenmen", pinyin: "Shénmén",
            meridian: "heart", meridianZh: "手少阴心经", meridianEn: "Heart Meridian",
            x: 214, y: 262, requiresDorsal: false,
            locationZh: "在腕部，腕掌侧横纹尺侧端，尺侧腕屈肌腱的桡侧凹陷处。",
            locationEn: "At the wrist, on the ulnar end of the palmar crease, in the depression on the radial side of the flexor carpi ulnaris tendon.",
            indicationsZh: "传统上常与睡眠不安、心神不宁、情绪紧张等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with restless sleep, an unsettled spirit, and emotional tension.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil
        ),
        Acupoint(
            id: "SI3", zh: "后溪", en: "Houxi", pinyin: "Hòuxī",
            meridian: "si", meridianZh: "手太阳小肠经", meridianEn: "Small Intestine Meridian",
            x: 236, y: 174, requiresDorsal: true,
            locationZh: "在手尺侧，第5掌指关节后方，握拳时横纹尽头赤白肉际处。",
            locationEn: "On the ulnar side of the hand, in the depression proximal to the head of the fifth metacarpal bone, at the end of the crease when a loose fist is made.",
            indicationsZh: "传统上常用于颈项强紧、肩背不适、头侧不适等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for neck stiffness, shoulder and upper-back discomfort, and side-of-head discomfort.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil
        ),

        // ── Body-region atlas points (display + tappable 3D markers; no AR coaching). ──────────
        // WHO Standard 2008 locations; all gentle, fingertip-safe points. Pregnancy-contraindicated
        // points (LI4/SP6/GB21/BL60/BL67) are excluded entirely; abdominal/strong points carry an
        // explicit caution. Sourced + adversarially verified (see claude-deliverables/references).

        // Head & face
        Acupoint(id: "EX-HN3", zh: "印堂", en: "Yintang", pinyin: "Yìntáng",
            meridian: "extra", meridianZh: "经外奇穴", meridianEn: "Extra Point",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在头部，两眉头连线的中点处（眉间正中，鼻根上方）。",
            locationEn: "On the forehead, at the midpoint between the medial ends of the two eyebrows (the glabella), per WHO Standard 2008.",
            indicationsZh: "传统上常与安神、舒缓紧张情绪与放松眉间相关联。",
            indicationsEn: "Traditionally associated with a sense of calm, easing mental tension, and relaxing the brow.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "head",
            cautionZh: "仅用指尖轻柔静压，勿压向眼睛；皮肤破损或不适时请勿按压。",
            cautionEn: "Use light, still fingertip pressure on the bone only — not toward the eyes. Avoid if the skin is broken or irritated."),
        Acupoint(id: "EX-HN5", zh: "太阳", en: "Taiyang", pinyin: "Tàiyáng",
            meridian: "extra", meridianZh: "经外奇穴", meridianEn: "Extra Point",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在头部颞侧，眉梢与外眼角连线中点向后约1寸的凹陷处（太阳穴）。",
            locationEn: "At the temple, in the depression about 1 cun posterior to the midpoint between the lateral end of the eyebrow and the outer corner of the eye.",
            indicationsZh: "传统上常与舒缓两侧太阳穴区域的头部紧张与放松双眼相关联。",
            indicationsEn: "Traditionally associated with easing tension around the temples and relaxing the eyes.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "head",
            cautionZh: "仅用指尖轻柔按压；此处血管丰富，切勿用力或长时间深压。",
            cautionEn: "Gentle fingertip pressure only; this area is vascular, so do not press hard or hold deep force."),
        Acupoint(id: "GV20", zh: "百会", en: "Baihui", pinyin: "Bǎihuì",
            meridian: "du", meridianZh: "督脉", meridianEn: "Governing Vessel",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在头部正中线上，两耳尖连线与正中线的交点处，前发际正中直上5寸。",
            locationEn: "On the vertex, on the head midline, where the line joining the two ear apexes crosses it; 5 cun behind the front hairline (WHO Standard 2008).",
            indicationsZh: "传统上常与提神安神、舒缓头部紧张与平静心绪相关联。",
            indicationsEn: "Traditionally associated with a clear, settled mind and easing overall head tension.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "head",
            cautionZh: "仅用指尖轻柔按压或轻轻打圈。",
            cautionEn: "Use gentle fingertip pressure or light circular motion only."),
        Acupoint(id: "EX-HN1", zh: "四神聪", en: "Sishencong", pinyin: "Sìshéncōng",
            meridian: "extra", meridianZh: "经外奇穴", meridianEn: "Extra Point",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在头顶部，百会（GV20）前、后、左、右各旁开1寸处，共四穴。",
            locationEn: "On the vertex, a group of four points 1 cun anterior, posterior, left, and right of Baihui (GV20).",
            indicationsZh: "传统上常与安神助眠、舒缓头部紧张与平复思绪相关联。",
            indicationsEn: "Traditionally associated with calm, restful ease, and relaxing a busy mind.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "head",
            cautionZh: "在四个点上各用指尖轻压即可，无需深压。",
            cautionEn: "Use light fingertip pressure on each of the four spots; no deep pressing needed."),

        // Chest (gentle pressure only)
        Acupoint(id: "CV17", zh: "膻中", en: "Shanzhong", pinyin: "Shānzhōng",
            meridian: "ren", meridianZh: "任脉", meridianEn: "Conception Vessel",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在胸部，前正中线上，平第4肋间隙，约当两乳头连线的中点。",
            locationEn: "On the anterior midline of the chest, on the sternum, level with the 4th intercostal space — roughly midway between the nipples (WHO Standard).",
            indicationsZh: "传统上常与放松胸部、舒缓气机、安抚情绪以及自在呼吸的感受相关联。",
            indicationsEn: "Traditionally associated with an open, relaxed chest, smooth flow of qi, emotional calm, and easeful breathing.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "chest",
            cautionZh: "胸部穴位——仅用指尖在胸骨上轻柔打圈，切勿用力。局部酸痛、淤青或发炎请避开。",
            cautionEn: "Chest point — only light fingertip circles over the breastbone; never press hard. Skip if the area is sore, bruised, or inflamed."),
        Acupoint(id: "KI27", zh: "俞府", en: "Shufu", pinyin: "Shūfǔ",
            meridian: "kidney", meridianZh: "足少阴肾经", meridianEn: "Kidney Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在胸部，锁骨下缘，前正中线旁开2寸的凹陷处。",
            locationEn: "On the upper chest, in the depression on the lower border of the clavicle, 2 cun lateral to the anterior midline (WHO Standard).",
            indicationsZh: "传统上常与舒展上胸、顺畅呼吸以及缓解胸闷的感受相关联。",
            indicationsEn: "Traditionally associated with an open upper chest, easeful breathing, and relief of chest tightness.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "chest",
            cautionZh: "胸部穴位——仅在锁骨下方凹陷处用指尖轻浅按压，切勿向胸腔深按或下压。",
            cautionEn: "Chest point — light, shallow fingertip pressure in the hollow under the collarbone; never press deep or down into the chest."),

        // Abdomen (gentle pressure; avoid in pregnancy / after meals)
        Acupoint(id: "CV12", zh: "中脘", en: "Zhongwan", pinyin: "Zhōngwǎn",
            meridian: "ren", meridianZh: "任脉", meridianEn: "Conception Vessel",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在上腹部，前正中线上，脐上4寸，约当胸骨下端与肚脐连线的中点。",
            locationEn: "On the upper abdomen, on the anterior midline, 4 cun above the navel — roughly midway between the navel and the lower end of the sternum (WHO Standard).",
            indicationsZh: "传统上常与上腹的舒适、餐后的轻松感与平和的胃部感受相关联。",
            indicationsEn: "Traditionally associated with upper-abdominal comfort, an easeful feeling after meals, and a settled stomach.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "abdomen",
            cautionZh: "腹部穴位——仅用手掌或指腹轻柔打圈，切勿深按。饭后、腹部不适时请避免；孕期请勿按腹部穴位并先咨询专业人士。",
            cautionEn: "Abdominal point — gentle palm or fingertip circles only, never deep pressure. Avoid right after meals or with abdominal discomfort; in pregnancy avoid abdominal points and check with a professional first."),
        Acupoint(id: "ST25", zh: "天枢", en: "Tianshu", pinyin: "Tiānshū",
            meridian: "stomach", meridianZh: "足阳明胃经", meridianEn: "Stomach Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在腹部，横平脐中，前正中线旁开2寸。",
            locationEn: "On the abdomen, 2 cun lateral to the centre of the navel (WHO Standard).",
            indicationsZh: "传统上常与肠胃通畅、腹部舒适与规律的消化相关联。",
            indicationsEn: "Traditionally associated with comfortable digestion and a settled abdomen.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "abdomen",
            cautionZh: "腹部穴位——仅用指腹轻柔按压。孕期应避免按压腹部穴位，并请先咨询专业人士。",
            cautionEn: "Abdominal point — gentle fingertip pressure only. Avoid abdominal points in pregnancy and check with a professional first."),

        // Arm (elbow + wrist)
        Acupoint(id: "LI11", zh: "曲池", en: "Quchi", pinyin: "Qūchí",
            meridian: "li", meridianZh: "手阳明大肠经", meridianEn: "Large Intestine Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "屈肘成直角，在肘横纹外侧端凹陷处，即尺泽(LU5)与肱骨外上髁连线的中点。",
            locationEn: "With the elbow flexed, in the depression at the outer (thumb-side) end of the elbow crease, midway between Chize (LU5) and the lateral epicondyle (WHO Standard 2008).",
            indicationsZh: "传统上常与上肢的舒适感、皮肤的清爽感以及整体放松相关联。",
            indicationsEn: "Traditionally associated with a sense of ease in the arm, refreshed skin comfort, and general relaxation.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "arm",
            cautionZh: "仅用指腹轻柔按压；若出现疼痛、刺痛或麻木请停止。",
            cautionEn: "Gentle fingertip pressure only; stop if you feel pain, tingling, or numbness."),
        Acupoint(id: "LU5", zh: "尺泽", en: "Chize", pinyin: "Chǐzé",
            meridian: "lung", meridianZh: "手太阴肺经", meridianEn: "Lung Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在肘横纹上，肱二头肌腱桡侧缘的凹陷处。",
            locationEn: "On the cubital crease, in the depression on the thumb (radial) side of the biceps tendon (WHO Standard 2008).",
            indicationsZh: "传统上常与胸部的舒畅感、平顺的呼吸感以及肘臂的放松相关联。",
            indicationsEn: "Traditionally associated with an open chest, easy comfortable breathing, and relaxation of the elbow and arm.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "arm",
            cautionZh: "保持在肌腱的拇指侧并只用轻力，避免用力压向肘横纹正中血管经过之处。",
            cautionEn: "Stay on the thumb-side of the tendon with gentle pressure; avoid pressing hard into the centre of the elbow crease where vessels run."),
        Acupoint(id: "TE4", zh: "阳池", en: "Yangchi", pinyin: "Yángchí",
            meridian: "sj", meridianZh: "手少阳三焦经", meridianEn: "Sanjiao Meridian",
            x: 0, y: 0, requiresDorsal: true,
            locationZh: "在腕后区，腕背侧远端横纹上，指伸肌腱的尺侧缘凹陷中。",
            locationEn: "On the back of the wrist, at the dorsal wrist crease, in the depression on the little-finger side of the extensor digitorum tendon (WHO Standard 2008).",
            indicationsZh: "传统上常与手腕的轻松灵活感以及手部的温暖舒适相关联。",
            indicationsEn: "Traditionally associated with a supple, relaxed wrist and warm, comfortable hands.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "arm",
            cautionZh: "在腕背用指腹轻柔按压；若有疼痛或麻木即停。",
            cautionEn: "Light fingertip pressure on the back of the wrist; stop if you feel pain or numbness."),
        Acupoint(id: "PC7", zh: "大陵", en: "Daling", pinyin: "Dàlíng",
            meridian: "pc", meridianZh: "手厥阴心包经", meridianEn: "Pericardium Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在腕前区，腕掌侧远端横纹中，掌长肌腱与桡侧腕屈肌腱之间。",
            locationEn: "On the palm-side of the wrist, at the wrist crease, midway between the two tendons (palmaris longus and flexor carpi radialis) (WHO Standard 2008).",
            indicationsZh: "传统上常与平静放松的心境以及手腕的舒适感相关联。",
            indicationsEn: "Traditionally associated with a calm, settled mind and comfort of the wrist.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "arm",
            cautionZh: "在腕横纹正中用指腹轻柔、短暂按压；若有刺麻感传向手部即放松。",
            cautionEn: "Gentle, brief fingertip pressure at the centre of the wrist crease; ease off if you feel tingling into the hand."),

        // Leg (knee + lower leg)
        Acupoint(id: "ST36", zh: "足三里", en: "Zusanli", pinyin: "Zúsānlǐ",
            meridian: "stomach", meridianZh: "足阳明胃经", meridianEn: "Stomach Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在小腿前外侧，犊鼻(ST35)下3寸，胫骨前嵴外开一横指处。",
            locationEn: "On the anterolateral lower leg, 3 cun below Dubi (ST35), one finger-breadth lateral to the front crest of the shin bone (WHO Standard).",
            indicationsZh: "传统上常与脾胃消化、精力充沛与整体强健的养生相关联。",
            indicationsEn: "Traditionally associated with comfortable digestion, steady energy, and a sense of overall vitality.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "leg",
            cautionZh: "用指腹稳而舒适地按压，是最常用的保健穴位之一。孕期请只用轻柔接触并先咨询专业人士。",
            cautionEn: "Press with the thumb pad, firm but comfortable — one of the most widely used wellness points. In pregnancy keep contact light and check with a professional first."),
        Acupoint(id: "GB34", zh: "阳陵泉", en: "Yanglingquan", pinyin: "Yánglíngquán",
            meridian: "gb", meridianZh: "足少阳胆经", meridianEn: "Gallbladder Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在小腿外侧，腓骨头前下方凹陷处。",
            locationEn: "On the outer lower leg, in the depression in front of and below the head of the fibula.",
            indicationsZh: "传统上常与肌肉、肌腱与膝部周围的轻松舒适感相关联。",
            indicationsEn: "Traditionally associated with ease and comfort in the muscles, tendons, and area around the knee.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "leg",
            cautionZh: "先找到腓骨头的骨性突起，再在其前下方的凹陷处轻柔按压。",
            cautionEn: "Find the bony fibular head first, then press gently in the hollow just below and in front of it."),
        Acupoint(id: "SP10", zh: "血海", en: "Xuehai", pinyin: "Xuèhǎi",
            meridian: "spleen", meridianZh: "足太阴脾经", meridianEn: "Spleen Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在大腿内侧，髌底内侧端上2寸，股内侧肌隆起处。",
            locationEn: "On the inner thigh, 2 cun above the inner-upper corner of the kneecap, on the bulge of the vastus medialis muscle.",
            indicationsZh: "传统上常与女性周期相关的舒适感及皮肤的清爽感相关联。",
            indicationsEn: "Traditionally associated with menstrual-cycle comfort and a sense of skin freshness.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "leg",
            cautionZh: "传统上为活血力较强的穴位，孕期宜避免。仅用轻柔按压。",
            cautionEn: "Traditionally a strong blood-moving point and best avoided during pregnancy. Use gentle pressure only."),
        Acupoint(id: "ST34", zh: "梁丘", en: "Liangqiu", pinyin: "Liángqiū",
            meridian: "stomach", meridianZh: "足阳明胃经", meridianEn: "Stomach Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在股前外侧，髌底外侧端上2寸，股外侧肌凹陷处。",
            locationEn: "On the front-outer thigh, 2 cun above the outer-upper corner of the kneecap, in the depression on the vastus lateralis.",
            indicationsZh: "传统上常与膝部周围及上腹部的一过性不适舒缓相关联。",
            indicationsEn: "Traditionally associated with easing transient discomfort around the knee and upper abdomen.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "leg",
            cautionZh: "作为郄穴传统上用于急性、短暂的不适；用指腹轻柔按压。",
            cautionEn: "As a 'cleft' point it is traditionally used for short-lived discomfort; gentle fingertip pressure."),
        Acupoint(id: "ST35", zh: "犊鼻", en: "Dubi", pinyin: "Dúbí",
            meridian: "stomach", meridianZh: "足阳明胃经", meridianEn: "Stomach Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在膝前，屈膝时髌韧带外侧凹陷处（外膝眼）。",
            locationEn: "On the front of the knee, with the knee bent, in the depression to the outer side of the patellar ligament (the 'lateral eye of the knee').",
            indicationsZh: "传统上常与膝关节周围的轻松与活动舒适感相关联。",
            indicationsEn: "Traditionally associated with comfort and ease of movement around the knee joint.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "leg",
            cautionZh: "屈膝使凹陷显现，在髌韧带旁的柔软凹陷处轻柔按压。",
            cautionEn: "Bend the knee to open the hollow, then press gently into the soft depression beside the kneecap tendon."),

        // Foot & ankle
        Acupoint(id: "LR3", zh: "太冲", en: "Taichong", pinyin: "Tàichōng",
            meridian: "liver", meridianZh: "足厥阴肝经", meridianEn: "Liver Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "足背，第1、2跖骨间，跖骨底结合部前方的凹陷中。",
            locationEn: "On the top of the foot, in the hollow just beyond where the 1st and 2nd foot bones meet (WHO Standard 2008).",
            indicationsZh: "传统上常与放松、舒缓情绪与压力、头部与眼部的舒适感、以及整体平衡相关联。",
            indicationsEn: "Traditionally associated with calm, easing tension and stress, comfort around the head and eyes, and a feeling of overall balance.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "foot",
            cautionZh: "仅用指尖轻柔按压。被视为行气较强的穴位，妊娠期传统上应避免或仅极轻接触。避免重压凹槽中可触及搏动的动脉处。",
            cautionEn: "Gentle fingertip pressure only. Considered a strong qi-moving point, so traditionally avoided or used very lightly in pregnancy. Don't press hard on the pulsing artery in the groove."),
        Acupoint(id: "ST44", zh: "内庭", en: "Neiting", pinyin: "Nèitíng",
            meridian: "stomach", meridianZh: "足阳明胃经", meridianEn: "Stomach Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "足背，第2、3趾间，趾蹼缘后方赤白肉际处的凹陷中。",
            locationEn: "On the top of the foot, between the 2nd and 3rd toes, in the depression just behind the web margin (WHO Standard 2008).",
            indicationsZh: "传统上常与清凉舒适感、面口部位的舒缓、以及饭后腹部的轻松感相关联。",
            indicationsEn: "Traditionally associated with a cooling, refreshed feeling, comfort around the face and mouth, and ease in the upper abdomen after meals.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "foot",
            cautionZh: "仅用指尖轻柔按压。出于谨慎，妊娠期应避免强刺激。",
            cautionEn: "Gentle fingertip pressure only. As a precaution, avoid strong stimulation in pregnancy."),
        Acupoint(id: "KI1", zh: "涌泉", en: "Yongquan", pinyin: "Yǒngquán",
            meridian: "kidney", meridianZh: "足少阴肾经", meridianEn: "Kidney Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "足底，屈足卷趾时足心最凹陷处，约当足底第2、3趾缝与足跟连线的前1/3与后2/3交点处。",
            locationEn: "On the sole, in the deepest depression when the toes are curled, at the front third of the line from the 2nd–3rd toe web to the back of the heel (WHO Standard 2008).",
            indicationsZh: "传统上常与放松入静、安睡、以及一种沉稳接地的感觉相关联。",
            indicationsEn: "Traditionally associated with relaxation and winding down, restful sleep, and a calm, grounded feeling.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "foot",
            cautionZh: "用拇指以舒适的力度轻柔按压。出于谨慎，妊娠期保持刺激轻柔。足底皮肤破损或过于敏感时请略过。",
            cautionEn: "Gentle, comfortable thumb pressure. As a precaution, keep stimulation light in pregnancy. Skip if the sole skin is broken or very ticklish."),
        Acupoint(id: "KI3", zh: "太溪", en: "Taixi", pinyin: "Tàixī",
            meridian: "kidney", meridianZh: "足少阴肾经", meridianEn: "Kidney Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "踝区，内踝尖与跟腱之间的凹陷中，与内踝尖平齐。",
            locationEn: "On the inner ankle, in the hollow between the tip of the inner ankle bone and the Achilles tendon, level with the ankle-bone tip (WHO Standard 2008).",
            indicationsZh: "传统上常与精力与活力感、舒缓的安眠、以及腰膝的轻松舒适相关联。",
            indicationsEn: "Traditionally associated with a sense of energy and vitality, restful sleep, and ease in the lower back and knees.",
            coachAlign: "", coachHold: "", mediapipeTarget: nil, region: "foot",
            cautionZh: "用指尖轻柔按压。一般被视为温和的补益穴位，耐受性良好；若感到动脉搏动请减轻力度。",
            cautionEn: "Gentle fingertip pressure. Generally a mild, well-tolerated point; ease off if you feel the artery throbbing in the hollow."),
    ]

    // Id → point index, so tap hit-tests and lookups don't linear-scan `all` every time.
    static let byId: [String: Acupoint] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
}

// Meridian colors from data.js MERIDIAN_COLORS.
enum MeridianColors {
    static let map: [String: Color] = [
        "lung": Color(hex: "#b8c6d9"), "li": Color(hex: "#d4b876"),
        "stomach": Color(hex: "#7ab89a"), "spleen": Color(hex: "#d4a857"),
        "heart": Color(hex: "#d97a85"), "si": Color(hex: "#d9a890"),
        "bladder": Color(hex: "#7ac0d4"), "kidney": Color(hex: "#9a85d4"),
        "pc": Color(hex: "#d485c0"), "sj": Color(hex: "#85d4c0"),
        "gb": Color(hex: "#6abd8a"), "liver": Color(hex: "#d48585"),
        "ren": Color(hex: "#f0e6d2"), "du": Color(hex: "#e8d4a0"),
        "extra": Color(hex: "#c4b3e0"),   // 经外奇穴 (Yintang/Taiyang/Sishencong) — distinct from du's gold
    ]
    static func color(_ id: String) -> Color { map[id] ?? Ink.gold }
}

// The fourteen channels (12 regular + Ren/Du), ported from data.js MERIDIANS. Tapping a channel
// on the 3D body surfaces this record + the atlas points that ride it. Descriptions are
// traditional/cultural framing only — no medical claims (per the app's wellness-only posture).
struct Meridian: Identifiable, Hashable {
    let id: String          // "lung" — key into MeridianColors / Acupoint.meridian
    let zh: String          // 手太阴肺经
    let en: String          // Lung
    let ab: String          // LU
    let descZh: String
    let descEn: String

    var name: String { AppLocale.pick(zh, en) }
    var desc: String { AppLocale.pick(descZh, descEn) }
    var color: Color { MeridianColors.color(id) }
    // The atlas points that lie on this channel (those we actually carry), in file order.
    var points: [Acupoint] { Acupoint.all.filter { $0.meridian == id } }

    static let all: [Meridian] = [
        Meridian(id: "lung", zh: "手太阴肺经", en: "Lung", ab: "LU",
            descZh: "起于胸中，沿手臂内侧前缘下行至拇指。传统中医将其与肺及呼吸相联系，沿经穴位传统上用于咳嗽、气喘与咽喉不适的相关调理。",
            descEn: "Runs from the chest along the inner edge of the arm to the thumb. In traditional Chinese medicine it is associated with the lungs and breathing; its points are traditionally associated with cough, wheezing, and throat discomfort."),
        Meridian(id: "li", zh: "手阳明大肠经", en: "Large Intestine", ab: "LI",
            descZh: "起于食指，沿手臂外侧上行至面部。传统上与大肠相关，其穴位常与面部、牙齿及肠胃方面的调理相关联。",
            descEn: "Travels from the index finger up the outer arm to the face. Traditionally linked to the large intestine; its points are classically associated with facial, dental, and digestive concerns."),
        Meridian(id: "stomach", zh: "足阳明胃经", en: "Stomach", ab: "ST",
            descZh: "起于面部，沿身体前侧与腿部前缘下行至第二趾。传统理论中与胃和消化相关。",
            descEn: "Descends from the face down the front of the torso and the front of the leg to the second toe. Associated with the stomach and digestion in traditional theory."),
        Meridian(id: "spleen", zh: "足太阴脾经", en: "Spleen", ab: "SP",
            descZh: "起于足大趾，沿腿内侧上行至胸部。传统上与脾、消化及运化水谷相关。",
            descEn: "Ascends from the big toe up the inner leg to the chest. Associated with the spleen, digestion, and the transformation of food in traditional theory."),
        Meridian(id: "heart", zh: "手少阴心经", en: "Heart", ab: "HT",
            descZh: "起于腋下，沿手臂内侧后缘下行至小指。传统上与心及神志相关。",
            descEn: "Runs from the armpit down the inner arm to the little finger. Traditionally linked to the heart and the mind."),
        Meridian(id: "si", zh: "手太阳小肠经", en: "Small Intestine", ab: "SI",
            descZh: "起于小指，沿手臂后侧上行至面部与耳前。传统上与小肠相关。",
            descEn: "Travels from the little finger up the back of the arm to the face and ear. Associated with the small intestine."),
        Meridian(id: "bladder", zh: "足太阳膀胱经", en: "Bladder", ab: "BL",
            descZh: "为十二经中最长者，起于内眼角，经头顶、背部两侧与腿后侧下行至小趾。传统上与膀胱相关。",
            descEn: "The longest of the twelve channels: from the inner eye over the head and down the back and leg to the little toe. Associated with the bladder."),
        Meridian(id: "kidney", zh: "足少阴肾经", en: "Kidney", ab: "KI",
            descZh: "起于足底，沿腿内侧上行至胸部。传统理论中与肾及人体根本之气相关。",
            descEn: "Rises from the sole of the foot up the inner leg to the chest. Associated with the kidneys and the body’s foundational vitality in traditional theory."),
        Meridian(id: "pc", zh: "手厥阴心包经", en: "Pericardium", ab: "PC",
            descZh: "起于胸中，沿手臂内侧中线下行至中指。传统上与心包相关，护卫心脏。",
            descEn: "Runs from the chest along the middle of the inner arm to the middle finger. Associated with the pericardium, which is said to protect the heart."),
        Meridian(id: "sj", zh: "手少阳三焦经", en: "Sanjiao", ab: "SJ",
            descZh: "起于无名指，沿手臂后侧中线上行至头侧。传统上与“三焦”即人体水液与气机的通道相关。",
            descEn: "Travels from the ring finger up the back of the arm to the side of the head. Linked to the “triple burner”, the traditional passages for the body’s fluids and qi."),
        Meridian(id: "gb", zh: "足少阳胆经", en: "Gallbladder", ab: "GB",
            descZh: "沿头部与身体侧面下行，经腿外侧至第四趾。传统上与胆及身体两侧相关。",
            descEn: "Runs along the side of the head and body, down the outer leg to the fourth toe. Traditionally associated with the gallbladder and the sides of the body."),
        Meridian(id: "liver", zh: "足厥阴肝经", en: "Liver", ab: "LR",
            descZh: "起于足大趾，沿腿内侧上行至胁肋。传统上与肝及气机的疏泄相关。",
            descEn: "Ascends from the big toe up the inner leg to the ribs. Associated with the liver and the smooth flow of qi in traditional theory."),
        Meridian(id: "ren", zh: "任脉", en: "Ren Mai", ab: "RN",
            descZh: "任脉行于身体前正中线，自小腹上行至下颌。传统理论称其为“阴脉之海”，统领诸阴经。",
            descEn: "The Conception Vessel, running up the front midline from the lower abdomen to the chin. Considered the “sea of the yin channels” in traditional theory."),
        Meridian(id: "du", zh: "督脉", en: "Du Mai", ab: "GV",
            descZh: "督脉行于背部正中线，沿脊柱上行至头顶。传统理论称其为“阳脉之海”，统领诸阳经。",
            descEn: "The Governing Vessel, running up the back midline along the spine to the head. Considered the “sea of the yang channels” in traditional theory."),
    ]
    static func by(_ id: String) -> Meridian? { all.first { $0.id == id } }
}
