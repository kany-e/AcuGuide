import XCTest
@testable import AcuGuide

// The moxibustion tab's gate, and the extended massage sequences.
final class MoxaGateTests: XCTestCase {

    // The gate cannot be passed by ignoring it. Every question must be answered before the button
    // does anything — the failure mode for a screen like this is that it becomes a single tap
    // someone gets past by reflex, which screens nobody.
    func testGateIsNotPassableUntilEveryQuestionIsAnswered() {
        var s = MoxaScreening()
        XCTAssertFalse(s.complete, "an untouched screening must not be complete")
        s.reducedFeeling = false
        s.diabetesOrNerve = false
        s.pregnantOrTrying = false
        XCTAssertFalse(s.complete, "three of four answered is not answered")
        s.skinBroken = false
        XCTAssertTrue(s.complete)
        XCTAssertFalse(s.blocksHeat, "four clear answers must not block")
    }

    // ANY yes blocks heat. They are ORed rather than scored: these are not risk factors that add up,
    // they are each independently sufficient. In particular `diabetesOrNerve` is asked separately
    // from `reducedFeeling` because neuropathy is frequently present and unrecognised, so someone
    // can answer "no" to reduced feeling honestly and still be exactly the person at risk.
    func testAnySingleYesBlocksHeat() {
        let paths: [WritableKeyPath<MoxaScreening, Bool?>] =
            [\.reducedFeeling, \.diabetesOrNerve, \.pregnantOrTrying, \.skinBroken]
        for path in paths {
            var s = MoxaScreening(reducedFeeling: false, diabetesOrNerve: false,
                                  pregnantOrTrying: false, skinBroken: false)
            s[keyPath: path] = true
            XCTAssertTrue(s.complete)
            XCTAssertTrue(s.blocksHeat, "a single yes must be sufficient to rule heat out")
        }
    }

    // The gate asks about PREGNANCY because the standard forbids warming the lower abdomen and the
    // lumbosacral region — and every point in the dataset is in one of those. This is the reason the
    // rest of the app's approach (exclude the restricted points, then need no screen) cannot be
    // reused here: excluding them would leave the feature empty.
    func testThePointsTheGateProtectsAreTheWholeDataset() {
        XCTAssertFalse(MoxaAtlas.all.isEmpty)
        XCTAssertEqual(MoxaAtlas.abdomen.count + MoxaAtlas.lumbar.count, MoxaAtlas.all.count,
                       "every moxa point is abdominal or lumbar — i.e. in a region the standard "
                       + "restricts in pregnancy, which is why a gate replaces point exclusion")
    }
}

final class RoutineSequenceTests: XCTestCase {

    // THE PRACTITIONER'S SEQUENCE. Her point was that the head routine had no LOCAL step at all — it
    // started at the hand and never touched the area the tension is in.
    func testHeadRoutineOpensWithALocalPointThenGoesDistal() throws {
        let r = try XCTUnwrap(Routine.all.first { $0.id == "head-ease" })
        XCTAssertEqual(r.steps.first?.pointId, "EX-HN5", "the sequence opens at the temple")
        XCTAssertEqual(r.steps.first?.role, .local)
        XCTAssertEqual(r.steps.first?.technique, .knead, "揉太阳 — kneaded, not pressed")
        XCTAssertTrue(r.steps.dropFirst().allSatisfy { $0.role == .distal },
                      "everything after the local anchor is distal along the channel")
        XCTAssertGreaterThan(r.steps.count, 2, "a 'more complete' sequence chains more than a pair")
    }

    // …and it is actually LONGER now. The old version accumulated 90 s across the whole routine,
    // against a taught 60–120 s per point.
    func testHeadRoutineClearsTheTaughtPerPointFloor() throws {
        let r = try XCTUnwrap(Routine.all.first { $0.id == "head-ease" })
        let total = r.steps.reduce(0.0) { $0 + $1.holdSeconds }
        XCTAssertGreaterThanOrEqual(total, 180, "the old routine banked only 90 s in total")
        for s in r.steps {
            XCTAssertGreaterThanOrEqual(s.holdSeconds, 60, "\(s.pointId) is below the taught floor")
        }
    }

    // EXTEND BY ADDING POINTS, NOT BY INFLATING ONE. A 2025 meta-regression found sessions per day
    // positively correlated with outcome while each session's duration correlated NEGATIVELY, and
    // there is a tissue ceiling — over-long work produces bruising, and rhabdomyolysis cases exist
    // after sustained strong massage. So the cap is structural, not a warning string.
    func testNoStepExceedsThePerPointCeiling() {
        for r in Routine.all {
            XCTAssertLessThanOrEqual(r.steps.count, Routine.maxSteps, "\(r.id) chains too many points")
            for s in r.steps {
                XCTAssertLessThanOrEqual(s.rounds, Routine.maxRoundsPerStep,
                                         "\(r.id)/\(s.pointId) exceeds the per-point ceiling — "
                                         + "lengthen a routine by adding points instead")
                XCTAssertGreaterThan(s.rounds, 0)
            }
        }
        XCTAssertEqual(Double(Routine.maxRoundsPerStep) * CoachConst.holdTargetS, 180,
                       "the ceiling is 3 minutes, the top of the taught per-point range")
    }

    // Every step must reference a point that exists, or a routine silently skips it at run time.
    func testEveryStepResolvesToARealPoint() {
        for r in Routine.all {
            for s in r.steps {
                XCTAssertNotNil(s.point, "\(r.id) references missing point \(s.pointId)")
            }
        }
    }

    // Adding head points to routines is the one genuinely new hazard in the extended sequences: the
    // oculocardiac reflex fires from periorbital pressure, not only from the globe, and EX-HN3 sits
    // between the brows. A structural exclusion beats a sentence in a caution that can be skimmed.
    func testHeadRegionExclusionsAreDeclaredAndDescribedInBothLanguages() {
        XCTAssertTrue(Routine.excludedRegions.contains(.eyeGlobe))
        XCTAssertTrue(Routine.excludedRegions.contains(.anteriorNeck))
        for region in Routine.excludedRegions {
            XCTAssertFalse(region.en.isEmpty, "\(region) needs English copy")
            XCTAssertFalse(region.zh.isEmpty, "\(region) needs Chinese copy")
        }
    }

    // The head routine's description must not make either of the two claims that are factually
    // wrong: 太阳 EX-HN5 is an 经外奇穴 and is NOT a Sanjiao point, and TE3 is not "on the same
    // channel as your temple" in the sense a reader would take. The Sources screen sets a precedent
    // of adversarially verified point data and this copy has to meet it.
    func testHeadRoutineCopyAvoidsTheTwoFalseChannelClaims() throws {
        let r = try XCTUnwrap(Routine.all.first { $0.id == "head-ease" })
        let en = r.descEn.lowercased()
        XCTAssertFalse(en.contains("taiyang is"), "太阳 is an extra point, not a channel point")
        XCTAssertFalse(en.contains("same channel as your temple"))
        XCTAssertTrue(en.contains("shaoyang") || en.contains("channel"),
                      "the true statement — the channel runs past the temple — should still be made")
    }
}
