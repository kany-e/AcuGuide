import SwiftUI

// The AR coaching window: forced safety gate -> live camera + acupoint overlay -> recap.
// Demo point = TE3 (the validated one). Safety gate is the immutable rule (no skip).
struct ARCoachView: View {
    let acupoint: Acupoint
    var onNext: (label: String, action: () -> Void)? = nil   // set when running inside a routine
    var onUseTimer: (() -> Void)? = nil   // camera-free escape from the permission screens (PracticeSessionView swaps in the timer)
    @StateObject private var engine: CoachEngine
    @StateObject private var camera: CameraCoach
    @StateObject private var voice = CoachVoice()
    @StateObject private var haptics = CoachHaptics()
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var acknowledged = false
    @State private var endedEarly = false          // "End" pressed — recap with partial rounds (normal, not failure)
    @State private var userPaused = false          // explicit pause: camera stops, progress is kept
    @State private var showEndConfirm = false      // guard banked progress against an accidental End
    @State private var feeling: String? = nil      // stable key: "relaxing" | "neutral" | "uncomfortable"
    @State private var practiceRecordId: String? = nil   // history record for this session (saved once)
    @State private var dorsalPositive = HandCalibration.dorsalWhenSignedPositive
    @State private var prevPhase: CoachPhase = .noHand

