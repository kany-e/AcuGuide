import XCTest
import CoreGraphics
import Vision
import SceneKit
import SwiftUI
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

// The hands-free confirm keyword matcher — pure, so ambient-speech safety is unit-tested.
final class LocateVoiceCommandTests: XCTestCase {
    func testConfirmPhrases() {
        XCTAssertEqual(LocateVoiceCommand.parse("okay so this is my spot"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("This is it"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("that's it."), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("confirm"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("嗯就是这里"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("确认"), .confirm)
    }
    func testSkipPhrases() {
        XCTAssertEqual(LocateVoiceCommand.parse("skip"), .skip)
        XCTAssertEqual(LocateVoiceCommand.parse("跳过"), .skip)
    }
    func testAmbientSpeechDoesNotTrigger() {
        // Bare agreement words and mid-sentence mentions must not fire.
        XCTAssertNil(LocateVoiceCommand.parse("yes"))
        XCTAssertNil(LocateVoiceCommand.parse("okay"))
        XCTAssertNil(LocateVoiceCommand.parse("i think this is it maybe not actually"))
        XCTAssertNil(LocateVoiceCommand.parse("is this the spot i wonder"))
        XCTAssertNil(LocateVoiceCommand.parse("这里有点酸"))
        XCTAssertNil(LocateVoiceCommand.parse(""))
    }

    // Typographic apostrophe (U+2019) — what iOS speech transcription actually emits for
    // contractions; the ASCII-only strip missed it and "that's it" silently failed on device.
    func testCurlyApostropheMatches() {
        XCTAssertEqual(LocateVoiceCommand.parse("that\u{2019}s it"), .confirm)
        XCTAssertEqual(LocateVoiceCommand.parse("okay that\u{2019}s it."), .confirm)
    }

    // Negations must NOT fire (the phrase is spoken precisely when an offer is live).
    func testNegationsDoNotTrigger() {
        XCTAssertNil(LocateVoiceCommand.parse("wait don't confirm"))
        XCTAssertNil(LocateVoiceCommand.parse("no this is not it"))
        XCTAssertNil(LocateVoiceCommand.parse("let's not skip"))
        XCTAssertNil(LocateVoiceCommand.parse("不要确认"))
        XCTAssertNil(LocateVoiceCommand.parse("先别确认"))
        XCTAssertNil(LocateVoiceCommand.parse("不就是这里"))
        XCTAssertNil(LocateVoiceCommand.parse("别跳过"))
    }

    // Whole-word matching: a keyword embedded in a larger word must not fire.
    func testEmbeddedKeywordDoesNotTrigger() {
        XCTAssertNil(LocateVoiceCommand.parse("let me reconfirm"))
        XCTAssertNil(LocateVoiceCommand.parse("再确认一下"))   // "let me double-check" — 确认 not a suffix
    }

    // Chinese matches by SUFFIX, so a settled phrase followed by later speech must not re-fire.
    func testChineseStaleTailDoesNotRefire() {
        XCTAssertNil(LocateVoiceCommand.parse("就是这里有点酸"))
        XCTAssertEqual(LocateVoiceCommand.parse("嗯就是这里吧"), .confirm)   // trailing filler trimmed
    }
}

// The selected-channel ink highlight: brightens the stroke's visible materials toward the meridian
// hue and back, while never touching the invisible hit-proxy tubes (colorBufferWriteMask empty).
final class ChannelHighlightTests: XCTestCase {
    private func channelNode() -> (node: SCNNode, core: SCNMaterial, halo: SCNMaterial, proxy: SCNMaterial) {
        // Core: opaque-ish, no emission. Halo: emissive wash. Proxy: invisible (no color writes).
        let core = SCNMaterial(); core.lightingModel = .constant
        core.diffuse.contents = UIColor(BodyAtlas.inkSwatch)
        let halo = SCNMaterial(); halo.lightingModel = .constant
        halo.diffuse.contents = UIColor(BodyAtlas.inkSwatch)
        halo.emission.contents = UIColor(BodyAtlas.inkSwatch); halo.emission.intensity = 0.6
        let proxy = SCNMaterial(); proxy.colorBufferWriteMask = []
        proxy.diffuse.contents = UIColor.magenta   // sentinel: must never change

        let node = SCNNode()
        func tube(_ m: SCNMaterial) -> SCNNode {
            let n = SCNNode(geometry: SCNCylinder(radius: 0.003, height: 0.05)); n.geometry?.firstMaterial = m; return n
        }
        node.addChildNode(tube(core)); node.addChildNode(tube(halo)); node.addChildNode(tube(proxy))
        return (node, core, halo, proxy)
    }

    func testHighlightBrightensVisibleMaterialsAndSkipsProxy() {
        let c = channelNode()
        let hue = UIColor(MeridianColors.color("sj"))

        BodyAtlas.setChannelHighlight([c.node], meridian: "sj", on: true)
        XCTAssertEqual(c.core.diffuse.contents as? UIColor, hue, "core stroke must take the meridian hue")
        XCTAssertEqual(c.halo.diffuse.contents as? UIColor, hue, "halo must take the meridian hue")
        XCTAssertEqual(c.halo.emission.contents as? UIColor, hue, "halo wash emission must take the hue")
        XCTAssertGreaterThan(c.halo.emission.intensity, 0.6, "highlight raises the wash emission")
        XCTAssertEqual(c.proxy.diffuse.contents as? UIColor, .magenta, "invisible hit-proxy must be untouched")

        BodyAtlas.setChannelHighlight([c.node], meridian: "sj", on: false)
        XCTAssertNotEqual(c.core.diffuse.contents as? UIColor, hue, "reset returns the core to ink")
        XCTAssertEqual(c.halo.emission.intensity, 0.6, accuracy: 1e-6, "reset returns the wash emission")
        XCTAssertEqual(c.proxy.diffuse.contents as? UIColor, .magenta)
    }
}
