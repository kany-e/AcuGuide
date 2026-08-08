import XCTest
@testable import AcuGuide

// The moxibustion dataset's load-bearing invariants.
//
// These points are different from every other point in the app: all five are pregnancy-restricted,
// and the rest of AcuGuide deliberately runs WITHOUT a pregnancy screen — LI4, SP6, GB21, BL60 and
// BL67 are excluded outright so that no gate is needed. That trade only holds while no restricted
// point is reachable from an ungated surface, so the separation between this dataset and
// `Acupoint.all` is a SAFETY mechanism, not an organisational preference. It is pinned here.
final class MoxaAtlasTests: XCTestCase {

    // THE ONE THAT MATTERS. `Acupoint.all` is enumerated by the atlas, the meridian overlays, the 3D
    // body and the CHAT's point list — none of which has a pregnancy gate. A point that is not in
    // `.all` cannot leak into a surface that enumerates `.all`; that is why the moxa points live in
    // their own collection instead of carrying a `moxaOnly` flag filtered at twelve call sites.
    func testMoxaPointsAreNotInTheUngatedAtlas() {
        let atlasIds = Set(Acupoint.all.map(\.id))
        for m in MoxaAtlas.all {
            XCTAssertFalse(atlasIds.contains(m.id),
                           "\(m.id) is pregnancy-restricted and must not be reachable from the "
                           + "ungated atlas/chat/meridian surfaces that enumerate Acupoint.all")
        }
    }

    // Every point here carries a caution, in both languages. This dataset has no "no caution needed"
    // case — if one ever appears it is a mistake, not a point that happens to be safe.
    func testEveryMoxaPointCarriesACautionInBothLanguages() {
        for m in MoxaAtlas.all {
            XCTAssertFalse(m.cautionEn.isEmpty, "\(m.id) has no English caution")
            XCTAssertFalse(m.cautionZh.isEmpty, "\(m.id) has no Chinese caution")
        }
        XCTAssertTrue(MoxaAtlas.allRestrictedInPregnancy)
    }

    // THE PROPORTIONAL PAYOFF, as arithmetic rather than a comment. Navel → pubic border is ONE
    // 5-cun span, and the three abdominal points sit at 0/5, 1.5/5 and 3/5 along it — so two marked
    // landmarks place all three. If a future edit re-derives these from the upper (8-cun) span, or
    // from 《灵枢·骨度》's 6.5-cun figure for the same segment, these numbers move and the test fails.
    func testAbdominalPointsShareOneSpanWithCorrectFractions() {
        let expected: [String: Double] = ["CV8": 0.0, "CV6": 1.5 / 5.0, "CV4": 3.0 / 5.0]
        for m in MoxaAtlas.abdomen {
            XCTAssertEqual(m.anchor.from, .navel, "\(m.id) must measure from the navel")
            XCTAssertEqual(m.anchor.to, .pubicBorder, "\(m.id) must measure to the pubic border")
            XCTAssertEqual(m.anchor.fraction, expected[m.id]!, accuracy: 1e-9,
                           "\(m.id) sits at the wrong fraction of the 5-cun navel→pubis span")
            XCTAssertFalse(m.anchor.bilateral, "\(m.id) is a midline point")
        }
        // The whole abdominal set is placeable from exactly two user-marked landmarks.
        let marks = Set(MoxaAtlas.abdomen.flatMap { [$0.anchor.from, $0.anchor.to] })
        XCTAssertEqual(marks, [.navel, .pubicBorder])
    }

    // BL23 is bilateral and GV4 is not — a plan that fires only one side of a pair is wrong, so the
    // pairing is derived from the lateral offset rather than stored as a second flag that could
    // disagree with it.
    func testLumbarPairingIsDerivedFromTheLateralOffset() {
        let gv4 = MoxaAtlas.lumbar.first { $0.id == "GV4" }!
        let bl23 = MoxaAtlas.lumbar.first { $0.id == "BL23" }!
        XCTAssertFalse(gv4.anchor.bilateral, "Mingmen is on the midline")
        XCTAssertTrue(bl23.anchor.bilateral, "Shenshu is a pair and must never fire one side only")
        XCTAssertEqual(bl23.anchor.lateral, 0.5, accuracy: 1e-9,
                       "1.5 cun of the 3-cun midline→scapular-border half-span")
        XCTAssertTrue(gv4.onBack && bl23.onBack)
    }

