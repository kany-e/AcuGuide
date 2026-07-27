import Foundation
import Speech
import AVFoundation

// Hands-free confirm for the guided locate step: BOTH of the user's hands are occupied (one being
// pressed, one pressing), so the "This is my spot" button is physically awkward even with the
// confirm latch — a short spoken command does it instead (user-requested). Recognition prefers
// ON-DEVICE when the device supports it (audio stays local) and falls back to Apple's speech service
// otherwise (user-approved: strict on-device-only just reported "unavailable" on a device without the
// on-device model). Listening is opt-in per session (the mic button on the LocateCard), runs only
// while the locate step is active, and stops on confirm/skip/pause/disappear.
enum LocateVoiceCommand: Equatable {
    case confirm   // "this is my spot" — same path as tapping the button
    case skip      // "skip" — same as tapping Skip
    // STUDY MODE, hands-free. Freezing the frame to read the guide is only useful if you can get
    // out of it again without a hand — the whole premise is that both are occupied (one receiving,
    // one pressing). A tap-to-resume would break exactly the constraint the feature exists for
    // (user-caught: "if they found the location, they would have to take it off and click
    // continue"). Recognition, not synthesis, so these add no voice clips and nothing to re-render.
    case study     // "show me" / "怎么找" — freeze the frame and open the full guide
    case resume    // "continue" / "继续" — unfreeze and carry on
    // ASK WHAT YOU CAN SAY, BY SAYING IT. This is the gap the first attempt at discoverability
    // left: the command list was behind a "?" button, i.e. a TOUCH target in a feature whose whole
    // premise is that both hands are busy. Apple's own Voice Control answers this with
    // "show me what to say" / "show commands" / "what can I say", and makes the result
    // context-sensitive to the current screen — that is the pattern being copied here.
    case help

    // Whole-WORD confirm/skip phrases. English matches the trailing TOKENS (not a character
    // suffix, so "reconfirm" no longer matches "confirm"); Chinese matches the trailing chars
    // after trimming filler particles. Both reject a negation immediately before the phrase
    // ("don't confirm" / 不要确认). Deliberately NOT bare "yes"/"好" — too easy to trip in ambient
    // conversation. Pure + unit-tested.
    static let confirmEn = ["this is my spot", "this is it", "thats it", "that is it", "confirm"]
    static let confirmZh = ["就是这里", "就在这里", "确认"]
    // Deliberately multi-word / specific: a bare "show" or "看" trips constantly in ambient speech.
    static let studyEn = ["show me", "show me how", "read it", "read it again", "how do i find it"]
    static let studyZh = ["怎么找", "看说明", "再说一次"]
    static let resumeEn = ["resume", "continue", "carry on", "go on", "im ready", "i am ready"]
    // NOTE the filler interaction: zhFillers strips a trailing 了 before matching, so a phrase that
    // ENDS in 了 can never match — 好了 reduces to 好 and 可以了 to 可以. Matching the stripped forms
    // instead is not an option either: bare 好 is exactly the "too easy to trip in ambient
    // conversation" case the confirm list already rejects. So the Chinese resume words are ones that
    // survive stripping intact and stay specific. (Caught by StudyVoiceCommandTests before shipping —
    // both 好了 and 可以了 were silently dead.)
    static let resumeZh = ["继续", "找到", "开始"]
    // Deliberately the phrasings people actually try, taken from Voice Control's own vocabulary.
    // "show me what to say" does NOT collide with studyEn's "show me": English matching is anchored
    // to the TRAILING tokens, so only an utterance ENDING in "show me" is a study request. Help is
    // still checked first, and VoiceCommandTableTests pins both.
    static let helpEn = ["what can i say", "show me what to say", "show commands", "what can you do"]
    static let helpZh = ["能说什么", "可以说什么", "有什么指令", "语音指令"]
    private static let negationsEn: Set<String> = ["dont", "not", "no", "never", "cant", "cannot", "wont", "shouldnt"]
    private static let negationsZh = "不别没"
    private static let zhFillers = "吧了啊嗯呢的哦噢呀"

