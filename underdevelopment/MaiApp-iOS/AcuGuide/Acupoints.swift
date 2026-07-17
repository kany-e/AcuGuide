import SwiftUI

// Acupoint dataset — hand set ported from MaiApp/src/data.js, body regions added later (all
// WHO-2008 sourced). x,y are legacy 360×440 hand-chart coordinates (still used by search/data
// provenance only — ALL 3D marker positions are authored in AcupointPlacements, Placements3D.swift).
// `mediapipeTarget` drives the AR coach and is non-nil for the EIGHT documented coached points
// (test-pinned: TE3 SI3 PC8 HT7 PC6 SJ5 TE4 PC7); every other point is atlas/timer-only.
// LI4 (合谷) is excluded entirely — it is pregnancy-contraindicated and must never appear,
// not even in the atlas.

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
    // BCP-47 id for the TTS voice AND the speech recognizer (both must agree, and both used to
    // hardcode the same ternary — one source now).
    static var speechLocaleID: String { isChinese ? "zh-CN" : "en-US" }
    static var speechLocale: Locale { Locale(identifier: speechLocaleID) }
}

// The coach's friendly face — copy says "Acu" rather than "the camera" / "the AI" (user feedback:
// the machine-voiced phrasing read cold; name chosen by the user). Same name in both languages —
// it echoes the app name and sits naturally in Chinese prose ("我是 Acu", like "Siri 帮你…").
// ONE constant, interpolated everywhere, so a rename is a one-line change; it never replaces the
// honest "(On-device AI …)" labeling on generated replies.
enum CoachPersona {
    static let name = "Acu"
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
    let coachAlign: String  // authored AR cue (TE3 stores its own; the other 7 use coachCues)
    let coachHold: String   // authored AR cue (see coachAlignL/coachHoldL resolution below)
    var coachAlignZh: String = ""   // zh AR cue (authored per point; empty → coachCues table)
    var coachHoldZh: String = ""
    let mediapipeTarget: MediaPipeTarget?   // non-nil for the 8 coached points (test-pinned)
    var region: String = "hand"     // head/chest/abdomen/arm/leg/foot/hand — groups the body atlas
    var cautionZh: String = ""      // per-point safety note (shown in the detail card); empty = none
    var cautionEn: String = ""

    // Localized accessors for the atlas UI + the AR coach card.
    var location: String     { AppLocale.pick(locationZh, locationEn) }
    var indications: String  { AppLocale.pick(indicationsZh, indicationsEn) }
    var caution: String      { AppLocale.pick(cautionZh, cautionEn) }
    var meridianName: String { AppLocale.pick(meridianZh, meridianEn) }
    // AR cue accessors: prefer the point's own stored cue (TE3), else the shared per-point cue table
    // (the other 7 coachable points), so the searching-phase cue can be point-specific. See
    // Acupoint.coachCues. Sourced/verified: claude-deliverables/references/acuguide_source_upgrade.md.
    var coachAlignL: String {
        let t = Acupoint.coachCues[id]
        let zh = coachAlignZh.isEmpty ? (t?.alignZh ?? "") : coachAlignZh
        let en = coachAlign.isEmpty  ? (t?.alignEn ?? "") : coachAlign
        return AppLocale.pick(zh.isEmpty ? en : zh, en)
    }
    var coachHoldL: String {
        let t = Acupoint.coachCues[id]
        let zh = coachHoldZh.isEmpty ? (t?.holdZh ?? "") : coachHoldZh
        let en = coachHold.isEmpty  ? (t?.holdEn ?? "") : coachHold
        return AppLocale.pick(zh.isEmpty ? en : zh, en)
    }
    // Standard English name translation (e.g. "Inner Pass") + classical point role (Five-Shu, Yuan,
    // Luo, Front-Mu …). Both are factual TCM reference data drawn from a side table (below), so the
    // 27 point literals stay untouched. Cultural/traditional framing only — no medical claims.
    var englishName: String { Acupoint.englishNames[id] ?? "" }
    var roleEn: String { Acupoint.classicalRole[id]?.en ?? "" }
    var roleZh: String { Acupoint.classicalRole[id]?.zh ?? "" }
    var role: String { AppLocale.pick(roleZh, roleEn) }

    // Plain-language "find it by feel first" guide for the coached points (see Acupoint.findGuide).
    // Present only where authored; the coach shows it as a locate step BEFORE the camera so the user
    // has the spot under their finger before the marker appears.
    var hasFindGuide: Bool { Acupoint.findGuide[id] != nil }
    var findHow: String { AppLocale.pick(Acupoint.findGuide[id]?.findZh ?? "", Acupoint.findGuide[id]?.findEn ?? "") }
    var findFeel: String { AppLocale.pick(Acupoint.findGuide[id]?.feelZh ?? "", Acupoint.findGuide[id]?.feelEn ?? "") }