    init(acupoint: Acupoint, roundsTarget: Int = CoachConst.sessionRounds,
         onNext: (label: String, action: () -> Void)? = nil,
         acknowledgedInitially: Bool = false,
         onUseTimer: (() -> Void)? = nil) {
        self.acupoint = acupoint
        self.onNext = onNext
        self.onUseTimer = onUseTimer
        // Build the engine first, then hand the SAME instance to the camera (assign-before-use,
        // no redundant default StateObject). roundsTarget: 1 for the first-run quick try; a
        // routine step's rounds otherwise. acknowledgedInitially: steps ≥2 of a ROUTINE run —
        // the safety gate was confirmed at step 1 of the same continuous session (never skipped
        // for a fresh session). startLocating: points with a find-by-feel guide open in the
        // ON-CAMERA locate step (dashed guide ring + instructions; the user's confirmed press
        // becomes their personal spot correction) before any coaching round runs.
        let eng = CoachEngine(roundsTarget: roundsTarget, startLocating: acupoint.hasFindGuide)
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
                // Recap check comes BEFORE the camera so a finished/ended session can never be
                // masked by it.
                recap.onAppear(perform: savePractice)
            } else {
                // Permission gate AFTER the safety gate: the system prompt arrives in context, a
                // denial gets an open-Settings hand-off instead of a black screen, and the capture
                // session only ever starts once authorized. The find-it-by-feel LOCATE step now
                // lives ON the camera (engine.mode == .locate): dashed guide ring + instructions,
                // the user's press gets labeled, and their confirmed spot corrects the ring.
                CameraGate(onAuthorized: { camera.start() }, onUseTimer: onUseTimer) { coachLayer }
            }
        }
        // Drive voice + haptics off phase TRANSITIONS only (debounced by the engine), and stop the
        // camera as soon as the routine completes so nothing keeps running behind the recap.
        .onChange(of: engine.phase) { handlePhaseChange(to: $0) }
        // Interruption robustness: a call / app-switch stops the camera (no capture in the
        // background); returning restarts it (start is idempotent + authorization-gated). The
        // machine's pause-grace and dt clamp make the gap read as a pause, never a credit jump.
        .onChange(of: scenePhase) { sp in
            // Only manage the camera past the safety gate (the locate step is on-camera now, so
            // every post-gate screen legitimately runs the capture session).
            guard acknowledged, engine.phase != .complete, !endedEarly else { return }
            // An explicit user pause survives an app-switch: don't auto-restart the camera under it.
            if sp == .background { camera.stop() } else if sp == .active && !userPaused { camera.start() }
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
                                 heldS: engine.totalHeldS, feeling: nil,
                                 roundsHeldS: engine.roundTimes.isEmpty ? nil : engine.roundTimes)
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
                            if engine.mode == .locate {
                                // Locate step: the ring is an APPROXIMATE guide ("about here"),
                                // drawn dashed so it reads as a search area, not a target lock.
                                Circle().stroke(Ink.gold, style: StrokeStyle(lineWidth: 3, dash: [7, 6]))
                                    .frame(width: r * 2, height: r * 2).position(m.pt)
                                Text(AppLocale.pick("≈ 大约在这里", "≈ about here"))
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Ink.gold.opacity(0.92)))
                                    .position(x: m.pt.x, y: m.pt.y - r - 18)
                            } else {
                                Circle().stroke(engine.color, lineWidth: 3)
                                    .frame(width: r * 2, height: r * 2).position(m.pt)
                                Circle().fill(engine.color).frame(width: 8, height: 8).position(m.pt)
                            }
                        }
                        if let t = engine.pressTip {
                            Circle().stroke(.white, lineWidth: 2).frame(width: 16, height: 16)
                                .position(mapFill(t, geo.size).pt)
                        }
                        // The settled press, labeled — the spot the app offers to remember.
                        if engine.mode == .locate, let cand = engine.locateCandidate {
                            let p = mapFill(cand, geo.size).pt
                            Circle().fill(Ink.gold).frame(width: 10, height: 10).position(p)
                            Text(AppLocale.pick("你按的位置", "your press"))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(.black.opacity(0.6)))
                                .position(x: p.x, y: p.y + 22)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea()

            VStack {
                debugBar
                Spacer()
                if engine.mode == .locate {
                    LocateCard(point: acupoint, engine: engine)
                } else {
                    feedbackCard
                }
            }

            if userPaused { pausedOverlay }
        }
        // Cap growth so the largest accessibility sizes can't break the camera overlay layout,
        // while still honoring Dynamic Type up to that bound.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        // End with banked progress → confirm first (the recap records honestly either way).
        .endSessionDialog(isPresented: $showEndConfirm, rounds: engine.roundsDone,
                          heldS: engine.totalHeldS) { endSession() }
    }

    // Explicit pause: the camera stops (nothing is watched or credited); round progress is kept —
    // the engine's pause-grace and dt clamp read the gap exactly like an app-switch.
    private func pauseSession() {
        userPaused = true
        camera.stop()
        voice.reset()   // cut any mid-utterance cue
    }
    private func resumeSession() {
        userPaused = false
        camera.start()
    }

    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "pause.circle").font(.system(size: 44)).foregroundStyle(Ink.paper)
                Text(AppLocale.pick("已暂停", "Paused")).font(.title3).foregroundStyle(Ink.paper)
                Text(AppLocale.pick("进度已保留 — 准备好了就继续。", "Your progress is kept — continue when ready."))
                    .font(.footnote).foregroundStyle(Ink.paper.opacity(0.8))
                Button(AppLocale.pick("继续", "Resume")) { resumeSession() }
                    .buttonStyle(GoldButtonStyle())
            }
            .padding(28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
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
            .accessibilityLabel(voice.muted ? AppLocale.pick("开启语音提示", "Unmute voice cues")
                                            : AppLocale.pick("关闭语音提示", "Mute voice cues"))
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
                if let hint = hintLine {
                    Text(hint).font(.caption2).foregroundStyle(Ink.warn)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            Spacer()
            Button { pauseSession() } label: {
                Image(systemName: "pause.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Capsule().stroke(Ink.line, lineWidth: 1))
            }
            .accessibilityLabel(AppLocale.pick("暂停", "Pause"))
            .accessibilityHint(AppLocale.pick("暂停练习，进度保留", "Pauses the session; progress is kept"))
            Button(AppLocale.pick("结束", "End")) {
                // With real progress banked, confirm; a just-started session ends immediately.
                if engine.roundsDone > 0 || engine.totalHeldS >= 5 { showEndConfirm = true } else { endSession() }
            }
                .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().stroke(Ink.line, lineWidth: 1))
                .accessibilityHint(AppLocale.pick("随时结束本次练习并查看小结", "End this session now and see your recap"))
        }
        .padding(14).panel().padding()
        // One VoiceOver element that re-announces the cue + hold progress as the phase changes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(acupoint.id) \(acupoint.zh). \(engine.cue)\(hintLine.map { " \($0)" } ?? "")")
        .accessibilityValue("\(Int(engine.progress * 100)) percent held")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // WHY-line under the cue: the engine's occlusion hint wins (specific), else the dim-scene hint —
    // only while the coach is genuinely failing to see (never over a good hold).
    private var hintLine: String? {
        if let h = engine.hintText { return h }
        let searching = engine.phase == .noHand || engine.phase == .searching || engine.phase == .wrongFace
        if camera.lowLight && searching {
            return AppLocale.pick("光线偏暗 — 试试更亮的地方。", "Low light — try a brighter spot.")
        }
        return nil
    }

    // Shared recap (SessionUI.swift); verifiedHold → the camera-vouched "steady press" wording.
    private var recap: some View {
        SessionRecapView(point: acupoint, roundsDone: engine.roundsDone,
                         roundsTarget: engine.roundsTarget, heldS: engine.totalHeldS,
                         roundTimes: engine.roundTimes, verifiedHold: true,
                         sessionComplete: engine.sessionComplete, feeling: $feeling,
                         onFeeling: { key in
                             if let id = practiceRecordId { PracticeStore.shared.setFeeling(id: id, feeling: key) }
                         },
                         onNext: onNext)
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
