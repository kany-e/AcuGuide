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

// THE ANTI-DRIFT GUARANTEE for the on-screen command list.
//
// VoiceCommandsView shows the user literal phrases, and it builds them from LocateVoiceCommand's
// own tables rather than retyping them — so a table edit updates the sheet automatically. What that
// does NOT cover is a phrase being added to a table that the PARSER then refuses (the Chinese
// filler-stripping already killed two silently: 好了 reduces to 好 and 可以了 to 可以, so both were
// dead entries before StudyVoiceCommandTests caught them). Advertising a phrase the app will not
// act on is worse than not advertising it, so every entry we display must parse to its own command.
final class VoiceCommandTableTests: XCTestCase {
    func testEveryAdvertisedPhraseParsesToItsOwnCommand() {
        let tables: [(String, [String], LocateVoiceCommand)] = [
            ("confirmEn", LocateVoiceCommand.confirmEn, .confirm),
            ("confirmZh", LocateVoiceCommand.confirmZh, .confirm),
            ("studyEn",   LocateVoiceCommand.studyEn,   .study),
            ("studyZh",   LocateVoiceCommand.studyZh,   .study),
            ("resumeEn",  LocateVoiceCommand.resumeEn,  .resume),
            ("resumeZh",  LocateVoiceCommand.resumeZh,  .resume),
            ("skip",      ["skip", "跳过"],              .skip),
            ("helpEn",    LocateVoiceCommand.helpEn,   .help),
            ("helpZh",    LocateVoiceCommand.helpZh,   .help),
        ]
        for (name, phrases, expected) in tables {
            XCTAssertFalse(phrases.isEmpty, "\(name) is empty — the sheet would show a command with no phrases")
            for phrase in phrases {
                XCTAssertEqual(LocateVoiceCommand.parse(phrase), expected,
                               "\(name): the sheet advertises \"\(phrase)\" but the parser does not accept it")
            }
        }
    }

    // The tables must not collide either: a phrase that parses as two different commands would make
    // the sheet a lie about at least one of them.
    func testNoPhraseIsClaimedByTwoCommands() {
        var seen: [String: LocateVoiceCommand] = [:]
        let all: [([String], LocateVoiceCommand)] = [
            (LocateVoiceCommand.confirmEn, .confirm), (LocateVoiceCommand.confirmZh, .confirm),
            (LocateVoiceCommand.studyEn, .study),     (LocateVoiceCommand.studyZh, .study),
            (LocateVoiceCommand.resumeEn, .resume),   (LocateVoiceCommand.resumeZh, .resume),
            (LocateVoiceCommand.helpEn, .help),       (LocateVoiceCommand.helpZh, .help),
        ]
        for (phrases, cmd) in all {
            for p in phrases {
                if let other = seen[p], other != cmd {
                    XCTFail("\"\(p)\" is listed under both \(other) and \(cmd)")
                }
                seen[p] = cmd
            }
        }
    }
}


// "show me what to say" and "show me" are one word apart, and one opens a list while the other
// freezes the camera. English matching is anchored to the TRAILING tokens, so only an utterance
// ENDING in "show me" is a study request — but that is a property worth pinning rather than
// remembering, because a single reordering of the parse would silently swap the two.
extension VoiceCommandTableTests {
    func testHelpAndStudyDoNotSwallowEachOther() {
        XCTAssertEqual(LocateVoiceCommand.parse("show me what to say"), .help)
        XCTAssertEqual(LocateVoiceCommand.parse("okay show me"), .study)
        XCTAssertEqual(LocateVoiceCommand.parse("hey what can i say"), .help)
        XCTAssertEqual(LocateVoiceCommand.parse("能说什么"), .help)
        XCTAssertEqual(LocateVoiceCommand.parse("怎么找"), .study)
        // And the negation guard still applies to the new command.
        XCTAssertNil(LocateVoiceCommand.parse("dont show commands"))
    }
}

