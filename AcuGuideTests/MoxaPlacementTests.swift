import XCTest
@testable import AcuGuide

// The placement cards, and the claim test the base substring scan cannot perform.
final class MoxaPlacementTests: XCTestCase {

    // THE EXTENDED SCAN. This is the point of MoxaSafety: "improves circulation" clears
    // testNoForbiddenMedicalClaims, and it is the documented proximate cause of the burns in the
    // foot-soak case series — a reason to believe the heat is doing something is a reason to leave it
    // on longer. Every moxa surface is scanned against the extended list here, so a claim that the
    // base suite would wave through fails instead.
    func testEveryMoxaSurfaceIsCleanAgainstTheExtendedClaimList() {
        func check(_ label: String, _ strings: [String]) {
            let en = strings.joined(separator: " ").lowercased()
            for term in MoxaSafety.extendedBannedEn {
                XCTAssertFalse(en.contains(term),
                               "\(label) contains '\(term)' — passes the base scan, still a claim")
            }
            let zh = strings.joined(separator: " ")
            for term in MoxaSafety.extendedBannedZh {
                XCTAssertFalse(zh.contains(term), "\(label) 含「\(term)」——基础检查放行，但仍是功效表述")
            }
        }
        for m in MoxaAtlas.all {
            check("moxa[\(m.id)]", [m.locationEn, m.locationZh, m.findEn, m.findZh,
                                    m.traditionEn, m.traditionZh, m.cautionEn, m.cautionZh])
        }
        for p in MoxaPlacements.all {
            check("placement[\(p.id)]", [p.titleEn, p.titleZh, p.bodyEn, p.bodyZh])
        }
        check("routingQuestion", [MoxaPlacements.routingQuestion])
        check("moxaNotice", MoxaNotice.allCopy)   // lines + the disclosure labels
        check("moxaGate", MoxaGateView.allCopy)
        // The clock and the strap advice are moxa surfaces like any other — a dose-escalating
        // claim beside a TIMER would be the worst possible place for one.
        check("moxaClock", MoxaClockCopy.allCopy)
        check("moxaStrap", MoxaStrapAdvice.allCopy)
    }

    // The list must not be so wide that honest copy becomes unwritable. These are the terms the app
    // needs and that carry no claim — 医疗 because 「并非医疗工具」 is the DISCLAIMER, 副作用 because
    // it is safety copy, 养生 because as a zh category label it has no object and no outcome.
    func testDeliberatelyPermittedTermsAreNotBanned() {
        for term in MoxaSafety.deliberatelyPermitted {
            XCTAssertFalse(MoxaSafety.extendedBannedZh.contains(term),
                           "banning 「\(term)」 would make honest copy unwritable")
        }
    }

    // ROUTING WITHOUT A SYMPTOM. The whole reason the cards are PLACEMENTS: a symptom menu would make
    // the next screen a prescription. The question asks what the user can physically do.
    func testRoutingAsksWhatYouCanDoNotWhatIsWrong() {
        let en = MoxaPlacements.routingQuestion.lowercased()
        XCTAssertTrue(en.contains("lie flat") || en.contains("sitting"),
                      "the question must route on posture/availability")
        for symptomWord in ["pain", "ache", "symptom", "bothering", "suffer", "problem", "condition"] {
            XCTAssertFalse(en.contains(symptomWord),
                           "'\(symptomWord)' turns the next screen into a prescription")
        }
    }

    // Every placement resolves, and the split between the two datasets is respected: a placement
    // names main-atlas points rather than duplicating them, because a second copy is what goes stale.
    func testPlacementsResolveAgainstBothDatasets() {
        XCTAssertEqual(MoxaPlacements.all.count, 3)
        for p in MoxaPlacements.all {
            XCTAssertEqual(p.points.count, p.moxaPointIds.count,
                           "\(p.id) references a moxa point that does not exist")
            for id in p.atlasPointIds {
                XCTAssertNotNil(Acupoint.byId[id], "\(p.id) references missing atlas point \(id)")
                XCTAssertFalse(MoxaAtlas.all.contains { $0.id == id },
                               "\(id) is in both datasets — it must live in exactly one")
            }
            XCTAssertFalse(p.moxaPointIds.isEmpty && p.atlasPointIds.isEmpty,
                           "\(p.id) covers no points at all")
        }
        // Between them the three placements must reach every gated moxa point, or a point exists
        // that nothing routes to.
        let routed = Set(MoxaPlacements.all.flatMap(\.moxaPointIds))
        XCTAssertEqual(routed, Set(MoxaAtlas.all.map(\.id)))
    }

    // NO SEQUENCE CLAIM. A draft cited 先上后下 to justify presenting the placements abdomen-first,
    // but the rule as written is 先阳后阴……先上后下 — yang before yin puts the BACK before the front.
    // Half-quoting a real source to authorise the app's own ordering is worse than claiming nothing,
    // so the shins card states the rule whole and the app claims no order.
    func testNoPlacementClaimsASessionOrder() {
        for p in MoxaPlacements.all {
            let en = p.bodyEn.lowercased()
            XCTAssertFalse(en.contains("start with") || en.contains("work down") || en.contains("in this order"),
                           "\(p.id) asserts a session order the sources do not support")
        }
        // …and where the rule IS quoted, it must be quoted whole, with the 先阳后阴 half present.
        let shins = MoxaPlacements.all.first { $0.id == "shins-st36" }!
        XCTAssertTrue(shins.bodyZh.contains("先阳后阴"),
                      "quoting 先上后下 without 先阳后阴 is the half-quotation that inverts the meaning")
    }

