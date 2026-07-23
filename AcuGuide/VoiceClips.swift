import Foundation
import AVFoundation
import CryptoKit

// PRE-RENDERED VOICE CLIPS.
//
// Every line this app speaks is a FIXED literal string (the coach/locate phrase tables and the atlas
// read-aloud, which comes from the acupoint dataset) — nothing user-generated or LLM-written is ever
// voiced. So instead of running a neural TTS engine on the device (a ~250 MB download plus real
// latency and memory pressure), the whole script is rendered ONCE offline with Kokoro (Apache-2.0,
// permits shipping the generated audio) and shipped as a few MB of AAC. That buys studio-quality
// bilingual speech with zero runtime risk, identical on every device, and no "go download a better
// voice in Settings" trip — which apps cannot trigger or even deep-link to anyway.
//
// A clip is looked up by a hash of (locale + text). If a line has no clip — a cue was reworded and
// not re-rendered, a new point was added — the lookup simply misses and the caller falls back to
// AVSpeechSynthesizer, so the app is never mute. `VoiceScriptTests` fails on that drift so it gets
// noticed at build time rather than in the field.
enum VoiceClips {
    static let directory = "VoiceClips"

    /// Stable filename for a spoken line: first 16 bytes of SHA-256 over "locale|normalized text".
    /// Normalizing (trim + collapse inner whitespace) keeps a stray newline in a source literal from
    /// silently orphaning its clip.
    static func key(_ text: String, locale: String) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data("\(locale)|\(normalized)".utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The bundled clip for a line in the CURRENT app language, or nil (→ caller falls back to AVSpeech).
    static func url(for text: String, locale: String = AppLocale.speechLocaleID) -> URL? {
        Bundle.main.url(forResource: key(text, locale: locale),
                        withExtension: "m4a", subdirectory: directory)
            ?? Bundle.main.url(forResource: key(text, locale: locale), withExtension: "m4a")
    }
}

// Plays one pre-rendered clip, mirroring the AVSpeechSynthesizer contract the callers already rely on:
// `onEnd` fires exactly once whether the clip finishes, is stopped, or fails to start — so the
// isSpeaking/speaking flags (which gate the voice-confirm mic and the read-aloud button) can never latch.
// It deliberately does NOT touch the audio session: the caller owns that (CoachVoice = .ambient so cues
// respect the silent switch, AtlasSpeaker = .playback for an explicit read-aloud), keeping one session owner.
final class ClipPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onEnd: (() -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Starts the clip; returns false if it couldn't play (caller then falls back to AVSpeech).
    @discardableResult
    func play(_ url: URL, onEnd: @escaping () -> Void) -> Bool {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        p.delegate = self
        player = p
        self.onEnd = onEnd
        guard p.play() else { player = nil; self.onEnd = nil; return false }
        return true
    }

    func stop() { finish(stopping: true) }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finish(stopping: false) }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finish(stopping: false) }

    // Clear state BEFORE invoking the callback so a callback that calls stop() again is a no-op.
    private func finish(stopping: Bool) {
        guard let p = player else { return }
        player = nil
        let callback = onEnd
        onEnd = nil
        if stopping { p.stop() }
        callback?()
    }
}

// THE render manifest — every line the app can speak, in both languages, produced by calling the real
// phrase tables rather than by re-listing the strings, so it cannot drift from what actually gets
// spoken. Used by the offline render script (via the dump test) and by the drift guard.
enum VoiceScript {
    struct Line: Hashable { let locale: String; let text: String }

    /// Enumerates every spoken line across both languages. Temporarily flips the app language to read
    /// each side of the bilingual `AppLocale.pick` pairs, then restores it.
    static func allLines() -> [Line] {
        let saved = AppSettings.shared.lang
        defer { AppSettings.shared.lang = saved }

        var seen = Set<Line>()
        var out: [Line] = []
        func add(_ text: String?, _ locale: String) {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let line = Line(locale: locale, text: text)
            if seen.insert(line).inserted { out.append(line) }
        }

        for lang in AppSettings.Lang.allCases {
            AppSettings.shared.lang = lang
            let locale = AppLocale.speechLocaleID

            // Coach + locate cues across every reachable (state, face, person) combination.
            for dorsal in [true, false] {
                for selfCoaching in [true, false] {
                    for phase in CoachPhase.allCases {
                        add(CoachVoice.phrase(for: phase, requiresDorsal: dorsal, selfCoaching: selfCoaching), locale)
                    }
                    for state in LocateState.allCases {
                        add(CoachVoice.locatePhrase(for: state, requiresDorsal: dorsal, selfCoaching: selfCoaching), locale)
                    }
                }
            }
            add(CoachVoice.savedLine, locale)

            // Atlas read-aloud: name + location + how-to-find for every point.
            for pt in Acupoint.all { add(pt.spokenInfo, locale) }
        }
        return out
    }
}
