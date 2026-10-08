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
        // SCROLLS. The content is a fixed stack of eight blocks — title, summary, per-round times,
        // the feeling prompt and its caption, the button row, the stop guidance, the next-step
        // button, the footer — and its own history records that the button row already overflowed a
        // 375 pt screen HORIZONTALLY (hence the ViewThatFits below). Vertically it had no escape at
        // all: at large Dynamic Type, or after a session that ends while the phone is sideways,
        // the stop guidance and the next-step button simply fall off the bottom. Those are the two
        // things that must never be unreachable — one is the safety response to "uncomfortable".
        return ScrollView {
            recapContent(held: held)
        }
    }

    @ViewBuilder private func recapContent(held: Int) -> some View {
        VStack(spacing: 20) {
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
            // ViewThatFits, not a fixed HStack: GoldButtonStyle adds 22 pt of padding per side at
            // .headline, so "Relaxing / Neutral / Uncomfortable" plus chrome overflows a 375 pt
            // screen — and it gets worse at every Dynamic Type step. The option that lost was
            // "Uncomfortable", the LONGEST label and the one that triggers the non-negotiable stop
            // guidance. The Chinese labels are short, so this was English-only and easy to miss.
            // Falls back to a vertical stack when the row cannot fit, so nothing ever truncates.
            ViewThatFits(in: .horizontal) {
                HStack { feelingButtons }
                VStack(spacing: 8) { feelingButtons }
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

    // Shared by both ViewThatFits arms so the row and the column render identical buttons.
    @ViewBuilder private var feelingButtons: some View {
        ForEach(FeelingScale.allCases, id: \.rawValue) { scale in
            Button(scale.buttonTitle) {
                feeling = scale.rawValue
                onFeeling(scale.rawValue)
            }
            .buttonStyle(GoldButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityHint(AppLocale.pick("记录这次练习的体验", "Notes how this session felt"))
        }
    }

    // What the summary may CLAIM depends on who was watching: the camera coach verified a STEADY
    // press, so it says so; the timer paced the rounds but could not see the hand, so it does not.
    // That distinction is the honest part (信) and survives any rewording.
    //
    // The closing line is Acu's (docs/acu-voice.md), and short: a finished session gets "a little each
    // day is plenty", an early stop gets plain permission. Neither ever asks for more. (It used to say
    // "stopping whenever you like is exactly right" after FINISHED sessions too, where nobody stopped.)
    private func summaryLine(held: Int) -> String {
        Self.summaryText(point: point, roundsDone: roundsDone, roundsTarget: roundsTarget, held: held,
                         verifiedHold: verifiedHold, finished: sessionComplete)
    }

    /// Pure, so the two rules above are tested rather than asserted: "steady press" only when the
    /// camera verified the hold, and a closing line that never asks for more. `finished` is the
    /// engine's own `sessionComplete`, not a second definition of done from the round counts.
    static func summaryText(point: Acupoint, roundsDone: Int, roundsTarget: Int, held: Int,
                            verifiedHold: Bool, finished: Bool) -> String {
        let heldZh = verifiedHold ? "稳稳按住约 \(held) 秒" : "共约 \(held) 秒"
        let heldEn = verifiedHold ? "about \(held) seconds of steady press" : "about \(held) seconds"
        if finished {
            return AppLocale.pick(
                "\(point.zh)（\(point.id)）\(roundsDone) 轮都按完了，\(heldZh)。每天按一会儿就好。",
                "All \(roundsDone) rounds on \(point.en) (\(point.id)) done — \(heldEn). A little each day is plenty.")
        }
        return AppLocale.pick(
            "\(point.zh)（\(point.id)）按了 \(roundsDone)/\(roundsTarget) 轮，\(heldZh)。想停就停，这样也很好。",
            "\(roundsDone) of \(roundsTarget) rounds on \(point.en) (\(point.id)) — \(heldEn). Stopping whenever you like is fine.")
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

// MARK: - Progress thresholds

// The two progress lines a session is judged against, in ONE place. Both used to be inline
// comparisons repeated across ARCoachView and TimerSessionView (End buttons and savePractice
// guards), which is what let the nav-bar Close ignore them entirely — a third exit that knew about
// neither rule. Any exit path and any recorder reads these, so they cannot drift apart again.
enum SessionProgress {
    /// Banked enough that ending deserves a confirmation first (the End button's long-standing rule).
    static func banked(roundsDone: Int, heldS: Double) -> Bool {
        roundsDone > 0 || heldS >= 5
    }
    /// Enough that savePractice writes a history record — below the confirm bar but above noise
    /// (opening a session and immediately quitting must not create a "0/4 rounds" entry).
    static func recordable(roundsDone: Int, heldS: Double) -> Bool {
        roundsDone > 0 || heldS >= 1.0
    }
}

// MARK: - Nav-bar Close routing

/// What the nav-bar Close does to the session under it. The Close button used to set `launch = nil`
/// unconditionally — silently discarding banked progress that the in-card End button protects with
/// a confirmation, and skipping the recap, which is the only place savePractice runs. Close is an
/// exit like any other, so it follows the same rules; the decision is a pure function so a test can
/// hold it to them.
enum SessionCloseAction: Equatable {
    case dismiss        // nothing banked, or a reading screen (gate/recap): close means close
    case confirmFirst   // banked progress: show the same dialog the End button shows
    case recap          // recordable but small: end straight to the recap so savePractice runs

    /// `readingScreen`: the safety gate, permission screens, and the recap — screens where Close
    /// is the way OUT, not an interruption of live practice (the recap has already recorded).
    static func forSession(readingScreen: Bool, roundsDone: Int, heldS: Double) -> SessionCloseAction {
        if readingScreen { return .dismiss }
        if SessionProgress.banked(roundsDone: roundsDone, heldS: heldS) { return .confirmFirst }
        if SessionProgress.recordable(roundsDone: roundsDone, heldS: heldS) { return .recap }
        return .dismiss
    }
}

/// Carries the Close attempt from RootView's nav bar down to whichever session view is live.
/// The bar and the session state live on opposite sides of a fullScreenCover boundary, so the
/// session REGISTERS a handler (keyed by a token — routine steps swap views, and the outgoing
/// step's onDisappear can fire after the incoming step's onAppear, so a bare "clear on disappear"
/// would null out the new step's handler). The handler returns true when the session intercepted
/// the close; false lets the caller dismiss.
final class SessionCloseRouter {
    private var handlers: [(token: UUID, attempt: () -> Bool)] = []

    func register(_ token: UUID, attempt: @escaping () -> Bool) {
        handlers.removeAll { $0.token == token }
        handlers.append((token, attempt))
    }
    func unregister(_ token: UUID) {
        handlers.removeAll { $0.token == token }
    }
    /// True when the live session took over (confirm dialog or recap); false → nothing to protect.
    func attemptClose() -> Bool {
        handlers.last?.attempt() ?? false
    }
}

private struct SessionCloseRouterKey: EnvironmentKey {
    static let defaultValue: SessionCloseRouter? = nil
}
extension EnvironmentValues {
    var sessionCloseRouter: SessionCloseRouter? {
        get { self[SessionCloseRouterKey.self] }
        set { self[SessionCloseRouterKey.self] = newValue }
    }
}