    /// WHICH phrase matched, not just which command. The gate that stops the app acting on its own
    /// spoken cues needs the phrase: the old gate was blanket — while CoachVoice spoke (plus a 0.6 s
    /// tail) EVERY recognised command was discarded — and `.ready` is the one cue withheld while the
    /// mic is open (Speech.swift), so the only quiet moment in the whole locate step was the moment
    /// 就是这里 is said. That is the device report verbatim: "voice recognition only works for
    /// 就是这里". Knowing the phrase lets the gate reject only what the app could actually have
    /// produced, so the user can barge in over a 3-5 s cue with 怎么找 / 跳过 / 能说什么.
    struct Match: Equatable { let kind: LocateVoiceCommand; let phrase: String }

    /// The cleanup parse() applies to a transcript — also used to normalize the app's OWN spoken
    /// line, so the echo check compares like with like.
    static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "[.,!?，。！？'’‘ʼ]", with: "", options: .regularExpression)
    }

    /// Every phrase the recognizer can act on, in the CURRENT app language. Handed to
    /// SFSpeechAudioBufferRecognitionRequest.contextualStrings as a lexical prior — without it the
    /// request is plain free-form dictation and a two-syllable command has to win against the whole
    /// language model, which is what "you have to say it very slow in order for it to understand"
    /// feels like. Language-scoped because the recognizer is built for one locale (AppLocale).
    static var allPhrases: [String] {
        AppLocale.isChinese
            ? confirmZh + ["跳过"] + studyZh + resumeZh + helpZh
            : confirmEn + ["skip"] + studyEn + resumeEn + helpEn
    }

    /// Could `spoken` — a line the app itself is saying right now — have produced this phrase? Only
    /// then is a recognition hit the app's own echo rather than the user.
    static func isSelfEcho(phrase: String, spoken: String) -> Bool {
        normalize(spoken).contains(phrase)
    }

    static func parse(_ transcript: String) -> LocateVoiceCommand? { match(transcript)?.kind }

    static func match(_ transcript: String) -> Match? {
        // Strip ASCII AND typographic apostrophes/quotes — iOS speech transcripts render
        // contractions with U+2019 ("that’s"), so the plain "'" alone missed "that's it".
        let cleaned = normalize(transcript)

        // ── English: trailing whole-token match + a 2-token negation window ──────────────────────
        let words = cleaned.split(separator: " ").map(String.init)
        func trailingMatch(_ phrase: String) -> Bool {
            let pw = phrase.split(separator: " ").map(String.init)
            guard words.count >= pw.count, Array(words.suffix(pw.count)) == pw else { return false }
            // The two words before the phrase must not negate it ("wait don't confirm").
            let before = words.dropLast(pw.count).suffix(2)
            return !before.contains(where: negationsEn.contains)
        }
        for k in helpEn where trailingMatch(k) { return Match(kind: .help, phrase: k) }   // before study: see helpEn
        for k in confirmEn where trailingMatch(k) { return Match(kind: .confirm, phrase: k) }
        if trailingMatch("skip") { return Match(kind: .skip, phrase: "skip") }
        for k in studyEn where trailingMatch(k) { return Match(kind: .study, phrase: k) }
        for k in resumeEn where trailingMatch(k) { return Match(kind: .resume, phrase: k) }

        // ── Chinese: no spaces → trailing-substring match after trimming filler, + negation guard ─
        var zh = Substring(cleaned)
        while let last = zh.last, zhFillers.contains(last) { zh = zh.dropLast() }
        func zhSuffix(_ k: String) -> Bool {
            guard zh.hasSuffix(k) else { return false }         // SUFFIX, not contains — kills stale-tail re-fire
            let before = zh.dropLast(k.count).suffix(2)          // 不要确认 / 先别确认 / 不就是这里
            return !before.contains(where: negationsZh.contains)
        }
        for k in helpZh where zhSuffix(k) { return Match(kind: .help, phrase: k) }
        for k in confirmZh where zhSuffix(k) { return Match(kind: .confirm, phrase: k) }
        if zhSuffix("跳过") { return Match(kind: .skip, phrase: "跳过") }
        for k in studyZh where zhSuffix(k) { return Match(kind: .study, phrase: k) }
        for k in resumeZh where zhSuffix(k) { return Match(kind: .resume, phrase: k) }
        return nil
    }
}

