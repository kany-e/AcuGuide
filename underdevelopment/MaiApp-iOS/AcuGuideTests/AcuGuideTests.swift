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
    // AppSettings.lang's didSet persists into the HOST APP's real UserDefaults — restore the
    // pre-test value in tearDown so running the suite doesn't flip the simulator app to English
    // for a Chinese-locale user (review-caught pollution).
    private var priorLang: AppSettings.Lang = .en

    override func setUp() {
        super.setUp()
        priorLang = AppSettings.shared.lang
        AppSettings.shared.lang = .en
        // Pin the chat's deterministic paths: no default on-device generator in tests (a host sim
        // MAY have Apple Intelligence, which would make the free-form fallback nondeterministic).
        // LLM behavior is tested separately with an injected mock (ChatLLMTests).
        ChatService.defaultGeneratorEnabled = false
    }

    override func tearDown() {
        AppSettings.shared.lang = priorLang
        super.tearDown()
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

    // Every camera-coached point must offer the find-it-by-feel locate step (it gates entry to the
    // camera), and both languages must be non-empty.
    func testCoachedPointsAllHaveAFindGuide() {
        for p in Acupoint.all where p.mediapipeTarget != nil {
            XCTAssertTrue(p.hasFindGuide, "\(p.id) is camera-coached but has no locate-step guide")
            AppSettings.shared.lang = .en
            XCTAssertFalse(p.findHow.isEmpty || p.findFeel.isEmpty, "\(p.id) EN find text empty")
            AppSettings.shared.lang = .zh
            XCTAssertFalse(p.findHow.isEmpty || p.findFeel.isEmpty, "\(p.id) ZH find text empty")
            AppSettings.shared.lang = .en
        }
    }

    func testLI4IsExcluded() {
        XCTAssertFalse(Acupoint.all.contains { $0.id == "LI4" },
                       "LI4 is pregnancy-contraindicated and must never appear.")
    }

    // The 3D-placement registry (AcupointPlacements) must stay LOCKED to the atlas — every consumer
    // is a guard-let/compactMap that silently skips a mismatch, so without these pins a typo'd or
    // renamed key just makes a marker vanish while the suite stays green (review-caught):
    // (1) every registry key resolves to a real point; (2) the full-body atlas keeps all 27 markers;
    // (3) hand-sheet farSide mirrors the point's palmar surface (it was structurally derived as
    // !requiresDorsal before R14.3 baked it; arm/foot sheets legitimately differ — requiresDorsal is
    // a hand-AR concept — so this is pinned for the hand only).
    func testPlacementRegistryLockedToAtlas() {
        for key in AcupointPlacements.table.keys {
            XCTAssertNotNil(Acupoint.byId[key], "registry key '\(key)' matches no atlas point — renamed or typo'd?")
        }
        XCTAssertEqual(BodyAtlas.acuMarkers.count, 27,
                       "full-body atlas marker count changed — a body: entry was dropped or mis-keyed")
        for pt in Acupoint.all where pt.region == "hand" {
            guard let p = AcupointPlacements.table[pt.id], p.detailUV != nil else { continue }
            XCTAssertEqual(p.detailFarSide, !pt.requiresDorsal,
                           "\(pt.id): hand-sheet farSide must sit on the point's own surface (palmar ⇔ far side)")
        }
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
                         p.locationZh, p.indicationsZh, p.roleEn, p.roleZh, p.englishName,
                         p.cautionEn, p.cautionZh])   // caution is user-facing (atlas detail cards) too
        }
        // Per-point AR cue table (the 7 non-TE3 coachable points get their cues from here).
        for (id, c) in Acupoint.coachCues { check("coachCues[\(id)]", [c.alignEn, c.holdEn, c.alignZh, c.holdZh]) }
        // Plain-language locate-step guide (shown before the camera).
        for (id, g) in Acupoint.findGuide { check("findGuide[\(id)]", [g.findEn, g.feelEn, g.findZh, g.feelZh]) }
        // Meridian descriptions (rewritten from the Atlas of Acupuncture Points pathways).
        for m in Meridian.all { check(m.id, [m.descEn, m.descZh]) }
        // Runtime-reachable copy beyond the datasets (the scan used to cover only the atlas
        // tables, so view copy could drift unchecked). View-local literals still aren't
        // enumerable at runtime — this covers every shared/static source of user-facing text.
        for r in Routine.all { check("routine[\(r.id)]", [r.zh, r.en, r.descZh, r.descEn]) }
        for f in ChatService.faqs { check("faq[\(f.topic)]", [f.aZh, f.aEn]) }
        check("persona", [CoachPersona.name])
        // (ChatLLM.instructions() is deliberately NOT scanned: it QUOTES the banned words to
        // forbid them to the model, and it is model-facing, not user-facing — ChatSafety.allowed
        // enforces the rule on what the model actually says.)
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
    // full hand, must reproduce the affine `weightedTarget` for the 7 text-derived coachable points to
    // well under a pixel (delta in handSize units); TE3 — whose affine anchor is now label-fitted while
    // the head was distilled from the OLD anchor — gets a LOOSE sanity bound instead (expected ~0.22,
    // asserted < 0.5 so a NaN/wild pid-path regression still fails). Proves the in-app learned path +
    // coordinate conventions match the trained head (no train/serve skew). Retrain the head on the
    // owned labels, then tighten TE3 back to 0.02.
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
                // TE3's affine anchor was re-fitted from owned expert labels (R14.1 — ring .11 /
                // pinky .47 / wrist .42; see Acupoints.swift), so the head — distilled from the OLD
                // anchor — deliberately diverges there by ~0.22 handSizes (the size of the label
                // correction). A LOOSE bound keeps its pid path exercised (NaN / wild-coordinate
                // regressions still fail); tighten back to 0.02 once the head is retrained.
                let bound = (id == "TE3") ? 0.5 : 0.02
                XCTAssertLessThan(d, bound, "\(label) \(id) learned head diverges from the affine anchor by \(d) handSizes")
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
            // TE3 excluded from the MEANS: its affine anchor is label-fitted (R14.1), so
            // head-vs-affine parity no longer holds there. Its pid path stays exercised by the
            // loose bound in testLearnedHeadMatchesAffineAnchors.
            if id == "TE3" { continue }
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
        // screenMarker raycasts against the mesh's OWN triangles (CPU Möller–Trumbore) — it no
        // longer depends on SceneKit render state, so this offscreen harness exercises the REAL
        // surface path (onSurface == true), not a fallback.
        let box = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
        let scene = SCNScene(); scene.rootNode.addChildNode(box)
        guard let front = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0, v: 0, farSide: false,
                                                    id: "F", color: .red, core: 0.02, halo: 0.03) else {
            XCTFail("center marker should land on the box"); return }
        XCTAssertTrue(front.onSurface, "the CPU raycast must hit the box's real surface")
        XCTAssertEqual(Float(front.node.position.z), 0.5, accuracy: 0.06, "centre → front plane")
        XCTAssertEqual(Float(front.node.position.x), 0, accuracy: 0.06)
        XCTAssertEqual(Float(front.node.position.y), 0, accuracy: 0.06)
        let back = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0, v: 0, farSide: true,
                                             id: "B", color: .red, core: 0.02, halo: 0.03)
        XCTAssertEqual(Float(back!.node.position.z), -0.5, accuracy: 0.06, "farSide → back plane")
        let right = AtlasMarkers.screenMarker(cameraZ: 2.4, mesh: box, u: 0.3, v: 0, farSide: false,
                                              id: "R", color: .red, core: 0.02, halo: 0.03)
        XCTAssertGreaterThan(Float(right!.node.position.x), 0.1, "u=+0.3 lands right of centre")
    }

    // "number" contains "numb" — whole-word matching must NOT trip the red-flag screen.
    func testChatBenignWordIsNotRedFlag() async {
        let reply = await ChatService().reply(to: "What is the number for TE3?", history: []).text
        XCTAssertFalse(reply.lowercased().contains("seeing a professional"),
                       "a benign word must not route to the red-flag reply; got: \(reply)")
    }

    // Natural symptom phrasings that contain no fixed keyword must still match via co-occurrence
    // pairs ("I'm feeling pain in my head" was user-reported falling through to the greeting).
    func testChatSymptomPhrasingVariants() async {
        for q in ["I'm feeling pain in my head", "my head hurts", "我头很痛"] {
            let a = await ChatService().reply(to: q, history: [])
            XCTAssertTrue(a.suggestions.contains { $0.id == "TE3" },
                          "'\(q)' should suggest TE3; got \(a.suggestions.map(\.id))")
        }
        // Word boundaries: fragments inside unrelated words must not match a pair half and shadow
        // the correct group ('headed' is not 'head' — this went to the headache group before).
        let wrist = await ChatService().reply(to: "I was headed home and now my wrist hurts", history: [])
        XCTAssertTrue(wrist.suggestions.contains { $0.id == "TE4" },
                      "a wrist complaint must reach the wrist group; got \(wrist.suggestions.map(\.id))")
        XCTAssertFalse(wrist.suggestions.contains { $0.id == "TE3" },
                       "'headed' must not read as a headache")
    }

    // The press-tip estimator — RAW tip first (device-confirmed it tracks the intended massage point
    // best; a pressing finger is bent, so extrapolation overshoots); the distal-segment rebuild is
    // ONLY the total-dropout fallback AND reports confidence 0 (an unmeasured guess must never start
    // an engagement — the palm-glaze gate keys off this); nil when the finger isn't tracked at all.
    func testPressTipPrefersRawTipAndFallsBackOnDropout() {
        var pts: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: 0.5, y: 0.8), .indexTip: CGPoint(x: 0.30, y: 0.30),
            .indexDIP: CGPoint(x: 0.40, y: 0.40), .indexPIP: CGPoint(x: 0.44, y: 0.46)]
        // Tip present — even at LOW confidence the raw tip wins, and it reports ITS OWN confidence
        // so the engagement gate can still reject it.
        let low = Hand(points: pts, chirality: .right,
                       confidence: [.indexTip: 0.35, .indexDIP: 0.9, .indexPIP: 0.9])
        let m = low.pressTip(.indexTip)!
        XCTAssertEqual(m.point, pts[.indexTip], "present tip always wins")
        XCTAssertEqual(m.confidence, 0.35, "the measurement carries the tip's own confidence")

        // Tip fully dropped → rebuild from the distal segment, at confidence 0.
        pts[.indexTip] = nil
        let dropped = Hand(points: pts, chirality: .right, confidence: [.indexDIP: 0.9, .indexPIP: 0.9])
        let t = dropped.pressTip(.indexTip)!
        XCTAssertEqual(Double(t.point.x), 0.40 + 0.9 * (0.40 - 0.44), accuracy: 1e-9,
                       "missing tip → extend the DIP−PIP segment")
        XCTAssertEqual(Double(t.point.y), 0.40 + 0.9 * (0.40 - 0.46), accuracy: 1e-9)
        XCTAssertEqual(t.confidence, 0, "a reconstructed tip is an unmeasured guess — must not gate as reliable")

        // Nothing tracked on the finger → nil (the tip-grace path handles the gap).
        pts[.indexDIP] = nil; pts[.indexPIP] = nil
        let bare = Hand(points: pts, chirality: .right)
        XCTAssertNil(bare.pressTip(.indexTip))

        // Fixture hands (no confidence dict) read as reliable — the validated paths are unchanged.
        let fixture = Hand(points: [.indexTip: CGPoint(x: 0.3, y: 0.3)], chirality: .right)
        XCTAssertEqual(fixture.pressTip(.indexTip)?.confidence, 1)
    }

    // The inverted-pass remap must be exact: a landmark detected in the 180°-rotated frame maps to
    // the SAME final coordinate as the identical landmark detected upright — otherwise the merged
    // hands from the two Vision passes live in different spaces and the press dot/ring jump.
    func testInvertedPassRemapMatchesUprightMapping() {
        for flipX in [true, false] {
            for p in [CGPoint(x: 0.3, y: 0.7), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.05, y: 0.92)] {
                let upright = HandVision.normalize(p, rotated180: false, flipX: flipX)
                // The same physical location seen in the 180°-rotated buffer appears at (1−x, 1−y).
                let rotatedSeen = CGPoint(x: 1 - p.x, y: 1 - p.y)
                let mapped = HandVision.normalize(rotatedSeen, rotated180: true, flipX: flipX)
                XCTAssertEqual(Double(mapped.x), Double(upright.x), accuracy: 1e-12)
                XCTAssertEqual(Double(mapped.y), Double(upright.y), accuracy: 1e-12)
            }
        }
    }

    // isDorsal must give the SAME verdict for the same physical hand regardless of coordinate
    // parity: Vision's chirality never flips with our manual mirror, so the back camera's
    // un-mirrored coordinates negate the cross product — mirroredCoords must compensate
    // (back-camera two-person mode read palm/back BACKWARDS before this).
    func testIsDorsalIsParityInvariant() {
        let mirrored: [HandJoint: CGPoint] = [
            .wrist: CGPoint(x: 0.50, y: 0.80), .indexMCP: CGPoint(x: 0.44, y: 0.55),
            .pinkyMCP: CGPoint(x: 0.62, y: 0.58), .middleMCP: CGPoint(x: 0.50, y: 0.52)]
        let front = Hand(points: mirrored, chirality: .right)                       // selfie convention
        let back = Hand(points: mirrored.mapValues { CGPoint(x: 1 - $0.x, y: $0.y) },
                        chirality: .right, mirroredCoords: false)                   // same hand, rear camera
        XCTAssertNotNil(front.isDorsal)
        XCTAssertEqual(front.isDorsal, back.isDorsal,
                       "same physical hand must read the same face on front and back cameras")
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

// The on-device-LLM chat layer, tested with an injected mock so no Apple Intelligence device is
// needed: the safety shell around the model is what must hold, not the model itself.
final class ChatLLMTests: XCTestCase {
    final class MockGen: ChatGenerator {
        var isAvailable = true
        var reply: String
        private(set) var calls = 0
        init(reply: String) { self.reply = reply }
        func generate(query: String, history: [ChatMessage]) async throws -> String { calls += 1; return reply }
    }

    override func setUp() { super.setUp(); AppSettings.shared.lang = .en }

    // The red-flag screen runs BEFORE the model and can never be overridden by it.
    func testRedFlagNeverReachesModel() async {
        let mock = MockGen(reply: "should never be used")
        let a = await ChatService(generator: mock).reply(to: "I'm pregnant, is SI3 ok?", history: [])
        XCTAssertEqual(mock.calls, 0, "red-flag input must never reach the model")
        XCTAssertTrue(a.text.lowercased().contains("professional"))
    }

    // Deterministic lookups win over the model — a point query stays a validated card.
    func testDeterministicMatchSkipsModel() async {
        let mock = MockGen(reply: "should never be used")
        let a = await ChatService(generator: mock).reply(to: "TE3", history: [])
        XCTAssertEqual(mock.calls, 0, "a direct point lookup must not consult the model")
        XCTAssertTrue(a.text.contains("Location:"))
    }

    // Model output violating the banned-claim rule is rejected wholesale → canned general reply.
    func testBannedOutputFallsBackToCannedReply() async {
        let mock = MockGen(reply: "Pressing TE3 will cure your headache quickly.")
        let a = await ChatService(generator: mock).reply(to: "tell me something nice", history: [])
        XCTAssertEqual(mock.calls, 1)
        XCTAssertFalse(a.text.lowercased().contains("cure"), "banned output must never surface")
        XCTAssertTrue(a.text.contains("fourteen meridians"), "must fall back to the canned general reply")
    }

    // Clean model output surfaces with the on-device-AI label and mentioned points become buttons.
    func testCleanOutputIsLabeledAndSuggestsMentionedPoints() async {
        let mock = MockGen(reply: "Many people find a quiet PC6 press relaxing before travel.")
        let a = await ChatService(generator: mock).reply(to: "any calm ritual before a trip?", history: [])
        XCTAssertEqual(mock.calls, 1)
        XCTAssertTrue(a.text.contains("PC6 press relaxing"))
        XCTAssertTrue(a.text.contains("On-device AI"), "generative replies must be labeled")
        XCTAssertTrue(a.suggestions.contains { $0.id == "PC6" }, "mentioned coachable points become buttons")
    }

    // Chinese point names embedded in the model's PROSE must not become practice buttons
    // (内关 inside 国内关系) — the LLM mention scan matches ids/romanized names only.
    func testEmbeddedChineseNameInOutputIsNotSuggested() async {
        let mock = MockGen(reply: "处理国内关系带来的压力时，先放松肩颈，配合缓慢呼吸。")
        let a = await ChatService(generator: mock).reply(to: "tell me something nice", history: [])
        XCTAssertEqual(mock.calls, 1)
        XCTAssertFalse(a.suggestions.contains { $0.id == "PC6" },
                       "内关 embedded in 国内关系 must not attach a PC6 button")
    }

    // Generator unavailable (no Apple Intelligence / toggle off) → exactly the old behavior.
    func testUnavailableGeneratorFallsBack() async {
        let mock = MockGen(reply: "should never be used"); mock.isAvailable = false
        let a = await ChatService(generator: mock).reply(to: "tell me something nice", history: [])
        XCTAssertEqual(mock.calls, 0)
        XCTAssertTrue(a.text.contains("fourteen meridians"))
    }
}

// On-device practice history: persistence round-trip, feeling attachment, cap, and the streak rule.
final class PracticeStoreTests: XCTestCase {
    private func freshStore() -> PracticeStore {
        let d = UserDefaults(suiteName: "practice-tests-\(UUID().uuidString)")!
        return PracticeStore(defaults: d)
    }
    private func rec(_ id: String, daysAgo: Int = 0, point: String = "TE3") -> PracticeRecord {
        PracticeRecord(id: id, date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                       pointId: point, rounds: 2, roundsTarget: 4, heldS: 61, feeling: nil)
    }

    func testAddAndFeelingPersist() {
        let d = UserDefaults(suiteName: "practice-tests-persist")!
        d.removePersistentDomain(forName: "practice-tests-persist")
        let store = PracticeStore(defaults: d)
        store.add(rec("a"))
        store.setFeeling(id: "a", feeling: "relaxing")
        // A new store over the SAME defaults must read the record + feeling back.
        let reloaded = PracticeStore(defaults: d)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records.first?.feeling, "relaxing")
        XCTAssertEqual(reloaded.records.first?.pointId, "TE3")
    }

    func testCapKeepsNewest() {
        let store = freshStore()
        for i in 0..<310 { store.add(rec("r\(i)")) }
        XCTAssertEqual(store.records.count, 300, "history is capped")
        XCTAssertEqual(store.records.last?.id, "r309", "newest records survive the cap")
        XCTAssertEqual(store.records.first?.id, "r10", "oldest records are dropped")
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let store = freshStore()
        XCTAssertEqual(store.streakDays, 0)
        store.add(rec("t", daysAgo: 0))
        store.add(rec("y", daysAgo: 1))
        store.add(rec("g", daysAgo: 3))     // gap at 2 days ago breaks the run
        XCTAssertEqual(store.streakDays, 2, "today + yesterday, broken by the gap")
    }
}

