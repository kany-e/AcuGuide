import XCTest
@testable import AcuGuide

// Phase 0 smoke test — proves the test target builds and links against the app.
// Phase 3 replaces/extends this with the fixture-driven CoachEngine timeline tests.
final class AcuGuideTests: XCTestCase {
    func testTE3IsTheOnlyARCoachedPoint() {
        let arPoints = Acupoint.all.filter { $0.mediapipeTarget != nil }
        XCTAssertEqual(arPoints.map(\.id), ["TE3"],
                       "TE3 must be the only AR-coached point (honest scope).")
    }

    func testLI4IsExcluded() {
        XCTAssertFalse(Acupoint.all.contains { $0.id == "LI4" },
                       "LI4 is pregnancy-contraindicated and must never appear.")
    }

    // The immutable rule: no treat / cure / heal / diagnose anywhere in user-facing copy.
    // Scans the whole bilingual atlas (the dataset most likely to drift on edits).
    func testNoForbiddenMedicalClaims() {
        let banned = ["treat", "cure", "heal", "diagnos"]
        for p in Acupoint.all {
            let blob = [p.locationEn, p.indicationsEn, p.coachAlign, p.coachHold,
                        p.locationZh, p.indicationsZh].joined(separator: " ").lowercased()
            for term in banned {
                XCTAssertFalse(blob.contains(term),
                               "\(p.id) copy contains forbidden term '\(term)'")
            }
        }
    }

    // Offline chat: a red-flag question (even one naming a point) must route to stop-and-seek-care,
    // not to a normal how-to-press reply. (Sim locale is en → English copy.)
    func testChatRedFlagRoutesToSafetyReply() async {
        let reply = await ChatService().reply(to: "I'm pregnant, is SI3 ok to press?", history: [])
        XCTAssertTrue(reply.lowercased().contains("professional"),
                      "red-flag question must route to the stop-and-seek-care reply; got: \(reply)")
    }

    // Offline chat: a Chinese phrase that merely embeds a 2-char point name must NOT be matched
    // as that point (外关 inside 对外关系 / 内关 inside 国内关系).
    func testChatDoesNotFalseMatchChineseProse() async {
        let reply = await ChatService().reply(to: "国内关系", history: [])
        // A point DETAIL reply contains "Location:"; the general greeting (which lists points as
        // examples) does not. The embedded 内关 must fall through to the greeting, not a PC6 detail.
        XCTAssertFalse(reply.contains("Location:"),
                       "embedded Chinese substring must not yield a point detail reply; got: \(reply)")
    }

    // "number" contains "numb" — whole-word matching must NOT trip the red-flag screen.
    func testChatBenignWordIsNotRedFlag() async {
        let reply = await ChatService().reply(to: "What is the number for TE3?", history: [])
        XCTAssertFalse(reply.lowercased().contains("seeing a professional"),
                       "a benign word must not route to the red-flag reply; got: \(reply)")
    }
}
