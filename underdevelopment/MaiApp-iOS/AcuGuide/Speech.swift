import AVFoundation

// Spoken coaching cues — native equivalent of the web app's useTTS. Speaks ONLY on a phase
// CHANGE (never per frame), bilingual by device locale, with a mute toggle. The on-screen cue
// copy stays in English; the spoken phrase is a short localized line per phase so a zh device
// hears Chinese. All copy stays within the non-negotiables (no treat/cure/heal/diagnose).
final class CoachVoice: ObservableObject {
    @Published var muted = false {
        didSet { if muted { synth.stopSpeaking(at: .immediate) } }
    }

    private let synth = AVSpeechSynthesizer()
    private var lastSpokenPhase: CoachPhase? = nil

    init() {
        // Use the app's audio session and the .ambient category so the spoken cue RESPECTS the
        // hardware silent switch and mixes with (rather than interrupting) any other audio.
        synth.usesApplicationAudioSession = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func reset() { lastSpokenPhase = nil; synth.stopSpeaking(at: .immediate) }

    // Call on every engine update; it self-debounces to phase changes.
    func update(phase: CoachPhase, requiresDorsal: Bool) {
        guard phase != lastSpokenPhase else { return }
        lastSpokenPhase = phase
        guard !muted, let line = phrase(for: phase, requiresDorsal: requiresDorsal) else { return }
        speak(line)
    }

    private func phrase(for phase: CoachPhase, requiresDorsal: Bool) -> String? {
        switch phase {
        case .noHand:           return AppLocale.pick("把手放进画面。", "Bring your hand into the frame.")
        case .wrongFace:        return requiresDorsal
            ? AppLocale.pick("把手背朝向相机。", "Turn the back of your hand toward the camera.")
            : AppLocale.pick("把手掌朝向相机。", "Turn your palm toward the camera.")
        case .searching:        return AppLocale.pick("移动到高亮区域。", "Move toward the highlighted area.")
        case .onTargetUnstable: return AppLocale.pick("保持稳定。", "Hold it steady.")
        case .holding:          return AppLocale.pick("很好，稳定地用力。", "Good — firm, steady pressure.")
        case .paused:           return AppLocale.pick("快好了，回到穴位上。", "Almost — move back onto the point.")
        case .complete:         return AppLocale.pick("保持得很好，完成了。", "Nicely held — all done.")
        }
    }

    private func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: AppLocale.isChinese ? "zh-CN" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }
}
