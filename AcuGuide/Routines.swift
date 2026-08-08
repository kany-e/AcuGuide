import Foundation

// Concern-driven ROUTINES — the front door users actually arrive with ("I can't sleep", "my neck is
// stiff"), chaining the existing session engine over 1–3 points. Steps referencing one of the 8
// camera-coached points run the AR coach; any other atlas point runs the guided TIMER session —
// the coached set stays EXACTLY the documented 8 (test-pinned). All copy follows the wellness
// rules (no treat/cure/heal/diagnose — scanned by testNoForbiddenMedicalClaims).
// A named hand technique. The practitioner's point was that a "complete" sequence specifies more
// than which points and for how long — it specifies WHAT THE HAND DOES, and the answer differs by
// region. These are the 推拿 verbs, kept as data so a step can say which one it means instead of the
// copy having to describe it in prose each time.
enum RoutineTechnique: String {
    case press   = "按"   // steady perpendicular pressure — the app's existing hold
    case knead   = "揉"   // small circles, skin moving with the finger
    case push    = "推"   // a straight stroke along a line
    case grasp   = "拿"   // lift-and-squeeze between thumb and fingers
    case pointed = "点"   // concentrated fingertip pressure, briefest of the five

    var zh: String { rawValue }
    var en: String {
        switch self {
        case .press:   return "press"
        case .knead:   return "knead"
        case .push:    return "push"
        case .grasp:   return "grasp"
        case .pointed: return "point-press"
        }
    }
}

// Where a step sits in the classical structure: the LOCAL point at the area itself, then a DISTAL
// one further along the related channel (近部取穴 + 循经远取). The app's routines already paired
// points but had no way to say which was which, so a head sequence could not be expressed at all —
// which is exactly the gap the practitioner identified with 太阳 → 中渚.
enum RoutineRole { case local, distal }

struct RoutineStep: Identifiable {
    let pointId: String
    let rounds: Int
    var technique: RoutineTechnique = .press
    var role: RoutineRole = .distal
    var id: String { pointId }
    var point: Acupoint? { Acupoint.byId[pointId] }

    /// Seconds of accumulated hold this step asks for.
    var holdSeconds: Double { Double(rounds) * CoachConst.holdTargetS }
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
    var minutes: Int { Self.minutes(forRounds: steps.reduce(0) { $0 + $1.rounds }) }

    // THE session-minutes estimate (n rounds of hold + the rests between them, floored at 1) —
    // routine cards, the builder preview and the single-point stepper all quote this one number.
    static func minutes(forRounds n: Int) -> Int {
        let seconds = Double(n) * CoachConst.holdTargetS + Double(max(0, n - 1)) * CoachConst.restS
        return max(1, Int((seconds / 60).rounded()))
    }

    // EXTEND BY ADDING POINTS, NOT BY INFLATING ONE.
    //
    // The practitioner said the routines were too short and she was right: `head-ease` was TE3 ×2 +
    // SJ5 ×1 — 90 seconds of accumulated hold across the whole routine, against a taught 60–120
    // seconds PER POINT. But "extend" has a correct axis and an incorrect one. Self-acupressure
    // guidance converges on 1–3 minutes per point, and a 2025 meta-regression found sessions per
    // DAY positively correlated with outcome while the duration of each session correlated
    // NEGATIVELY. There is a tissue ceiling too — over-long work produces 皮下出血, and published
    // rhabdomyolysis cases exist after sustained strong massage.
    //
    // So the per-point cap is structural rather than a warning string, and routines grow by
    // chaining more points. 6 rounds = 180 s, the top of the taught range.
    static let maxRoundsPerStep = 6
    /// The most points one routine may chain. A sequence long enough to need its own pre-checks
    /// (an hour after eating, stop on a new symptom) is a different thing from a two-minute press,
    /// and 6 is where the taught self-massage sequences sit.
    static let maxSteps = 6

    // MOVING ROUTINES ONTO THE HEAD CROSSES INTO A HIGHER-RISK ZONE than fingertip work on a wrist,
    // and this is the one genuinely new hazard the extended sequences introduce.
    //
    // The oculocardiac reflex fires from pressure on the eye globe OR the periorbital structures via
    // a trigeminal–vagal arc, and its documented outcomes are bradycardia, arrhythmia and asystole.
    // The atlas already carries 印堂 EX-HN3 between the brows and 太阳 EX-HN5 at the temple, so this
    // is reachable today, not hypothetical. Separately, deliberate carotid sinus massage is a
    // clinical manoeuvre performed under monitoring — the anterior neck is not somewhere a phone
    // should route a user to press.
    //
    // Kept as a set the routine builder checks rather than as a sentence in a caution string,
    // because a warning can be read and ignored while a structural exclusion cannot. Pinned by test,
    // in the same spirit as the camera-coached eight.
    enum Region: String, CaseIterable {
        case eyeGlobe, anteriorNeck
        var zh: String {
            switch self {
            case .eyeGlobe:     return "眼球本身（只按眼眶骨缘）"
            case .anteriorNeck: return "颈前部、喉结两侧"
            }
        }
        var en: String {
            switch self {
            case .eyeGlobe:     return "the eyeball itself — bony rim of the socket only"
            case .anteriorNeck: return "the front of the neck, either side of the windpipe"
            }
        }
    }
    static let excludedRegions = Region.allCases

    static let all: [Routine] = [
        Routine(id: "wind-down", zh: "睡前放松", en: "Evening wind-down", icon: "moon.stars",
                descZh: "睡前的温和收尾：神门与内关，配合缓慢呼吸，让身心安静下来。",
                descEn: "A gentle close to the day: Shenmen and Neiguan with slow breathing, letting body and mind settle.",
                steps: [RoutineStep(pointId: "HT7", rounds: 2), RoutineStep(pointId: "PC6", rounds: 2)]),
        // THE PRACTITIONER'S SEQUENCE: 太阳 → 中渚, local anchor first, then distal along the
        // related channel. Her point was that the old version had no local step at all — it started
        // at the hand and never touched the area the tension is actually in — and that 90 seconds
        // across the whole routine was too short.
        //
        // WORDING THAT MUST NOT DRIFT: 太阳 EX-HN5 is an 经外奇穴, an extra point, and by definition
        // NOT part of the fourteen-channel nomenclature — so it is not "a Sanjiao point". And the
        // textbook distal for the sides of the head is FOOT-shaoyang GB43; borrowing hand-shaoyang
        // TE3 is legitimised by 同名经取穴, the same-name-channel principle, plus TE3's own standing
        // as the Shu-Stream point of its channel. The description says the channel runs past the
        // temple, which is true (《灵枢·经脉》 traces it past 客主人 to the outer canthus), and stops
        // short of the two claims that would be false.
        Routine(id: "head-ease", zh: "头部舒缓", en: "Head-tension ease", icon: "brain.head.profile",
                descZh: "先在太阳穴局部轻揉，再取手少阳经远端的外关与中渚——这条经络经过耳前与颞侧。面部力度要比身体轻很多。",
                descEn: "Knead lightly at the temple first, then work outward to Waiguan and Zhongzhu on the hand-Shaoyang channel, which runs past the ear and temple. Use much lighter pressure on the face than on the body.",
                steps: [RoutineStep(pointId: "EX-HN5", rounds: 2, technique: .knead, role: .local),
                        RoutineStep(pointId: "SJ5", rounds: 2, technique: .press, role: .distal),
                        RoutineStep(pointId: "TE3", rounds: 3, technique: .press, role: .distal)]),
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
