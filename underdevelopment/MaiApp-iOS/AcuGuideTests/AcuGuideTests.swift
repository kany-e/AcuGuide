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
}
