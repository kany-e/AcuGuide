import XCTest
import SceneKit
@testable import AcuGuide

// Phase 0 smoke test — proves the test target builds and links against the app.
// Phase 3 replaces/extends this with the fixture-driven CoachEngine timeline tests.
final class AcuGuideTests: XCTestCase {
    // Several tests assert English copy (e.g. "Lung Meridian", "professional"). AppLocale follows
    // AppSettings.lang, which defaults to the device/simulator locale and persists — so on a Chinese
    // simulator those assertions would see Chinese copy and fail. Pin English here so the suite is
    // deterministic regardless of the ambient locale (the logic under test is locale-independent).
    override func setUp() {
        super.setUp()
        AppSettings.shared.lang = .en
    }

    // The AR-coached set = the 8 documented hand/wrist points (TE3 + the others, sourced to WHO 2008).
    // Every coachable point must have anchor weights summing > 0 (weightedTarget divides by the sum),
    // and LI4 must never be coachable.
    func testARCoachedPointsAreTheDocumentedHandSet() {
        let ar = Set(Acupoint.all.filter { $0.mediapipeTarget != nil }.map(\.id))
        XCTAssertEqual(ar, ["TE3", "SI3", "PC8", "HT7", "PC6", "SJ5", "TE4", "PC7"],
                       "AR-coached points are the 8 documented hand/wrist points.")
        XCTAssertFalse(ar.contains("LI4"), "LI4 must never be coachable.")
        for p in Acupoint.all where p.mediapipeTarget != nil {
            let total = p.mediapipeTarget!.anchors.reduce(0) { $0 + $1.weight }
            XCTAssertGreaterThan(total, 0, "\(p.id) anchor weights must sum > 0.")
        }
    }

    // A symptom query surfaces practiceable (AR-coachable) suggestions the chat UI turns into
    // "Practice with camera" buttons; a red-flag query must NOT offer any.
    func testChatSuggestsPracticePointForSymptom() async {
        let a = await ChatService().reply(to: "I have a tension headache", history: [])
        XCTAssertTrue(a.suggestions.contains { $0.id == "TE3" },
                      "a headache query should suggest TE3; got: \(a.suggestions.map(\.id))")
        XCTAssertTrue(a.suggestions.allSatisfy { $0.mediapipeTarget != nil },
                      "all suggestions must be AR-coachable.")
        let danger = await ChatService().reply(to: "I have a sudden severe headache", history: [])
        XCTAssertTrue(danger.suggestions.isEmpty, "a red-flag query must not offer practice buttons.")
    }

    func testLI4IsExcluded() {
        XCTAssertFalse(Acupoint.all.contains { $0.id == "LI4" },
                       "LI4 is pregnancy-contraindicated and must never appear.")
    }

    // The immutable rule: no treat / cure / heal / diagnose anywhere in user-facing copy.
    // Scans the whole bilingual atlas + the reference side tables + meridian descriptions
    // (the datasets most likely to drift on edits). "heal" ⊂ "health", so this also forbids
    // "health"/"healthcare" — copy says "wellness" / "medical professional" instead.
    func testNoForbiddenMedicalClaims() {
        let banned = ["treat", "cure", "heal", "diagnos"]
        func check(_ label: String, _ strings: [String]) {
            let blob = strings.joined(separator: " ").lowercased()
            for term in banned {
                XCTAssertFalse(blob.contains(term), "\(label) copy contains forbidden term '\(term)'")
            }
        }
        for p in Acupoint.all {
            check(p.id, [p.locationEn, p.indicationsEn, p.coachAlign, p.coachHold,
                         p.locationZh, p.indicationsZh, p.roleEn, p.roleZh, p.englishName])
        }
        // Per-point AR cue table (the 7 non-TE3 coachable points get their cues from here).
        for (id, c) in Acupoint.coachCues { check("coachCues[\(id)]", [c.alignEn, c.holdEn, c.alignZh, c.holdZh]) }
        // Meridian descriptions (rewritten from the Atlas of Acupuncture Points pathways).
        for m in Meridian.all { check(m.id, [m.descEn, m.descZh]) }
    }

