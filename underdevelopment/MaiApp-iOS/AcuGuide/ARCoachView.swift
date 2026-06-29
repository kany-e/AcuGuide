import SwiftUI

// The AR coaching window: forced safety gate -> live camera + acupoint overlay -> recap.
// Demo point = TE3 (the validated one). Safety gate is the immutable rule (no skip).
struct ARCoachView: View {
    let acupoint: Acupoint
    @StateObject private var engine: CoachEngine
    @StateObject private var camera: CameraCoach
    @StateObject private var voice = CoachVoice()
    @StateObject private var haptics = CoachHaptics()
    @ObservedObject private var settings = AppSettings.shared
    @State private var acknowledged = false
    @State private var feeling: String? = nil      // stable key: "relief" | "nochange" | "worse"
    @State private var dorsalPositive = HandCalibration.dorsalWhenSignedPositive
    @State private var prevPhase: CoachPhase = .noHand

    init(acupoint: Acupoint) {
        self.acupoint = acupoint
        // Build the engine first, then hand the SAME instance to the camera (assign-before-use,
        // no redundant default StateObject).
        let eng = CoachEngine()
        _engine = StateObject(wrappedValue: eng)
        _camera = StateObject(wrappedValue: CameraCoach(engine: eng, acupoint: acupoint))
    }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            if !acknowledged {
                SafetyGate { acknowledged = true; camera.start() }
            } else if engine.phase == .complete || feeling != nil {
                recap
            } else {
                coachLayer
            }
        }
        // Drive voice + haptics off phase TRANSITIONS only (debounced by the engine), and stop the
        // camera as soon as the routine completes so nothing keeps running behind the recap.
        .onChange(of: engine.phase) { handlePhaseChange(to: $0) }
        .onDisappear { camera.stop(); voice.reset() }
    }

    private func handlePhaseChange(to phase: CoachPhase) {
        voice.update(phase: phase, requiresDorsal: acupoint.requiresDorsal)

        // Haptics: a light tick the first time the finger enters the target zone (not on every
        // unstable wobble), and a success pattern at COMPLETE. Nothing on NO_HAND / WRONG_FACE.
        let wasOnTarget = prevPhase == .onTargetUnstable || prevPhase == .holding
        let isOnTarget = phase == .onTargetUnstable || phase == .holding
        if isOnTarget && !wasOnTarget { haptics.enterTick() }
        if phase == .complete && prevPhase != .complete { haptics.complete() }

        if phase == .complete { camera.stop() }
        prevPhase = phase
    }

    private var coachLayer: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: camera.session, mirrored: camera.mirrored)
                    .ignoresSafeArea().accessibilityHidden(true)

                // Target ring + inner dot (smoothed center from the engine). Purely visual — the
                // feedback card below is the VoiceOver-announced source of truth.
                Group {
                    if let c = engine.ringCenter {
                        let p = CGPoint(x: c.x * geo.size.width, y: c.y * geo.size.height)
                        let r = engine.ringRadius * geo.size.width
                        Circle().stroke(engine.color, lineWidth: 3)
                            .frame(width: r * 2, height: r * 2).position(p)
                        Circle().fill(engine.color).frame(width: 8, height: 8).position(p)
                    }
                    if let t = engine.pressTip {
                        Circle().stroke(.white, lineWidth: 2).frame(width: 16, height: 16)
                            .position(x: t.x * geo.size.width, y: t.y * geo.size.height)
                    }
                }
                .accessibilityHidden(true)

                VStack {
                    debugBar
                    Spacer()
                    feedbackCard
                }
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
            Button { voice.muted.toggle() } label: {
                Image(systemName: voice.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.callout).foregroundStyle(Ink.paper.opacity(0.85))
                    .padding(8).background(Circle().fill(.black.opacity(0.35)))
            }
            .accessibilityLabel(voice.muted ? "Unmute voice cues" : "Mute voice cues")
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
                Text(acupoint.id + " · " + acupoint.zh).font(.caption).foregroundStyle(Ink.gold)
                Text(engine.cue).font(.subheadline).foregroundStyle(Ink.text)
                    .lineLimit(3).minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(14).panel().padding()
        // One VoiceOver element that re-announces the cue + hold progress as the phase changes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(acupoint.id) \(acupoint.zh). \(engine.cue)")
        .accessibilityValue("\(Int(engine.progress * 100)) percent held")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var recap: some View {
        VStack(spacing: 20) {
            Text(AppLocale.pick("保持得很好", "Nicely held")).font(.title2).foregroundStyle(Ink.gold)
            Text(AppLocale.pick("你在 \(acupoint.id)（\(acupoint.zh)）上稳定地保持了。",
                                "You stayed on \(acupoint.id) (\(acupoint.zh)) steadily."))
                .foregroundStyle(Ink.text).multilineTextAlignment(.center)
            Text(AppLocale.pick("感觉如何？", "How do you feel?")).font(.headline).foregroundStyle(Ink.text)
            HStack {
                ForEach([("relief", AppLocale.pick("有所缓解", "Some relief")),
                         ("nochange", AppLocale.pick("没有变化", "No change")),
                         ("worse", AppLocale.pick("感觉更糟", "Felt worse"))], id: \.0) { item in
                    Button(item.1) { feeling = item.0 }.buttonStyle(GoldButtonStyle())
                        .accessibilityHint(AppLocale.pick("记录练习后的感受", "Records how you feel after the routine"))
                }
            }
            // "Felt worse" → advise stopping, never "continue" (immutable safety behavior).
            if feeling == "worse" {
                Text(AppLocale.pick("请暂时停止。如果症状严重或持续，请考虑就医。",
                                    "Please stop for now. If symptoms are severe or persistent, consider seeing a professional."))
                    .font(.footnote).foregroundStyle(Ink.terracotta).multilineTextAlignment(.center).padding()
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
