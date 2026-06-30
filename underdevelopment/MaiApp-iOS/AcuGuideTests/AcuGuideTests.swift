import XCTest
@testable import AcuGuide

// Phase 0 smoke test — proves the test target builds and links against the app.
// Phase 3 replaces/extends this with the fixture-driven CoachEngine timeline tests.
final class AcuGuideTests: XCTestCase {
    // The AR-coached set = the 8 documented hand/wrist points (TE3 + the others, sourced to WHO 2008).
    // Every coachable point must have anchor weights summing > 0 (weightedTarget divides by the sum),
    // and LI4 must never be coachable.
    func testARCoachedPointsAreTheDocumentedHandSet() {
        let ar = Set(Acupoint.all.filter { $0.mediapipeTarget != nil }.map(\.id))
        XCTAssertEqual(ar, ["TE3", "SI3", "PC8", "HT7", "PC6", "SJ5", "TE4", "PC7"],
                       "AR-coached points are the 8 documented hand/wrist points.")
        XCTAssertFalse(ar.contains("LI4"), "LI4 must never be coachable.")
        for p in Acupoint.all where p.mediapipeTarget != nil {
            let total = p.mediapipeTarget!.anchors.reduce(0) { $0 + $1.weight }
            XCTAssertGreaterThan(total, 0, "\(p.id) anchor weights must sum > 0.")
        }
    }

    // A symptom query surfaces practiceable (AR-coachable) suggestions the chat UI turns into
    // "Practice with camera" buttons; a red-flag query must NOT offer any.
    func testChatSuggestsPracticePointForSymptom() async {
        let a = await ChatService().reply(to: "I have a tension headache", history: [])
        XCTAssertTrue(a.suggestions.contains { $0.id == "TE3" },
                      "a headache query should suggest TE3; got: \(a.suggestions.map(\.id))")
        XCTAssertTrue(a.suggestions.allSatisfy { $0.mediapipeTarget != nil },
                      "all suggestions must be AR-coachable.")
        let danger = await ChatService().reply(to: "I have a sudden severe headache", history: [])
        XCTAssertTrue(danger.suggestions.isEmpty, "a red-flag query must not offer practice buttons.")
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
        let reply = await ChatService().reply(to: "I'm pregnant, is SI3 ok to press?", history: []).text
        XCTAssertTrue(reply.lowercased().contains("professional"),
                      "red-flag question must route to the stop-and-seek-care reply; got: \(reply)")
    }

    // Offline chat: a Chinese phrase that merely embeds a 2-char point name must NOT be matched
    // as that point (外关 inside 对外关系 / 内关 inside 国内关系).
    func testChatDoesNotFalseMatchChineseProse() async {
        let reply = await ChatService().reply(to: "国内关系", history: []).text
        // A point DETAIL reply contains "Location:"; the general greeting (which lists points as
        // examples) does not. The embedded 内关 must fall through to the greeting, not a PC6 detail.
        XCTAssertFalse(reply.contains("Location:"),
                       "embedded Chinese substring must not yield a point detail reply; got: \(reply)")
    }

    // Meridian matching must not misfire on ordinary Chinese prose: "我胃经常痛" (my stomach often
    // aches) embeds 胃经 inside 胃经常, and must NOT be read as the Stomach meridian — while a real
    // channel name ("肺经") still resolves. (Sim locale en → English copy; meridianReply says
    // "<Name> Meridian (…)", the greeting says "fourteen meridians".)
    func testChatMeridianMatchAvoidsChineseProse() async {
        let prose = await ChatService().reply(to: "我胃经常痛", history: []).text
        XCTAssertFalse(prose.contains("Stomach Meridian"),
                       "prose embedding <organ>经 must not yield a meridian card; got: \(prose)")
        let real = await ChatService().reply(to: "肺经", history: []).text
        XCTAssertTrue(real.contains("Lung Meridian"),
                      "a real channel name should resolve to its meridian; got: \(real)")
    }

    // "number" contains "numb" — whole-word matching must NOT trip the red-flag screen.
    func testChatBenignWordIsNotRedFlag() async {
        let reply = await ChatService().reply(to: "What is the number for TE3?", history: []).text
        XCTAssertFalse(reply.lowercased().contains("seeing a professional"),
                       "a benign word must not route to the red-flag reply; got: \(reply)")
    }
}