// Routines: every step resolves to a real atlas point; the CAMERA-coached surface stays exactly
// the documented 8 (routines may add timer-guided points but can never grow the AR set); all copy
// obeys the banned-claims rule; LI4 can never sneak in through a routine.
final class RoutineTests: XCTestCase {
    func testRoutineStepsResolveAndRespectTheCoachedSet() {
        let coached = Set(Acupoint.all.filter { $0.mediapipeTarget != nil }.map(\.id))
        XCTAssertEqual(coached.count, 8, "the camera-coached set must stay the documented 8")
        for r in Routine.all {
            XCTAssertFalse(r.steps.isEmpty)
            XCTAssertGreaterThan(r.minutes, 0)
            for step in r.steps {
                XCTAssertNotNil(Acupoint.byId[step.pointId], "\(r.id) references unknown point \(step.pointId)")
                XCTAssertGreaterThan(step.rounds, 0)
                XCTAssertNotEqual(step.pointId, "LI4", "LI4 must never appear in a routine")
            }
        }
    }

    func testRoutineCopyHasNoForbiddenClaims() {
        let banned = ["treat", "cure", "heal", "diagnos"]
        for r in Routine.all {
            let blob = [r.zh, r.en, r.descZh, r.descEn].joined(separator: " ").lowercased()
            for term in banned {
                XCTAssertFalse(blob.contains(term), "routine \(r.id) copy contains forbidden term '\(term)'")
            }
        }
    }
}