    // Plain read-aloud of WHERE the point is + how to find it, for the atlas "read aloud" button.
    var spokenInfo: String {
        var parts = [AppLocale.pick(zh, en), location]
        if hasFindGuide {
            parts.append(findHow)
            if !findFeel.isEmpty { parts.append(findFeel) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

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
            coachAlign: "Back of the hand up — feel for the soft groove just behind your ring and pinky knuckles.",
            coachHold: "Good — keep it steady, breathe slow, small easy circles.",
            coachAlignZh: "手背朝上，摸一摸无名指和小指指节后方的小凹沟。",
            coachHoldZh: "很好 — 稳稳按住，跟着呼吸，慢慢画小圈。",
            // TE3 anchors are FITTED FROM OWNED EXPERT LABELS (Jul 7 2026): 9 device-captured
            // labels (M3 harness, both hands; claude-deliverables/data/te3_labels_2026-07-07.jsonl),
            // shared-weight least squares in isotropic units, leave-one-out mean error 0.096·handSize
            // (max 0.154) — vs 0.233 mean / 1-of-9 inside tolerance for the previous WHO-text-derived
            // ring .46/pinky .34/wrist .20. The fit is more ULNAR and much more PROXIMAL than the
            // anatomical fractions suggested because Vision's MCP landmarks sit distal of the
            // anatomical joint heads (on the knuckle bumps) — exactly the bias text-derivation can't
            // see. Richer joint sets LOO-scored marginally better but with |w|≈2–3 (noise-amplifying
            // overfit on n=9); this 3-anchor form keeps every weight ≤ 0.5. Re-fit if more labels land.
            mediapipeTarget: MediaPipeTarget(
                anchors: [
                    AnchorWeight(landmark: .ringMCP, weight: 0.11),
                    AnchorWeight(landmark: .pinkyMCP, weight: 0.47),
                    AnchorWeight(landmark: .wrist, weight: 0.42),
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
            coachAlign: "", coachHold: "",
            // AR target — palmar forearm, 2 cun PROXIMAL to the wrist crease, between the tendons
            // (WHO 2008; who.int/publications/i/item/9789290613831). No forearm tracking, so this is
            // EXTRAPOLATED just past the wrist: wrist + 0.7·(wrist−middleMCP) ≈ 2 cun. Kept SHORT on
            // purpose — a larger factor amplifies hand rotation/jitter and the marker swings around.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .wrist,     weight: 1.7),
                AnchorWeight(landmark: .middleMCP, weight: -0.7),
            ], toleranceXHandSize: 0.22, pressFinger: .indexTip)
        ),
        Acupoint(
            id: "SJ5", zh: "外关", en: "Waiguan", pinyin: "Wàiguān",
            meridian: "sj", meridianZh: "手少阳三焦经", meridianEn: "Sanjiao Meridian",
            x: 174, y: 320, requiresDorsal: true,
            locationZh: "在前臂背侧，腕背横纹上约2寸，与内关相对。",
            locationEn: "On the dorsal side of the forearm, about two cun above the dorsal wrist crease, opposite Neiguan.",
            indicationsZh: "传统上常用于头侧不适、耳部不适、上肢酸楚等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for side-of-head discomfort, ear discomfort, and aching of the arm.",
            coachAlign: "", coachHold: "",
            // AR target — dorsal forearm, 2 cun proximal to the dorsal wrist crease, opposite PC6
            // (WHO 2008; sportsmedicineacupuncture.com/san-jiao-5-waiguan). Same 2-cun distance as
            // PC6, so the SAME short extrapolation: wrist + 0.7·(wrist−middleMCP). (A bigger factor —
            // the old 1.6 — made the marker swing as the forearm rotated.) Reliability: low.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .wrist,     weight: 1.7),
                AnchorWeight(landmark: .middleMCP, weight: -0.7),
            ], toleranceXHandSize: 0.24, pressFinger: .indexTip)
        ),
        Acupoint(
            id: "PC8", zh: "劳宫", en: "Laogong", pinyin: "Láogōng",
            meridian: "pc", meridianZh: "手厥阴心包经", meridianEn: "Pericardium Meridian",
            x: 186, y: 214, requiresDorsal: false,
            locationZh: "在手掌中央，约当第2、3掌骨之间偏于第3掌骨处。",
            locationEn: "At the center of the palm, between the second and third metacarpal bones, nearer the third.",
            indicationsZh: "传统上常与心烦、口部不适、手心热等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with restlessness, mouth discomfort, and warmth of the palms.",
            coachAlign: "", coachHold: "",
            // AR target — centre of the palm, between the 2nd/3rd metacarpals, just proximal to the
            // MCP line (WHO 2008; meandqi.com/.../laogong-pc-8). Interpolated inside the tracked
            // joints: middle-biased, radial (index), distal-of-centre toward the knuckles. Palmar.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .middleMCP, weight: 0.50),
                AnchorWeight(landmark: .indexMCP,  weight: 0.18),
                AnchorWeight(landmark: .wrist,     weight: 0.32),
            ], toleranceXHandSize: 0.16, pressFinger: .indexTip)
        ),
        Acupoint(
            id: "HT7", zh: "神门", en: "Shenmen", pinyin: "Shénmén",
            meridian: "heart", meridianZh: "手少阴心经", meridianEn: "Heart Meridian",
            x: 214, y: 262, requiresDorsal: false,
            locationZh: "在腕部，腕掌侧横纹尺侧端，尺侧腕屈肌腱的桡侧凹陷处。",
            locationEn: "At the wrist, on the ulnar end of the palmar crease, in the depression on the radial side of the flexor carpi ulnaris tendon.",
            indicationsZh: "传统上常与睡眠不安、心神不宁、情绪紧张等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with restless sleep, an unsettled spirit, and emotional tension.",
            coachAlign: "", coachHold: "",
            // AR target — ulnar end of the palmar wrist crease (WHO 2008;
            // meandqi.com/.../shenmen-ht-7). At the wrist, nudged toward the little-finger side. Palmar.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .wrist,    weight: 0.85),
                AnchorWeight(landmark: .pinkyMCP, weight: 0.15),
            ], toleranceXHandSize: 0.13, pressFinger: .indexTip)
        ),
        Acupoint(
            id: "SI3", zh: "后溪", en: "Houxi", pinyin: "Hòuxī",
            meridian: "si", meridianZh: "手太阳小肠经", meridianEn: "Small Intestine Meridian",
            x: 236, y: 174, requiresDorsal: true,
            locationZh: "在手尺侧，第5掌指关节后方，握拳时横纹尽头赤白肉际处。",
            locationEn: "On the ulnar side of the hand, in the depression proximal to the head of the fifth metacarpal bone, at the end of the crease when a loose fist is made.",
            indicationsZh: "传统上常用于颈项强紧、肩背不适、头侧不适等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for neck stiffness, shoulder and upper-back discomfort, and side-of-head discomfort.",
            coachAlign: "", coachHold: "",
            // AR target — ulnar border, proximal to the 5th MCP (WHO 2008; evidencebasedacupuncture.org
            // /smallintestine/si3-hou-xi). pinkyMCP heavy, pulled proximal (wrist) + ulnar (−ringMCP).
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .pinkyMCP, weight: 0.85),
                AnchorWeight(landmark: .wrist,    weight: 0.35),
                AnchorWeight(landmark: .ringMCP,  weight: -0.20),
            ], toleranceXHandSize: 0.15, pressFinger: .indexTip)
        ),

        // ── Additional hand atlas points (2D chart + 3D hand drill-down; no AR coaching). ───────
        // WHO Standard 2008 locations; fingertip-safe, none pregnancy-contraindicated (LI4 remains
        // excluded entirely). Shown wherever region=="hand" is listed (the 3D hand drill-down);
        // NOT added to the full-body mitten markers (Meridians.acuMarkers) — the low-poly body hand
        // has no fingers to place them against; the drill-down is the hand's canonical chart.
        Acupoint(
            id: "TE2", zh: "液门", en: "Yemen", pinyin: "Yèmén",
            meridian: "sj", meridianZh: "手少阳三焦经", meridianEn: "Sanjiao Meridian",
            x: 238, y: 128, requiresDorsal: true,
            locationZh: "在手背，第4、5指缝间，指蹼缘后方赤白肉际处。",
            locationEn: "On the back of the hand, between the ring and little fingers, just proximal to the margin of the web.",
            indicationsZh: "传统上常用于头侧不适、耳部不适、咽喉不适等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for side-of-head discomfort, ear discomfort, and throat discomfort.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil
        ),
        Acupoint(
            id: "HT8", zh: "少府", en: "Shaofu", pinyin: "Shàofǔ",
            meridian: "heart", meridianZh: "手少阴心经", meridianEn: "Heart Meridian",
            x: 222, y: 196, requiresDorsal: false,
            locationZh: "在手掌，第4、5掌骨之间，握拳时小指尖所指处。",
            locationEn: "On the palm, between the fourth and fifth metacarpal bones — where the tip of the little finger lands when a fist is made.",
            indicationsZh: "传统上常与心烦、掌心发热、睡眠不安等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with restlessness, warmth in the palm, and unsettled sleep.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil
        ),
        Acupoint(
            id: "LU10", zh: "鱼际", en: "Yuji", pinyin: "Yújì",
            meridian: "lung", meridianZh: "手太阴肺经", meridianEn: "Lung Meridian",
            x: 128, y: 232, requiresDorsal: false,
            locationZh: "在手掌，第1掌骨中点桡侧，赤白肉际处（大鱼际隆起边缘）。",
            locationEn: "On the palm, at the midpoint of the first metacarpal bone on its radial side, at the border of the thenar eminence.",
            indicationsZh: "传统上常用于咽喉不适、咳嗽、掌心发热等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for throat discomfort, cough, and warmth in the palm.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil
        ),
        Acupoint(
            id: "LU9", zh: "太渊", en: "Taiyuan", pinyin: "Tàiyuān",
            meridian: "lung", meridianZh: "手太阴肺经", meridianEn: "Lung Meridian",
            x: 148, y: 266, requiresDorsal: false,
            locationZh: "在腕部，腕掌侧横纹桡侧端，桡动脉搏动处的凹陷中。",
            locationEn: "At the wrist, on the radial end of the palmar crease, in the depression beside the radial artery.",
            indicationsZh: "传统上常与咳嗽、气短、腕部酸楚等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with cough, shortness of breath, and aching of the wrist.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil,
            cautionZh: "此处可触及桡动脉搏动，按压需轻柔，勿用力压迫脉搏。",
            cautionEn: "The radial pulse runs here — keep pressure light and avoid pressing hard on the artery."
        ),
        Acupoint(
            id: "LI5", zh: "阳溪", en: "Yangxi", pinyin: "Yángxī",
            meridian: "li", meridianZh: "手阳明大肠经", meridianEn: "Large Intestine Meridian",
            x: 140, y: 252, requiresDorsal: true,
            locationZh: "在腕背侧横纹桡侧，拇指上翘时两条肌腱之间的凹陷（鼻烟窝）中。",
            locationEn: "On the radial side of the dorsal wrist crease, in the hollow between the two tendons that appears when the thumb is raised (the anatomical snuffbox).",
            indicationsZh: "传统上常用于腕部不适、拇指侧紧张、头面不适等相关调理。",
            indicationsEn: "Traditionally used in acupuncture practice for wrist discomfort, thumb-side tension, and discomfort of the head and face.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil
        ),
        Acupoint(
            id: "SI4", zh: "腕骨", en: "Wangu", pinyin: "Wàngǔ",
            meridian: "si", meridianZh: "手太阳小肠经", meridianEn: "Small Intestine Meridian",
            x: 240, y: 224, requiresDorsal: true,
            locationZh: "在手尺侧，第5掌骨底与三角骨之间的凹陷处，赤白肉际。",
            locationEn: "On the ulnar side of the hand, in the depression between the base of the fifth metacarpal bone and the triquetrum.",
            indicationsZh: "传统上常与腕尺侧不适、颈项强紧等相关联。",
            indicationsEn: "Commonly associated in acupuncture practice with discomfort on the ulnar side of the wrist and neck stiffness.",
            coachAlign: "", coachHold: "",
            mediapipeTarget: nil
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
            coachAlign: "", coachHold: "",
            // AR target — dorsal wrist crease, ulnar to the extensor digitorum tendon (WHO 2008;
            // acupoints.org/te4-acupuncture-point). At the wrist, slightly toward the ring/ulnar side.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .wrist,     weight: 0.84),
                AnchorWeight(landmark: .middleMCP, weight: 0.09),
                AnchorWeight(landmark: .ringMCP,   weight: 0.07),
            ], toleranceXHandSize: 0.16, pressFinger: .indexTip),
            region: "arm",
            cautionZh: "在腕背用指腹轻柔按压；若有疼痛或麻木即停。",
            cautionEn: "Light fingertip pressure on the back of the wrist; stop if you feel pain or numbness."),
        Acupoint(id: "PC7", zh: "大陵", en: "Daling", pinyin: "Dàlíng",
            meridian: "pc", meridianZh: "手厥阴心包经", meridianEn: "Pericardium Meridian",
            x: 0, y: 0, requiresDorsal: false,
            locationZh: "在腕前区，腕掌侧远端横纹中，掌长肌腱与桡侧腕屈肌腱之间。",
            locationEn: "On the palm-side of the wrist, at the wrist crease, midway between the two tendons (palmaris longus and flexor carpi radialis) (WHO Standard 2008).",
            indicationsZh: "传统上常与平静放松的心境以及手腕的舒适感相关联。",
            indicationsEn: "Traditionally associated with a calm, settled mind and comfort of the wrist.",
            coachAlign: "", coachHold: "",
            // AR target — midpoint of the palmar wrist crease, between the PL & FCR tendons (WHO 2008;
            // meandqi.com/.../daling-pc-7). The wrist landmark sits on the crease centre. Palmar.
            mediapipeTarget: MediaPipeTarget(anchors: [
                AnchorWeight(landmark: .wrist,     weight: 0.90),
                AnchorWeight(landmark: .middleMCP, weight: 0.10),
            ], toleranceXHandSize: 0.12, pressFinger: .indexTip),
            region: "arm",
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

    // ── Reference side tables (factual TCM data; sourced + verified) ──────────────────────────────
    // See claude-deliverables/references/acuguide_source_upgrade.md. Kept out of the 27 point
    // literals so a data refresh is one edit here. No treat/cure/heal/diagnose copy (test-enforced).

    // Standard English name translations of the point names (Deadman / WHO-style).
    static let englishNames: [String: String] = [
        "TE3": "Central Islet", "PC6": "Inner Pass", "SJ5": "Outer Pass", "PC8": "Palace of Toil",
        "HT7": "Spirit Gate", "SI3": "Back Ravine", "EX-HN3": "Hall of Impression",
        // EX-HN5 (太阳) has no separate translation — its recognised name IS "Taiyang" (the point's `en`).
        "GV20": "Hundred Meetings", "EX-HN1": "Four Alert Spirits", "CV17": "Chest Centre", "KI27": "Shu Mansion",
        "CV12": "Central Venter", "ST25": "Celestial Pivot", "LI11": "Pool at the Bend", "LU5": "Cubit Marsh",
        "TE4": "Yang Pool", "PC7": "Great Mound", "ST36": "Leg Three Li", "GB34": "Yang Mound Spring",
        "SP10": "Sea of Blood", "ST34": "Beam Hill", "ST35": "Calf's Nose", "LR3": "Supreme Surge",
        "ST44": "Inner Court", "KI1": "Gushing Spring", "KI3": "Supreme Stream",
        "TE2": "Fluid Gate", "HT8": "Lesser Mansion", "LU10": "Fish Border",
        "LU9": "Supreme Abyss", "LI5": "Yang Ravine", "SI4": "Wrist Bone",
    ]

    // Classical point category / role (Yin Yang House, each verified live; corroborated by the Atlas
    // command-point tables). Cultural framing of a point's traditional role and channel — not a claim.
    static let classicalRole: [String: (en: String, zh: String)] = [
        "TE3": ("Shu-Stream (Wood) point of the Sanjiao channel", "手少阳三焦经 输(木)穴"),
        "PC6": ("Luo-Connecting & Command point of the Pericardium; Master point of the Yin Wei vessel (paired with SP4)", "手厥阴心包经 络穴、八脉交会穴(通阴维脉,配公孙)"),
        "SJ5": ("Luo-Connecting point of the Sanjiao; Master point of the Yang Wei vessel (paired with GB41)", "手少阳三焦经 络穴、八脉交会穴(通阳维脉,配足临泣)"),
        "PC8": ("Ying-Spring (Fire) point of the Pericardium; also its Exit and a Ghost point", "手厥阴心包经 荥(火)穴、出穴、鬼穴"),
        "HT7": ("Yuan-Source & Shu-Stream (Earth) point of the Heart", "手少阴心经 原穴、输(土)穴"),
        "SI3": ("Shu-Stream (Wood) & Tonification point of the Small Intestine; Master point of the Governing Vessel (paired with BL62)", "手太阳小肠经 输(木)穴、补穴;八脉交会穴(通督脉,配申脉)"),
        "EX-HN3": ("Extra (non-channel) point between the eyebrows", "经外奇穴（印堂）"),
        "EX-HN5": ("Extra (non-channel) point at the temple", "经外奇穴（太阳）"),
        "GV20": ("Sea-of-Marrow point; meeting of the Governing Vessel with the yang channels", "督脉 百会;髓海、诸阳之会"),
        "EX-HN1": ("Four extra (non-channel) points around GV20 at the vertex", "经外奇穴（四神聪）"),
        "CV17": ("Hui-Meeting (Influential) point of Qi; Front-Mu point of the Pericardium", "任脉 气会、心包募穴"),
        "CV12": ("Front-Mu point of the Stomach; Hui-Meeting (Influential) point of the Fu organs", "任脉 胃募穴、腑会"),
        "ST25": ("Front-Mu point of the Large Intestine", "足阳明胃经 大肠募穴"),
        "LI11": ("He-Sea (Earth) & Tonification point of the Large Intestine; also a Ghost point", "手阳明大肠经 合(土)穴、补穴、鬼穴"),
        "LU5": ("He-Sea (Water) point of the Lung", "手太阴肺经 合(水)穴"),
        "TE4": ("Yuan-Source point of the Sanjiao", "手少阳三焦经 原穴"),
        "PC7": ("Shu-Stream (Earth) & Yuan-Source point of the Pericardium; also a Ghost point", "手厥阴心包经 输(土)穴、原穴、鬼穴"),
        "ST36": ("He-Sea (Earth) & Lower-He-Sea point of the Stomach; Sea of Water & Grain; Command point of the abdomen", "足阳明胃经 合(土)穴、下合穴;水谷之海、四总穴(肚腹)"),
        "GB34": ("He-Sea (Earth) & Lower-He-Sea point of the Gallbladder; Hui-Meeting (Influential) point of the sinews", "足少阳胆经 合(土)穴、下合穴、筋会"),
        "SP10": ("A point of the Spleen channel", "足太阴脾经（血海）"),
        "ST34": ("Xi-Cleft (Accumulation) point of the Stomach", "足阳明胃经 郄穴"),
        "LR3": ("Shu-Stream (Earth) & Yuan-Source point of the Liver", "足厥阴肝经 输(土)穴、原穴"),
        "ST44": ("Ying-Spring (Water) point of the Stomach", "足阳明胃经 荥(水)穴"),
        "KI1": ("Jing-Well (Wood) point of the Kidney", "足少阴肾经 井(木)穴"),
        "KI3": ("Shu-Stream (Earth) & Yuan-Source point of the Kidney", "足少阴肾经 输(土)穴、原穴"),
        "TE2": ("Ying-Spring (Water) point of the Sanjiao", "手少阳三焦经 荥(水)穴"),
        "HT8": ("Ying-Spring (Fire) point of the Heart", "手少阴心经 荥(火)穴"),
        "LU10": ("Ying-Spring (Fire) point of the Lung", "手太阴肺经 荥(火)穴"),
        "LU9": ("Yuan-Source & Shu-Stream (Earth) point of the Lung; Hui-Meeting (Influential) point of the vessels", "手太阴肺经 原穴、输(土)穴;脉会"),
        "LI5": ("Jing-River (Fire) point of the Large Intestine", "手阳明大肠经 经(火)穴"),
        "SI4": ("Yuan-Source point of the Small Intestine", "手太阳小肠经 原穴"),
    ]

    // Per-point AR alignment + hold cues for the 8 coachable hand/wrist points (TE3 keeps its own in
    // the literal). Sharpened with Yin Yang House self-location tricks; the WHO-anchored math is
    // unchanged. Fed into the live searching-phase cue via coachAlignL / coachHoldL.
    static let coachCues: [String: (alignEn: String, holdEn: String, alignZh: String, holdZh: String)] = [
        "PC6": ("Palm up. Three finger-widths above the wrist crease, in the groove between the two central tendons.",
                "Good — settle in, and let your breathing slow right down.",
                "掌心朝上。腕横纹上三横指，两条中央肌腱之间的凹沟处。",
                "很好 — 稳稳按住，让呼吸慢慢沉下来。"),
        "SJ5": ("Back of the forearm up. Three finger-widths above the wrist crease, between the two bones — directly opposite Neiguan.",
                "Nice — light and steady, easy breaths.",
                "前臂背面朝上。腕背横纹上三横指，两骨之间，正对内关。",
                "很好 — 力度轻而稳，呼吸放缓。"),
        "PC8": ("Palm up. Curl your middle finger to the palm — press where its tip lands, in the centre.",
                "Good — a soft, steady press; let the whole palm relax.",
                "掌心朝上。将中指弯向掌心，指尖所落的掌心中央处即是。",
                "很好 — 柔柔按住，让整个手掌放松。"),
        "HT7": ("Palm up. Find the small round bone at the little-finger base of the palm; the point sits just inside it on the wrist crease.",
                "Good — a light, steady hold; let your shoulders soften too.",
                "掌心朝上。找到小指侧掌根的小圆骨，穴位就在其内侧的腕横纹上。",
                "很好 — 轻轻按住，肩膀也一起放松。"),
        "SI3": ("Make a loose fist. Find the very end of the palm crease on the little-finger side, where the skin colour changes.",
                "Nice — steady right there, slow easy breaths.",
                "轻轻握拳。找到小指侧掌横纹的尽头、手心和手背肤色交界处。",
                "很好 — 就这样稳稳按住，慢慢呼吸。"),
        "TE4": ("Back of the wrist up. On the wrist crease, in the hollow toward the little-finger side of the central tendon.",
                "Good — gentle and steady, along with your breath.",
                "手腕背面朝上。腕背横纹上，中央肌腱靠小指侧的凹陷处。",
                "很好 — 轻而稳地按住，跟着呼吸。"),
        "PC7": ("Palm up. The middle of the wrist crease, in the hollow between the two central tendons.",
                "Good — a light, steady press; let the wrist go loose.",
                "掌心朝上。腕掌横纹正中，两条中央肌腱之间的凹陷处。",
                "很好 — 轻轻按住，让手腕放松下来。"),
    ]

    // Plain-language "find it by feel" guide for the locate step BEFORE the camera coach — so the
    // user has the real spot under their finger, then the marker just confirms it. Deliberately
    // JARGON-FREE (knuckles, not "metacarpophalangeal"; tendons you can see, not Latin names),
    // sourced from the same WHO 2008 + iaomai.app locations as `location`, rewritten for a beginner.
    // Each entry: how to find it, then the sensation that confirms it. Wellness self-care only.
    static let findGuide: [String: (findEn: String, feelEn: String, findZh: String, feelZh: String)] = [
        "TE3": ("Back of the hand up. Slide a fingertip down the gap between your ring and little-finger knuckles; just behind them you drop into a small dip between the two hand bones.",
                "Feel the small tender dip between the bones?",
                "手背朝上。沿无名指与小指指节之间的缝向下滑，指节后方能摸到两根手骨之间的小凹陷。",
                "摸到两骨之间那个略酸的小凹陷了吗？"),
        "SI3": ("Make a loose fist. On the little-finger edge of your hand, find where the main palm crease ends — the spot is just behind the knuckle, where palm skin meets back-of-hand skin.",
                "Feel where the crease ends on the side of your hand?",
                "轻轻握拳。在手的小指侧，找到掌横纹的尽头 — 穴位就在指节后方、手心和手背肤色交界的地方。",
                "摸到手侧掌纹尽头的位置了吗？"),
        "PC8": ("Palm up. Curl your middle finger in until its tip touches your palm — the spot is right where the tip lands, in the centre of the palm.",
                "Fingertip resting in the centre of your palm?",
                "掌心朝上。把中指弯向掌心，指尖触到掌心处即是 — 就在手掌正中。",
                "指尖正落在掌心中央了吗？"),
        "HT7": ("Palm up. Run a finger along the wrist crease toward the little-finger side until you meet a small pea-shaped bone; the spot sits just before it, on the crease.",
                "Feel the little round bone at the base of the palm?",
                "掌心朝上。沿腕横纹向小指侧摸，会碰到一颗豌豆大的小圆骨 — 穴位就在它前方的横纹上。",
                "摸到掌根那颗小圆骨了吗？"),
        "PC6": ("Palm up. Lay three fingers across the forearm just above the wrist crease; the spot is under the far edge of your third finger, between the two tendons that rise when you cup your hand.",
                "Feel the two tendons under your fingertip?",
                "掌心朝上。三横指并拢放在腕横纹上方，第三指外侧缘下、两条肌腱之间即是（手掌微握时肌腱会浮起）。",
                "指尖下摸到那两条肌腱了吗？"),
        "SJ5": ("Back of the forearm up. Measure three fingers above the wrist crease, midway between the two forearm bones — directly opposite Neiguan on the palm side.",
                "Midway between the two forearm bones, three fingers up?",
                "前臂背面朝上。腕背横纹上三横指，两骨之间正中 — 与掌面的内关正相对。",
                "在腕上三横指、两骨正中了吗？"),
        "TE4": ("Back of the wrist up. Follow the wrist crease from the base of your ring finger; the spot is a soft hollow on the crease, just to the little-finger side of the tendon.",
                "Feel the soft hollow on the back of the wrist?",
                "手腕背面朝上。从无名指根部沿腕背横纹摸，穴位是横纹上的一个软凹陷、在肌腱靠小指侧。",
                "摸到腕背横纹上的软凹陷了吗？"),
        "PC7": ("Palm up. The spot is in the middle of the wrist crease, in the dip between the two tendons that rise when you cup your hand.",
                "In the centre dip of the wrist crease?",
                "掌心朝上。穴位在腕掌横纹正中，两条肌腱之间的凹陷处（手掌微握时肌腱浮起）。",
                "在腕横纹正中的凹陷里了吗？"),
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
            descZh: "起于胸部近腋处，沿上肢内侧前缘下行至腕部桡侧，止于拇指桡侧端。传统中医将其与肺与呼吸相联系，沿经穴位传统上与咳嗽、气喘及咽喉舒适相关联。",
            descEn: "Runs from the chest near the armpit down the anterior-inner edge of the arm to the radial (thumb) side of the wrist, ending at the thumb. In traditional Chinese medicine it is associated with the lungs and breathing; its points are traditionally linked with cough, wheezing, and throat comfort."),
        Meridian(id: "li", zh: "手阳明大肠经", en: "Large Intestine", ab: "LI",
            descZh: "起于食指，沿前臂背侧桡缘与上肢外侧上行至肩、颈与面颊，止于鼻旁。传统上与大肠相关，其穴位常与面、鼻、齿及肠胃方面的调理相关联。",
            descEn: "Travels from the index finger up the back-outer (radial) forearm and the lateral arm to the shoulder, neck, and cheek, ending beside the nose. Traditionally linked to the large intestine; its points are classically associated with the face, nose, teeth, and digestive comfort."),
        Meridian(id: "stomach", zh: "足阳明胃经", en: "Stomach", ab: "ST",
            descZh: "起于面部，沿身体前面与下肢前外侧下行至第二趾。传统理论中与胃和消化相关。",
            descEn: "Descends from the face down the front of the torso and the front-outer aspect of the leg to the second toe. Associated with the stomach and digestion in traditional theory."),
        Meridian(id: "spleen", zh: "足太阴脾经", en: "Spleen", ab: "SP",
            descZh: "起于足大趾内侧，沿足与下肢内侧（赤白肉际）上行，经大腿前内侧入腹，上行至胸侧。传统上与脾、消化及运化水谷相关。",
            descEn: "Ascends from the inner big toe along the inner foot and leg (at the red-white skin line), through the inner thigh to the abdomen and the side of the chest. Associated with the spleen, digestion, and the transformation of food in traditional theory."),
        Meridian(id: "heart", zh: "手少阴心经", en: "Heart", ab: "HT",
            descZh: "起于腋窝中央，沿上肢内侧后缘下行，经腕部尺侧至小指桡侧端。传统上与心及神志相关。",
            descEn: "Runs from the centre of the armpit down the inner-back edge of the arm, past the little-finger side of the wrist, to the tip of the little finger. Traditionally linked to the heart and the mind."),
        Meridian(id: "si", zh: "手太阳小肠经", en: "Small Intestine", ab: "SI",
            descZh: "起于小指尺侧，沿手掌尺缘与上肢后外侧上行至肩胛，再经颈、颊上行至耳前。传统上与小肠相关。",
            descEn: "Travels from the little finger along the outer (ulnar) edge of the hand and the back of the arm to the shoulder blade, then up the neck and cheek to the front of the ear. Associated with the small intestine."),
        Meridian(id: "bladder", zh: "足太阳膀胱经", en: "Bladder", ab: "BL",
            descZh: "为十二经中最长者，起于内眼角，过头顶后沿背部两线下行，经下肢后侧至小趾。传统上与膀胱相关。",
            descEn: "The longest of the twelve channels: from the inner corner of the eye over the vertex and down the back in two lines, along the back of the leg to the little toe. Associated with the bladder."),
        Meridian(id: "kidney", zh: "足少阴肾经", en: "Kidney", ab: "KI",
            descZh: "起于足底，经内踝后方沿下肢内侧上行至腹部，止于锁骨下缘凹陷处。传统理论中与肾及人体根本之气相关。",
            descEn: "Rises from the sole of the foot, behind the inner ankle and up the inner leg to the abdomen, ending in the hollow below the collarbone. Associated with the kidneys and the body’s foundational vitality in traditional theory."),
        Meridian(id: "pc", zh: "手厥阴心包经", en: "Pericardium", ab: "PC",
            descZh: "起于胸部乳旁，沿上肢内侧中线下行，经前臂两筋之间过手掌，止于中指尖。传统上与心包相关，护卫心脏。",
            descEn: "Runs from the chest beside the nipple down the middle of the inner arm, between the two forearm tendons, across the palm to the tip of the middle finger. Associated with the pericardium, which is said to protect the heart."),
        Meridian(id: "sj", zh: "手少阳三焦经", en: "Sanjiao", ab: "SJ",
            descZh: "起于无名指，经第4、5掌骨之间沿腕背与前臂背侧上行，过肘沿上肢外侧至肩，再上行至颈，环绕耳部。传统上与“三焦”即人体水液与气机的通道相关。",
            descEn: "Travels from the ring finger between the 4th and 5th knuckles, up the back of the wrist and forearm, past the elbow and along the outer arm to the shoulder, then up the neck to circle the ear. Linked to the “triple burner”, the traditional passages for the body’s fluids and qi."),
        Meridian(id: "gb", zh: "足少阳胆经", en: "Gallbladder", ab: "GB",
            descZh: "起于外眼角，绕耳与颞部、越头顶后沿颈与躯干侧面及下肢外侧下行至第四趾。传统上与胆及身体两侧相关。",
            descEn: "Zig-zags from the outer corner of the eye around the ear and over the head, down the side of the neck and trunk and the outer leg to the fourth toe. Traditionally associated with the gallbladder and the sides of the body."),
        Meridian(id: "liver", zh: "足厥阴肝经", en: "Liver", ab: "LR",
            descZh: "起于足大趾，经足背沿下肢内侧上行，过外阴至小腹与胁肋。传统上与肝及气机的疏泄相关。",
            descEn: "Ascends from the big toe over the top of the foot and up the inner leg, past the genitals to the lower abdomen and ribs. Associated with the liver and the smooth flow of qi in traditional theory."),
        Meridian(id: "ren", zh: "任脉", en: "Ren Mai", ab: "RN",
            descZh: "任脉自会阴沿身体前正中线上行，过腹、胸至咽喉与颏部。传统理论称其为“阴脉之海”，统领诸阴经。",
            descEn: "The Conception Vessel, running from the perineum up the front midline through the abdomen and chest to the throat and chin. Considered the “sea of the yin channels” in traditional theory."),
        Meridian(id: "du", zh: "督脉", en: "Du Mai", ab: "GV",
            descZh: "督脉自尾骨沿脊柱上行至项，越头顶后沿前额与鼻下行至上唇。传统理论称其为“阳脉之海”，统领诸阳经。",
            descEn: "The Governing Vessel, running from the tailbone up the spine to the nape, over the vertex and down the forehead and nose to the upper lip. Considered the “sea of the yang channels” in traditional theory."),
    ]
    static func by(_ id: String) -> Meridian? { all.first { $0.id == id } }
}
