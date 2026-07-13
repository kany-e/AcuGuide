import XCTest
import CoreGraphics
import Vision
@testable import AcuGuide

// The two-pass Vision merge + backoff policies, extracted pure exactly so the review-caught
// failure scenes are pinned by unit tests (they used to live inline in captureOutput, reachable
// only with a live camera buffer).
final class CameraCoachMergeTests: XCTestCase {

    private func hand(wrist: CGPoint, chirality: VNChirality, conf: Float, weak: Bool = false) -> Hand {
        Hand(points: [.wrist: wrist, .middleMCP: CGPoint(x: wrist.x, y: wrist.y - 0.28)],
             chirality: chirality, weak: weak, detectionConfidence: conf)
    }

    // THE review-caught scene: mid-press both wrists sit within the dup radius. The presser's
    // confident inverted read must replace the PRESSER's entry (nearest, same chirality) — never
    // the receiver's.
    func testInvertedReadReplacesNearestSameChiralityNotReceiver() {
        let receiver = hand(wrist: CGPoint(x: 0.50, y: 0.60), chirality: .right, conf: 0.6)
        let presser  = hand(wrist: CGPoint(x: 0.44, y: 0.52), chirality: .left, conf: 0.35, weak: true)
        var hands = [receiver, presser]
        // Inverted read of the SAME presser: wrist ~0.02 from the presser entry, ~0.11 from the
        // receiver — both inside the 0.15 radius, but chirality + nearest pick the presser.
        let inverted = hand(wrist: CGPoint(x: 0.455, y: 0.535), chirality: .left, conf: 0.85)
        XCTAssertTrue(CameraCoach.mergeInvertedRead(inverted, into: &hands))
        XCTAssertEqual(hands.count, 2)
        XCTAssertEqual(hands[0].detectionConfidence, 0.6, "the receiver entry must be untouched")
        XCTAssertEqual(hands[1].detectionConfidence, 0.85, "the presser entry takes the better read")
        XCTAssertFalse(hands[1].weak)
    }

    // Cross-pass chirality DISAGREEMENT on the same physical hand: near-coincident wrists merge
    // (conflict radius), so the hand is not duplicated into a phantom two-hand scene.
    func testConflictingLabelsMergeOnlyWhenNearCoincident() {
        // Near-coincident (0.01 apart): treated as the same hand despite the label conflict.
        var hands = [hand(wrist: CGPoint(x: 0.50, y: 0.60), chirality: .left, conf: 0.4)]
        let coincident = hand(wrist: CGPoint(x: 0.508, y: 0.605), chirality: .right, conf: 0.8)
        XCTAssertTrue(CameraCoach.mergeInvertedRead(coincident, into: &hands))
        XCTAssertEqual(hands.count, 1, "near-coincident conflicting labels = one physical hand")
        XCTAssertEqual(hands[0].detectionConfidence, 0.8)

        // Farther apart (0.12): conflicting labels = genuinely distinct hands → appended.
        var hands2 = [hand(wrist: CGPoint(x: 0.50, y: 0.60), chirality: .left, conf: 0.4)]
        let distinct = hand(wrist: CGPoint(x: 0.62, y: 0.60), chirality: .right, conf: 0.8)
        XCTAssertTrue(CameraCoach.mergeInvertedRead(distinct, into: &hands2))
        XCTAssertEqual(hands2.count, 2, "distinct conflicting-label hands must both survive")
    }

    // The confidence bias: the primary read wins unless the inverted one is CLEARLY better —
    // source alternation was itself a jitter cause.
    func testPrimaryWinsInsideConfidenceBias() {
        var hands = [hand(wrist: CGPoint(x: 0.50, y: 0.60), chirality: .left, conf: 0.6)]
        let slightlyBetter = hand(wrist: CGPoint(x: 0.51, y: 0.60), chirality: .left, conf: 0.65)
        XCTAssertFalse(CameraCoach.mergeInvertedRead(slightlyBetter, into: &hands))
        XCTAssertEqual(hands[0].detectionConfidence, 0.6, "a marginal inverted read must not swap the source")
    }

    // A full array with no duplicate match: the read is dropped, never a third entry.
    func testNoAppendWhenFull() {
        var hands = [hand(wrist: CGPoint(x: 0.2, y: 0.5), chirality: .left, conf: 0.6),
                     hand(wrist: CGPoint(x: 0.8, y: 0.5), chirality: .right, conf: 0.6)]
        let stray = hand(wrist: CGPoint(x: 0.5, y: 0.2), chirality: .left, conf: 0.9)
        XCTAssertFalse(CameraCoach.mergeInvertedRead(stray, into: &hands))
        XCTAssertEqual(hands.count, 2)
    }

    // Unknown chirality is a wildcard for the duplicate match (a true duplicate whose label
    // Vision couldn't read must still merge at the full radius).
    func testUnknownChiralityMatchesAtFullRadius() {
        var hands = [hand(wrist: CGPoint(x: 0.50, y: 0.60), chirality: .unknown, conf: 0.4)]
        let read = hand(wrist: CGPoint(x: 0.58, y: 0.65), chirality: .right, conf: 0.8)
        XCTAssertTrue(CameraCoach.mergeInvertedRead(read, into: &hands))
        XCTAssertEqual(hands.count, 1)
        XCTAssertEqual(hands[0].detectionConfidence, 0.8)
    }

    // Backoff policy: EVERY trigger throttles after the no-yield streak (the missing-hand
    // exemption ran the doubled inference at full rate through idle no-hands stretches), and the
    // throttle stride still lets every Nth frame through.
    func testInvertedPassBackoff() {
        // No trigger → never run.
        XCTAssertFalse(CameraCoach.shouldRunInvertedPass(missingHand: false, hasWeak: false,
                                                         noUpgradeStreak: 0, tick: 1))
        // Fresh streak → full rate for both triggers.
        XCTAssertTrue(CameraCoach.shouldRunInvertedPass(missingHand: true, hasWeak: false,
                                                        noUpgradeStreak: 0, tick: 1))
        XCTAssertTrue(CameraCoach.shouldRunInvertedPass(missingHand: false, hasWeak: true,
                                                        noUpgradeStreak: 11, tick: 1))
        // Past the streak → only every Nth frame, for BOTH triggers.
        let stride = CoachConst.invertedBackoffStride
        XCTAssertFalse(CameraCoach.shouldRunInvertedPass(missingHand: true, hasWeak: false,
                                                         noUpgradeStreak: 12, tick: stride + 1))
        XCTAssertTrue(CameraCoach.shouldRunInvertedPass(missingHand: true, hasWeak: false,
                                                        noUpgradeStreak: 12, tick: stride * 2))
        XCTAssertFalse(CameraCoach.shouldRunInvertedPass(missingHand: false, hasWeak: true,
                                                         noUpgradeStreak: 20, tick: stride + 1))
    }
}
