import SwiftUI

// Shared session UI — the recap screen, the end-session confirmation, and the experience scale
// existed as near-verbatim copies in ARCoachView and TimerSessionView (plus a third hand-rolled
// key mapping in HistoryView/PracticeStore). One source of truth for each now lives here; the
// session-specific behavior (savePractice, the timer's dialog-pause, the camera teardown) stays
// in the owning views.

// MARK: - Experience scale

// The canonical self-reported EXPERIENCE scale (deliberately not an outcome score — one session
// can't honestly be judged "relief vs worse", but comfort is real signal for which points suit
// the user). Raw values are the stable keys written to PracticeStore; legacy keys from the
// earlier outcome-framed prompt (relief/nochange/worse) map onto the scale so old records still
// read and count correctly.
enum FeelingScale: String, CaseIterable {
    case relaxing, neutral, uncomfortable

    // Accepts canonical keys AND legacy aliases (nil / unknown → nil).
    init?(anyKey: String?) {
        switch anyKey {
        case "relaxing", "relief": self = .relaxing
        case "neutral", "nochange": self = .neutral
        case "uncomfortable", "worse": self = .uncomfortable
        default: return nil
        }
    }

    // ── Non-negotiable safety decisions, hoisted out of the view body so they are testable. ──
    // These used to be inline `feeling == FeelingScale.uncomfortable.rawValue` string comparisons in
    // RecapView, which no test could reach — and which compared against the CANONICAL key only, so a
    // stored legacy "worse" entry (accepted by init(anyKey:)) slipped past and still offered
    // "continue". Routing both decisions through init(anyKey:) closes that.

    /// This outcome must show stop guidance.
    var advisesStop: Bool { self == .uncomfortable }

    /// Whether a routine may offer its next-step button after this outcome.
    /// Unrecorded (nil) or unrecognized → the user never said it hurt, so continuing is allowed.
    static func allowsContinue(_ key: String?) -> Bool {
        guard let scale = FeelingScale(anyKey: key) else { return true }
        return !scale.advisesStop
    }

    /// Whether the stop-and-consider-care guidance must be shown for this recorded outcome.
    static func showsStopGuidance(_ key: String?) -> Bool {
        FeelingScale(anyKey: key)?.advisesStop ?? false
    }

    // History-row label (lowercase in English, matching the session line it sits on).
    var label: String {
        switch self {
        case .relaxing: return AppLocale.pick("放松", "relaxing")
        case .neutral: return AppLocale.pick("一般", "neutral")
        case .uncomfortable: return AppLocale.pick("不舒服", "uncomfortable")
        }
    }

    // Recap button title.
    var buttonTitle: String {
        switch self {
        case .relaxing: return AppLocale.pick("很放松", "Relaxing")
        case .neutral: return AppLocale.pick("一般", "Neutral")
        case .uncomfortable: return AppLocale.pick("不舒服", "Uncomfortable")
        }
    }

    var color: Color {
        switch self {
        case .relaxing: return Ink.jade
        case .neutral: return Ink.textDim
        case .uncomfortable: return Ink.terracotta
        }
    }
}

// MARK: - Session recap

// The recap shown when a session completes or is ended early (both first-class outcomes — the
// summary reports honestly either way). Shared by the camera coach and the guided timer; the
// parent keeps savePractice and passes the store write through onFeeling.
struct SessionRecapView: View {
    let point: Acupoint
    let roundsDone: Int
    let roundsTarget: Int
    let heldS: Double
    var roundTimes: [Double]? = nil      // per-round held seconds; the breakdown line shows only when count > 1
    var verifiedHold: Bool = false       // camera-verified press → the "steady press" summary wording
    let sessionComplete: Bool
    @Binding var feeling: String?        // stable key: "relaxing" | "neutral" | "uncomfortable"
    let onFeeling: (String) -> Void      // parent attaches the key to its history record
    var onNext: (label: String, action: () -> Void)? = nil   // routine hand-off (suppressed after "uncomfortable")

