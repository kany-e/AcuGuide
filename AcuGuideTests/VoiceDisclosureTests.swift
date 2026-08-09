import XCTest
@testable import AcuGuide

// DISCLOSURE vs BEHAVIOR — the mic story, pinned in both directions.
//
// What went wrong: ARCoachView started the mic on EVERY camera session (device-requested) while
// three shipped disclosure surfaces — docs/privacy-policy.md, PrivacyView, and the setup card —
// went on saying voice was "off until you enable the microphone". Worse, the disclosures promised
// "only that short phrase is sent" to Apple, while the tap streams every audio buffer, so on a
// device without on-device recognition the whole ambient stream goes to Apple's speech service.
//
// The contract these tests hold everything to:
//   1. Hands-free voice control DEFAULTS ON (AppSettings.handsFreeVoice) — the device fix stands.
//   2. The auto-start is gated on that preference (plus a manual session opt-in) in exactly one
//      place, LocateVoiceControl.autoStartAllowed.
//   3. Every disclosure surface says "on by default", names the Settings off switch, and carries
//      the server-recognition caveat — and none of them resurrects the old opt-in story.
// Flip the default, remove the gate, or reword a disclosure back to "off until", and something
// here fails and names the surface that drifted.
final class VoiceDisclosureTests: XCTestCase {
    private var priorLang: AppSettings.Lang = .en
    private var priorHandsFree: Any?

    override func setUp() {
        super.setUp()
        priorLang = AppSettings.shared.lang
        // Snapshot the RAW default-store state (the key may legitimately be absent), so tearDown
        // can restore "never touched" rather than forcing a value into every later test.
        priorHandsFree = UserDefaults.standard.object(forKey: AppSettings.handsFreeVoiceKey)
        AppSettings.shared.lang = .en
    }

    override func tearDown() {
        AppSettings.shared.lang = priorLang
        if let prior = priorHandsFree as? Bool {
            AppSettings.shared.handsFreeVoice = prior
        } else {
            AppSettings.shared.handsFreeVoice = true   // the published default
            UserDefaults.standard.removeObject(forKey: AppSettings.handsFreeVoiceKey)
        }
        super.tearDown()
    }

    // ── Behavior ─────────────────────────────────────────────────────────────────────────────────

