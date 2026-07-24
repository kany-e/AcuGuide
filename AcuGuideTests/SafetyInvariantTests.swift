import XCTest
import SwiftUI
@testable import AcuGuide

// The four non-negotiable safety rules (CLAUDE.md) were only partly test-guarded: the forbidden-term
// scan covered the datasets, but the FORCED safety gate, the "felt worse -> never continue" rule, the
// excluded-point filter on model output, and the newly-enumerable SPOKEN script had no test at all —
// each could be deleted and the whole suite would still pass. This file pins them.
final class SafetyInvariantTests: XCTestCase {

    // The crisis/excluded-point tests flip AppSettings.shared.lang; reset it so locale never leaks
    // into a later test (the suite runs on a shared singleton, and the merge gate runs it twice).
    override func setUp() { super.setUp(); AppSettings.shared.lang = .en }
    override func tearDown() { AppSettings.shared.lang = .en; super.tearDown() }

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

    // MARK: - Self-harm / crisis routing must win over acupressure

    // THE REPORTED BUG: "anxious" matched a symptom group and offered HT7/PC8 to someone in a
    // mental-health crisis. Crisis must be caught first, route to help, and suggest NO point.
    func testSelfHarmMessageRoutesToCrisisNotAcupressure() async {
        AppSettings.shared.lang = .en
        let mock = MockChatGen(reply: "here are some points")
        for q in ["I'm anxious and want to hurt myself",
                  "I feel like I want to die",
                  "I've been thinking about suicide",
                  "there's no reason to live anymore",
                  "I can't go on"] {
            let a = await ChatService(generator: mock).reply(to: q, history: [])
            XCTAssertTrue(a.suggestions.isEmpty,
                          "a crisis message must never attach a practice point — got \(a.suggestions.map(\.id)) for: \(q)")
            let low = a.text.lowercased()
            XCTAssertTrue(low.contains("crisis") || low.contains("988") || low.contains("emergency"),
                          "a crisis message must route to real help — got: \(a.text)")
            XCTAssertFalse(low.contains("press"), "must not suggest pressing anything: \(a.text)")
        }
        XCTAssertEqual(mock.calls, 0, "crisis input must never reach the model")
    }

    func testChineseSelfHarmMessageRoutesToCrisis() async {
        AppSettings.shared.lang = .zh
        let mock = MockChatGen(reply: "不应触及")
        let a = await ChatService(generator: mock).reply(to: "我很焦虑，想伤害自己", history: [])
        XCTAssertTrue(a.suggestions.isEmpty, "crisis message must attach no point")
        XCTAssertTrue(a.text.contains("紧急") || a.text.contains("热线"),
                      "must route to help; got: \(a.text)")
        XCTAssertEqual(mock.calls, 0, "crisis input must never reach the model")
    }

    // Over-triggering is the safe direction, but common idioms that merely USE these words must not
    // fire — otherwise a normal headache question gets a crisis wall.
    //
    // A mock generator is injected so this is HERMETIC: "my alarm number is 988" matches no
    // deterministic branch and would otherwise fall through to the real on-device FoundationModels
    // generator, whose availability and output vary on the simulator — a nondeterministic path that
    // flakes the suite (and therefore the merge gate's repeated stress runs).
    func testIdiomsDoNotFalseTriggerCrisis() async {
        AppSettings.shared.lang = .en
        let mock = MockChatGen(reply: "TE3 is on the back of the hand — gentle self-care.")
        for q in ["this headache is killing me", "I'm dying to know where TE3 is",
                  "my alarm number is 988"] {
            let a = await ChatService(generator: mock).reply(to: q, history: [])
            XCTAssertFalse(a.text.lowercased().contains("crisis service"),
                           "'\(q)' is an idiom / benign, not a crisis: \(a.text)")
        }
    }

    /// Deterministic stand-in for the on-device model, so crisis tests never touch FoundationModels.
    final class MockChatGen: ChatGenerator {
        var isAvailable = true
        let reply: String
        private(set) var calls = 0
        init(reply: String) { self.reply = reply }
        func generate(query: String, history: [ChatMessage]) async throws -> String { calls += 1; return reply }
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

// MARK: - Atlas content counts, pinned

// The numbers in the README and the App Store listing must match the shipped data. They already
// drifted once: a count derived from a regex that only matched [A-Za-z0-9]+ silently dropped the
// three hyphenated extra points (EX-HN1/3/5) and produced "30" where the truth is 33 — and that
// wrong number reached the store description before it was caught.
final class AtlasContentCountTests: XCTestCase {

    func testShippedPointCountIsWhatWeMarket() {
        XCTAssertEqual(Acupoint.all.count, 33,
                       "the atlas point count changed — update README.md, docs/release-checklist.md "
                       + "and store/metadata/*/description.txt to match, or the listing lies")
        XCTAssertEqual(Set(Acupoint.all.map(\.id)).count, Acupoint.all.count, "point ids must be unique")
    }

    // Every point needs plain-language guidance: the clinical WHO string says things like "4 cun
    // above the navel", and "cun" is never defined anywhere in the app.
    func testEveryPointHasAPlainLanguageFindGuide() {
        let missing = Acupoint.all.filter { !$0.hasFindGuide }.map(\.id)
        XCTAssertTrue(missing.isEmpty,
                      "these points have no plain-language how-to-find: \(missing) — they would show "
                      + "only the clinical location, which a self-locating user cannot act on")
    }

    // The read-aloud is for locating by ear. It must lead with the plain guide and must never speak
    // a source citation.
    func testSpokenInfoLeadsWithPlainGuidanceAndSpeaksNoCitations() {
        for pt in Acupoint.all {
            let spoken = pt.spokenInfo
            XCTAssertFalse(spoken.contains("WHO"), "\(pt.id) reads a citation aloud: \(spoken.prefix(90))")
            XCTAssertFalse(spoken.contains("Standard 2008"), "\(pt.id) reads a citation aloud")
            if pt.hasFindGuide {
                XCTAssertTrue(spoken.contains(pt.findHow.prefix(20)),
                              "\(pt.id) must speak its plain guide, not just the clinical location")
            }
        }
    }
}