// THE WHOLE "does this transcript fire a command" DECISION, PURE — nothing here touches audio, so
// the interaction that broke voice control on device is unit-testable (LocateVoiceGateTests). The
// two defects that lost commands both lived inside one four-line `if` in handle(), where nothing
// could reach them.
enum LocateVoiceGate {
    /// One command per utterance burst — but per KIND, see decide().
    static let repeatDebounceS: TimeInterval = 2.0

    /// - transcript:    the recognizer's cumulative text for the current task
    /// - firedAtLength: consume-once anchor (the transcript must grow past the last fire)
    /// - lastKind:      what fired last, or nil
    /// - appSaying:     the line the app is speaking RIGHT NOW (+ a recognizer-lag tail), else nil
    /// - blanketMute:   ignore everything — for the one caller with no single known line
    static func decide(transcript: String,
                       firedAtLength: Int,
                       lastKind: LocateVoiceCommand?,
                       sinceLastFire: TimeInterval,
                       appSaying: String?,
                       blanketMute: Bool) -> LocateVoiceCommand.Match? {
        // The commands sheet renders every literal phrase ON SCREEN, where VoiceOver may read them
        // into the open mic. There is no single "line" to compare against there, so that caller keeps
        // the old blunt behaviour — it is a modal the user is reading, not a coaching step.
        guard !blanketMute else { return nil }
        // Consume-once: the transcript is cumulative within a task, so require it to have grown.
        guard transcript.count > firedAtLength + 1 else { return nil }
        guard let m = LocateVoiceCommand.match(transcript) else { return nil }
        // ECHO, NOT BLANKET. Reject only a phrase the app's own current line actually contains.
        if let saying = appSaying, LocateVoiceCommand.isSelfEcho(phrase: m.phrase, spoken: saying) {
            return nil
        }
        // KIND-AWARE DEBOUNCE. The old single `lastFired` was global, so a command that does NOTHING
        // in the current state still burned the window for the one that would have worked: 找到了
        // parses as .resume, which is a silent no-op when no frame is frozen (ARCoachView), and it
        // then blocked the 就是这里 said a second later. Repeats of the SAME kind are what needs
        // damping; a different kind is new intent.
        if m.kind == lastKind && sinceLastFire <= repeatDebounceS { return nil }
        return m
    }
}

final class LocateVoiceControl: ObservableObject {
    // A command carries a fresh id so `.onChange(of:)` in the view fires once per recognition —
    // the view OWNS the handler (dies with the view), so there is no engine/camera retain cycle
    // like a control-held `onCommand` closure would create (review-caught leak).
    struct Command: Equatable { let id: UUID; let kind: LocateVoiceCommand }

    @Published private(set) var listening = false
    @Published private(set) var denied = false        // mic or speech permission refused
    @Published private(set) var unavailable = false   // recognizer kept failing → gave up (asset missing, etc.)
    @Published private(set) var command: Command? = nil

    // On-device recognition for the CURRENT app language, or nil (feature hidden).
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapFormat: AVAudioFormat?            // the format the LIVE tap was installed with

    // ONE monotonically-rising token, bumped by stop() and every (re)start. Async permission
    // callbacks and recognition-task callbacks capture the value at their scheduling time and
    // no-op if it has moved on — this closes BOTH the "stop() can't cancel an in-flight start()"
    // zombie-mic race and the "stale cancelled task restarts the live one" churn (review-caught).
    private var generation = 0

    private var lastFired = Date.distantPast   // debounce: one command per utterance burst
    private var firedAtLength = 0              // consume-once: don't re-fire until the transcript grows past here
    private var noProgressRestarts = 0         // recognizer-failure backoff / cap
    private static let maxRestarts = 3