    // The back points are the highest-risk configuration in the feature — unseen, unreachable, and
    // the user may doze off face-down on a hot box. Their copy must say so; a caution that omits it
    // is worse than none because it looks like the hazard was considered.
    func testBackPointCautionsNameTheUnreachabilityAndTheStrapOnFailure() {
        for m in MoxaAtlas.all where m.onBack {
            let en = m.cautionEn.lowercased()
            XCTAssertTrue(en.contains("back"), "\(m.id) caution must say it is on the back")
            XCTAssertTrue(en.contains("reach"),
                          "\(m.id) caution must say the box cannot be reached — that is the hazard")
            XCTAssertTrue(en.contains("second person") || en.contains("timer"),
                          "\(m.id) caution must name the mitigation")
        }
    }

    // A popular shortcut places L2 "level with the navel". Surface anatomy clusters the umbilicus at
    // L4, so that lands one to two levels low — near BL25, not L2. The find text must route the user
    // via the iliac crest instead, and must not mention the navel at all for the lumbar points.
    func testLumbarFindTextUsesTheIliacCrestAndNotTheNavel() {
        for m in MoxaAtlas.lumbar {
            XCTAssertTrue(m.findEn.lowercased().contains("hip bones") || m.findEn.lowercased().contains("crest"),
                          "\(m.id) must locate L2 from the iliac-crest line")
            XCTAssertFalse(m.findEn.lowercased().contains("navel"),
                           "\(m.id): 'level with the navel' is the common shortcut and it is wrong — "
                           + "the umbilicus sits at about L4")
            XCTAssertFalse(m.findZh.contains("肚脐"), "\(m.id) 中文找法不应以肚脐定位第2腰椎")
        }
    }

    // AN AREA, NOT A DOT, for the lumbar points — and a dot for the abdominal ones. The distinction
    // is evidential: iliac-crest palpation carries a systematic UPWARD bias of one to two vertebral
    // levels (~3.5–7 cm, largest in women), which is far outside a single-hole box's ±2 cm, whereas
    // the navel and pubic border propagate ~1.3 cm. Drawing a confident dot from the biased landmark
    // would be false precision on a heat source.
    func testOnlyTheLumbarPointsAreDrawnAsAnArea() {
        for m in MoxaAtlas.lumbar {
            XCTAssertTrue(m.anchor.drawAsArea, "\(m.id) derives from the iliac crest and must not be a dot")
        }
        for m in MoxaAtlas.abdomen {
            XCTAssertFalse(m.anchor.drawAsArea, "\(m.id) has stable midline landmarks")
        }
        XCTAssertGreaterThan(MoxaBox.multiHoleToleranceCm, MoxaBox.singleHoleToleranceCm)
    }

    // No dose is stated in 壮 anywhere. The unit counts cone-burns applied to the skin, which is not
    // what a moxa box delivers — and a drafted "classical dosage 7–10 壮" was doubly wrong, since the
    // text cited beside it prescribes doses in the hundreds.
    // 壮 may appear ONLY to disavow itself. The unit counts cone-burns applied to bare skin, so it
    // does not describe anything a box does — but the honest correction to the 《扁鹊心书》 citation has
    // to say that the text prescribes cones in the HUNDREDS, precisely to establish that the lineage
    // does not transfer to a 20-minute warm box. Same shape as ChatLLM.instructions, which quotes the
    // words it forbids. So the rule is not "never mention 壮", it is "never state a dose in 壮" — and
    // a mention must carry the disavowal in the same string, where a reader cannot miss it.
    func testZhuangAppearsOnlyToDisavowItself() {
        for m in MoxaAtlas.all {
            for s in [m.traditionZh, m.cautionZh, m.findZh, m.locationZh] where s.contains("壮") {
                XCTAssertTrue(s.contains("不是一回事") || s.contains("不同"),
                              "\(m.id): 壮 may only appear alongside the statement that it does not "
                              + "describe what a box does — otherwise it reads as a dose")
            }
            for s in [m.traditionEn, m.cautionEn, m.findEn, m.locationEn] where s.contains("cones") {
                XCTAssertTrue(s.contains("not what a box does"),
                              "\(m.id): naming the classical cone count without disavowing it invites "
                              + "the reader to treat it as a dose")
            }
        }
    }
}
