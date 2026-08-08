import XCTest
@testable import AcuGuide

// The navel→pubic-bone walkthrough's arithmetic.
//
// This is the whole reason the proportional method was worth building rather than printing a fixed
// "four fingers below the navel": the span is 5 cun BY DEFINITION, so measuring it in the user's own
// units makes every derived distance personal without ever needing a centimetre figure.
final class MoxaSpanTests: XCTestCase {

    // THE PROPERTY THAT MAKES THE METHOD WORK. A point at fraction f of the span sits at f × the
    // measured span, in whatever unit the span was measured in. So two people of very different
    // sizes get different finger counts from the same fraction, and each is right for their body.
    func testDerivedDistanceScalesWithTheMeasuredSpan() {
        let short = MoxaSpan(fingerWidths: 5.5)
        let tall = MoxaSpan(fingerWidths: 8.0)
        let f = MoxaAtlas.abdomen.first { $0.id == "CV4" }!.anchor.fraction

        XCTAssertEqual(short.fingerWidths(at: f), 5.5 * 0.6, accuracy: 1e-9)
        XCTAssertEqual(tall.fingerWidths(at: f), 8.0 * 0.6, accuracy: 1e-9)
        XCTAssertGreaterThan(tall.fingerWidths(at: f), short.fingerWidths(at: f),
                             "a longer torso must put the point further down, in the user's own units")
    }

    // 神阙 is the origin of the span, so it must come out as "the navel itself" and not as a
    // computed distance of zero.
    func testTheOriginPointDerivesToZero() {
        let span = MoxaSpan(fingerWidths: 7)
        let cv8 = MoxaAtlas.abdomen.first { $0.id == "CV8" }!
        XCTAssertEqual(span.fingerWidths(at: cv8.anchor.fraction), 0, accuracy: 1e-9)
    }

    // The three points must come out in anatomical order down the belly, whatever the span. If a
    // future edit swapped a fraction this ordering is the first thing that would break.
    func testPointsDeriveInOrderDownTheMidline() {
        for widths in [5.0, 6.5, 7.0, 8.5] {
            let span = MoxaSpan(fingerWidths: widths)
            let ordered = MoxaAtlas.abdomen.map { span.fingerWidths(at: $0.anchor.fraction) }
            XCTAssertEqual(ordered, ordered.sorted(),
                           "at \(widths) finger-widths the points come out of order")
            XCTAssertLessThanOrEqual(ordered.last!, widths,
                                     "no point may fall below the pubic bone")
        }
    }

    // 一夫法 (four fingers = 3 cun) against a 5-cun span predicts ~6.7 finger-widths on ANYONE —
    // the figure is a property of the proportional system, not of body size. It is what the
    // mismeasurement check is calibrated against, so it is pinned rather than left as a comment.
    func testExpectedSpanFollowsFromTheProportionalSystem() {
        XCTAssertEqual(MoxaSpan.expectedFingerWidths, 5.0 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(MoxaSpan.expectedFingerWidths, 6.666666, accuracy: 1e-5)
        XCTAssertFalse(MoxaSpan(fingerWidths: MoxaSpan.expectedFingerWidths).looksMismeasured)
    }

    // The mismeasurement hint must be quiet across the range real people report and speak up only
    // for values that indicate the measurement itself went wrong — fingers held apart, or a pubic
    // ridge missed because a full bladder padded it. A check that fires on ordinary bodies would
    // train people to ignore it.
    func testMismeasurementHintIsQuietAcrossTheOfferedRange() {
        for n in [5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5] {
            XCTAssertFalse(MoxaSpan(fingerWidths: n).looksMismeasured,
                           "\(n) is offered as a choice in the UI, so it must not be flagged")
        }
        XCTAssertTrue(MoxaSpan(fingerWidths: 3).looksMismeasured)
        XCTAssertTrue(MoxaSpan(fingerWidths: 12).looksMismeasured)
    }

    // A worked example, so the numbers a user actually sees are pinned rather than only the algebra:
    // a 7-finger span puts 气海 at 2.1 and 关元 at 4.2 finger-widths below the navel.
    func testWorkedExampleForASevenFingerSpan() {
        let span = MoxaSpan(fingerWidths: 7)
        let byId = Dictionary(uniqueKeysWithValues: MoxaAtlas.abdomen.map { ($0.id, $0) })
        XCTAssertEqual(span.fingerWidths(at: byId["CV6"]!.anchor.fraction), 2.1, accuracy: 1e-9)
        XCTAssertEqual(span.fingerWidths(at: byId["CV4"]!.anchor.fraction), 4.2, accuracy: 1e-9)
    }
}
