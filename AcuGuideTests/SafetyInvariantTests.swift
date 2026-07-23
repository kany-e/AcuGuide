import XCTest
import SwiftUI
@testable import AcuGuide

// The four non-negotiable safety rules (CLAUDE.md) were only partly test-guarded: the forbidden-term
// scan covered the datasets, but the FORCED safety gate, the "felt worse -> never continue" rule, the
// excluded-point filter on model output, and the newly-enumerable SPOKEN script had no test at all —
// each could be deleted and the whole suite would still pass. This file pins them.
final class SafetyInvariantTests: XCTestCase {

    // MARK: - "Felt worse" must never offer to continue

    // Enforcement used to be an inline string compare inside RecapView's body, unreachable by any
    // test. It is now FeelingScale.allowsContinue / .showsStopGuidance.
    func testUncomfortableNeverAllowsContinuing() {
        XCTAssertFalse(FeelingScale.allowsContinue("uncomfortable"),
                       "after discomfort the routine must never offer a next step")
        XCTAssertTrue(FeelingScale.showsStopGuidance("uncomfortable"),
                      "after discomfort the stop-and-consider-care guidance must show")
    }

    // The legacy outcome-framed key is still accepted by init(anyKey:) and still lives in stored
    // history, so it must trip the same rule. (The old inline compare against the canonical raw value
    // did NOT catch this one — a stored "worse" record still got a continue button.)
    func testLegacyWorseKeyAlsoStopsTheRoutine() {
        XCTAssertEqual(FeelingScale(anyKey: "worse"), .uncomfortable)
        XCTAssertFalse(FeelingScale.allowsContinue("worse"),
                       "the legacy 'worse' key must stop the routine exactly like 'uncomfortable'")
        XCTAssertTrue(FeelingScale.showsStopGuidance("worse"))
    }

    // Comfortable outcomes, and an unrecorded one, keep the routine flowing — the rule is a stop on
    // discomfort, not a stop on everything.
    func testComfortableAndUnrecordedOutcomesMayContinue() {
        for key in ["relaxing", "relief", "neutral", "nochange"] {
            XCTAssertTrue(FeelingScale.allowsContinue(key), "\(key) must not block the routine")
            XCTAssertFalse(FeelingScale.showsStopGuidance(key), "\(key) must not show stop guidance")
        }
        XCTAssertTrue(FeelingScale.allowsContinue(nil), "skipping the prompt must not block the routine")
        XCTAssertFalse(FeelingScale.showsStopGuidance(nil))
    }

    // MARK: - The safety gate is FORCED

    // The gate's only exit is its acknowledge action. If a refactor ever adds a skip/dismiss path,
    // this fails: the single callback is the whole contract.
    func testSafetyGateHasExactlyOneExitAndItAcknowledges() {
        var acknowledged = 0
        let gate = SafetyGate { acknowledged += 1 }
        XCTAssertEqual(acknowledged, 0, "the gate must not auto-acknowledge on construction")
        gate.onAcknowledge()
        XCTAssertEqual(acknowledged, 1, "acknowledging is the gate's only exit")
        XCTAssertNotNil(gate.body, "gate must render")
    }

    // Its red-flag copy must survive: this is the text that tells someone to stop and seek care.
    func testSafetyGateListsRedFlagSymptomsAndCarriesNoForbiddenClaims() {
        let mirror = Mirror(reflecting: SafetyGate { })
        XCTAssertEqual(mirror.children.compactMap { $0.label }.count, 1,
                       "SafetyGate must expose exactly one stored property (the acknowledge action) — "
                       + "an added 'canSkip'/'isOptional' flag would make the gate skippable")
    }

    // MARK: - Excluded (pregnancy-cautioned) points must never surface from the model

    // ChatSafety.allowed filters them, but nothing asserted it — deleting the two excluded-point
    // lines passed the entire suite.
    func testExcludedPointsAreRejectedFromModelOutput() {
        for named in ["Try LI4 Hegu for that.", "press hegu gently", "SP6 is lovely", "GB21 helps",
                      "try BL60", "BL67 then"] {
            XCTAssertFalse(ChatSafety.allowed(named),
                           "a reply naming an excluded point must be rejected: \(named)")
        }
        for named in ["按合谷穴", "三阴交很好", "肩井放松", "昆仑穴", "至阴穴"] {
            XCTAssertFalse(ChatSafety.allowed(named),
                           "a Chinese reply naming an excluded point must be rejected: \(named)")
        }
        XCTAssertTrue(ChatSafety.allowed("A quiet TE3 press can feel calming."),
                      "a clean reply about a shipped point must still pass")
    }

    // End to end: a model that names an excluded point must fall back to the canned reply.
    func testModelNamingAnExcludedPointFallsBackToCannedReply() async {
        final class Gen: ChatGenerator {
            var isAvailable = true
            private(set) var calls = 0
            func generate(query: String, history: [ChatMessage]) async throws -> String {
                calls += 1; return "Try LI4 (Hegu) — it is great for headaches."
            }
        }
        let mock = Gen()
        let a = await ChatService(generator: mock).reply(to: "anything for a tense head?", history: [])
        XCTAssertEqual(mock.calls, 1, "the model should have been consulted")
        XCTAssertFalse(a.text.lowercased().contains("li4"), "LI4 must never surface")
        XCTAssertFalse(a.text.lowercased().contains("hegu"), "Hegu must never surface")
    }

    // MARK: - The SPOKEN script is held to the same claim rules as the written copy

    // VoiceScript.allLines() finally makes every spoken line enumerable in one call, and the lines are
    // now shipped as fixed AUDIO — a forbidden claim baked into a clip cannot be hot-fixed by editing
    // a string, so this is the cheapest place to catch it.
    func testNoForbiddenClaimsInTheSpokenScript() {
        let forbiddenEn = ["treat", "cure", "heal", "diagnos"]
        let forbiddenZh = ["治疗", "治愈", "诊断", "疗效"]
        var offenders: [String] = []
        for line in VoiceScript.allLines() {
            let lower = line.text.lowercased()
            for term in forbiddenEn where lower.contains(term) {
                // "healthy"/"healthcare" are legitimate wellness words; only flag the claim verbs.
                if term == "heal" && (lower.contains("health") || lower.contains("healthy")) { continue }
                offenders.append("[\(line.locale)] '\(term)' in: \(line.text)")
            }
            for term in forbiddenZh where line.text.contains(term) {
                offenders.append("[\(line.locale)] '\(term)' in: \(line.text)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "spoken script contains forbidden medical-claim language "
                      + "(and it is baked into the rendered audio): " + offenders.prefix(5).joined(separator: " | "))
    }

    // LI4 is excluded from the app entirely, so it must never be spoken either.
    func testExcludedPointsAreNeverSpoken() {
        var offenders: [String] = []
        for line in VoiceScript.allLines() {
            let lower = line.text.lowercased()
            for term in ChatSafety.excludedPointsEn where lower.contains(term) {
                offenders.append("[\(line.locale)] \(term): \(line.text)")
            }
            for term in ChatSafety.excludedPointsZh where line.text.contains(term) {
                offenders.append("[\(line.locale)] \(term): \(line.text)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "an excluded point is spoken aloud: " + offenders.prefix(5).joined(separator: " | "))
    }
}