    // Offline chat: a red-flag question (even one naming a point) must route to stop-and-seek-care,
    // not to a normal how-to-press reply. (Sim locale is en → English copy.)
    func testChatRedFlagRoutesToSafetyReply() async {
        let reply = await ChatService().reply(to: "I'm pregnant, is SI3 ok to press?", history: []).text
        XCTAssertTrue(reply.lowercased().contains("professional"),
                      "red-flag question must route to the stop-and-seek-care reply; got: \(reply)")
    }

    // Offline chat: a Chinese phrase that merely embeds a 2-char point name must NOT be matched
    // as that point (外关 inside 对外关系 / 内关 inside 国内关系).
    func testChatDoesNotFalseMatchChineseProse() async {
        let reply = await ChatService().reply(to: "国内关系", history: []).text
        // A point DETAIL reply contains "Location:"; the general greeting (which lists points as
        // examples) does not. The embedded 内关 must fall through to the greeting, not a PC6 detail.
        XCTAssertFalse(reply.contains("Location:"),
                       "embedded Chinese substring must not yield a point detail reply; got: \(reply)")
    }

    // Meridian matching must not misfire on ordinary Chinese prose: "我胃经常痛" (my stomach often
    // aches) embeds 胃经 inside 胃经常, and must NOT be read as the Stomach meridian — while a real
    // channel name ("肺经") still resolves. (Sim locale en → English copy; meridianReply says
    // "<Name> Meridian (…)", the greeting says "fourteen meridians".)
    func testChatMeridianMatchAvoidsChineseProse() async {
        let prose = await ChatService().reply(to: "我胃经常痛", history: []).text
        XCTAssertFalse(prose.contains("Stomach Meridian"),
                       "prose embedding <organ>经 must not yield a meridian card; got: \(prose)")
        let real = await ChatService().reply(to: "肺经", history: []).text
        XCTAssertTrue(real.contains("Lung Meridian"),
                      "a real channel name should resolve to its meridian; got: \(real)")
    }

    // Face locator covers only FACE-VISIBLE head points (Yintang/Taiyang); they are real head-region
    // atlas points and are not hand-AR-coached. Vertex points (Baihui/Sishencong) are excluded.
    func testFaceLocatablePointsAreVisibleHeadPoints() {
        XCTAssertEqual(FaceAcupoints.locatableIDs, ["EX-HN3", "EX-HN5"])
        for id in FaceAcupoints.locatableIDs {
            let p = Acupoint.byId[id]
            XCTAssertNotNil(p, "\(id) must exist in the atlas")
            XCTAssertEqual(p?.region, "head", "\(id) must be a head-region point")
            XCTAssertNil(p?.mediapipeTarget, "\(id) is a face-locator point, not a hand AR target")
        }
        XCTAssertFalse(FaceAcupoints.isLocatable("GV20"), "Baihui (vertex) is not front-face-visible")
        XCTAssertFalse(FaceAcupoints.isLocatable("TE3"), "hand points are not face-locatable")
    }

    // Torso locator covers the abdomen midline points (Zhongwan/Tianshu) placed by the cun grid.
    func testTorsoLocatablePointsAreAbdomenPoints() {
        XCTAssertEqual(TorsoAcupoints.locatableIDs, ["CV12", "ST25"])
        for id in TorsoAcupoints.locatableIDs {
            let p = Acupoint.byId[id]
            XCTAssertNotNil(p, "\(id) must exist in the atlas")
            XCTAssertEqual(p?.region, "abdomen", "\(id) must be an abdomen-region point")
        }
        XCTAssertFalse(TorsoAcupoints.isLocatable("TE3"), "hand points are not torso-locatable")
    }