    // A fresh install resolves to ON. This is the single fact every "on by default" sentence in the
    // copy tests below depends on — if product direction ever flips it, this failure plus those
    // assertions are the checklist of surfaces to reword.
    func testHandsFreeVoiceDefaultsOn() {
        let name = "hands-free-fresh-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertTrue(AppSettings.resolveHandsFreeVoice(from: d),
                      "Absent key must resolve ON — the disclosures say 'on by default'.")
        d.set(false, forKey: AppSettings.handsFreeVoiceKey)
        XCTAssertFalse(AppSettings.resolveHandsFreeVoice(from: d),
                       "A stored opt-out must win over the default.")
    }

    // The opt-out is durable: it reaches UserDefaults, and the singleton round-trips it.
    func testHandsFreeVoicePersists() {
        AppSettings.shared.handsFreeVoice = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettings.handsFreeVoiceKey),
                       "The Settings toggle must reach UserDefaults, or the opt-out lasts one launch.")
        XCTAssertFalse(AppSettings.resolveHandsFreeVoice(from: UserDefaults.standard))
        AppSettings.shared.handsFreeVoice = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettings.handsFreeVoiceKey))
    }

    // The one auto-start decision, exhaustively. `sessionOptIn` is the manual mic-button case: a
    // user whose preference is OFF turned it on for this session, and a pause or phone call must
    // not silently revoke that choice.
    func testAutoStartGate() {
        typealias Gate = LocateVoiceControl
        XCTAssertTrue(Gate.autoStartAllowed(available: true, handsFreeVoice: true, sessionOptIn: false))
        XCTAssertTrue(Gate.autoStartAllowed(available: true, handsFreeVoice: false, sessionOptIn: true),
                      "A manual session opt-in must survive the re-arm sites.")
        XCTAssertFalse(Gate.autoStartAllowed(available: true, handsFreeVoice: false, sessionOptIn: false),
                       "Preference OFF with no manual opt-in must mean NO mic — this is the promise Settings makes.")
        XCTAssertFalse(Gate.autoStartAllowed(available: false, handsFreeVoice: true, sessionOptIn: false),
                       "No recognizer for the locale → nothing to start, whatever the preference says.")
        XCTAssertFalse(Gate.autoStartAllowed(available: false, handsFreeVoice: false, sessionOptIn: true))
    }

    // End to end on the control itself: with the preference off, the shared auto-start entry point
    // must not open the mic. (The affirmative path is not driven here — start() requests real
    // speech/mic authorization, which has no business running headless in CI.)
    func testAutoStartRespectsOptOut() {
        AppSettings.shared.handsFreeVoice = false
        let control = LocateVoiceControl()
        control.autoStartIfEnabled()
        XCTAssertFalse(control.listening,
                       "autoStartIfEnabled must be a no-op when the user opted out in Settings.")
    }

    // ── Disclosures ──────────────────────────────────────────────────────────────────────────────

    // PrivacyView (Settings → Privacy) — the in-app surface where "off until you turn on the mic"
    // lived longest.
    func testPrivacyViewTellsTheAutoOnStory() {
        for lang in [AppSettings.Lang.en, .zh] {
            AppSettings.shared.lang = lang
            let copy = PrivacyView().allCopyForTesting.joined(separator: " ")
            if lang == .en {
                let lower = copy.lowercased()
                XCTAssertTrue(lower.contains("on by default"),
                              "en PrivacyView must state the mic is on by default")
                XCTAssertTrue(lower.contains("apple's speech service"),
                              "en PrivacyView must carry the server-recognition caveat")
                XCTAssertTrue(lower.contains("settings"),
                              "en PrivacyView must name the durable off switch")
                XCTAssertFalse(lower.contains("off until"),
                               "en PrivacyView has resurrected the stale opt-in claim")
            } else {
                XCTAssertTrue(copy.contains("默认开启"), "zh PrivacyView must state the mic is on by default")
                XCTAssertTrue(copy.contains("Apple 的语音服务"), "zh PrivacyView must carry the server-recognition caveat")
                XCTAssertTrue(copy.contains("设置"), "zh PrivacyView must name the durable off switch")
                XCTAssertFalse(copy.contains("默认关闭"), "zh PrivacyView has resurrected the stale opt-in claim")
            }
        }
    }

    // The setup card — shown BEFORE the first camera session, i.e. before the first permission
    // prompt, which is what makes its disclosure meaningful.
    func testSetupCardTellsTheAutoOnStory() {
        for lang in [AppSettings.Lang.en, .zh] {
            AppSettings.shared.lang = lang
            let copy = CameraSetupCard(onContinue: {}).allCopyForTesting.joined(separator: " ")
            if lang == .en {
                let lower = copy.lowercased()
                XCTAssertTrue(lower.contains("on by default"),
                              "en setup card must state the mic comes on by default")
                XCTAssertTrue(lower.contains("apple's speech service"),
                              "en setup card must carry the server-recognition caveat")
                XCTAssertFalse(lower.contains("skipping is completely fine"),
                               "en setup card still carries the pre-auto-start opt-in copy")
                XCTAssertFalse(lower.contains("switch it on later"),
                               "en setup card still carries the pre-auto-start opt-in copy")
            } else {
                XCTAssertTrue(copy.contains("默认开启"), "zh setup card must state the mic comes on by default")
                XCTAssertTrue(copy.contains("Apple 的语音服务"), "zh setup card must carry the server-recognition caveat")
                XCTAssertFalse(copy.contains("不开也完全没问题"),
                               "zh setup card still carries the pre-auto-start opt-in copy")
            }
        }
    }

    // docs/privacy-policy.md — the store-facing document, bundled read-only into this test target
    // (project.yml) precisely so it cannot drift from the app again without failing here.
    func testPrivacyPolicyDocTellsTheAutoOnStory() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "privacy-policy",
                                                           withExtension: "md"),
                                "privacy-policy.md is not bundled — check the test-target resources in project.yml")
        let doc = try String(contentsOf: url, encoding: .utf8)
        let lower = doc.lowercased()
        // English half.
        XCTAssertTrue(lower.contains("on by default"), "policy (en) must state voice control is on by default")
        XCTAssertTrue(lower.contains("everything the microphone hears"),
                      "policy (en) must say the server path streams everything heard, not one phrase")
        XCTAssertTrue(lower.contains("apple's speech service"))
        XCTAssertFalse(lower.contains("off until you enable"),
                       "policy (en) has resurrected the stale opt-in claim")
        XCTAssertFalse(lower.contains("that short spoken phrase is sent"),
                       "policy (en) has resurrected the only-one-phrase claim")
        // Chinese half.
        XCTAssertTrue(doc.contains("默认开启"), "policy (zh) must state voice control is on by default")
        XCTAssertTrue(doc.contains("全部内容"), "policy (zh) must say the server path streams everything heard")
        XCTAssertFalse(doc.contains("默认关闭"), "policy (zh) has resurrected the stale opt-in claim")
    }

    // The reworded surfaces obey the same safety rule as every other user-facing string.
    func testNewCopyIsSafe() {
        for lang in [AppSettings.Lang.en, .zh] {
            AppSettings.shared.lang = lang
            let lines = PrivacyView().allCopyForTesting + CameraSetupCard(onContinue: {}).allCopyForTesting
            for line in lines {
                for banned in ["treat", "cure", "heal", "diagnose"] {
                    XCTAssertFalse(line.lowercased().contains(banned), "\(lang): banned word in: \(line)")
                }
                for banned in ["治疗", "治愈", "根治", "诊断"] {
                    XCTAssertFalse(line.contains(banned), "\(lang): banned word in: \(line)")
                }
            }
        }
    }
}
