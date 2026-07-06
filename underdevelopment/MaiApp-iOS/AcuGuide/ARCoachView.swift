import SwiftUI

// The AR coaching window: forced safety gate -> live camera + acupoint overlay -> recap.
// Demo point = TE3 (the validated one). Safety gate is the immutable rule (no skip).
struct ARCoachView: View {
    let acupoint: Acupoint
    var onNext: (label: String, action: () -> Void)? = nil   // set when running inside a routine
    @StateObject private var engine: CoachEngine
    @StateObject private var camera: CameraCoach
    @StateObject private var voice = CoachVoice()
    @StateObject private var haptics = CoachHaptics()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var acknowledged = false
    @State private var endedEarly = false          // "End" pressed — recap with partial rounds (normal, not failure)
    @State private var feeling: String? = nil      // stable key: "relaxing" | "neutral" | "uncomfortable"
    @State private var practiceRecordId: String? = nil   // history record for this session (saved once)
    @State private var dorsalPositive = HandCalibration.dorsalWhenSignedPositive
    @State private var prevPhase: CoachPhase = .noHand

    init(acupoint: Acupoint, roundsTarget: Int = CoachConst.sessionRounds,
         onNext: (label: String, action: () -> Void)? = nil,
         acknowledgedInitially: Bool = false) {
        self.acupoint = acupoint
        self.onNext = onNext
        // Build the engine first, then hand the SAME instance to the camera (assign-before-use,
        // no redundant default StateObject). roundsTarget: 1 for the first-run quick try; a
        // routine step's rounds otherwise. acknowledgedInitially: steps ≥2 of a ROUTINE run —
        // the safety gate was confirmed at step 1 of the same continuous session (never skipped
        // for a fresh session).
        let eng = CoachEngine(roundsTarget: roundsTarget)
        _engine = StateObject(wrappedValue: eng)
        _camera = StateObject(wrappedValue: CameraCoach(engine: eng, acupoint: acupoint))
        _acknowledged = State(initialValue: acknowledgedInitially)
    }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            if !acknowledged {
                SafetyGate { acknowledged = true }
            } else if engine.phase == .complete || endedEarly || feeling != nil {
                recap.onAppear(perform: savePractice)
            } else {
                // Permission gate AFTER the safety gate: the system prompt arrives in context, a
                // denial gets an open-Settings hand-off instead of a black screen, and the capture
                // session only ever starts once authorized.
                CameraGate(onAuthorized: { camera.start() }) { coachLayer }
            }
        }
        // Drive voice + haptics off phase TRANSITIONS only (debounced by the engine), and stop the
        // camera as soon as the routine completes so nothing keeps running behind the recap.
        .onChange(of: engine.phase) { handlePhaseChange(to: $0) }
        // Interruption robustness: a call / app-switch stops the camera (no capture in the
        // background); returning restarts it (start is idempotent + authorization-gated). The
        // machine's pause-grace and dt clamp make the gap read as a pause, never a credit jump.
        .onChange(of: scenePhase) { sp in
            guard acknowledged, engine.phase != .complete, !endedEarly else { return }
            if sp == .background { camera.stop() } else if sp == .active { camera.start() }
        }
        .onDisappear { camera.stop(); voice.reset() }
    }

    private func handlePhaseChange(to phase: CoachPhase) {
        voice.update(phase: phase, requiresDorsal: acupoint.requiresDorsal)

        // Haptics: a light tick the first time the finger enters the target zone (not on every
        // unstable wobble), a tick when a round completes (→ RESTING), and the success pattern at
        // session COMPLETE. Nothing on NO_HAND / WRONG_FACE.
        let wasOnTarget = prevPhase == .onTargetUnstable || prevPhase == .holding
        let isOnTarget = phase == .onTargetUnstable || phase == .holding
        if isOnTarget && !wasOnTarget { haptics.enterTick() }
        if phase == .resting && prevPhase != .resting { haptics.enterTick() }
        if phase == .complete && prevPhase != .complete { haptics.complete() }

        if phase == .complete { camera.stop() }
        prevPhase = phase
    }

    // End the session at any point — quitting early is a normal outcome; the recap reports honestly.
    private func endSession() {
        camera.stop(); voice.reset()
        endedEarly = true
    }

    // One history record per session, written when the recap first appears; the self-reported
    // feeling attaches to the same record when chosen. Local-only (PracticeStore).
    private func savePractice() {
        guard practiceRecordId == nil else { return }
        // Only sessions with actual practice count — opening the coach and immediately quitting
        // must not create a "0/4 rounds" history entry or credit a streak day.
        guard engine.roundsDone > 0 || engine.totalHeldS >= 1.0 else { return }
        let rec = PracticeRecord(id: UUID().uuidString, date: Date(), pointId: acupoint.id,
                                 rounds: engine.roundsDone, roundsTarget: engine.roundsTarget,
                                 heldS: engine.totalHeldS, feeling: nil)
        PracticeStore.shared.add(rec)
        practiceRecordId = rec.id
    }

    // Map a normalized landmark (top-left origin) through the preview's aspect-fill crop, so the
    // overlay lands on the SAME pixels the user sees. Returns the screen point + the displayed
    // frame width (to scale the ring radius, which is a fraction of frame width).
    private func mapFill(_ n: CGPoint, _ size: CGSize) -> (pt: CGPoint, dispW: CGFloat) {
        let fw = camera.frameAspect, fh: CGFloat = 1
        let s = max(size.width / fw, size.height / fh)   // aspect-fill: cover, crop overflow
        let dw = s * fw, dh = s * fh
        let ox = (size.width - dw) / 2, oy = (size.height - dh) / 2
        return (CGPoint(x: ox + n.x * dw, y: oy + n.y * dh), dw)
    }

    private var coachLayer: some View {
        ZStack {
            // Preview + overlay share a FULL-SCREEN coordinate space (ignoresSafeArea), so the
            // ring/press-dot land on the same pixels the aspect-fill preview shows. The chrome is
            // kept OUTSIDE this and respects the safe area (status bar / home indicator).
            GeometryReader { geo in
                ZStack {
                    CameraPreview(session: camera.session, mirrored: camera.mirrored,
                                  configGeneration: camera.configGeneration)
                        .accessibilityHidden(true)

                    Group {
                        if let c = engine.ringCenter {
                            let m = mapFill(c, geo.size)
                            let r = engine.ringRadius * m.dispW
                            Circle().stroke(engine.color, lineWidth: 3)
                                .frame(width: r * 2, height: r * 2).position(m.pt)
                            Circle().fill(engine.color).frame(width: 8, height: 8).position(m.pt)
                        }
                        if let t = engine.pressTip {
                            Circle().stroke(.white, lineWidth: 2).frame(width: 16, height: 16)
                                .position(mapFill(t, geo.size).pt)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea()

            VStack {
                debugBar
                Spacer()
                feedbackCard
            }
        }
        // Cap growth so the largest accessibility sizes can't break the camera overlay layout,
        // while still honoring Dynamic Type up to that bound.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // On-device field-calibration toggles (Phase 1): flip the mirror or invert the
    // face gate in one place if they fire backwards on a given device.
    private var debugBar: some View {
        HStack(spacing: 10) {
            Spacer()
            // Front ⇄ back camera. Back camera = two-person mode: point the phone at the OTHER
            // person's hand while they receive the press.
            Button { camera.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.callout).foregroundStyle(Ink.paper.opacity(0.85))
                    .padding(8).background(Circle().fill(.black.opacity(0.35)))
            }
            .accessibilityLabel(AppLocale.pick("切换前后摄像头", "Switch camera"))
            .accessibilityHint(AppLocale.pick("后置摄像头适合为他人按压", "Use the back camera to coach someone else's hand"))
            Button { voice.muted.toggle() } label: {
                Image(systemName: voice.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.callout).foregroundStyle(Ink.paper.opacity(0.85))
                    .padding(8).background(Circle().fill(.black.opacity(0.35)))
            }
            .accessibilityLabel(voice.muted ? "Unmute voice cues" : "Mute voice cues")
            #if DEBUG
            // Field-calibration switches (debug builds only): flip the landmark mirroring or invert
            // the palm/dorsal gate in one place if either fires backwards on a given device.
            Menu {
                Toggle("Mirror preview", isOn: Binding(
                    get: { camera.mirrorFlip }, set: { camera.mirrorFlip = $0 }))
                Toggle("Dorsal = signed > 0", isOn: Binding(
                    get: { dorsalPositive },
                    set: { dorsalPositive = $0; HandCalibration.dorsalWhenSignedPositive = $0 }))
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.callout).foregroundStyle(Ink.paper.opacity(0.8))
                    .padding(8).background(Circle().fill(.black.opacity(0.35)))
            }
            .accessibilityLabel("Calibration")
            #endif
        }
        .padding(.horizontal).padding(.top, 8)
    }

    private var feedbackCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Ink.line, lineWidth: 5).frame(width: 46, height: 46)
                Circle().trim(from: 0, to: engine.progress)
                    .stroke(engine.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(acupoint.id + " · " + acupoint.zh).font(.caption).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("第 \(min(engine.roundsDone + 1, engine.roundsTarget))/\(engine.roundsTarget) 轮",
                                        "Round \(min(engine.roundsDone + 1, engine.roundsTarget)) of \(engine.roundsTarget)"))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                }
                Text(engine.cue).font(.subheadline).foregroundStyle(Ink.text)
                    .lineLimit(3).minimumScaleFactor(0.7)
            }
            Spacer()
            Button(AppLocale.pick("结束", "End")) { endSession() }
                .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().stroke(Ink.line, lineWidth: 1))
                .accessibilityHint(AppLocale.pick("随时结束本次练习并查看小结", "End this session now and see your recap"))
        }
        .padding(14).panel().padding()
        // One VoiceOver element that re-announces the cue + hold progress as the phase changes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(acupoint.id) \(acupoint.zh). \(engine.cue)")
        .accessibilityValue("\(Int(engine.progress * 100)) percent held")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var recap: some View {
        let held = Int(engine.totalHeldS.rounded())
        let full = engine.sessionComplete
        return VStack(spacing: 20) {
            Text(full ? AppLocale.pick("保持得很好", "Nicely held")
                      : AppLocale.pick("练习结束", "Good session")).font(.title2).foregroundStyle(Ink.gold)
            Text(AppLocale.pick(
                "你在 \(acupoint.id)（\(acupoint.zh)）上完成了 \(engine.roundsDone)/\(engine.roundsTarget) 轮，累计稳定按压约 \(held) 秒。想停就停，本来就该如此。",
                "You did \(engine.roundsDone) of \(engine.roundsTarget) rounds on \(acupoint.id) (\(acupoint.zh)) — about \(held) seconds of steady press. Stopping whenever you like is exactly right."))
                .foregroundStyle(Ink.text).multilineTextAlignment(.center)
            // EXPERIENCE prompt, not an outcome score: one session can't honestly be judged
            // "relief vs worse" — but comfort is real signal for which points suit you, and
            // "uncomfortable" carries the immutable stop-advice behavior.
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
            // "Uncomfortable" → advise stopping, never "continue" (immutable safety behavior).
            if feeling == "uncomfortable" {
                Text(AppLocale.pick("请暂时停止。如果不适严重或持续，请考虑就医。",
                                    "Please stop for now. If the discomfort is strong or persistent, consider seeing a professional."))
                    .font(.footnote).foregroundStyle(Ink.terracotta).multilineTextAlignment(.center).padding()
            }
            // Routine flow: hand off to the next step (suppressed after "Uncomfortable" — never
            // encourage continuing past discomfort).
            if let next = onNext, feeling != "uncomfortable" {
                Button(next.label) { next.action() }.buttonStyle(GoldButtonStyle())
            }
            Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                .font(.caption2).foregroundStyle(Ink.textDim)
        }
        .padding(28)
    }
}

// Immutable safety gate — forced acknowledgement, no skip, no treat/cure/heal/diagnose copy.
struct SafetyGate: View {
    let onAcknowledge: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppLocale.pick("开始之前", "Before you begin")).font(.title2).foregroundStyle(Ink.gold)
            Text(AppLocale.pick("这是养生自我保养，并非医疗工具。如出现以下情况，请停止并就医：",
                                "This is wellness self-care, not a medical tool. Stop and seek care if you notice:"))
                .foregroundStyle(Ink.text)
            ForEach([AppLocale.pick("突发剧烈疼痛", "sudden severe pain"),
                     AppLocale.pick("麻木或无力", "numbness or weakness"),
                     AppLocale.pick("头晕", "dizziness"),
                     AppLocale.pick("症状加重", "worsening symptoms")], id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Ink.text).font(.subheadline)
            }
            Text(AppLocale.pick("如果你怀孕或有健康状况，请先咨询专业人士。",
                                "If you are pregnant or have a medical condition, check with a professional first."))
                .font(.footnote).foregroundStyle(Ink.textDim)
            Spacer().frame(height: 8)
            Button(AppLocale.pick("我明白了", "I understand"), action: onAcknowledge)
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
        }
        .padding(28)
    }
}
