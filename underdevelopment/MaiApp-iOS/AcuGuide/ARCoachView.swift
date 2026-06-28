import SwiftUI

// The AR coaching window: forced safety gate -> live camera + acupoint overlay -> recap.
// Demo point = TE3 (the validated one). Safety gate is the immutable rule (no skip).
struct ARCoachView: View {
    let acupoint: Acupoint
    @StateObject private var engine: CoachEngine
    @StateObject private var camera: CameraCoach
    @StateObject private var voice = CoachVoice()
    @StateObject private var haptics = CoachHaptics()
    @State private var acknowledged = false
    @State private var feeling: String? = nil
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
            Ink.parch.ignoresSafeArea()
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
                CameraPreview(session: camera.session, mirrored: camera.mirrored).ignoresSafeArea()

                // Target ring + inner dot (smoothed center from the engine).
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

                VStack {
                    debugBar
                    Spacer()
                    feedbackCard
                }
            }
        }
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
            }
            Spacer()
        }
        .padding(14).panel().padding()
    }

    private var recap: some View {
        VStack(spacing: 20) {
            Text("Nicely held").font(.title2).foregroundStyle(Ink.gold)
            Text("You stayed on \(acupoint.id) (\(acupoint.zh)) steadily.")
                .foregroundStyle(Ink.paper).multilineTextAlignment(.center)
            Text("How do you feel?").font(.headline).foregroundStyle(Ink.paper)
            HStack {
                ForEach(["Some relief", "No change", "Felt worse"], id: \.self) { f in
                    Button(f) { feeling = f }.buttonStyle(GoldButtonStyle())
                }
            }
            if feeling == "Felt worse" {
                Text("Please stop for now. If symptoms are severe or persistent, consider seeing a professional.")
                    .font(.footnote).foregroundStyle(Ink.terracotta).multilineTextAlignment(.center).padding()
            }
            Text("Wellness self-care only — not medical advice.")
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
            Text("Before you begin").font(.title2).foregroundStyle(Ink.gold)
            Text("This is wellness self-care, not a medical tool. Stop and seek care if you notice:")
                .foregroundStyle(Ink.paper)
            ForEach(["sudden severe pain", "numbness or weakness", "dizziness", "worsening symptoms"], id: \.self) {
                Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Ink.paper).font(.subheadline)
            }
            Text("If you are pregnant or have a medical condition, check with a professional first.")
                .font(.footnote).foregroundStyle(Ink.textDim)
            Spacer().frame(height: 8)
            Button("I understand", action: onAcknowledge)
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
        }
        .padding(28)
    }
}