// The guided timer session: rounds → rest → next round → complete, with an honest clock (banked
// hold never double-counts) and scene-pause that freezes it.
final class TimerSessionTests: XCTestCase {
    func testRoundsRestCompleteCycle() {
        let s = TimerSession(roundsTarget: 2, roundHoldS: 0.4, restS: 0.3)
        XCTAssertEqual(s.coachPhase, .searching)   // ready
        s.start()
        XCTAssertEqual(s.phase, .holding)
        for _ in 0..<4 { s.tick(0.1) }              // 0.4s → round 1 done
        XCTAssertEqual(s.roundsDone, 1)
        XCTAssertEqual(s.phase, .resting)
        XCTAssertEqual(s.progress, 0, "next round starts from zero")
        XCTAssertEqual(s.totalHeldS, 0.4, accuracy: 1e-9, "banked exactly one round — no double count")
        for _ in 0..<3 { s.tick(0.1) }              // 0.3s rest → holding again
        XCTAssertEqual(s.phase, .holding)
        for _ in 0..<4 { s.tick(0.1) }              // round 2 → complete
        XCTAssertTrue(s.sessionComplete)
        XCTAssertEqual(s.roundsDone, 2)
        XCTAssertEqual(s.totalHeldS, 0.8, accuracy: 1e-9)
        s.tick(0.1)                                  // ticks after completion change nothing
        XCTAssertEqual(s.totalHeldS, 0.8, accuracy: 1e-9)
    }

