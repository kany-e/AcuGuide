import AVFoundation

// Spoken coaching cues — native equivalent of the web app's useTTS. Speaks ONLY on a phase
// CHANGE (never per frame), bilingual by device locale, with a mute toggle. The on-screen cue
// copy stays in English; the spoken phrase is a short localized line per phase so a zh device
// hears Chinese. All copy stays within the non-negotiables (no treat/cure/heal/diagnose).
final class CoachVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    // Persisted via AppSettings so the choice survives sessions (was per-session state).
    @Published var muted = AppSettings.shared.voiceMuted {
        didSet {
            AppSettings.shared.voiceMuted = muted
            if muted { stopSpeaking() }
        }
    }
    // True while an utterance is rendering — the locate voice-confirm mic reads this (bridged in
    // ARCoachView) to ignore recognition while the app is speaking, so it can't transcribe and act
    // on its own cues (the self-confirmation loop; review-caught).
    @Published private(set) var isSpeaking = false {
        didSet { if !isSpeaking { lastCueEnd = Date() } }
    }
    /// The line currently (or most recently) being spoken. Handed to LocateVoiceControl so the mic
    /// can reject the app's OWN voice without rejecting the user's — see the echo gate in
    /// LocateVoice.swift, which replaced a blanket mute that swallowed nearly every command.
    private(set) var lastSpokenText: String? = nil

    private var lastCueEnd = Date.distantPast
    /// Minimum quiet gap between spoken cues WHILE THE MIC IS OPEN. stepLocate flips between
    /// noPress/settling/offGuide inside a second (CoachConst.locateSteadyS 0.6 / locateWindowS 0.8)
    /// and the zh clips for those states run ~1.8-5.0 s, so back-to-back cues left the recognizer
    /// almost no clean audio to decode a command out of. This does not mute the coach — eyes-free
    /// users still need the instruction — it just stops it holding the floor continuously.
    private static let listeningCueGapS: TimeInterval = 2.0

    private let synth = AVSpeechSynthesizer()
    // Pre-rendered neural clip for this line when one is bundled (see VoiceClips); AVSpeech is the
    // fallback for anything unrendered, so the coach is never mute.
    private let clip = ClipPlayer()
    private var lastSpokenPhase: CoachPhase? = nil
    private var lastSpokenLocate: LocateState? = nil

    override init() {
        super.init()
        // Use the app's audio session and the .ambient category so the spoken cue RESPECTS the
        // hardware silent switch and mixes with (rather than interrupting) any other audio.
        synth.usesApplicationAudioSession = true
        synth.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { isSpeaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { isSpeaking = false }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { isSpeaking = false }

    func reset() {
        lastSpokenPhase = nil
        lastSpokenLocate = nil
        stopSpeaking()
        // NOT under a live mic. reset() is called from beginStudy (the freeze-the-frame command) while
        // the mic is session-scoped and listening, and deactivating the shared session there pulled it
        // out from under the input tap — so the very command that froze the frame killed the mic that
        // would have unfrozen it, which is the one thing this hands-free feature cannot afford.
        guard !LocateVoiceControl.micHoldsSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Guided-locate cues — the locate step never changes CoachPhase, so without these lines the
    // whole find-the-spot flow was SILENT for eyes-free users (review-caught). Same
    // transition-debounced contract as update(phase:). `selfCoaching` = front camera (your own
    // hand) vs back camera (someone else's — the "your hand" lines switch person).
    func updateLocate(state: LocateState, requiresDorsal: Bool, selfCoaching: Bool = true,
                      voiceConfirmActive: Bool = false) {
        guard state != lastSpokenLocate else { return }
        // While the hands-free mic is open, the AVSpeech .ready cue would play out the speaker at the
        // exact moment the user speaks their confirm — its didStart sets isSpeaking → appSpeaking,
        // which suppresses (and the consume-once transcript then drops) the command, so voice-confirm
        // never fired. Stay silent on .ready while listening (the VoiceOver announcement + haptic still
        // signal readiness). Do NOT record it as spoken, so it can still be delivered if .ready is
        // re-entered while the mic is off.
        if state == .ready && voiceConfirmActive { return }
        lastSpokenLocate = state
        guard !muted,
              let line = Self.locatePhrase(for: state, requiresDorsal: requiresDorsal,
                                      selfCoaching: selfCoaching) else { return }
        // .ready is the behavior-changing line (the confirm just unlocked) — never drop it.
        if speaking && state != .ready { return }
        speak(line, priority: state == .ready)
    }

    // Locate → coach handover (confirm or skip): cut any stale locate line mid-utterance — the
    // .ready instruction otherwise kept playing AFTER the user confirmed — and clear both
    // debounce anchors so the first cue of the next mode actually speaks (the isSpeaking guard
    // was silently swallowing it; review-caught).
    func handover() {
        lastSpokenPhase = nil
        lastSpokenLocate = nil
        stopSpeaking()
    }

    // The one moment that must never pass silently: the user's spot was SAVED. Confirm and Skip
    // otherwise land on identical screens (review-caught).
    func locateSaved() {
        handover()
        guard !muted else { return }
        speak(Self.savedLine, priority: true)
    }

    // The saved-it line, hoisted out of locateSaved() so VoiceScript can enumerate it too.
    static var savedLine: String {
        AppLocale.pick("已记住你的位置 — 圆圈就在那里。", "Saved — the ring now sits on your spot.")
    }

    // `static` + internal so VoiceScript can enumerate every line for the pre-rendered clip manifest
    // (the phrase tables stay the ONE source of truth — the render list can't drift from what's spoken).
    static func locatePhrase(for state: LocateState, requiresDorsal: Bool,
                              selfCoaching: Bool) -> String? {
        switch state {
        // The shared get-in-view / flip-the-hand instructions delegate to the coach phrases —
        // one source of truth (they were verbatim copies that would drift; review-caught).
        case .noHand:    return phrase(for: .noHand, requiresDorsal: requiresDorsal, selfCoaching: selfCoaching)
        case .wrongFace: return phrase(for: .wrongFace, requiresDorsal: requiresDorsal, selfCoaching: selfCoaching)
        case .noPress:   return selfCoaching
            ? AppLocale.pick("用另一只手的指尖，在虚线圈附近按一按找找。",
                             "Feel around the dashed ring with your other fingertip.")
            : AppLocale.pick("用你的指尖，在对方手上的虚线圈附近按一按找找。",
                             "Feel around the dashed ring on their hand with your fingertip.")
        case .offGuide:  return AppLocale.pick("有点远了，回到虚线圈附近。", "A little far — closer to the dashed ring.")
        case .settling:  return AppLocale.pick("按住不动一小会儿。", "Hold the press still a moment.")
        // Deliberately KEYWORD-FREE ("save", not "this is my spot"/"confirm"): this line is spoken
        // out the speaker while the voice-confirm mic may be open, so it must not contain a command
        // the recognizer would transcribe and act on (the self-confirmation loop; review-caught).
        case .ready:     return AppLocale.pick("很好 — 现在可以保存这个位置了。", "Good — you can save this spot now.")
        }
    }

    // Call on every engine update; it self-debounces to phase changes.
    func update(phase: CoachPhase, requiresDorsal: Bool, selfCoaching: Bool = true) {
        guard phase != lastSpokenPhase else { return }
        lastSpokenPhase = phase
        guard !muted, let line = Self.phrase(for: phase, requiresDorsal: requiresDorsal,
                                        selfCoaching: selfCoaching) else { return }
        // Don't clip an in-progress cue for a transient phase oscillation (e.g. a NO_HAND ↔
        // WRONG_FACE flicker at the frame edge chopping each utterance mid-word). Let the current
        // one finish — EXCEPT for the two behavior-changing instructions, which must never be
        // dropped: COMPLETE (the finish cue) and RESTING ("release" — without preemption a round
        // completing mid-utterance left eyes-free users pressing through the whole rest gap).
        if speaking && phase != .complete && phase != .resting { return }
        // …and the same two survive the listening cue-gap, or the rule above would hold only against
        // an in-progress utterance and not against the rate limit.
        speak(line, priority: phase == .complete || phase == .resting)
    }

    static func phrase(for phase: CoachPhase, requiresDorsal: Bool,
                        selfCoaching: Bool = true) -> String? {
        switch phase {
        case .noHand:           return selfCoaching
            ? AppLocale.pick("把手放到镜头前吧。", "Bring your hand into view.")
            : AppLocale.pick("把对方的手放进画面吧。", "Bring their hand into view.")
        case .wrongFace:
            if !selfCoaching {
                return requiresDorsal
                    ? AppLocale.pick("把对方的手翻过来，手背对着镜头。", "Turn their hand over — back to the camera.")
                    : AppLocale.pick("把对方的手翻过来，手心对着镜头。", "Turn their hand over — palm to the camera.")
            }
            return requiresDorsal
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

    /// Anything currently coming out of the speaker — either backend.
    private var speaking: Bool { synth.isSpeaking || clip.isPlaying }

    private func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        clip.stop()
    }

    /// `priority` lines are never rate-limited. HOLD THE FLOOR LESS WHILE THE MIC IS OPEN: barge-in
    /// (the echo gate in LocateVoice) lets the user's command survive a cue, but the recognizer still
    /// needs audio that is not full-level coach speech to decode it out of. Cues inside the gap are
    /// DROPPED, not queued — they describe a state that changes several times a second, so a stale
    /// one is worse than none.
    ///
    /// The gap must therefore never see a line whose job is to tell the user something CHANGED. It
    /// was first written to exempt one hard-coded string (`.ready`), which silently ate the rest:
    /// "Saved — the ring now sits on your spot" (the one moment that must never pass in silence),
    /// the first cue after a handover, and the `.complete`/`.resting` instructions that
    /// `update(phase:)` has its own comment promising never to drop. Priority is a property of the
    /// CALL, not of the string.
    private func speak(_ text: String, priority: Bool = false) {
        if !priority, LocateVoiceControl.micHoldsSession,
           Date().timeIntervalSince(lastCueEnd) < Self.listeningCueGapS { return }
        lastSpokenText = text
        stopSpeaking()
        try? AVAudioSession.sharedInstance().setActive(true)
        // Pre-rendered neural clip when we have one (studio quality, no synthesis cost); otherwise
        // fall back to the best installed system voice so a reworded/new line is still spoken.
        if let url = VoiceClips.url(for: text) {
            isSpeaking = true
            let started = clip.play(url) { [weak self] in self?.isSpeaking = false }
            if started { return }
            isSpeaking = false
        }
        synth.speak(SpeechVoice.utterance(text))
    }
}

// Picks the most NATURAL available voice for a language and builds a calm utterance — shared by the
// coach cues and the atlas read-aloud so both sound the same. Prefers premium > enhanced > default
// (compact) quality: the enhanced/premium neural voices are the good-sounding ones, but the user has
// to install them once in Settings → Accessibility → Spoken Content → Voices; if none is installed we
// fall back to the built-in compact voice (still works, just more synthetic).
enum SpeechVoice {
    // The best installed voice per locale is stable for the session — cache it so we don't enumerate
    // the whole system voice catalog on every spoken cue. (Main-thread only, like all speak() calls.)
    private static var cache: [String: AVSpeechSynthesisVoice?] = [:]
    static func best(for localeID: String) -> AVSpeechSynthesisVoice? {
        if let hit = cache[localeID] { return hit }
        let lang = localeID.lowercased()
        let prefix = String(lang.prefix(2))                      // "en", "zh"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            let vl = $0.language.lowercased()
            return vl == lang || vl.hasPrefix(prefix)
        }
        func quality(_ v: AVSpeechSynthesisVoice) -> Int {
            if #available(iOS 16.0, *), v.quality == .premium { return 3 }
            return v.quality == .enhanced ? 2 : 1
        }
        // Exact-locale match wins, then highest quality, then a stable name order.
        func rank(_ v: AVSpeechSynthesisVoice) -> Int { (v.language.lowercased() == lang ? 10 : 0) + quality(v) }
        let chosen = voices.max { rank($0) != rank($1) ? rank($0) < rank($1) : $0.identifier > $1.identifier }
            ?? AVSpeechSynthesisVoice(language: localeID)
        cache[localeID] = chosen
        return chosen
    }

    // A calm, natural utterance in the current app language (a touch slower than default reads warmer).
    static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = best(for: AppLocale.speechLocaleID)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        u.pitchMultiplier = 1.0
        return u
    }
}

// Reads acupoint info aloud in the atlas / detail cards — decoupled from the coach's CoachVoice so it
// can be used anywhere a point is shown. Opt-in (a speaker button); toggling stops it. Uses .playback
// so an explicit "read aloud" tap is audible even with the silent switch on.
final class AtlasSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AtlasSpeaker()
    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()
    private let clip = ClipPlayer()   // pre-rendered neural clip when bundled; AVSpeech otherwise
    override init() { super.init(); synth.delegate = self; synth.usesApplicationAudioSession = true }

    func toggle(_ text: String) { speaking ? stop() : speak(text) }
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Stop the previous utterance BEFORE claiming the session. Stopping fires that utterance's
        // completion handler, which calls restore() and hands the session back to .ambient — so doing
        // this after setCategory/setActive would tear down the session we just set up and leave the
        // new read-aloud playing under .ambient, i.e. silenced by the hardware mute switch.
        synth.stopSpeaking(at: .immediate)
        clip.stop()
        // NOT WHILE THE MIC OWNS THE SESSION. `.playback` has no input route, so claiming it here
        // kills a live recognition tap — the exact hazard CoachVoice.reset() is guarded against, and
        // it became reachable the moment the read-aloud button was promoted to a named "Listen"
        // capsule on the coaching card. The mic's own shape (.playAndRecord + .voiceChat) is already
        // audible over the loudspeaker, so a read-aloud under it just works; the only thing given up
        // is `.duckOthers`, which matters less than silently deafening the hands-free controls.
        if !LocateVoiceControl.micHoldsSession {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        if let url = VoiceClips.url(for: text) {
            speaking = true
            let started = clip.play(url) { [weak self] in self?.speaking = false; self?.restore() }
            if started { return }
            speaking = false
        }
        synth.speak(SpeechVoice.utterance(text))
    }
    func stop() { synth.stopSpeaking(at: .immediate); clip.stop() }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { speaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { speaking = false; restore() }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { speaking = false; restore() }

    // Restore the app's gentle silent-switch-respecting default when a read-aloud ends, so the
    // .playback/.duckOthers we set for it doesn't leak app-wide — otherwise other apps stay ducked and
    // later coach cues (CoachVoice sets .ambient only once in init) would play over the silent switch.
    private func restore() {
        // …and symmetrically: if the mic owns the session there is nothing of ours to hand back, and
        // dropping it to `.ambient` + setActive(false) would leave the tap running over a dead route
        // with nothing to repair it (recoverFromConfigChange re-arms the task but never re-sets the
        // category).
        guard !LocateVoiceControl.micHoldsSession else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
