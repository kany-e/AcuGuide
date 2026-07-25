import SwiftUI
import UIKit

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
    // Hands-free confirm for the locate step (both hands are pressing — speaking beats tapping).
    @StateObject private var locateVoice = LocateVoiceControl()
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
    @State private var savedChip: String? = nil    // transient over-camera confirmation chip

    init(acupoint: Acupoint, roundsTarget: Int = CoachConst.sessionRounds,
         onNext: (label: String, action: () -> Void)? = nil,
         acknowledgedInitially: Bool = false,
         onUseTimer: (() -> Void)? = nil,
         forceLocate: Bool = false) {
        self.acupoint = acupoint
        self.onNext = onNext
        self.onUseTimer = onUseTimer
        // Build the engine first, then hand the SAME instance to the camera (assign-before-use,
        // no redundant default StateObject). roundsTarget: 1 for the first-run quick try; a
        // routine step's rounds otherwise. acknowledgedInitially: steps ≥2 of a ROUTINE run —
        // the safety gate was confirmed at step 1 of the same continuous session (never skipped
        // for a fresh session).
        // startLocating: points with a find-by-feel guide open in the ON-CAMERA locate step —
        // but ONLY until the user has saved a spot. A returning calibrated user goes straight to
        // coaching (a transient "using your saved spot" chip + the re-find button in the top bar
        // replace the full teach card — it gated EVERY session and routine step; review-caught).
        // forceLocate: entered from "Find my spot" — re-open the locate step even though a spot is
        // already saved, so re-calibrating never requires deleting the old one first.
        let calibrated = PointCalibration.shared.hasCalibration(acupoint.id)
        let eng = CoachEngine(roundsTarget: roundsTarget,
                              startLocating: acupoint.hasFindGuide && (forceLocate || !calibrated))
        _engine = StateObject(wrappedValue: eng)
        _camera = StateObject(wrappedValue: CameraCoach(engine: eng, acupoint: acupoint))
        _acknowledged = State(initialValue: acknowledgedInitially)
        _savedChip = State(initialValue: calibrated && acupoint.hasFindGuide && !forceLocate
            ? AppLocale.pick("已使用你保存的位置", "Using your saved spot") : nil)
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
            } else if !settings.seenCameraSetup {
                // First camera session ever: the physical setup card. Sits AFTER the recap check
                // on purpose — the invariant above (a finished session is never masked) outranks
                // it, and it can't actually trigger there since reaching a recap means the card
                // was already passed.
                // It also sits BEFORE CameraGate rather than inside it: the whole point is to get
                // the phone propped up before the camera is live, and CameraGate starts capture as
                // soon as its content appears, so hosting the card inside it would run the capture
                // session behind a screen that shows no camera. The cost is that someone who then
                // DENIES the camera has spent their one-time card on a session they can't run —
                // Settings can bring it back, which is part of why that reset exists.
                CameraSetupCard(onContinue: { settings.seenCameraSetup = true },
                                voiceControl: locateVoice)
            } else {
                // Permission gate AFTER the safety gate: the system prompt arrives in context, a
                // denial gets an open-Settings hand-off instead of a black screen, and the capture
                // session only ever starts once authorized. The find-it-by-feel LOCATE step now
                // lives ON the camera (engine.mode == .locate): dashed guide ring + instructions,
                // the user's press gets labeled, and their confirmed spot corrects the ring.
                CameraGate(onAuthorized: { camera.start() }, onUseTimer: onUseTimer) { coachLayer }
            }
        }
        // Same reason as the timer session: the user is holding a point with both hands and not
        // touching the screen. Released automatically in the recap, on pause, and on disappear.
        .keepScreenAwake(while: acknowledged && engine.phase != .complete && !endedEarly
                                && feeling == nil && !userPaused)
        // Drive voice + haptics off phase TRANSITIONS only (debounced by the engine), and stop the
        // camera as soon as the routine completes so nothing keeps running behind the recap.
        .onChange(of: engine.phase) { handlePhaseChange(to: $0) }
        // The locate step never changes CoachPhase, so it needs its own transition hook — without
        // it the whole find-the-spot flow was silent to voice, haptics, and VoiceOver.
        .onChange(of: engine.locateState) { handleLocateChange(to: $0) }
        // Interruption robustness: a call / app-switch stops the camera (no capture in the
        // background); returning restarts it (start is idempotent + authorization-gated). The
        // machine's pause-grace and dt clamp make the gap read as a pause, never a credit jump.
        .onChange(of: scenePhase) { sp in
            // Only manage the camera past the safety gate (the locate step is on-camera now, so
            // every post-gate screen legitimately runs the capture session).
            guard acknowledged, engine.phase != .complete, !endedEarly else { return }
            // An explicit user pause survives an app-switch: don't auto-restart the camera under it.
            if sp == .background {
                engine.suspendLocate()   // frames stop → the confirm latch must not outlive them
                locateVoice.stop()
                camera.stop()
            } else if sp == .active && !userPaused { camera.start() }
        }
        // Voice commands act through the SAME paths as the buttons (confirm gate included).
        // Observed, not a control-held closure: the handler is owned by the view, so it can't
        // retain the engine/camera graph into a leak (review-caught). Guarded on live locate state
        // + not paused, so a command delivered just as the step ends / pauses is dropped.
        .onChange(of: locateVoice.command) { cmd in
            guard let cmd, engine.mode == .locate, !userPaused, !endedEarly else { return }
            switch cmd.kind {
            case .confirm:
                if engine.confirmLocate(point: acupoint) {
                    LocatedStore.shared.markLocated(acupoint.id)
                    handleLocateConfirmed()   // mode → .coach flips the mic off via onChange below
                }
            case .skip:
                engine.endLocate()
                voice.handover()
            }
        }
        // The app's own TTS goes out the speaker into the open mic — pause recognition while it
        // speaks so voice confirm can't transcribe and fire on the app's own cues.
        .onChange(of: voice.isSpeaking) { locateVoice.setAppSpeaking($0) }
        // Leaving the locate step by ANY path shuts the mic — listening is locate-scoped.
        .onChange(of: engine.mode) { if $0 == .coach { locateVoice.stop() } }
        // The .ready spoken cue is suppressed WHILE listening (so the app doesn't talk over the confirm)
        // and deliberately not marked as spoken. If the user turns the mic off while still settled at
        // .ready, re-speak it now — handleLocateChange only fires on a locateState CHANGE, so otherwise
        // the cue would be lost until the state bounces out of .ready. (The VoiceOver announcement was
        // already posted when .ready was reached, so eyes-free users weren't left silent regardless.)
        .onChange(of: locateVoice.listening) { listening in
            if !listening, engine.mode == .locate, engine.locateState == .ready, !userPaused, !endedEarly {
                voice.updateLocate(state: .ready, requiresDorsal: acupoint.requiresDorsal,
                                   selfCoaching: camera.usingFront, voiceConfirmActive: false)
            }
        }
        .onDisappear { locateVoice.stop(); camera.stop(); voice.reset() }
    }

    private func handleLocateChange(to state: LocateState) {
        guard engine.mode == .locate else { return }
        voice.updateLocate(state: state, requiresDorsal: acupoint.requiresDorsal,
                           selfCoaching: camera.usingFront, voiceConfirmActive: locateVoice.listening)
        if state == .ready {
            haptics.enterTick()   // the confirm just unlocked — a felt cue, like entering the ring
            // The VoiceOver announcement is ALWAYS posted — it's the eyes-free readiness signal and,
            // being keyword-free, is safe to speak while the mic is open (it can't self-trigger the
            // recognizer, and unlike the AVSpeech cue it does NOT set CoachVoice.isSpeaking, so it
            // never suppresses recognition of the user's confirm). Only the AVSpeech .ready cue —
            // which DOES gate the mic via appSpeaking — is held back while listening (in Speech.swift).
            UIAccessibility.post(notification: .announcement,
                                 argument: AppLocale.pick("位置已锁定 — 准备好就保存。",
                                                          "Spot settled — save it when you're ready."))
        }
    }

    // The saved-it moment must not be silent OR invisible — confirm and Skip otherwise land on
    // pixel-identical screens (review-caught). Voice + haptic + VoiceOver + a transient chip.
    private func handleLocateConfirmed() {
        haptics.complete()
        voice.locateSaved()
        UIAccessibility.post(notification: .announcement,
                             argument: AppLocale.pick("已记住你的位置。", "Saved — the ring now sits on your spot."))
        savedChip = AppLocale.pick("已记住你的位置", "Saved — this is your spot now")
    }

    private func handlePhaseChange(to phase: CoachPhase) {
        voice.update(phase: phase, requiresDorsal: acupoint.requiresDorsal,
                     selfCoaching: camera.usingFront)
        // The engine discards every hand during the rest gap — skip Vision entirely there
        // (~25% of a 4-round session; the empty frames keep the rest clock ticking).
        camera.setDetectionPaused(phase == .resting)

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
        engine.suspendLocate()   // void the confirm latch so a spoken confirm can't fire on the recap
        locateVoice.stop()
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

    private var coachLayer: some View {
        ZStack {
            // Preview + overlay share a FULL-SCREEN coordinate space (ignoresSafeArea), so the
            // ring/press-dot land on the same pixels the aspect-fill preview shows. The chrome is
            // kept OUTSIDE this and respects the safe area (status bar / home indicator).
            ZStack {
                CameraPreview(session: camera.session, mirrored: camera.mirrored,
                              configGeneration: camera.configGeneration)
                    .accessibilityHidden(true)
                // The 30 Hz ring/dot stream renders in its OWN subview observing CoachOverlay, so
                // per-frame invalidation stays inside it instead of re-evaluating this entire
                // full-screen body every camera frame (review-caught).
                CoachOverlayLayer(engine: engine, overlay: engine.overlay,
                                  frameAspect: camera.frameAspect)
            }
            .ignoresSafeArea()

            VStack {
                debugBar
                if let chip = savedChip {
                    Text(chip)
                        .font(.caption.weight(.semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Ink.gold.opacity(0.92)))
                        .transition(.opacity)
                        .task { try? await Task.sleep(nanoseconds: 2_800_000_000)
                                withAnimation(.easeOut(duration: 0.4)) { savedChip = nil } }
                }
                Spacer()
                if engine.mode == .locate {
                    LocateCard(point: acupoint, engine: engine, voiceControl: locateVoice,
                               hint: hintLine,
                               onPause: { pauseSession() },
                               onEnd: { endSession() },   // nothing banked during locate → no confirm needed
                               onConfirmed: { handleLocateConfirmed() },
                               onSkipped: { voice.handover() })   // let the first coach cue speak
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
        engine.suspendLocate()   // the confirm latch is frame-clocked — void it while frames stop
        locateVoice.stop()       // nothing should be listening behind the pause overlay
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
            // Re-find the spot: back into the guided locate step from coaching — without this, a
            // bad confirm (or a ring that feels off) was only fixable by ending the whole session.
            if acupoint.hasFindGuide && engine.mode == .coach {
                Button {
                    engine.beginLocate()
                    voice.handover()   // cut any coach cue; the locate cues take over
                } label: {
                    Image(systemName: "target")
                        .font(.callout).foregroundStyle(Ink.paper.opacity(0.85))
                        .padding(8).background(Circle().fill(.black.opacity(0.35)))
                }
                .accessibilityLabel(AppLocale.pick("重新找位", "Re-find the spot"))
                .accessibilityHint(AppLocale.pick("重新进入找位步骤，更新你保存的位置",
                                                  "Re-enter the locate step to update your saved spot"))
            }
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
            HoldProgressRing(overlay: engine.overlay, color: engine.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(acupoint.id + " · " + acupoint.zh).font(.caption).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("第 \(min(engine.roundsDone + 1, engine.roundsTarget))/\(engine.roundsTarget) 轮",
                                        "Round \(min(engine.roundsDone + 1, engine.roundsTarget)) of \(engine.roundsTarget)"))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                }
                Text(engine.cue).font(.subheadline).foregroundStyle(Ink.text)
                    .lineLimit(3).minimumScaleFactor(0.7)
                // HOW TO FIND IT, on the camera screen, while the coach is still hunting.
                //
                // The spoken cue tells the user to find the point "around the outlined area", but the
                // written guidance had only ONE render site on this screen — inside LocateCard's
                // collapsed disclosure — and a user who has already calibrated this point skips the
                // locate step entirely (ARCoachView.swift:46 `startLocating: … && !calibrated`). So the
                // audio promised instructions the screen never showed (user-reported).
                //
                // Shown only while searching/no-hand: it must never crowd the card during a good hold,
                // and it must never grow the card mid-press. No tap needed — both hands are busy.
                if acupoint.hasFindGuide,
                   engine.phase == .searching || engine.phase == .noHand || engine.phase == .wrongFace {
                    Text(acupoint.findHow)
                        .font(.caption2).foregroundStyle(Ink.gold)
                        .lineLimit(3).minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(AppLocale.pick("这样找：", "How to find it: ") + acupoint.findHow)
                }
                // The point's OWN caution, alongside the find guide and under the same
                // still-hunting condition — the forced safety gate covers generic red flags and says
                // nothing point-specific, and a caution is most useful before the finger settles.
                // Never during .holding: it must not appear as if something has gone wrong mid-press.
                if !acupoint.caution.isEmpty,
                   engine.phase == .searching || engine.phase == .noHand || engine.phase == .wrongFace {
                    Text(acupoint.caution)
                        .font(.caption2).foregroundStyle(Ink.terracotta)
                        .lineLimit(2).minimumScaleFactor(0.75)
                        .accessibilityLabel(AppLocale.pick("注意：", "Caution: ") + acupoint.caution)
                }
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
    // only while the coach is genuinely failing to see (never over a good hold / settled press).
    // Shared by feedbackCard AND LocateCard; the "failing to see" predicate is mode-aware because
    // CoachPhase is frozen during locate (locateState is the live signal there).
    private var hintLine: String? {
        if let h = engine.hintText { return h }
        let searching: Bool
        if engine.mode == .locate {
            searching = engine.locateState == .noHand || engine.locateState == .noPress
                || engine.locateState == .wrongFace
        } else {
            searching = engine.phase == .noHand || engine.phase == .searching || engine.phase == .wrongFace
        }
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

// The 30 Hz overlay: guide ring, press dot, labeled press, saved-spot dot. Observes CoachOverlay
// (per-frame) + the engine (transition-rate mode/phase color), so camera-frame invalidation stays
// INSIDE this subview instead of re-evaluating the whole ARCoachView body (review-caught).
private struct CoachOverlayLayer: View {
    @ObservedObject var engine: CoachEngine
    @ObservedObject var overlay: CoachOverlay
    let frameAspect: CGFloat

    // Map a normalized landmark (top-left origin) through the preview's aspect-fill crop, so the
    // overlay lands on the SAME pixels the user sees. Returns the screen point + the displayed
    // frame width (to scale the ring radius, which is a fraction of frame width).
    private func mapFill(_ n: CGPoint, _ size: CGSize) -> (pt: CGPoint, dispW: CGFloat) {
        let fw = frameAspect, fh: CGFloat = 1
        let s = max(size.width / fw, size.height / fh)   // aspect-fill: cover, crop overflow
        let dw = s * fw, dh = s * fh
        let ox = (size.width - dw) / 2, oy = (size.height - dh) / 2
        return (CGPoint(x: ox + n.x * dw, y: oy + n.y * dh), dw)
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if let c = overlay.ringCenter {
                    let m = mapFill(c, geo.size)
                    let r = overlay.ringRadius * m.dispW
                    if engine.mode == .locate {
                        // Locate step: the dashed ring marks the STANDARD spot — the same datum
                        // the capture gate and the storage clamp use, so the cue's "closer to the
                        // dashed ring" is always followable (review-caught datum split).
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
                // Re-locate: the previously saved spot stays visible as a small reference dot
                // while the dashed ring guides from the standard spot.
                if engine.mode == .locate, let s = overlay.savedSpot {
                    let p = mapFill(s, geo.size).pt
                    Circle().fill(Ink.jade).frame(width: 8, height: 8).position(p)
                        .overlay(Circle().stroke(.white, lineWidth: 1).frame(width: 8, height: 8).position(p))
                    Text(AppLocale.pick("已保存", "saved"))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .position(x: p.x, y: p.y - 16)
                }
                if let t = overlay.pressTip {
                    Circle().stroke(.white, lineWidth: 2).frame(width: 16, height: 16)
                        .position(mapFill(t, geo.size).pt)
                }
                // The settled press, labeled — the spot the app offers to remember (rides the
                // live hand pose while the confirm latch holds).
                if engine.mode == .locate, let cand = overlay.locateCandidate {
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
}

// The 46 pt hold-progress ring — its own subview so the per-frame progress writes invalidate
// only this circle, not the whole feedback card / coach body.
private struct HoldProgressRing: View {
    @ObservedObject var overlay: CoachOverlay
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Ink.line, lineWidth: 5).frame(width: 46, height: 46)
            Circle().trim(from: 0, to: overlay.progress)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 46, height: 46)
        }
    }
}

// Immutable safety gate — forced acknowledgement, no skip, no treat/cure/heal/diagnose copy.
struct SafetyGate: View {
    let onAcknowledge: () -> Void
    var body: some View {
        // The warning content SCROLLS; the acknowledge button is PINNED below it. This gate is
        // forced (its only exit is the button), so at large Dynamic Type sizes the old fixed VStack
        // pushed "I understand" off the bottom of the screen with no way to reach it — a forced gate
        // that becomes UNPASSABLE. Pinning the button keeps the single exit visible at every text
        // size; scrolling keeps the red-flag list fully readable rather than truncated.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(AppLocale.pick("开始之前", "Before you begin")).font(.title2).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("这是养生自我保养，并非医疗工具。如出现以下情况，请停止并就医：",
                                        "This is wellness self-care, not a medical tool. Stop and seek care if you notice:"))
                        .foregroundStyle(Ink.text)
                    ForEach([AppLocale.pick("突发剧烈疼痛", "sudden severe pain"),
                             AppLocale.pick("麻木或无力", "numbness or weakness"),
                             AppLocale.pick("头晕", "dizziness"),
                             AppLocale.pick("症状加重", "worsening symptoms")], id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Ink.text).font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(AppLocale.pick("如果你怀孕或有健康状况，请先咨询专业人士。",
                                        "If you are pregnant or have a medical condition, check with a professional first."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Button(AppLocale.pick("我明白了", "I understand"), action: onAcknowledge)
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
        }
    }
}
