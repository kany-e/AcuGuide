import AVFoundation

// Spoken coaching cues — native equivalent of the web app's useTTS. Speaks ONLY on a phase
// CHANGE (never per frame), bilingual by device locale, with a mute toggle. The on-screen cue
// copy stays in English; the spoken phrase is a short localized line per phase so a zh device
// hears Chinese. All copy stays within the non-negotiables (no treat/cure/heal/diagnose).
final class CoachVoice: ObservableObject {
    // Persisted via AppSettings so the choice survives sessions (was per-session state).
    @Published var muted = AppSettings.shared.voiceMuted {
        didSet {
            AppSettings.shared.voiceMuted = muted
            if muted { synth.stopSpeaking(at: .immediate) }
        }
    }

    private let synth = AVSpeechSynthesizer()
    private var lastSpokenPhase: CoachPhase? = nil

    init() {
        // Use the app's audio session and the .ambient category so the spoken cue RESPECTS the
        // hardware silent switch and mixes with (rather than interrupting) any other audio.
        synth.usesApplicationAudioSession = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func reset() {
        lastSpokenPhase = nil
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Call on every engine update; it self-debounces to phase changes.
    func update(phase: CoachPhase, requiresDorsal: Bool) {
        guard phase != lastSpokenPhase else { return }
        lastSpokenPhase = phase
        guard !muted, let line = phrase(for: phase, requiresDorsal: requiresDorsal) else { return }
        // Don't clip an in-progress cue for a transient phase oscillation (e.g. a NO_HAND ↔
        // WRONG_FACE flicker at the frame edge chopping each utterance mid-word). Let the current
        // one finish — EXCEPT for the two behavior-changing instructions, which must never be
        // dropped: COMPLETE (the finish cue) and RESTING ("release" — without preemption a round
        // completing mid-utterance left eyes-free users pressing through the whole rest gap).
        if synth.isSpeaking && phase != .complete && phase != .resting { return }
        speak(line)
    }

    private func phrase(for phase: CoachPhase, requiresDorsal: Bool) -> String? {
        switch phase {
        case .noHand:           return AppLocale.pick("把手放到镜头前吧。", "Bring your hand into view.")
        case .wrongFace:        return requiresDorsal
            ? AppLocale.pick("翻一下手，手背对着镜头。", "Turn your hand over — back to the camera.")
            : AppLocale.pick("翻一下手，手心对着镜头。", "Turn your hand over — palm to the camera.")
        case .searching:        return AppLocale.pick("顺着圆圈慢慢找。", "Ease over toward the ring.")
        case .onTargetUnstable: return AppLocale.pick("就是这里，轻轻稳住。", "That's it — settle in.")
        case .holding:          return AppLocale.pick("很好，就这样稳稳按住。", "Good — keep that steady press.")
        case .resting:          return AppLocale.pick("松开手指，放松呼吸。", "Release — and breathe.")
        case .paused:           return AppLocale.pick("没关系，慢慢回到穴位上。", "No rush — ease back onto the point.")
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
