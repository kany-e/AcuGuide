import SwiftUI

// Mirrors MaiApp's data.js. x,y are in the 360 x 440 hand-SVG coordinate box used by
// the 2D HandAtlasView. `mediapipeTarget` drives the AR coach (anchor weights on the
// Vision hand landmarks). Paste the full ACUPOINTS list from data.js into `all` — this
// includes TE3 (the validated AR demo point) plus a few examples.

struct AnchorWeight: Hashable {
    let landmark: HandJoint   // which Vision joint
    let weight: Double
}

struct MediaPipeTarget: Hashable {
    let anchors: [AnchorWeight]          // weighted sum of landmarks
    let toleranceXHandSize: Double       // hit radius as a fraction of hand size
    let pressFinger: HandJoint           // which fingertip presses (INDEX_TIP for TE3)
}

struct Acupoint: Identifiable, Hashable {
    let id: String          // "TE3"
    let zh: String          // 中渚
    let pinyin: String      // Zhongzhu
    let meridian: String    // "sj"
    let x: Double           // hand-SVG x (0...360)
    let y: Double           // hand-SVG y (0...440)
    let requiresDorsal: Bool
    let coachAlign: String
    let coachHold: String
    let mediapipeTarget: MediaPipeTarget?   // nil for atlas-only points

    static let all: [Acupoint] = [
        Acupoint(
            id: "TE3", zh: "中渚", pinyin: "Zhongzhu", meridian: "sj",
            x: 232, y: 150, requiresDorsal: true,
            coachAlign: "Back of the hand up. Find the groove behind your ring and pinky knuckles.",
            coachHold: "Good — firm, steady pressure with slow breathing, small gentle circles.",
            mediapipeTarget: MediaPipeTarget(
                anchors: [
                    AnchorWeight(landmark: .ringMCP, weight: 0.45),
                    AnchorWeight(landmark: .pinkyMCP, weight: 0.40),
                    AnchorWeight(landmark: .wrist, weight: 0.15),
                ],
                toleranceXHandSize: 0.16,
                pressFinger: .indexTip
            )
        ),
        // Atlas-only examples (no AR coaching this round):
        Acupoint(id: "SI3", zh: "后溪", pinyin: "Houxi", meridian: "si",
                 x: 250, y: 250, requiresDorsal: true,
                 coachAlign: "Pinky edge of the hand, below the knuckle.",
                 coachHold: "Steady pressure.", mediapipeTarget: nil),
        Acupoint(id: "HT7", zh: "神门", pinyin: "Shenmen", meridian: "heart",
                 x: 150, y: 360, requiresDorsal: false,
                 coachAlign: "Wrist crease, pinky side.",
                 coachHold: "Light, steady pressure.", mediapipeTarget: nil),
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
