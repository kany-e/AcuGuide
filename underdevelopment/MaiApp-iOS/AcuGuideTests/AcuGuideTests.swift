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
}