    // Config-change recovery burst tracking. An occasional audio route/format settle (the app's TTS
    // engaging the shared session, a Bluetooth route change) reshapes the graph and must be RECOVERED
    // from, not treated as fatal — the old hard stop() killed the mic on essentially every spoken cue.
    // Only a rapid STORM of changes (a genuinely broken route) is fatal. `ignoreConfigUntil` absorbs
    // the engine's own initial reconfigure right after start.
    private var lastConfigRecover = Date.distantPast
    private var configRecoverBurst = 0
    private var ignoreConfigUntil = Date.distantPast

    // SELF-CONFIRMATION GUARD, NARROWED FROM A BLANKET MUTE.
    //
    // The app's own spoken cues come out the speaker into the open mic, so the recognizer transcribes
    // them and could act on them. The old guard handled that by ignoring ALL recognition while
    // CoachVoice spoke, plus a 0.6 s tail — and during the locate step the coach speaks almost
    // continuously: the zh clips run ~1.8-5.0 s and stepLocate flips between noPress/settling/
    // offGuide inside a second (CoachConst.locateSteadyS 0.6 / locateWindowS 0.8). Since `.ready` is
    // the ONE cue withheld while the mic is open (Speech.updateLocate), the only quiet window in the
    // entire step was the moment 就是这里 is said — which is exactly the device report, "voice
    // recognition only works for 就是这里". Every other command was being recognised and thrown away.
    //
    // Now we keep WHAT the app is saying and reject only a command phrase that line actually
    // contains, so the user can barge in over a cue. `blanketMute` remains for the one caller that
    // has no single known line (the commands sheet, whose phrases VoiceOver may read out loud).
    private var appSaying: String? = nil
    private var appSayingUntil = Date.distantPast
    private var blanketMute = false
    private var lastKind: LocateVoiceCommand? = nil

    private var observers: [NSObjectProtocol] = []

    // Whether to OFFER the mic button. Deliberately NOT gated on supportsOnDeviceRecognition:
    // that flag commonly reads false until Speech has been authorized once and the on-device asset
    // is present, so gating the button on it created a deadlock — the button stayed hidden, so the
    // tap that would REQUEST authorization never happened, so the flag never flipped true and voice
    // control was permanently invisible on a fresh install (and always on Simulator; user-reported
    // "does not work"). A recognizer merely EXISTS for supported locales; on-device support is now
    // resolved after authorization inside start(), which surfaces `unavailable` if it truly can't run.
    var available: Bool { recognizer != nil }

    init() { recognizer = SFSpeechRecognizer(locale: AppLocale.speechLocale) }
    deinit { removeObservers() }

    func toggle() { listening ? stop() : start() }

    /// True while this control owns the shared session with a live input tap. Anything that would
    /// hand the session back to `.ambient` — a category with NO INPUT ROUTE — has to check this, or
    /// the mic stays "listening" over a dead route with nothing to repair it.
    static private(set) var micHoldsSession = false

