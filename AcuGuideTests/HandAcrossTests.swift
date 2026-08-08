import XCTest
@testable import AcuGuide

// THE TEST THAT SHOULD HAVE CAUGHT "TE3 IS ON THE 3-4 FINGER".
//
// It shipped because nothing asserted a hand point's SIDEWAYS position against anything external.
// The three suites that look like they do cannot fail on a wrong `across`:
//   • DetailSnapshotTests asserts only that the marker is on the surface, un-snapped, and inside the
//     bounding box — all true of a marker on entirely the wrong bone.
//   • BodyMeshProbeTests.testReportHandPointsAcrossThePalm measures exactly the right quantity and
//     then only PRINTS it. Not one assertion in the whole function.
//   • The two that do assert are self-referential: they compute their expected values FROM
//     HandAnatomy.spots, so the table always agrees with itself. That was a deliberate change — it
//     stopped re-sourcing from failing tests — and the cost was that re-sourcing could no longer
//     fail a test either.
//
// So this asserts against the file's OWN SCALE REFERENCE (HandAnatomy.swift header: MCP heads at
// +0.30 / +0.08 / −0.14 / −0.36) rather than against the table being checked. A point whose own
// comment names an inter-metacarpal space must sit in that space, not on the metacarpal beside it.
final class HandAcrossTests: XCTestCase {

    /// The four MCP heads from the header's scale reference, index → little.
    private let mcpHeads: [Double] = [0.30, 0.08, -0.14, -0.36]

    /// Midpoint of the two metacarpals bounding a groove. `gap` 1 = 2nd/3rd … 3 = 4th/5th.
    private func groove(_ gap: Int) -> Double { (mcpHeads[gap - 1] + mcpHeads[gap]) / 2 }

    /// Half the spacing between adjacent metacarpals — the widest a point can be off its named
    /// groove before it is nearer a neighbouring metacarpal than the valley it claims.
    private var tolerance: Double { abs(mcpHeads[0] - mcpHeads[1]) / 2 }

    // Points whose own documentation names an inter-metacarpal space. Each must actually be in it.
    func testPointsNamingAnIntermetacarpalSpaceSitInIt() {
        let cases: [(id: String, gap: Int, why: String)] = [
            ("TE3", 3, "中渚 — in the groove between the 4th and 5th metacarpals"),
            ("HT8", 3, "少府 — its own comment says 'between the 4th and 5th metacarpals'"),
            ("TE2", 3, "液门 — the 4th/5th web, directly distal to TE3 on the same line"),
        ]
        for c in cases {
            let spot = HandAnatomy.spots[c.id]
            XCTAssertNotNil(spot, "\(c.id) missing from HandAnatomy")
            guard let spot else { continue }
            let target = groove(c.gap)
            XCTAssertEqual(Double(spot.across), target, accuracy: tolerance,
                           "\(c.id) (\(c.why)) sits at across \(spot.across); the \(c.gap)th groove "
                           + "is at \(target) by the file's own MCP scale reference. Off by more "
                           + "than half a metacarpal spacing puts it ON a metacarpal, not between "
                           + "two — which is how TE3 came to render against the 3rd/4th gap.")
        }
    }

    // TE3 and TE2 are the same inter-metacarpal line: TE3 is 液门直上1寸, one cun proximal to TE2.
    // They may differ slightly as the metacarpals converge proximally, but a large gap between them
    // means one of the two has drifted off the line — which is precisely what happened.
    func testTE3AndTE2ShareTheirInterMetacarpalLine() throws {
        let te3 = try XCTUnwrap(HandAnatomy.spots["TE3"])
        let te2 = try XCTUnwrap(HandAnatomy.spots["TE2"])
        XCTAssertEqual(Double(te3.across), Double(te2.across), accuracy: 0.06,
                       "TE3 is 液门直上1寸 — the same line one cun proximal — so their `across` must "
                       + "very nearly agree. They were 0.07 apart, and TE3 was the one off the line.")
        XCTAssertGreaterThan(te2.along, te3.along, "TE2 is distal to TE3")
    }

    // The ulnar column must stay ordered: SI3 is the ulnar BORDER, so nothing that names an
    // inter-metacarpal groove may sit further ulnar than it.
    func testNothingIsMoreUlnarThanTheUlnarBorderPoint() throws {
        let si3 = try XCTUnwrap(HandAnatomy.spots["SI3"])
        for id in ["TE3", "TE2", "HT8"] {
            let s = try XCTUnwrap(HandAnatomy.spots[id])
            XCTAssertGreaterThan(s.across, si3.across,
                                 "\(id) is between metacarpals; SI3 is the ulnar border, so \(id) "
                                 + "must be less ulnar than it")
        }
    }

    // The detail hand sheet derives from HandAnatomy, so `Placements3D` must not also carry a
    // detailUV for a hand point: the value is never read, and one that looks authoritative is how a
    // "recalibrate TE3" lands in dead code and ships nothing. Structural, so the trap cannot return.
    // Scoped to points FILED under region "hand". TE4 and PC7 also live in HandAnatomy — the hand
    // sheet re-derives them because they sit on the wrist creases it draws — but they are filed
    // under "arm" and appear on the ARM sheet too, where their detailUV is read and live. So the
    // rule is not "no HandAnatomy point may have a detailUV", it is "a point whose detail sheet IS
    // the hand sheet must not carry one", which is the set where the value is genuinely dead.
    func testHandRegionPointsCarryNoDeadDetailUV() {
        for (id, _) in HandAnatomy.spots {
            guard Acupoint.byId[id]?.region == "hand" else { continue }
            if let p = AcupointPlacements.table[id] {
                XCTAssertNil(p.detailUV,
                             "\(id) has a detailUV in Placements3D, but detailLayout(region:\"hand\") "
                             + "derives hand markers from HandAnatomy and never reads it — a "
                             + "plausible-looking dead coordinate is worse than none, because it is "
                             + "what a 'recalibrate this point' edit lands in")
            }
        }
    }
}
