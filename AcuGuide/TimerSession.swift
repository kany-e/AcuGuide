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

    // Pause is a SET of reasons, not competing booleans (the old scene/user flag pair needed
    // n² cross-guards and still let combinations slip): the clock runs only while the set is
    // empty. .scene = app not active (background OR inactive — an incoming-call banner must not
    // credit hold time), .user = explicit pause button, .dialog = the End confirmation is up
    // (the user has let go of the point to operate it).
    enum PauseReason: Hashable { case scene, user, dialog }
    @Published private(set) var pauseReasons: Set<PauseReason> = []
    var userPaused: Bool { pauseReasons.contains(.user) }

    // End is TERMINAL: nothing (scene resume included) may restart the ticker afterwards — an
    // ended-early session used to be resurrected under its own recap by a background/foreground
    // cycle (review-caught).
    private(set) var ended = false

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

    // A session must not credit time the user isn't being guided through; resuming picks up
    // exactly where the clock stopped. The clock runs only while pauseReasons is empty.
    func pause(_ reason: PauseReason = .user) {
        guard phase == .holding || phase == .resting, !ended else { return }
        pauseReasons.insert(reason)
        ticker?.invalidate(); ticker = nil
    }
    func resume(_ reason: PauseReason = .user) {
        pauseReasons.remove(reason)
        guard pauseReasons.isEmpty, !ended, phase == .holding || phase == .resting else { return }
        run()
    }

    // Legacy names — the tests drive the scene path through these.
    func scenePaused() { pause(.scene) }
    func sceneResumed() { resume(.scene) }

    func end() { ended = true; ticker?.invalidate(); ticker = nil }

    private func run() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick(0.1) }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // Advance the session clock. Public so tests drive it deterministically without a Timer.
    func tick(_ dt: Double) {
        if ended { return }
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
        // Pause on ANY non-active state (.inactive covers the incoming-call banner, Notification
        // Center, the app switcher — the ticker must not credit unguided time through them).
        // The model's `ended` guard keeps a finished/ended session from being resurrected here.
        .onChange(of: scenePhase) { sp in
            if sp == .active { session.resume(.scene) } else { session.pause(.scene) }
        }
        // The End dialog implies the user has let go of the point — stop the blind clock while
        // they deliberate (dismissal by any route lands here, including tap-outside).
        .onChange(of: showEndConfirm) { up in
            if up { session.pause(.dialog) } else { session.resume(.dialog) }
        }
        // A paced round is 30s of holding still with nothing touching the screen — precisely what
        // iOS calls idle. Without this the phone dims and locks mid-round, and the user cannot tap
        // to wake without letting go of the point they are being coached to hold.
        .keepScreenAwake(while: acknowledged && !session.sessionComplete && !endedEarly
                                && feeling == nil && session.pauseReasons.isEmpty)
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
            // The ready-state copy below says "find the spot with the notes above" — but until now the
            // only note above was the clinical WHO location ("4 cun above the navel"), which is exactly
            // the string a self-locating user cannot act on. Show the plain-language guide when the
            // point has one, so the instruction and the notes it refers to actually agree.
            if acupoint.hasFindGuide {
                Text(AppLocale.pick("这样找：", "To find it: ") + acupoint.findHow)
                    .font(.footnote).foregroundStyle(Ink.gold)
                    .multilineTextAlignment(.center).padding(.horizontal)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // THE POINT'S OWN CAUTION, on the screen where the press actually happens. The forced
            // safety gate covers generic red flags; it says nothing point-specific. This screen runs
            // 25 of the 33 points, and a bundled routine could walk a user straight into pressing
            // LR3 without ever showing "don't press hard on the pulsing artery in the groove" —
            // the string existed and was rendered on the atlas card, just never here.
            if !acupoint.caution.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text(acupoint.caution).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Ink.terracotta)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 24)
                .accessibilityLabel(AppLocale.pick("注意：", "Caution: ") + acupoint.caution)
            }

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
                Text(AppLocale.pick("照上面的说明找到位置，让指尖以舒服的力度贴住，准备好就开始。",
                                    "Find the spot with the notes above, let your fingertip settle in comfortably, and begin whenever you're ready."))
                    .font(.footnote).foregroundStyle(Ink.textDim)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Button(AppLocale.pick("开始", "Begin")) { session.start() }
                    .buttonStyle(GoldButtonStyle())
            } else {
                HStack(spacing: 10) {
                    Button(session.userPaused ? AppLocale.pick("继续", "Resume") : AppLocale.pick("暂停", "Pause")) {
                        if session.userPaused { session.resume() } else { session.pause() }
                    }
                        .font(.caption.weight(.semibold)).foregroundStyle(session.userPaused ? Ink.gold : Ink.textDim)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().stroke(session.userPaused ? Ink.gold : Ink.line, lineWidth: 1))
                        .accessibilityHint(AppLocale.pick("暂停或继续，进度保留", "Pause or resume; progress is kept"))
                    Button(AppLocale.pick("结束", "End")) {
                        if session.roundsDone > 0 || session.totalHeldS >= 5 { showEndConfirm = true }
                        else { endedEarly = true; session.end() }
                    }
                        .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().stroke(Ink.line, lineWidth: 1))
                }
                if session.userPaused {
                    Text(AppLocale.pick("已暂停 — 进度已保留。", "Paused — your progress is kept."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                }
            }

            WellnessFooter()
        }
        .padding()
        // Shared confirm (SessionUI.swift). The dialog-pause side effect stays in this view's
        // .onChange(of: showEndConfirm) — it is timer-specific, not part of the dialog.
        .endSessionDialog(isPresented: $showEndConfirm, rounds: session.roundsDone,
                          heldS: session.totalHeldS) { endedEarly = true; session.end() }
    }

    private var cueText: String {
        switch session.phase {
        case .ready:   return AppLocale.pick("准备好再开始", "Begin when ready")
        case .holding: return AppLocale.pick("稳定按压 · 缓慢呼吸", "Steady press · slow breath")
        case .resting: return AppLocale.pick("松开 · \(session.restRemaining)s", "Release · \(session.restRemaining)s")
        case .complete: return AppLocale.pick("完成", "Done")
        }
    }

    // Shared recap (SessionUI.swift). No roundTimes and no verifiedHold: the timer paced the
    // rounds but couldn't watch the press, so the summary stays "about N seconds".
    private var recap: some View {
        SessionRecapView(point: acupoint, roundsDone: session.roundsDone,
                         roundsTarget: session.roundsTarget, heldS: session.totalHeldS,
                         sessionComplete: session.sessionComplete, feeling: $feeling,
                         onFeeling: { key in
                             if let id = practiceRecordId { PracticeStore.shared.setFeeling(id: id, feeling: key) }
                         },
                         onNext: onNext)
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