    /// The session shape the MIC needs, hoisted out of beginListening so it can be re-claimed.
    ///
    /// Mode `.voiceChat` selects the voice-processing I/O path — hardware echo cancellation and the
    /// tuned input chain — which is what a two-syllable spoken command needs while the coach is
    /// talking out of the loudspeaker. The old call set no mode at all, i.e. `.default`: a playback
    /// shape, so several seconds of full-level speech was decoded mixed in with the user's command.
    /// `.allowBluetooth` is deliberately GONE: it offers the system a headset's HANDS-FREE link as
    /// the INPUT, an 8/16 kHz mono SCO channel that the tap then records faithfully.
    /// `.allowBluetoothA2DP` stays, so the user's headphones remain the OUTPUT — the reason the
    /// option was added — while the input stays on the built-in mic.
    static func reclaimSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .voiceChat,
                           options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try? s.setActive(true)
        micHoldsSession = true
    }

    /// Called by the view when the app's TTS starts/stops (bridged from CoachVoice.isSpeaking),
    /// WITH the line being spoken so the echo check can compare like with like. Passing no line
    /// falls back to the old blanket behaviour — correct for the commands sheet, where the phrases
    /// are on screen for VoiceOver to read and there is no single utterance to match against.
    func setAppSpeaking(_ speaking: Bool, saying line: String? = nil) {
        if speaking {
            blanketMute = (line == nil)
            appSaying = line
            appSayingUntil = .distantFuture
        } else {
            blanketMute = false
            // Keep the line for a short tail: the recognizer reports the cue's own words up to ~0.6 s
            // after it stops playing, so dropping the line at didFinish would let the echo through.
            appSayingUntil = Date().addingTimeInterval(0.6)
        }
    }

    func start() {
        guard !listening, recognizer != nil else { return }
        denied = false; unavailable = false
        generation += 1
        let gen = generation
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }   // stop()/re-toggle cancelled us
                guard auth == .authorized else { self.denied = true; return }
                // We do NOT gate on `supportsOnDeviceRecognition` here — it reads false until the
                // on-device asset downloads (which only STARTS after this first authorization) and is an
                // unreliable predictor. armTask prefers on-device when available and falls back to the
                // server otherwise, so we just try. (Simulator has no audio input → beginListening's
                // sample-rate guard reports unavailable immediately.)
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard gen == self.generation else { return }
                        guard granted else { self.denied = true; return }
                        self.beginListening()
                    }
                }
            }
        }
    }

    private func beginListening() {
        guard !listening, recognizer != nil else { return }   // armTask re-binds it where it's used
        Self.reclaimSession()

        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        // No usable input route → there is no mic to listen with (the Simulator, or a device with no
        // input). Report it honestly instead of silently no-op'ing the mic button.
        guard format.sampleRate > 0 else { restoreSession(); unavailable = true; return }
        audioEngine.prepare()
        guard (try? audioEngine.start()) != nil else { restoreSession(); return }

        ignoreConfigUntil = Date().addingTimeInterval(0.5)   // absorb the engine's own start-time settle
        configRecoverBurst = 0
        registerObservers()
        noProgressRestarts = 0
        listening = true
        armTask()
    }

    // Create a fresh request + tap + recognition task. Shared by the initial start and every
    // keep-alive restart (was two verbatim copies). The tap closure captures its OWN request
    // immutably, so the realtime audio thread never reads the main-thread-mutated `self.request`
    // (that unsynchronized access was a crash-class data race; review-caught).
    private func armTask() {
        guard listening, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // THE LEXICAL PRIOR THIS ALWAYS NEEDED. Without it the request is plain free-form dictation:
        // a 2-4 character command has to out-score the whole language model, and over-articulating is
        // the user's only lever — "you have to say it very slow in order for it to understand".
        // contextualStrings biases the decoder toward the exact phrases we can act on, and
        // .confirmation tells it to expect a short command rather than a sentence.
        req.contextualStrings = LocateVoiceCommand.allPhrases
        req.taskHint = .confirmation
        // Prefer ON-DEVICE recognition when the device supports it (audio stays local); otherwise fall
        // back to Apple's speech service so voice-confirm works at all (user-approved privacy trade —
        // on-device wasn't installed for the app's language on the user's iPhone, so requiring it just
        // reported "unavailable"). Only the short confirm phrase is ever spoken while listening.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req
        firedAtLength = 0

        let input = audioEngine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        tapFormat = fmt                              // remembered so a benign config change can be ignored
        input.removeTap(onBus: 0)                    // idempotent; clears any prior task's tap
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
            req.append(buffer)                       // captured request — no self, no shared mutable read
        }

        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.listening, gen == self.generation else { return }
                self.handle(result: result, error: error)
            }
        }
    }

    // All recognition-callback handling, main-thread + generation-guarded by the caller.
    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let text = result?.bestTranscription.formattedString, !text.isEmpty {
            noProgressRestarts = 0                   // real transcription → the pipeline is healthy
            configRecoverBurst = 0                   // …and route recovery is working, not storming
            if let m = LocateVoiceGate.decide(transcript: text,
                                              firedAtLength: firedAtLength,
                                              lastKind: lastKind,
                                              sinceLastFire: Date().timeIntervalSince(lastFired),
                                              appSaying: Date() < appSayingUntil ? appSaying : nil,
                                              blanketMute: blanketMute) {
                lastFired = Date()
                lastKind = m.kind
                firedAtLength = text.count
                command = Command(id: UUID(), kind: m.kind)
            }
        }
        // The recognizer ends tasks on its own (~1 min cap, final results, errors). Keep the
        // session alive by starting a fresh task — but back off and give up after repeated
        // no-progress failures (a missing on-device asset otherwise spins a main-thread loop),
        // and never restart over a dead engine.
        guard result?.isFinal == true || error != nil else { return }
        teardownTask()
        guard audioEngine.isRunning else { failAndStop(); return }
        if result?.isFinal != true { noProgressRestarts += 1 }   // a clean final is progress, not a failure
        guard noProgressRestarts < Self.maxRestarts else { failAndStop(); return }
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.listening, gen == self.generation else { return }
            self.armTask()
        }
    }

    private func failAndStop() {
        stop()
        unavailable = true
    }

    private func teardownTask() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
    }

    func stop() {
        generation += 1                              // cancels any in-flight start()/restart
        guard listening else { return }
        listening = false
        removeObservers()
        teardownTask()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        restoreSession()
    }

    // Hand the audio session back to the gentle playback-only mode the voice cues use — also from
    // the failure bails, so a mic that never started can't leave the session in .playAndRecord
    // (which ignores the silent switch for every later cue; review-caught).
    private func restoreSession() {
        request?.endAudio(); request = nil
        tapFormat = nil
        Self.micHoldsSession = false
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    // A system interruption (call/Siri/alarm) or route/format change stops the engine; without
    // observing them the mic stays "listening" over a dead tap forever (Haptics already models
    // this pattern). Simplest truthful response: stop(), so the UI reflects reality and the user
    // re-taps. (No auto-resume — the mic is opt-in.)
    private func registerObservers() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        let onInterrupt: (Notification) -> Void = { [weak self] note in
            guard let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            DispatchQueue.main.async { self?.stop() }
        }
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: nil, queue: nil, using: onInterrupt))
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                                        object: audioEngine, queue: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.recoverFromConfigChange() }
        })
    }

    // Rebuild the mic tap + recognition task over the (possibly new-format) input after an audio
    // graph reconfigure, instead of tearing the feature down. Bumps `generation` so any trailing
    // callback from the torn-down task no-ops; a rapid burst of changes (broken route) gives up.
    private func recoverFromConfigChange() {
        guard listening else { return }
        let now = Date()
        guard now >= ignoreConfigUntil else { return }   // the engine's own start-time settle
        // A CONFIG CHANGE IS NOT AUTOMATICALLY A REBUILD. Every spoken cue calls setActive(true) on
        // the shared session, which fires this notification without the input format actually
        // changing — and rebuilding is expensive in the one currency that matters here: teardownTask()
        // CANCELS the recognition task, throwing away the cumulative transcript, and armTask() starts
        // a blank one with firedAtLength reset. A command spoken across a cue boundary was therefore
        // destroyed outright, not merely delayed, with nothing to re-evaluate it. If the format is
        // unchanged and the engine is still running, there is nothing to repair.
        if audioEngine.isRunning, let tapFormat,
           audioEngine.inputNode.outputFormat(forBus: 0) == tapFormat { return }
        // Only RAPID-FIRE changes (a genuinely broken route re-settling faster than we can re-arm)
        // count toward giving up; an occasional TTS/route settle >0.3s apart resets the burst and
        // recovers indefinitely. (A slow-but-persistent flap that still yields recognition also
        // resets the burst in handle().)
        configRecoverBurst = now.timeIntervalSince(lastConfigRecover) < 0.3 ? configRecoverBurst + 1 : 0
        lastConfigRecover = now
        guard configRecoverBurst < 4 else { failAndStop(); return }
        generation += 1                                  // stale callbacks from the old task no-op
        teardownTask()
        if !audioEngine.isRunning {
            audioEngine.prepare()
            guard (try? audioEngine.start()) != nil else { failAndStop(); return }
        }
        armTask()                                        // re-installs the tap on the current format
        ignoreConfigUntil = Date().addingTimeInterval(0.5)   // absorb THIS restart's own settle
    }
    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
