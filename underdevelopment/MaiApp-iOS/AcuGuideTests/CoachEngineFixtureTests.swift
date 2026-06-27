import XCTest
@testable import AcuGuide

// Fixture-driven validation of the ported state machine — the Swift mirror of
// demo-app/cv/engine.test.js. Each replay fixture's FrameState stream is fed into
// CoachStateMachine and the observed phase timeline is checked against the fixture's
// ground-truth `expected_phase_sequence` (ordered-subsequence, transient states allowed).
// This locks the validated engine.js behavior against regressions in the Swift port.
//
// Scope note: pressCount / rhythm / motion are intentionally NOT asserted — the native
// app drops cadence/BPM by design (position + steady-hold only). Only the phase machine
// and reaching COMPLETE are ported.
final class CoachEngineFixtureTests: XCTestCase {

    // Fixtures are 8-12s clips; production hold target is 30s. Use a short completion
    // target so the end-to-end fixture reaches COMPLETE within the clip (== engine.test.js).
    private let testHoldTargetS = 2.0

    // MARK: Fixture decoding (only the fields the temporal layer consumes)

    private struct Doc: Decodable { let meta: Meta; let frames: [Frame]
        enum CodingKeys: String, CodingKey { case meta = "_meta"; case frames } }
    private struct Meta: Decodable { let groundTruth: GroundTruth }
    private struct GroundTruth: Decodable { let expected_phase_sequence: [String] }
    private struct Frame: Decodable {
        let t: Double
        let receivingHand: Hand
        let target: Target
        let contact: Contact
        let quality: Quality
    }
    private struct Hand: Decodable { let present: Bool; let face: String? }
    private struct Target: Decodable { let surface: String?; let trackable: String? }
    private struct Contact: Decodable {
        let insideEnterRadius: Bool?; let insideExitRadius: Bool?; let offset_xHandSize: Double?
    }
    private struct Quality: Decodable { let confidence: Double?; let wristInFrame: Bool? }

    private func loadDoc(_ name: String) throws -> Doc {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"),
                               "fixture \(name).json not bundled")
        return try JSONDecoder().decode(Doc.self, from: Data(contentsOf: url))
    }

    // Build the per-frame temporal input — mirrors engine.js isUsable + faceIsCorrect + contact.
    private func input(_ f: Frame) -> CoachFrameInput {
        let conf = f.quality.confidence ?? 0
        let offModel = f.target.trackable == "off_model_extrapolated"
        var present = f.receivingHand.present && conf >= 0.5
        if offModel && f.quality.wristInFrame == false { present = false }

        let faceCorrect: Bool
        if let surface = f.target.surface, !surface.isEmpty {
            faceCorrect = (f.receivingHand.face == surface)
        } else {
            faceCorrect = true   // no requirement encoded -> don't gate
        }

        return CoachFrameInput(
            t: f.t, present: present, faceCorrect: faceCorrect,
            insideEnterRadius: f.contact.insideEnterRadius ?? false,
            insideExitRadius: f.contact.insideExitRadius ?? false,
            offsetXHandSize: f.contact.offset_xHandSize)
    }

    private func token(_ p: CoachPhase) -> String {
        switch p {
        case .noHand:           return "NO_HAND"
        case .wrongFace:        return "WRONG_FACE"
        case .searching:        return "SEARCHING"
        case .onTargetUnstable: return "ON_TARGET_UNSTABLE"
        case .holding:          return "HOLDING"
        case .paused:           return "PAUSED"
        case .complete:         return "COMPLETE"
        }
    }

    private func run(_ doc: Doc) -> (phases: [String], finalPhase: String) {
        let sm = CoachStateMachine(holdTargetS: testHoldTargetS)
        var observed: [String] = []
        for f in doc.frames { observed.append(token(sm.step(input(f)))) }
        return (collapse(observed), observed.last ?? "")
    }

    // MARK: ground-truth matching (ported verbatim from engine.test.js)

    private func collapse(_ list: [String]) -> [String] {
        var out: [String] = []
        for p in list where out.last != p { out.append(p) }
        return out
    }
    private func normalizeLabel(_ label: String) -> String {
        if label.hasPrefix("HOLDING") { return "HOLDING" }
        if label.contains("NO_HAND") { return "NO_HAND" }
        return label
    }
    private func acceptedPhases(_ label: String) -> [String] {
        switch label {
        case "WRONG_POSITION": return ["SEARCHING"]   // finger present, off target
        default:               return [label]
        }
    }
    private func containsPhasesInOrder(_ observed: [String], _ expectedLabels: [String]) -> Bool {
        let expected = collapse(expectedLabels.map(normalizeLabel))
        var i = 0
        for label in expected {
            let ok = acceptedPhases(label)
            while i < observed.count && !ok.contains(observed[i]) { i += 1 }
            if i >= observed.count { return false }
            i += 1
        }
        return true
    }

    private func assertFixture(_ name: String) throws {
        let doc = try loadDoc(name)
        let res = run(doc)
        XCTAssertTrue(
            containsPhasesInOrder(res.phases, doc.meta.groundTruth.expected_phase_sequence),
            "\(name): expected \(doc.meta.groundTruth.expected_phase_sequence) in order; got \(res.phases)")
    }

    func testFixture1_TE3CorrectGoodRhythm() throws { try assertFixture("fixture_1_te3_correct_good_rhythm") }
    func testFixture2_TE3WrongPosition()     throws { try assertFixture("fixture_2_te3_wrong_position") }
    func testFixture3_PC6CorrectTooFast()    throws { try assertFixture("fixture_3_pc6_correct_too_fast") }
    func testFixture4_NoHandThenPartial()    throws { try assertFixture("fixture_4_no_hand_then_partial") }
    func testFixture5_TE3FullFlow()          throws { try assertFixture("fixture_5_te3_full_flow") }

    // The integration smoke test: the full-flow fixture must walk the whole machine to COMPLETE.
    func testFixture5_ReachesComplete() throws {
        let res = run(try loadDoc("fixture_5_te3_full_flow"))
        XCTAssertEqual(res.finalPhase, "COMPLETE", "full-flow fixture must reach COMPLETE")
    }
}