// THE GATE THAT SWALLOWED NEARLY EVERY COMMAND.
//
// Device report: "voice recognition only works for 就是这里, and you have to say it very slow." The
// first half was not a recognition failure at all — commands were being recognised correctly and
// then DISCARDED. The old gate ignored all recognition while CoachVoice was speaking (plus a 0.6 s
// tail), and `.ready` is the one cue withheld while the mic is open (Speech.updateLocate), so the
// only quiet window in the whole locate step was the moment 就是这里 is said. Every other phrase
// landed inside a 1.8-5.0 s spoken cue and was dropped.
//
// The decision now lives in a pure function precisely so this can be pinned.
final class LocateVoiceGateTests: XCTestCase {
    private func decide(_ transcript: String, saying: String? = nil, lastKind: LocateVoiceCommand? = nil,
                        since: TimeInterval = 99, firedAt: Int = 0,
                        blanket: Bool = false) -> LocateVoiceCommand? {
        LocateVoiceGate.decide(transcript: transcript, firedAtLength: firedAt, lastKind: lastKind,
                               sinceLastFire: since, appSaying: saying, blanketMute: blanket)?.kind
    }

    // THE REGRESSION. Each of these is spoken while the coach is mid-cue; all of them used to be
    // thrown away, which is why only the one said during the silent .ready state ever worked.
    func testUserCanBargeInOverACueTheAppIsSpeaking() {
        let cue = "有点远了，回到虚线圈附近。"          // .offGuide — 3 s of speech
        XCTAssertEqual(decide("怎么找", saying: cue), .study)
        XCTAssertEqual(decide("跳过", saying: cue), .skip)
        XCTAssertEqual(decide("能说什么", saying: cue), .help)
        XCTAssertEqual(decide("就是这里", saying: cue), .confirm)
    }

    // …but the app still must not act on its OWN voice. The coach's .onTargetUnstable line literally
    // contains 就是这里, so this is not hypothetical: without the echo check the app would confirm
    // the spot for the user the moment it said "就是这里，轻轻稳住".
    func testTheAppsOwnWordsAreStillRejected() {
        XCTAssertNil(decide("就是这里", saying: "就是这里，轻轻稳住。"))
        XCTAssertNil(decide("就是这里轻轻稳住", saying: "就是这里，轻轻稳住。"))
        XCTAssertNil(decide("thats it", saying: "That's it — settle in."))
        // Punctuation must not let the echo through — both sides are normalized the same way.
        XCTAssertNil(decide("就是这里", saying: "就是这里"))
    }

    // A DIFFERENT command is new intent, not a repeat. The old single global debounce meant 找到了 —
    // which parses as .resume and does NOTHING when no frame is frozen — burned the 2 s window and
    // blocked the 就是这里 said right after it.
    func testADifferentCommandIsNotDebouncedBehindASilentNoOp() {
        XCTAssertEqual(decide("就是这里", lastKind: .resume, since: 0.4), .confirm)
        XCTAssertNil(decide("继续", lastKind: .resume, since: 0.4), "a repeat of the same kind still damps")
        XCTAssertEqual(decide("继续", lastKind: .resume, since: 3.0), .resume, "…and clears after the window")
    }

    // The commands sheet has no single spoken line — VoiceOver may read any of the phrases printed
    // on it — so that one caller keeps the blunt gate.
    func testBlanketMuteStillSuppressesEverything() {
        XCTAssertNil(decide("就是这里", blanket: true))
        XCTAssertNil(decide("skip", blanket: true))
    }

    // Consume-once: the transcript is cumulative within a task, so a command must not re-fire on
    // every subsequent partial result.
    func testACommandDoesNotRefireOnTheSameTranscript() {
        XCTAssertNil(decide("就是这里", firedAt: 4))
        XCTAssertEqual(decide("就是这里跳过", firedAt: 4), .skip)
    }

    // The lexical prior handed to the recognizer must be exactly what the parser can act on —
    // biasing it toward a phrase the parser rejects would make the app hear a command and ignore it.
    func testEveryContextualStringParses() {
        for p in LocateVoiceCommand.allPhrases {
            XCTAssertNotNil(LocateVoiceCommand.parse(p), "\(p) is offered to the recognizer but does not parse")
        }
        XCTAssertFalse(LocateVoiceCommand.allPhrases.isEmpty)
    }
}