    // M1 shadow-mode: the learned CoreML head, run through the app's ShadowLocalizer on a synthetic
    // full hand, must reproduce the affine `weightedTarget` for all 8 coachable points to well under a
    // pixel (delta in handSize units). Proves the in-app learned path + coordinate conventions match the
    // trained head (no train/serve skew) — the no-regression floor, verified on Apple's own stack.
    func testLearnedHeadMatchesAffineAnchors() {
        let base: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
            .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
            .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
            .thumbTip: CGPoint(x: 0.34, y: 0.62)]
        guard ShadowLocalizer.shared.isAvailable else { XCTFail("AcupointHead model not bundled/loadable"); return }
        // Test BOTH handedness — the left case exercises the chirality fold (mirror base x + .left),
        // matching how train.py generated left hands. (Live front-camera mirror vs Vision chirality is
        // the one thing only the on-device shadow log can confirm — hence shadow mode before cut-over.)
        let hands: [(String, Hand)] = [
            ("right", Hand(points: base, chirality: .right)),
            ("left",  Hand(points: base.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) }, chirality: .left)),
        ]
        for (label, hand) in hands {
            for (pid, id) in ShadowLocalizer.points.enumerated() {
                guard let anchors = Acupoint.byId[id]?.mediapipeTarget?.anchors,
                      let affine = hand.weightedTarget(anchors),
                      let learned = ShadowLocalizer.shared.predict(hand: hand, pointId: pid)?.target else {
                    XCTFail("\(id): could not compute learned/affine target"); continue }
                let d = Double(hypot(learned.x - affine.x, learned.y - affine.y)) / Double(hand.handSize)
                print(String(format: "shadow-test %@ %@: Δ=%.5f handSizes", label, id, d))
                XCTAssertLessThan(d, 0.02, "\(label) \(id) learned head diverges from the affine anchor by \(d) handSizes")
            }
        }
    }

    // SHADOW LOG, captured offline: replays the LIVE front-camera convention (CameraCoach.buildHand
    // x-mirrors EVERY landmark for the selfie preview while chirality stays anatomical) and records the
    // two shadow deltas per point — exactly what the on-device os_log would print, but deterministic and
    // without a device/hand. Confirms the review's finding: `asis` (the naive live path) is systematically
    // off, `unmirror` ≈ 0 → the fix at cut-over is to feed the head un-mirrored (anatomical) coords.
    func testShadowLiveMirrorConventionCapture() {
        let anatomical: [HandJoint: CGPoint] = [   // a right hand as train.py saw it (unmirrored)
            .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55), .middleMCP: CGPoint(x: 0.50, y: 0.52),
            .ringMCP: CGPoint(x: 0.56, y: 0.54), .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .indexTip: CGPoint(x: 0.42, y: 0.30),
            .middleTip: CGPoint(x: 0.50, y: 0.27), .ringTip: CGPoint(x: 0.58, y: 0.30), .pinkyTip: CGPoint(x: 0.66, y: 0.36),
            .thumbTip: CGPoint(x: 0.34, y: 0.62)]
        guard ShadowLocalizer.shared.isAvailable else { XCTFail("model not bundled"); return }
        // LIVE right hand in the mirrored selfie: buildHand mirrors x on every joint; chirality stays .right.
        let live = Hand(points: anatomical.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) }, chirality: .right)
        print("── shadow capture (LIVE front-camera convention) ── handSizes ──")
        var meanAsis = 0.0, meanUnmir = 0.0, cnt = 0.0
        for (pid, id) in ShadowLocalizer.points.enumerated() {
            guard let anchors = Acupoint.byId[id]?.mediapipeTarget?.anchors,
                  let affine = live.weightedTarget(anchors),
                  let asis = ShadowLocalizer.shared.predict(hand: live, pointId: pid, mirrorInput: false)?.target,
                  let unmir = ShadowLocalizer.shared.predict(hand: live, pointId: pid, mirrorInput: true)?.target else {
                XCTFail("\(id): compute failed"); continue }
            let dA = Double(hypot(asis.x - affine.x, asis.y - affine.y)) / Double(live.handSize)
            let dU = Double(hypot(unmir.x - affine.x, unmir.y - affine.y)) / Double(live.handSize)
            print(String(format: "capture %@: asis=%.4f  unmirror=%.4f", id, dA, dU))
            meanAsis += dA; meanUnmir += dU; cnt += 1
        }
        meanAsis /= cnt; meanUnmir /= cnt
        print(String(format: "MEAN: asis=%.4f  unmirror=%.4f handSizes → %@", meanAsis, meanUnmir,
                     meanUnmir < meanAsis ? "un-mirroring is the live-correct convention" : "asis is correct"))
        // Lock in the finding: on live selfie inputs, the un-mirrored path matches the affine target and
        // the naive as-is path does not. If this ever flips, the mirror assumption changed.
        XCTAssertLessThan(meanUnmir, 0.01, "un-mirrored learned target should match the affine target on live inputs")
        XCTAssertGreaterThan(meanAsis, meanUnmir, "the naive as-is path should be worse on mirrored live inputs")
    }

    // The detailed-view marker placement (AtlasMarkers.screenMarker) must land dots ON the model,
    // regardless of pose. Pure geometry now, so it's unit-testable: a unit box at the origin, camera at
    // (0,0,2.4). Center → front face (z≈+0.5); farSide → back face (z≈−0.5); u>0 → right of centre.
    func testScreenMarkerLandsOnMesh() {
        let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        let scene = SCNScene(); scene.rootNode.addChildNode(box)   // hit-testing needs scene membership
        guard let front = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0, v: 0, farSide: false,
                                                    id: "F", color: .red, core: 0.02, halo: 0.03) else {
            XCTFail("center marker should land on the box"); return }
        XCTAssertEqual(Float(front.position.z), 0.5, accuracy: 0.06, "centre hits the front face")
        XCTAssertEqual(Float(front.position.x), 0, accuracy: 0.06)
        XCTAssertEqual(Float(front.position.y), 0, accuracy: 0.06)
        let back = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0, v: 0, farSide: true,
                                             id: "B", color: .red, core: 0.02, halo: 0.03)
        XCTAssertEqual(Float(back!.position.z), -0.5, accuracy: 0.06, "farSide hits the back face")
        let right = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0.3, v: 0, farSide: false,
                                              id: "R", color: .red, core: 0.02, halo: 0.03)
        XCTAssertGreaterThan(Float(right!.position.x), 0.1, "u=+0.3 lands right of centre")
    }

    // "number" contains "numb" — whole-word matching must NOT trip the red-flag screen.
    func testChatBenignWordIsNotRedFlag() async {
        let reply = await ChatService().reply(to: "What is the number for TE3?", history: []).text
        XCTAssertFalse(reply.lowercased().contains("seeing a professional"),
                       "a benign word must not route to the red-flag reply; got: \(reply)")
    }

    // M3 label harness: the inverse aspect-fill map MUST exactly undo the forward map, or every tapped
    // label is silently offset from the joints it's paired with (train/serve skew via the label itself).
    func testLocatorFillRoundTrips() {
        let size = CGSize(width: 390, height: 844)
        let fa: CGFloat = 9.0 / 16.0
        for n in [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.88, y: 0.12)] {
            let screen = locatorMapFill(n, in: size, frameAspect: fa)
            let back = locatorInverseFill(screen, in: size, frameAspect: fa)
            XCTAssertEqual(Double(back.x), Double(n.x), accuracy: 1e-6, "inverse must undo forward (x)")
            XCTAssertEqual(Double(back.y), Double(n.y), accuracy: 1e-6, "inverse must undo forward (y)")
        }
    }

    // A collected label must JSON round-trip with every field intact (the training pipeline reads this JSONL).
    func testLabelRecordRoundTrips() throws {
        let rec = LabelRecord(v: 1, pointId: "TE3", chirality: "right", handSize: 0.12,
                              joints: ["wrist": [0.5, 0.8], "middleMCP": [0.5, 0.52]],
                              confidence: ["wrist": 0.98, "middleMCP": 0.91],
                              target: [0.44, 0.30], affine: [0.45, 0.31], mirrored: true,
                              ts: 1_700_000_000, session: "sess", image: "a.jpg")
        let back = try JSONDecoder().decode(LabelRecord.self, from: JSONEncoder().encode(rec))
        XCTAssertEqual(back.pointId, "TE3")
        XCTAssertEqual(back.joints["wrist"], [0.5, 0.8])
        XCTAssertEqual(back.target, [0.44, 0.30])
        XCTAssertEqual(back.affine, [0.45, 0.31])
        XCTAssertTrue(back.mirrored)
    }
}
