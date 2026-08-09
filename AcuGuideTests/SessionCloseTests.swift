import XCTest
@testable import AcuGuide

// The nav-bar Close used to set `launch = nil` unconditionally — the one session exit that neither
// confirmed banked progress (the in-card End button does) nor passed through the recap, which is
// the only place savePractice runs. SessionCloseAction is the shared decision both session views
// now route Close through; these tests pin it to the two threshold rules it must agree with.
final class SessionCloseTests: XCTestCase {

    // ── The thresholds themselves (SessionProgress) ──────────────────────────────────────────
    // One place for both lines, shared by the End buttons, savePractice, and Close. The values are
    // behavior users already know: 5 s / any round earns a confirm; 1 s earns a history record.

    func testBankedLineMatchesTheEndButtonsRule() {
        XCTAssertTrue(SessionProgress.banked(roundsDone: 1, heldS: 0), "any completed round is banked")
        XCTAssertTrue(SessionProgress.banked(roundsDone: 0, heldS: 5))
        XCTAssertFalse(SessionProgress.banked(roundsDone: 0, heldS: 4.99),
                       "just under the line ends without a confirm, as End always has")
    }

    func testRecordableLineMatchesSavePracticesRule() {
        XCTAssertTrue(SessionProgress.recordable(roundsDone: 1, heldS: 0))
        XCTAssertTrue(SessionProgress.recordable(roundsDone: 0, heldS: 1.0))
        XCTAssertFalse(SessionProgress.recordable(roundsDone: 0, heldS: 0.99),
                       "opening a session and immediately quitting must not create a history entry")
    }

    // Banked implies recordable — if the confirm line ever slipped BELOW the record line, Close
    // could confirm-guard progress that the recap would then silently refuse to save.
    func testEverythingBankedIsAlsoRecordable() {
        for rounds in 0...2 {
            for held in stride(from: 0.0, through: 8.0, by: 0.5) where
                SessionProgress.banked(roundsDone: rounds, heldS: held) {
                XCTAssertTrue(SessionProgress.recordable(roundsDone: rounds, heldS: held),
                              "\(rounds) rounds / \(held)s: confirm-guarded but not recordable")
            }
        }
    }

    // ── The Close decision ───────────────────────────────────────────────────────────────────

    // Banked progress gets the SAME confirm dialog the in-card End button shows — Close must never
    // be the quiet way around it.
    func testCloseWithBankedProgressConfirmsFirst() {
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: false, roundsDone: 2, heldS: 40),
                       .confirmFirst)
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: false, roundsDone: 0, heldS: 5),
                       .confirmFirst)
    }

    // Recordable-but-small progress goes straight to the recap: too little to argue about, but the
    // recap is where savePractice runs, and Close must not skip the write.
    func testCloseWithRecordableProgressEndsToTheRecap() {
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: false, roundsDone: 0, heldS: 3),
                       .recap)
    }

    // Nothing banked → Close just closes. An accidentally opened session must not cost a recap
    // screen on the way out.
    func testCloseWithNothingBankedDismisses() {
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: false, roundsDone: 0, heldS: 0),
                       .dismiss)
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: false, roundsDone: 0, heldS: 0.9),
                       .dismiss)
    }

    // On the reading screens — the gates before the camera and the recap after — Close is the way
    // OUT, whatever the counters say: the recap has already recorded, and a gate has nothing to
    // protect. Without this, the recap's own Close would re-open the End confirm forever.
    func testCloseOnReadingScreensAlwaysDismisses() {
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: true, roundsDone: 4, heldS: 120),
                       .dismiss)
        XCTAssertEqual(SessionCloseAction.forSession(readingScreen: true, roundsDone: 0, heldS: 0),
                       .dismiss)
    }
}
