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

    /// DRIFT GUARD: once clips are bundled, every spoken line must have one. Skips (rather than fails)
    /// when no clips are bundled at all, so the suite still passes before the first render.
    func testEverySpokenLineHasABundledClip() throws {
        let lines = VoiceScript.allLines()
        let present = lines.filter { VoiceClips.url(for: $0.text, locale: $0.locale) != nil }
        try XCTSkipIf(present.isEmpty, "no voice clips bundled yet — render step not run")

        let missing = lines.filter { VoiceClips.url(for: $0.text, locale: $0.locale) == nil }
        XCTAssertTrue(missing.isEmpty,
                      "\(missing.count) spoken line(s) have no rendered clip (re-run the render script): "
                      + missing.prefix(5).map { "[\($0.locale)] \($0.text)" }.joined(separator: " | "))
    }
}
