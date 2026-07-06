import SwiftUI

// Guided TIMER practice — the session experience (rounds, release gaps, voice, haptics, recap,
// history) for every atlas point WITHOUT camera verification. The camera-coached set stays exactly
// the 8 documented hand points; everything else gets this: the user self-locates with the point's
// landmark instructions and the app paces the rounds and breathing. Same round/rest constants as
// the coach, so the practice shape is identical either way.
final class TimerSession: ObservableObject {
    enum Phase { case ready, holding, resting, complete }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var progress: Double = 0        // current round 0…1
    @Published private(set) var roundsDone = 0
    @Published private(set) var restRemaining = 0
    let roundsTarget: Int
    private let roundHoldS: Double
    private let restS: Double

    private var holdTime = 0.0
    private var restLeft = 0.0
    private var heldAccum = 0.0
    private var ticker: Timer?
    private var pausedByScene = false
    private(set) var userPaused = false

    var totalHeldS: Double { heldAccum + holdTime }
    var sessionComplete: Bool { phase == .complete }

    init(roundsTarget: Int = CoachConst.sessionRounds,
         roundHoldS: Double = CoachConst.holdTargetS,
         restS: Double = CoachConst.restS) {
        self.roundsTarget = roundsTarget
        self.roundHoldS = roundHoldS
        self.restS = restS
    }

    func start() {
        guard phase == .ready else { return }
        phase = .holding
        run()
    }

    // Backgrounding pauses the clock (a timer session must not credit time the user wasn't guided
    // through); foregrounding resumes exactly where it left off. An explicit USER pause is a
    // separate flag so returning from an app-switch never restarts a session the user paused.
    func scenePaused() { guard phase == .holding || phase == .resting else { return }
        pausedByScene = true; ticker?.invalidate(); ticker = nil }
    func sceneResumed() { guard pausedByScene else { return }; pausedByScene = false
        if !userPaused { run() } }

    func pause() { guard phase == .holding || phase == .resting, !userPaused else { return }
        userPaused = true; ticker?.invalidate(); ticker = nil }
    func resume() { guard userPaused else { return }; userPaused = false
        if !pausedByScene { run() } }

    func end() { ticker?.invalidate(); ticker = nil }

    private func run() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick(0.1) }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // Advance the session clock. Public so tests drive it deterministically without a Timer.
    func tick(_ dt: Double) {
        switch phase {
        case .holding:
            holdTime += dt
            progress = min(1, holdTime / roundHoldS)
            if holdTime >= roundHoldS {
                roundsDone += 1
                heldAccum += holdTime; holdTime = 0; progress = 0
                if roundsDone >= roundsTarget {
                    phase = .complete; end()
                } else {
                    restLeft = restS; restRemaining = Int(restS.rounded(.up))
                    phase = .resting
                }
            }
        case .resting:
            restLeft -= dt
            restRemaining = max(0, Int(restLeft.rounded(.up)))
            if restLeft <= 0 { phase = .holding }
        case .ready, .complete:
            break
        }
    }

    // Bridge to the coach's phase vocabulary so CoachVoice/haptics speak the same cues.
    var coachPhase: CoachPhase {
        switch phase {
        case .ready: return .searching
        case .holding: return .holding
        case .resting: return .resting
        case .complete: return .complete
        }
    }
}

// The guided-timer session screen: safety gate → self-locate instructions → paced rounds → recap.
struct TimerSessionView: View {
    let acupoint: Acupoint
    var roundsTarget: Int = CoachConst.sessionRounds
    var onNext: (label: String, action: () -> Void)? = nil   // set when running inside a routine

    @StateObject private var session: TimerSession
    @StateObject private var voice = CoachVoice()
    @StateObject private var haptics = CoachHaptics()
    @Environment(\.scenePhase) private var scenePhase
    @State private var acknowledged = false
    @State private var endedEarly = false
    @State private var feeling: String? = nil
    @State private var practiceRecordId: String? = nil
    @State private var prevPhase: TimerSession.Phase = .ready
    @State private var userPaused = false
    @State private var showEndConfirm = false

