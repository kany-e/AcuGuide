import XCTest
@testable import AcuGuide

// PRODUCT SCOPE, PINNED. These are decisions, not computations — the test exists so that changing one
// is a deliberate edit with its reason in front of you, not a stray flip of a Bool.
final class ReleaseScopeTests: XCTestCase {

    // Moxibustion is held out of v1. Before flipping this, the things ReleaseScope lists as never
    // having been seen on a phone should have been: the abdomen camera marks on a real trunk, the
    // background skin-check notification, and the clock across a real sitting.
    func testMoxaIsNotInThisRelease() {
        XCTAssertFalse(ReleaseScope.moxaShipsInThisRelease,
                       "moxa was held out of v1 on purpose — see ReleaseScope before shipping it")
    }

    // Hidden is not deleted: the moxa surfaces must still exist and keep their safety rules, so the
    // tab can come back without a rewrite. If these stop compiling or start failing, the hold has
    // turned into rot.
    func testHiddenMoxaIsStillIntactBehindTheFlag() {
        XCTAssertEqual(MoxaGateView.questionCount, 5, "the forced screening is still five questions")
        XCTAssertEqual(MoxaClockPlan.capMinutes, 15, "the hard cap is unchanged")
        XCTAssertFalse(MoxaAtlas.all.isEmpty, "the moxa dataset is still there")
    }
}