    // The CV5 correction, pinned. The shipped mitigation ("centre it on Qihai and it misses Shimen")
    // was false: CV5 is at 脐下2寸, between CV6 (1.5) and CV4 (3.0), so ANY box covering both covers
    // it. A mitigation that does not mitigate is worse than none, because it licenses the one-box
    // plan it appears to make safe.
    func testTheCV5GeometryIsStatedHonestlyAndNotAsAMitigation() {
        let cv6 = MoxaAtlas.abdomen.first { $0.id == "CV6" }!
        let abdomen = MoxaPlacements.all.first { $0.id == "abdomen-midline" }!
        for text in [cv6.traditionEn, abdomen.bodyEn] {
            XCTAssertFalse(text.lowercased().contains("centre it on qihai"),
                           "that mitigation is false — no single box covering both misses CV5")
            XCTAssertTrue(text.contains("Shimen"), "the geometry must still be disclosed")
        }
        XCTAssertTrue(cv6.traditionEn.contains("one point at a time"),
                      "the only honest instruction is one point at a time")
    }

    // 隔盐灸 means salt-SEPARATED: the salt is the insulator. The shipped caution described an open
    // flame directly on skin, which is 直接灸 — the method 隔盐灸 is defined against.
    func testSaltMethodIsDescribedAsInsulatingNotDirect() {
        let cv8 = MoxaAtlas.abdomen.first { $0.id == "CV8" }!
        XCTAssertTrue(cv8.cautionEn.lowercased().contains("insulating")
                      || cv8.cautionEn.lowercased().contains("separated"),
                      "隔 means separated by — the salt is the insulating layer")
        XCTAssertFalse(cv8.cautionEn.lowercased().contains("directly over the skin"),
                       "that describes 直接灸, which is what 隔盐灸 is defined against")
    }

    // The 《扁鹊心书》 lineage must not be borrowed for the lumbar placement: the primary text's fourth
    // point is 命关 (SP17 region), not 命门 GV4. Removing it leaves placement B with no 无病时
    // provenance, which is the correct outcome.
    func testLumbarCopyDoesNotBorrowTheBianqueLineage() {
        for m in MoxaAtlas.lumbar {
            XCTAssertFalse(m.traditionZh.contains("扁鹊心书"),
                           "\(m.id): that text names 命关, not 命门 — the lineage does not transfer")
            XCTAssertFalse(m.traditionEn.contains("warming set"),
                           "\(m.id): no 组穴 by that name exists in the classical corpus")
        }
        // Where CV4 DOES name the text, it must name the substitution rather than rely on it.
        let cv4 = MoxaAtlas.abdomen.first { $0.id == "CV4" }!
        XCTAssertTrue(cv4.traditionEn.contains("Mingguan"),
                      "if the text is cited, the 命关/命门 substitution must be disclosed")
    }

    // MARK: - The notice's disclosure

    // The notice now shows two of its six lines and folds the rest away, because six bullets at the
    // top of the tab (and again on every placement card) is a wall nobody reads. That trade is only
    // safe while the VISIBLE two are the mechanism and the action; a reorder of `lines` would move
    // the fold silently and leave a user reading about carbon monoxide instead of about their skin.
    func testTheTwoVisibleNoticeLinesAreTheMechanismAndTheAction() {
        let zhWas = AppSettings.shared.lang
        AppSettings.shared.lang = .en
        defer { AppSettings.shared.lang = zhWas }

        let lead = MoxaNotice.leadLines
        XCTAssertEqual(lead.count, 2, "two lines lead; the rest are one tap away")
        XCTAssertEqual(lead + MoxaNotice.moreLines, MoxaNotice.lines,
                       "the split must partition the notice — no line may be dropped or duplicated")

        let visible = lead.joined(separator: " ").lowercased()
        XCTAssertTrue(visible.contains("removes the hand"),
                      "the injury MECHANISM (the box takes away the hand that would have noticed) must stay visible")
        XCTAssertTrue(visible.contains("on a timer") && visible.contains("lightly pink"),
                      "the ACTION (look on a timer, stop while lightly pink) must stay visible")
    }

    // A disclosure that under-reports what it hides is a disclosure that teaches the user to leave
    // it closed. The count is derived, and this is what keeps it derived.
    func testTheMoreLabelReportsTheRealNumberOfHiddenLines() {
        let zhWas = AppSettings.shared.lang
        AppSettings.shared.lang = .en
        defer { AppSettings.shared.lang = zhWas }

        XCTAssertTrue(MoxaNotice.moreLabel.contains("\(MoxaNotice.moreLines.count)"),
                      "the label must name how many lines are folded away — got '\(MoxaNotice.moreLabel)'")
        XCTAssertFalse(MoxaNotice.moreLines.isEmpty, "nothing folded away means the disclosure is chrome")
    }
}
