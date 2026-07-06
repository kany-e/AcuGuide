import Foundation

// Concern-driven ROUTINES — the front door users actually arrive with ("I can't sleep", "my neck is
// stiff"), chaining the existing session engine over 1–3 points. Steps referencing one of the 8
// camera-coached points run the AR coach; any other atlas point runs the guided TIMER session —
// the coached set stays EXACTLY the documented 8 (test-pinned). All copy follows the wellness
// rules (no treat/cure/heal/diagnose — scanned by testNoForbiddenMedicalClaims).
struct RoutineStep: Identifiable {
    let pointId: String
    let rounds: Int
    var id: String { pointId }
    var point: Acupoint? { Acupoint.byId[pointId] }
}

struct Routine: Identifiable {
    let id: String
    let zh: String, en: String
    let icon: String                 // SF Symbol for the card
    let descZh: String, descEn: String
    let steps: [RoutineStep]

    var name: String { AppLocale.pick(zh, en) }
    var desc: String { AppLocale.pick(descZh, descEn) }
    // Rough session length: rounds × 30s press + 10s rests between rounds/steps.
    var minutes: Int {
        let rounds = steps.reduce(0) { $0 + $1.rounds }
        let seconds = Double(rounds) * CoachConst.holdTargetS + Double(max(0, rounds - 1)) * CoachConst.restS
        return max(1, Int((seconds / 60).rounded()))
    }

    static let all: [Routine] = [
        Routine(id: "wind-down", zh: "睡前放松", en: "Evening wind-down", icon: "moon.stars",
                descZh: "睡前的温和收尾：神门与内关，配合缓慢呼吸，让身心安静下来。",
                descEn: "A gentle close to the day: Shenmen and Neiguan with slow breathing, letting body and mind settle.",
                steps: [RoutineStep(pointId: "HT7", rounds: 2), RoutineStep(pointId: "PC6", rounds: 2)]),
        Routine(id: "head-ease", zh: "头部舒缓", en: "Head-tension ease", icon: "brain.head.profile",
                descZh: "传统上用于头侧紧张的组合：中渚与外关。",
                descEn: "The pairing traditionally used for side-of-head tension: Zhongzhu and Waiguan.",
                steps: [RoutineStep(pointId: "TE3", rounds: 2), RoutineStep(pointId: "SJ5", rounds: 1)]),
        Routine(id: "neck-shoulders", zh: "颈肩放松", en: "Neck & shoulders", icon: "figure.arms.open",
                descZh: "伏案之后的颈肩组合：后溪与外关。",
                descEn: "The after-desk pairing for neck and shoulders: Houxi and Waiguan.",
                steps: [RoutineStep(pointId: "SI3", rounds: 2), RoutineStep(pointId: "SJ5", rounds: 2)]),
        Routine(id: "travel-calm", zh: "出行安稳", en: "Travel calm", icon: "airplane",
                descZh: "出行前后按压内关 — 恶心方向研究最多的穴位。",
                descEn: "Neiguan around travel — the point with the most studied record for nausea.",
                steps: [RoutineStep(pointId: "PC6", rounds: 3)]),
        Routine(id: "desk-wrists", zh: "桌前手腕", en: "Desk wrists", icon: "keyboard",
                descZh: "打字间隙照顾手腕：阳池与大陵。",
                descEn: "Care for typing wrists: Yangchi and Daling.",
                steps: [RoutineStep(pointId: "TE4", rounds: 2), RoutineStep(pointId: "PC7", rounds: 2)]),
        Routine(id: "grounding", zh: "引气归足", en: "Evening grounding", icon: "leaf",
                descZh: "计时引导的足部收尾：太冲与涌泉（无需相机，自行定位）。",
                descEn: "A timer-guided foot finish: Taichong and Yongquan (no camera — self-located).",
                steps: [RoutineStep(pointId: "LR3", rounds: 2), RoutineStep(pointId: "KI1", rounds: 2)]),
    ]
}
