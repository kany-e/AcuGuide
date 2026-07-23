import XCTest
@testable import AcuGuide

// The pre-rendered voice clips (see VoiceClips.swift) are generated from VoiceScript.allLines(), which
// calls the REAL phrase tables. These tests keep that pipeline honest: one dumps the manifest for the
// offline render script, the other fails when a spoken line has drifted away from its rendered clip.
final class VoiceScriptTests: XCTestCase {

    /// Prints the render manifest as JSON between markers so the offline script can lift it out of the
    /// test log. Not an assertion — it's the build step's data source.
    func testDumpVoiceScriptManifest() throws {
        let lines = VoiceScript.allLines()
        XCTAssertFalse(lines.isEmpty, "the app must have spoken lines to render")

        let payload = lines.map {
            ["key": VoiceClips.key($0.text, locale: $0.locale), "locale": $0.locale, "text": $0.text]
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        print("<<<VOICE_SCRIPT_BEGIN>>>")
        print(String(data: data, encoding: .utf8) ?? "[]")
        print("<<<VOICE_SCRIPT_END>>>")
    }

    /// Both languages must be covered, and the script must be DETERMINISTIC — pre-rendering is only
    /// valid if the same call always yields the same strings (nothing time-, state- or count-dependent
    /// leaks into a spoken line).
    func testScriptIsFixedTextInBothLanguages() {
        let lines = VoiceScript.allLines()
        let locales = Set(lines.map(\.locale))
        XCTAssertEqual(locales, ["en-US", "zh-CN"], "script must cover both spoken locales")
        XCTAssertEqual(VoiceScript.allLines(), lines, "spoken script must be deterministic to pre-render")
        for line in lines {
            XCTAssertFalse(line.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        // Keys must be unique per (locale, text) and stable.
        let keys = lines.map { VoiceClips.key($0.text, locale: $0.locale) }
        XCTAssertEqual(Set(keys).count, keys.count, "clip keys must not collide")
        XCTAssertEqual(VoiceClips.key(" Hello   world ", locale: "en-US"),
                       VoiceClips.key("Hello world", locale: "en-US"),
                       "whitespace normalization must be stable")
    }

    /// DRIFT GUARD (missing direction): every spoken line must have a rendered clip.
    ///
    /// This deliberately does NOT skip when nothing is bundled. It used to `XCTSkipIf(present.isEmpty)`,
    /// which meant the one failure it most needed to catch — the clips silently dropping out of the app
    /// target — turned into a green skip. The clips are shipped now, so absence is a failure.
    func testEverySpokenLineHasABundledClip() {
        let lines = VoiceScript.allLines()
        let missing = lines.filter { VoiceClips.url(for: $0.text, locale: $0.locale) == nil }
        XCTAssertTrue(missing.isEmpty,
                      "\(missing.count) spoken line(s) have no rendered clip (re-run tools/voice/render_voice.py): "
                      + missing.prefix(5).map { "[\($0.locale)] \($0.text)" }.joined(separator: " | "))
    }

    /// DRIFT GUARD (orphan direction): every clip shipped in the app must still be claimed by a spoken
    /// line. Re-rendering copies files in but never prunes, so a reworded line leaves its old clip
    /// behind as dead weight that nothing can ever play — invisible to the missing-direction check.
    ///
    /// Reads the shipped bundle rather than the repo-side manifest so it verifies what actually ships.
    func testNoOrphanedClipsAreShipped() throws {
        let bundled = Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: VoiceClips.directory) ?? []
        XCTAssertFalse(bundled.isEmpty,
                       "no clips found in \(VoiceClips.directory)/ — the folder reference in project.yml is gone, "
                       + "so every line would silently fall back to AVSpeech")

        let shipped = Set(bundled.map { $0.deletingPathExtension().lastPathComponent })
        let expected = Set(VoiceScript.allLines().map { VoiceClips.key($0.text, locale: $0.locale) })
        let orphans = shipped.subtracting(expected)
        XCTAssertTrue(orphans.isEmpty,
                      "\(orphans.count) orphaned clip(s) ship but are unreachable — delete them: "
                      + orphans.sorted().prefix(5).joined(separator: ", "))
        XCTAssertEqual(shipped, expected, "shipped clip set must match the spoken script exactly")
    }
}
