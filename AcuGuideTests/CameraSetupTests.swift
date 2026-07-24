import XCTest
@testable import AcuGuide

// The first-run camera setup card. The behavior worth pinning isn't the layout — it's that the
// card is shown ONCE and stays recoverable, and that its copy actually names the thing that
// strands a first-timer (both hands are busy, so put the phone down).
final class CameraSetupTests: XCTestCase {
    private var priorSeen = false
    private var priorLang: AppSettings.Lang = .en

    override func setUp() {
        super.setUp()
        // AppSettings is a UserDefaults.standard-backed singleton — snapshot and restore both
        // flags, or this test leaks first-run state into every test that runs after it (the merge
        // gate re-runs the whole suite specifically to catch that).
        priorSeen = AppSettings.shared.seenCameraSetup
        priorLang = AppSettings.shared.lang
        AppSettings.shared.lang = .en
    }

    override func tearDown() {
        AppSettings.shared.seenCameraSetup = priorSeen
        AppSettings.shared.lang = priorLang
        super.tearDown()
    }

    // Shown once: the flag persists through the singleton's own defaults round-trip. A card that
    // reappeared every session would be a toll booth on the app's main flow.
    func testSeenFlagPersists() {
        AppSettings.shared.seenCameraSetup = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "seenCameraSetup"))
        AppSettings.shared.seenCameraSetup = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "seenCameraSetup"),
                      "The dismissal must reach UserDefaults, or the card returns every launch.")
    }

    // Default is false, so a fresh install DOES get the card — the whole point.
    func testFreshInstallSeesCard() {
        let name = "camera-setup-fresh-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        defer { d.removePersistentDomain(forName: name) }
        XCTAssertFalse(d.bool(forKey: "seenCameraSetup"))
    }

    // Recoverable: Settings clears the flag, which is what re-arms the card.
    func testResetRearmsCard() {
        AppSettings.shared.seenCameraSetup = true
        AppSettings.shared.seenCameraSetup = false      // the Settings "show setup tips again" row
        XCTAssertFalse(AppSettings.shared.seenCameraSetup)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "seenCameraSetup"))
    }

    // The card has to actually say the thing. The failure it exists to prevent is a first-timer
    // holding the phone with no free hand to press with, so "both hands" and putting the phone
    // down are the two claims that must survive any future copy edit.
    func testCopyNamesTheBothHandsProblem() {
        for lang in [AppSettings.Lang.en, .zh] {
            AppSettings.shared.lang = lang
            let copy = CameraSetupCard(onContinue: {}).allCopyForTesting.joined(separator: " ")
            XCTAssertFalse(copy.isEmpty, "\(lang): setup card copy is empty")
            if lang == .en {
                XCTAssertTrue(copy.lowercased().contains("both hands"),
                              "en: the card must state that both hands are occupied")
                XCTAssertTrue(copy.lowercased().contains("prop"),
                              "en: the card must tell the user to prop the phone up")
            } else {
                XCTAssertTrue(copy.contains("两只手") || copy.contains("双手"),
                              "zh: the card must state that both hands are occupied")
                XCTAssertTrue(copy.contains("放稳") || copy.contains("靠在"),
                              "zh: the card must tell the user to prop the phone up")
            }
        }
    }

    // Same safety rule as every other user-facing string.
    func testCopyIsSafe() {
        for lang in [AppSettings.Lang.en, .zh] {
            AppSettings.shared.lang = lang
            for line in CameraSetupCard(onContinue: {}).allCopyForTesting {
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