    func testScenePauseFreezesTheClock() {
        let s = TimerSession(roundsTarget: 1, roundHoldS: 0.4, restS: 0.2)
        s.start()
        s.tick(0.2)
        s.scenePaused()                              // background: ticker gone; manual tick still counts,
        let heldAtPause = s.totalHeldS               // but the app's Timer is invalidated — assert state
        XCTAssertEqual(heldAtPause, 0.2, accuracy: 1e-9)
        s.sceneResumed()
        s.tick(0.2)
        XCTAssertTrue(s.sessionComplete)
    }
}

// Practice insights: week window and the feelings tally.
final class PracticeInsightTests: XCTestCase {
    private func store() -> PracticeStore {
        PracticeStore(defaults: UserDefaults(suiteName: "insights-\(UUID().uuidString)")!)
    }
    private func rec(daysAgo: Int, feeling: String? = nil) -> PracticeRecord {
        PracticeRecord(id: UUID().uuidString,
                       date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
                       pointId: "TE3", rounds: 2, roundsTarget: 4, heldS: 60, feeling: feeling)
    }

    func testWeekCountAndFeelingTally() {
        let s = store()
        s.add(rec(daysAgo: 0, feeling: "relaxing"))
        s.add(rec(daysAgo: 2, feeling: "relaxing"))
        s.add(rec(daysAgo: 6, feeling: "uncomfortable"))
        s.add(rec(daysAgo: 10, feeling: "neutral"))       // outside the week, inside 30d
        s.add(rec(daysAgo: 40, feeling: "relaxing"))      // outside 30d entirely
        XCTAssertEqual(s.weekCount, 3)
        let tally = s.feelingTally()
        XCTAssertEqual(tally.relaxing, 2)
        XCTAssertEqual(tally.neutral, 1)
        XCTAssertEqual(tally.uncomfortable, 1)
        XCTAssertFalse(s.exportJSON().isEmpty)
        XCTAssertTrue(s.exportJSON().contains("TE3"))
    }

    // Records written by the earlier OUTCOME-framed prompt (relief/nochange/worse) must keep
    // counting on the experience scale — history is not invalidated by the reframe.
    func testLegacyFeelingKeysMapOntoExperienceScale() {
        let s = store()
        s.add(rec(daysAgo: 1, feeling: "relief"))
        s.add(rec(daysAgo: 2, feeling: "nochange"))
        s.add(rec(daysAgo: 3, feeling: "worse"))
        let tally = s.feelingTally()
        XCTAssertEqual(tally.relaxing, 1)
        XCTAssertEqual(tally.neutral, 1)
        XCTAssertEqual(tally.uncomfortable, 1)
    }
}