    var body: some View {
        let held = Int(heldS.rounded())
        return VStack(spacing: 20) {
            Text(sessionComplete ? AppLocale.pick("保持得很好", "Nicely held")
                                 : AppLocale.pick("练习结束", "Good session"))
                .font(.title2).foregroundStyle(Ink.gold)
            Text(summaryLine(held: held))
                .foregroundStyle(Ink.text).multilineTextAlignment(.center)
            if let times = roundTimes, times.count > 1 {
                Text(AppLocale.pick("各轮：", "Rounds: ")
                     + times.map { "\(Int($0.rounded()))s" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Ink.textDim)
            }
            // EXPERIENCE prompt, not an outcome score: one session can't honestly be judged
            // "relief vs worse" — but comfort is real signal for which points suit you, and
            // "uncomfortable" carries the immutable stop-advice behavior.
            Text(AppLocale.pick("这次按压感觉如何？", "How did that feel?")).font(.headline).foregroundStyle(Ink.text)
            Text(AppLocale.pick("（可跳过 — 记录体验，日积月累看出哪些穴位适合你。）",
                                "(Optional — over time this shows which points suit you.)"))
                .font(.caption2).foregroundStyle(Ink.textDim)
            HStack {
                ForEach(FeelingScale.allCases, id: \.rawValue) { scale in
                    Button(scale.buttonTitle) {
                        feeling = scale.rawValue
                        onFeeling(scale.rawValue)
                    }.buttonStyle(GoldButtonStyle())
                        .accessibilityHint(AppLocale.pick("记录这次练习的体验", "Notes how this session felt"))
                }
            }
            // "Uncomfortable" → advise stopping, never "continue" (immutable safety behavior).
            if FeelingScale.showsStopGuidance(feeling) {
                Text(AppLocale.pick("请暂时停止。如果不适严重或持续，请考虑就医。",
                                    "Please stop for now. If the discomfort is strong or persistent, consider seeing a professional."))
                    .font(.footnote).foregroundStyle(Ink.terracotta).multilineTextAlignment(.center).padding()
            }
            // Routine flow: hand off to the next step (suppressed after "Uncomfortable" — never
            // encourage continuing past discomfort).
            if let next = onNext, FeelingScale.allowsContinue(feeling) {
                Button(next.label) { next.action() }.buttonStyle(GoldButtonStyle())
            }
            WellnessFooter()
        }
        .padding(28)
    }

    // Two exact wordings, kept character-identical to the originals: the camera coach vouches for
    // a STEADY press (it verified the hold); the timer paced the rounds but couldn't watch.
    private func summaryLine(held: Int) -> String {
        verifiedHold
            ? AppLocale.pick(
                "你在 \(point.id)（\(point.zh)）上完成了 \(roundsDone)/\(roundsTarget) 轮，累计稳定按压约 \(held) 秒。想停就停，本来就该如此。",
                "You did \(roundsDone) of \(roundsTarget) rounds on \(point.id) (\(point.zh)) — about \(held) seconds of steady press. Stopping whenever you like is exactly right.")
            : AppLocale.pick(
                "你在 \(point.id)（\(point.zh)）上完成了 \(roundsDone)/\(roundsTarget) 轮，累计约 \(held) 秒。想停就停，本来就该如此。",
                "You did \(roundsDone) of \(roundsTarget) rounds on \(point.id) (\(point.zh)) — about \(held) seconds. Stopping whenever you like is exactly right.")
    }
}

// MARK: - End-session confirmation

// End with banked progress → confirm first; the recap records honestly either way. Session-side
// effects of the dialog being up (e.g. the timer pausing its clock while the user deliberates)
// belong to the owning view, not here.
private struct EndSessionDialog: ViewModifier {
    @Binding var isPresented: Bool
    let rounds: Int
    let heldS: Double
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(AppLocale.pick("结束本次练习？", "End this session?"),
                                isPresented: $isPresented, titleVisibility: .visible) {
                Button(AppLocale.pick("结束并查看小结", "End and see recap"), role: .destructive) { onConfirm() }
                Button(AppLocale.pick("继续练习", "Keep going"), role: .cancel) {}
            } message: {
                Text(AppLocale.pick("已完成 \(rounds) 轮、累计约 \(Int(heldS.rounded())) 秒 — 小结会如实记录。",
                                    "\(rounds) rounds and ~\(Int(heldS.rounded()))s so far — the recap records it honestly."))
            }
    }
}

extension View {
    func endSessionDialog(isPresented: Binding<Bool>, rounds: Int, heldS: Double,
                          onConfirm: @escaping () -> Void) -> some View {
        modifier(EndSessionDialog(isPresented: isPresented, rounds: rounds, heldS: heldS,
                                  onConfirm: onConfirm))
    }
}
