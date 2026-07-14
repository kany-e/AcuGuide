import Foundation
import Speech
import AVFoundation

// Hands-free confirm for the guided locate step: BOTH of the user's hands are occupied (one being
// pressed, one pressing), so the "This is my spot" button is physically awkward even with the
// confirm latch — a short spoken command does it instead (user-requested). Strictly ON-DEVICE
// recognition: if the device can't recognize locally, the feature reports unavailable rather than
// ever sending audio off the device (the app's privacy stance). Listening is opt-in per session
// (the mic button on the LocateCard), runs only while the locate step is active, and stops on
// confirm/skip/pause/disappear.
enum LocateVoiceCommand {
    case confirm   // "this is my spot" — same path as tapping the button
    case skip      // "skip" — same as tapping Skip

    // Pure keyword matcher over a live transcription (unit-tested). Matches the TAIL of the
    // transcript so earlier ambient speech can't retrigger, and requires the distinctive phrases —
    // deliberately NOT bare "yes"/"好" (too easy to trip in ambient conversation).
    static func parse(_ transcript: String) -> LocateVoiceCommand? {
        let t = transcript.lowercased()
            .replacingOccurrences(of: "[.,!?，。！？']", with: "", options: .regularExpression)
        // Only the last few words matter — a command spoken now, not history.
        let tail = t.split(separator: " ").suffix(6).joined(separator: " ")
        let confirmEn = ["this is my spot", "this is it", "thats it", "that is it", "confirm"]
        let skipEn = ["skip"]
        for k in confirmEn where tail.hasSuffix(k) || t.hasSuffix(k) { return .confirm }
        for k in skipEn where tail.hasSuffix(k) { return .skip }
        // Chinese transcripts have no spaces — match the tail of the raw string.
        let zhTail = String(t.suffix(8))
        for k in ["就是这里", "就在这里", "确认"] where zhTail.contains(k) { return .confirm }
        if zhTail.contains("跳过") { return .skip }
        return nil
    }
}

final class LocateVoiceControl: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var denied = false      // mic or speech permission refused
    // On-device recognition for the CURRENT app language, or nil (feature hidden).
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastFired = Date.distantPast        // debounce: one command per utterance burst
    var onCommand: ((LocateVoiceCommand) -> Void)?

    var available: Bool { recognizer?.supportsOnDeviceRecognition == true }

    init() {
        let locale = Locale(identifier: AppLocale.isChinese ? "zh-CN" : "en-US")
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func toggle() { listening ? stop() : start() }

    func start() {
        guard !listening, let recognizer, recognizer.supportsOnDeviceRecognition else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard auth == .authorized else { self?.denied = true; return }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self?.denied = true; return }
                        self?.beginListening()
                    }
                }
            }
        }
    }

    private func beginListening() {
        guard !listening, let recognizer else { return }
        // .playAndRecord so CoachVoice's spoken cues keep working while the mic is open;
        // defaultToSpeaker keeps them audible (playAndRecord routes to the earpiece otherwise).
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true      // audio must never leave the device
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }   // no usable input route (Simulator quirk)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        guard (try? audioEngine.start()) != nil else {
            input.removeTap(onBus: 0)
            return
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString,
               let cmd = LocateVoiceCommand.parse(text),
               Date().timeIntervalSince(self.lastFired) > 2.0 {
                self.lastFired = Date()
                DispatchQueue.main.async { self.onCommand?(cmd) }
            }
            // The recognizer ends tasks on its own (~1 min cap, final results, errors) — keep the
            // session alive by starting a fresh task while the user is still in the locate step.
            if result?.isFinal == true || error != nil {
                DispatchQueue.main.async {
                    guard self.listening else { return }
                    self.teardownTask()
                    self.beginListeningTaskOnly()
                }
            }
        }
        listening = true
    }

    // Restart just the recognition request/task over the already-running audio tap.
    private func beginListeningTaskOnly() {
        guard listening, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString,
               let cmd = LocateVoiceCommand.parse(text),
               Date().timeIntervalSince(self.lastFired) > 2.0 {
                self.lastFired = Date()
                DispatchQueue.main.async { self.onCommand?(cmd) }
            }
            if result?.isFinal == true || error != nil {
                DispatchQueue.main.async {
                    guard self.listening else { return }
                    self.teardownTask()
                    self.beginListeningTaskOnly()
                }
            }
        }
    }

    private func teardownTask() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
    }

    func stop() {
        guard listening else { return }
        listening = false
        teardownTask()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        // Hand the audio session back to the gentle playback-only mode the voice cues use.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
}