    init(acupoint: Acupoint, roundsTarget: Int = CoachConst.sessionRounds,
         onNext: (label: String, action: () -> Void)? = nil,
         acknowledgedInitially: Bool = false) {
        self.acupoint = acupoint
        self.roundsTarget = roundsTarget
        self.onNext = onNext
        _session = StateObject(wrappedValue: TimerSession(roundsTarget: roundsTarget))
        _acknowledged = State(initialValue: acknowledgedInitially)
    }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            if !acknowledged {
                SafetyGate { acknowledged = true }
            } else if session.sessionComplete || endedEarly || feeling != nil {
                recap.onAppear(perform: savePractice)
            } else {
                sessionLayer
            }
        }
        .onChange(of: session.phase) { p in
            voice.update(phase: session.coachPhase, requiresDorsal: acupoint.requiresDorsal)
            if p == .resting && prevPhase != .resting { haptics.enterTick() }
            if p == .complete && prevPhase != .complete { haptics.complete() }
            prevPhase = p
        }
        .onChange(of: scenePhase) { sp in
            if sp == .background { session.scenePaused() } else if sp == .active { session.sceneResumed() }
        }
        .onDisappear { session.end(); voice.reset() }
    }

    private var sessionLayer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(MeridianColors.color(acupoint.meridian)).frame(width: 10, height: 10)
                Text("\(acupoint.id) · \(acupoint.zh)").font(Typo.serif(20, weight: .semibold)).foregroundStyle(Ink.gold)
                Text(acupoint.en).font(Typo.code(15)).foregroundStyle(Ink.textDim)
            }
            Text(acupoint.location)
                .font(.subheadline).foregroundStyle(Ink.text)
                .multilineTextAlignment(.center).padding(.horizontal)

            ZStack {
                Circle().stroke(Ink.line, lineWidth: 8).frame(width: 150, height: 150)
                Circle().trim(from: 0, to: session.progress)
                    .stroke(session.phase == .resting ? Ink.jade : Ink.gold,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
                VStack(spacing: 2) {
                    Text(AppLocale.pick("第 \(min(session.roundsDone + 1, session.roundsTarget))/\(session.roundsTarget) 轮",
                                        "Round \(min(session.roundsDone + 1, session.roundsTarget)) of \(session.roundsTarget)"))
                        .font(.caption).foregroundStyle(Ink.textDim)
                    Text(cueText).font(.subheadline).foregroundStyle(Ink.text)
                        .multilineTextAlignment(.center).padding(.horizontal, 10)
                }.frame(width: 150)
            }

            if session.phase == .ready {
                Text(AppLocale.pick("按说明找到该处，用指尖以稳而舒适的力度按住，然后开始。",
                                    "Find the spot with the instructions above, settle your fingertip with firm-but-comfortable pressure, then begin."))
                    .font(.footnote).foregroundStyle(Ink.textDim)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Button(AppLocale.pick("开始", "Begin")) { session.start() }
                    .buttonStyle(GoldButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button(userPaused ? AppLocale.pick("继续", "Resume") : AppLocale.pick("暂停", "Pause")) {
                        if userPaused { session.resume() } else { session.pause() }
                        userPaused.toggle()
                    }
                        .font(.caption.weight(.semibold)).foregroundStyle(userPaused ? Ink.gold : Ink.textDim)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().stroke(userPaused ? Ink.gold : Ink.line, lineWidth: 1))
                        .accessibilityHint(AppLocale.pick("暂停或继续，进度保留", "Pause or resume; progress is kept"))
                    Button(AppLocale.pick("结束", "End")) {
                        if session.roundsDone > 0 || session.totalHeldS >= 5 { showEndConfirm = true }
                        else { endedEarly = true; session.end() }
                    }
                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().stroke(Ink.line, lineWidth: 1))
                }
                if userPaused {
                    Text(AppLocale.pick("已暂停 — 进度已保留。", "Paused — your progress is kept."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                }
            }

            Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                .font(.caption2).foregroundStyle(Ink.textDim)
        }
        .padding()
        .confirmationDialog(AppLocale.pick("结束本次练习？", "End this session?"),
                            isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button(AppLocale.pick("结束并查看小结", "End and see recap"), role: .destructive) {
                endedEarly = true; session.end()
            }
            Button(AppLocale.pick("继续练习", "Keep going"), role: .cancel) {}
        } message: {
            Text(AppLocale.pick("已完成 \(session.roundsDone) 轮、累计约 \(Int(session.totalHeldS.rounded())) 秒 — 小结会如实记录。",
                                "\(session.roundsDone) rounds and ~\(Int(session.totalHeldS.rounded()))s so far — the recap records it honestly."))
        }
    }

    private var cueText: String {
        switch session.phase {
        case .ready:   return AppLocale.pick("准备好再开始", "Begin when ready")
        case .holding: return AppLocale.pick("稳定按压 · 缓慢呼吸", "Steady press · slow breath")
        case .resting: return AppLocale.pick("松开 · \(session.restRemaining)s", "Release · \(session.restRemaining)s")
        case .complete: return AppLocale.pick("完成", "Done")
        }
    }

    private var recap: some View {
        let held = Int(session.totalHeldS.rounded())
        return VStack(spacing: 20) {
            Text(session.sessionComplete ? AppLocale.pick("保持得很好", "Nicely held")
                                         : AppLocale.pick("练习结束", "Good session"))
                .font(.title2).foregroundStyle(Ink.gold)
            Text(AppLocale.pick(
                "你在 \(acupoint.id)（\(acupoint.zh)）上完成了 \(session.roundsDone)/\(session.roundsTarget) 轮，累计约 \(held) 秒。想停就停，本来就该如此。",
                "You did \(session.roundsDone) of \(session.roundsTarget) rounds on \(acupoint.id) (\(acupoint.zh)) — about \(held) seconds. Stopping whenever you like is exactly right."))
                .foregroundStyle(Ink.text).multilineTextAlignment(.center)
            // EXPERIENCE prompt, not an outcome score (see ARCoachView recap for the rationale).
            Text(AppLocale.pick("这次按压感觉如何？", "How did that feel?")).font(.headline).foregroundStyle(Ink.text)
            Text(AppLocale.pick("（可跳过 — 记录体验，日积月累看出哪些穴位适合你。）",
                                "(Optional — over time this shows which points suit you.)"))
                .font(.caption2).foregroundStyle(Ink.textDim)
            HStack {
                ForEach([("relaxing", AppLocale.pick("很放松", "Relaxing")),
                         ("neutral", AppLocale.pick("一般", "Neutral")),
                         ("uncomfortable", AppLocale.pick("不舒服", "Uncomfortable"))], id: \.0) { item in
                    Button(item.1) {
                        feeling = item.0
                        if let id = practiceRecordId { PracticeStore.shared.setFeeling(id: id, feeling: item.0) }
                    }.buttonStyle(GoldButtonStyle())
                        .accessibilityHint(AppLocale.pick("记录这次练习的体验", "Notes how this session felt"))
                }
            }
            if feeling == "uncomfortable" {
                Text(AppLocale.pick("请暂时停止。如果不适严重或持续，请考虑就医。",
                                    "Please stop for now. If the discomfort is strong or persistent, consider seeing a professional."))
                    .font(.footnote).foregroundStyle(Ink.terracotta).multilineTextAlignment(.center).padding()
            }
            // Routine flow hand-off — suppressed after "Uncomfortable" (never encourage continuing
            // past discomfort).
            if let next = onNext, feeling != "uncomfortable" {
                Button(next.label) { next.action() }.buttonStyle(GoldButtonStyle())
            }
            Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                .font(.caption2).foregroundStyle(Ink.textDim)
        }
        .padding(28)
    }

    private func savePractice() {
        guard practiceRecordId == nil else { return }
        guard session.roundsDone > 0 || session.totalHeldS >= 1.0 else { return }
        let rec = PracticeRecord(id: UUID().uuidString, date: Date(), pointId: acupoint.id,
                                 rounds: session.roundsDone, roundsTarget: session.roundsTarget,
                                 heldS: session.totalHeldS, feeling: nil)
        PracticeStore.shared.add(rec)
        practiceRecordId = rec.id
    }
}
