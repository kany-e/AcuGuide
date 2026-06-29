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

    // Localized accessors for the atlas UI + the AR coach card.
    var location: String     { AppLocale.pick(locationZh, locationEn) }
    var indications: String  { AppLocale.pick(indicationsZh, indicationsEn) }
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
            // TE3 sits in the depression proximal to the 4th metacarpophalangeal joint, between
            // the 4th & 5th metacarpals (Acupoints.org; TCM Wiki). Bias toward the ring knuckle and
            // proximal (toward the wrist) so the target lands in the proximal groove, not on the web.
            mediapipeTarget: MediaPipeTarget(
                anchors: [
                    AnchorWeight(landmark: .ringMCP, weight: 0.45),
                    AnchorWeight(landmark: .pinkyMCP, weight: 0.30),
                    AnchorWeight(landmark: .wrist, weight: 0.25),
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
    ]
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
    ]
    static func color(_ id: String) -> Color { map[id] ?? Ink.gold }
}
