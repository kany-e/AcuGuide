import XCTest
@testable import AcuGuide

// The camera locate step for the moxa points: which points it may draw, and where on the trunk it
// puts them. The Vision half cannot be unit-tested (VNHumanBodyPoseObservation has no public
// initialiser), so what is pinned here is the part that decides SAFETY and PLACEMENT — the rule for
// who gets a dot at all, and the arithmetic that turns a moxa anchor into a fraction of the
// neck→root line.
final class MoxaCameraLocateTests: XCTestCase {

    // THE BACK POINTS MUST NEVER REACH THE CAMERA, and not because a list says so. They are anchored
    // to the iliac-crest line, which palpates one to two vertebral levels high — 3.5 to 7 cm — and
    // their own data already sets `drawAsArea` for exactly that reason. A dot on a live picture
    // drawn from that landmark is false precision on a heat source, so the rule is derived from the
    // anchor and a new point is answered by its own data.
    func testOnlyTheAbdominalMidlineIsCameraLocatable() {
        let locatable = Set(MoxaTorsoAcupoints.locatable.map(\.id))
        XCTAssertEqual(locatable, ["CV8", "CV6", "CV4"],
                       "only the navel→pubic-border midline points may be marked on a live picture")
        for p in MoxaAtlas.all where MoxaTorsoAcupoints.isLocatable(p) {
            XCTAssertFalse(p.onBack, "\(p.id) is on the back — a selfie preview cannot show it")
            XCTAssertFalse(p.anchor.drawAsArea,
                           "\(p.id) is drawn as an AREA because its landmark is biased; it must not get a dot")
            XCTAssertFalse(p.anchor.bilateral, "\(p.id) is bilateral — one dot on the midline would be wrong")
        }
    }

    // Every point the camera CANNOT place still has to be reachable and findable by hand, or the
    // rebuild has quietly dropped half the atlas out of the flow.
    func testTheNonLocatablePointsStillCarryTheirOwnFindingSteps() {
        for p in MoxaAtlas.all where !MoxaTorsoAcupoints.isLocatable(p) {
            XCTAssertFalse(p.findEn.isEmpty, "\(p.id) has no camera step, so its written steps are all there is")
            XCTAssertFalse(p.findZh.isEmpty, "\(p.id) 没有相机步骤，文字步骤就是全部")
        }
    }

    // THE ARITHMETIC, against the frame that already shipped. TorsoAcupoints lays the trunk out as
    // 22 cun from neck to root with the navel at 17; a moxa anchor is a fraction of the LAST 5 of
    // those (navel → pubic border). So the three points land at 17, 18.5 and 20 cun down.
    func testAnchorFractionsMapOntoTheTrunkLine() {
        let expected: [String: Double] = [
            "CV8": 17.0 / 22.0,          // Shenque IS the navel — fraction 0.00
            "CV6": 18.5 / 22.0,          // Qihai, 1.5 cun below it — fraction 0.30 of 5 cun
            "CV4": 20.0 / 22.0,          // Guanyuan, 3 cun below it — fraction 0.60
        ]
        for p in MoxaTorsoAcupoints.locatable {
            guard let want = expected[p.id] else {
                XCTFail("\(p.id) became camera-locatable without an expected position"); continue
            }
            XCTAssertEqual(MoxaTorsoAcupoints.trunkFraction(p), want, accuracy: 0.0001,
                           "\(p.id) sits at the wrong fraction of the neck→root line")
        }
    }

    // Ordering is the sanity check the user reads: they must come down the body in the order the
    // placement copy describes, or a mis-framed shot would not look wrong.
    func testTheMarksRunDownTheBodyInOrder() {
        let byFraction = MoxaTorsoAcupoints.locatable
            .sorted { MoxaTorsoAcupoints.trunkFraction($0) < MoxaTorsoAcupoints.trunkFraction($1) }
        XCTAssertEqual(byFraction.map(\.id), ["CV8", "CV6", "CV4"],
                       "navel first, then down toward the pubic border")
        for p in MoxaTorsoAcupoints.locatable {
            let t = MoxaTorsoAcupoints.trunkFraction(p)
            XCTAssertTrue(t > 0.5 && t < 1.0, "\(p.id) fell off the abdominal half of the trunk line")
        }
    }

    // The locator's copy must say what it is and what it is not — it is the screen most likely to be
    // read as the app approving a sitting.
    func testTheLocatorSaysItDoesNotDecideOrTime() {
        let zhWas = AppSettings.shared.lang
        AppSettings.shared.lang = .en
        defer { AppSettings.shared.lang = zhWas }
        let all = MoxaLocateCopy.allCopy.joined(separator: " ").lowercased()
        XCTAssertTrue(all.contains("estimate"), "the proportional estimate must be named as one")
        XCTAssertTrue(all.contains("does not decide") && all.contains("does not keep time"),
                      "the locator must disclaim deciding and timing — it does neither")
    }
}
