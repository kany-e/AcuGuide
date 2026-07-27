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

    static func parse(_ transcript: String) -> LocateVoiceCommand? {
        // Strip ASCII AND typographic apostrophes/quotes — iOS speech transcripts render
        // contractions with U+2019 ("that’s"), so the plain "'" alone missed "that's it".
        let cleaned = transcript.lowercased()
            .replacingOccurrences(of: "[.,!?，。！？'’‘ʼ]", with: "", options: .regularExpression)

        // ── English: trailing whole-token match + a 2-token negation window ──────────────────────
        let words = cleaned.split(separator: " ").map(String.init)
        func trailingMatch(_ phrase: String) -> Bool {
            let pw = phrase.split(separator: " ").map(String.init)
            guard words.count >= pw.count, Array(words.suffix(pw.count)) == pw else { return false }
            // The two words before the phrase must not negate it ("wait don't confirm").
            let before = words.dropLast(pw.count).suffix(2)
            return !before.contains(where: negationsEn.contains)
        }
        for k in helpEn where trailingMatch(k) { return .help }   // before study: see helpEn
        for k in confirmEn where trailingMatch(k) { return .confirm }
        if trailingMatch("skip") { return .skip }
        for k in studyEn where trailingMatch(k) { return .study }
        for k in resumeEn where trailingMatch(k) { return .resume }

        // ── Chinese: no spaces → trailing-substring match after trimming filler, + negation guard ─
        var zh = Substring(cleaned)
        while let last = zh.last, zhFillers.contains(last) { zh = zh.dropLast() }
        func zhSuffix(_ k: String) -> Bool {
            guard zh.hasSuffix(k) else { return false }         // SUFFIX, not contains — kills stale-tail re-fire
            let before = zh.dropLast(k.count).suffix(2)          // 不要确认 / 先别确认 / 不就是这里
            return !before.contains(where: negationsZh.contains)
        }
        for k in helpZh where zhSuffix(k) { return .help }
        for k in confirmZh where zhSuffix(k) { return .confirm }
        if zhSuffix("跳过") { return .skip }
        for k in studyZh where zhSuffix(k) { return .study }
        for k in resumeZh where zhSuffix(k) { return .resume }
        return nil
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

    // Self-confirmation guard: the app's own spoken cues + VoiceOver announcements come out the
    // speaker into the open mic. While CoachVoice is speaking (and a short tail after), ignore
    // recognition so the app can't transcribe and act on its own voice (review-caught). The cue
    // copy is also reworded keyword-free — this is the defense-in-depth half.
    private var appSpeaking = false
    private var ignoreHitsUntil = Date.distantPast

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

    // Called by the view when the app's TTS starts/stops (bridged from CoachVoice.isSpeaking).
    func setAppSpeaking(_ speaking: Bool) {
        appSpeaking = speaking
        if !speaking { ignoreHitsUntil = Date().addingTimeInterval(0.6) }   // recognizer lag tail
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
        // .playAndRecord so CoachVoice's spoken cues keep working while the mic is open;
        // defaultToSpeaker keeps them audible, allowBluetoothA2DP keeps output on the user's
        // headphones (without it, enabling the mic yanks audio to the phone speaker).
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)

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
        // Prefer ON-DEVICE recognition when the device supports it (audio stays local); otherwise fall
        // back to Apple's speech service so voice-confirm works at all (user-approved privacy trade —
        // on-device wasn't installed for the app's language on the user's iPhone, so requiring it just
        // reported "unavailable"). Only the short confirm phrase is ever spoken while listening.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req
        firedAtLength = 0

        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)                    // idempotent; clears any prior task's tap
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
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
            // Ignore the app's own voice, and only fire once per fresh utterance (the transcript
            // is cumulative within a task; require it to have grown past the last fire).
            let quiet = !appSpeaking && Date() >= ignoreHitsUntil
            if quiet, text.count > firedAtLength + 1,
               let cmd = LocateVoiceCommand.parse(text),
               Date().timeIntervalSince(lastFired) > 2.0 {
                lastFired = Date()
                firedAtLength = text.count
                command = Command(id: UUID(), kind: cmd)
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
