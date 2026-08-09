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
        XCTAssertFalse(s.complete, "three of five answered is not answered")
        s.skinBroken = false
        XCTAssertFalse(s.complete, "the age/fragile-skin question is part of the gate, not an extra")
        s.olderAdultOrFragile = false
        XCTAssertTrue(s.complete)
        XCTAssertFalse(s.blocksHeat, "five clear answers must not block")
    }

    // THE FIFTH QUESTION IS A REGIME SWITCH, NOT A BLOCK — in both directions. Age/fragile skin is
    // not a contraindication (blocking would just push older users past the gate dishonestly); what
    // it changes is the skin-check clock, which loses its "feels fine, skip this look" shortcut.
    // Pinned both ways because either drift is a real failure: blocking on age locks people out,
    // and dropping checksRequired quietly restores the skip path for the people burn-unit series
    // are full of (mean age 64.5, low-temperature burns painless in the moment).
    func testOlderAdultAnswerChangesTheCheckRegimeAndNeverBlocksHeat() {
        var s = MoxaScreening(reducedFeeling: false, diabetesOrNerve: false,
                              pregnantOrTrying: false, skinBroken: false,
                              olderAdultOrFragile: true)
        XCTAssertTrue(s.complete)
        XCTAssertFalse(s.blocksHeat, "age/fragile skin must never rule heat out by itself")
        XCTAssertTrue(s.checksRequired, "a yes must harden the check regime")
        s.olderAdultOrFragile = false
        XCTAssertFalse(s.checksRequired)
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
                                  pregnantOrTrying: false, skinBroken: false,
                                  olderAdultOrFragile: false)
            s[keyPath: path] = true
            XCTAssertTrue(s.complete)
            XCTAssertTrue(s.blocksHeat, "a single yes must be sufficient to rule heat out")
        }
    }

    // THE RE-ASK RULE, PINNED. The tab used to hold the completed screening in a bare @State
    // inside RootView's TabView, so "per entry" silently meant "per process" — answers about a
    // pregnancy, a healing burn or a new numbness trusted for days. MoxaScreeningVisit is the
    // structural fix; these tests hold it to both halves of the promise.
    func testScreeningDoesNotSurviveLeavingTheTab() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var v = MoxaScreeningVisit()
        XCTAssertNil(v.current(at: t0), "a fresh visit must start at the gate")
        let s = MoxaScreening(reducedFeeling: false, diabetesOrNerve: false,
                              pregnantOrTrying: false, skinBroken: false,
                              olderAdultOrFragile: false)
        v.record(s, at: t0)
        XCTAssertEqual(v.current(at: t0), s, "a just-answered screening must be honored")
        v.endVisit()
        XCTAssertNil(v.current(at: t0),
                     "leaving the tab ends the visit — the gate re-asks on every entry")
    }

    func testScreeningExpiresByAgeEvenWithoutLeavingTheTab() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var v = MoxaScreeningVisit()
        v.record(MoxaScreening(reducedFeeling: false, diabetesOrNerve: false,
                               pregnantOrTrying: false, skinBroken: false,
                               olderAdultOrFragile: false), at: t0)
        XCTAssertNotNil(v.current(at: t0.addingTimeInterval(MoxaScreeningVisit.maxAge - 1)),
                        "a continuous sitting must not be re-asked mid-read")
        XCTAssertNil(v.current(at: t0.addingTimeInterval(MoxaScreeningVisit.maxAge)),
                     "answers about a body must not outlive the visit by days — the app can sit "
                     + "backgrounded on this tab indefinitely, so age is the backstop")
        // expireIfStale must MUTATE (drop the stored answers), not merely decline to return them:
        // a read can't trigger a SwiftUI re-render, so the mutation is what re-presents the gate.
        v.expireIfStale(at: t0.addingTimeInterval(MoxaScreeningVisit.maxAge))
        XCTAssertNil(v.current(at: t0),
                     "after expiry the answers are gone, not merely masked by the clock")
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

    // THE BUILDER OBEYS THE SAME STRUCTURAL CAP. It hardcoded its own maxSteps = 8 while
    // Routine.maxSteps documented 6 as the ceiling — the one door the structural rule didn't cover
    // (whole-app critique, Aug 2026). One constant now, pinned so a local override cannot return.
    func testRoutineBuilderSharesTheStructuralStepCap() {
        XCTAssertEqual(RoutineBuilderView.maxSteps, Routine.maxSteps,
                       "the builder must not re-declare its own sequence ceiling")
    }

    // AUTOFILL. A point the user doesn't know arrives with rounds from bundled precedent — the
    // number a practitioner-reviewed sequence uses — and the default of 2 otherwise. Every
    // suggestion must land inside the builder's stepper range for every point in the atlas, or the
    // builder would construct a step its own UI cannot express.
    func testAutofillSuggestsBundledPrecedentWithinBuilderBounds() {
        XCTAssertEqual(RoutineAutofill.suggestedRounds(for: "TE3"), 3, "head-ease uses TE3 ×3")
        XCTAssertEqual(RoutineAutofill.suggestedRounds(for: "PC6"), 3, "travel-calm uses PC6 ×3")
        XCTAssertEqual(RoutineAutofill.suggestedRounds(for: "SI3"), 3, "stiff-neck uses SI3 ×3")
        XCTAssertEqual(RoutineAutofill.suggestedRounds(for: "HT8"), RoutineAutofill.defaultRounds,
                       "a point no bundled routine uses gets the default")
        for pt in Acupoint.all {
            let n = RoutineAutofill.suggestedRounds(for: pt.id)
            XCTAssertTrue((1...RoutineAutofill.maxBuilderRounds).contains(n),
                          "\(pt.id): suggestion \(n) is outside the builder's stepper range")
        }
        XCTAssertLessThanOrEqual(RoutineAutofill.maxBuilderRounds, Routine.maxRoundsPerStep,
                                 "the builder ceiling must sit inside the structural one")
    }

    // The young-person additions exist, resolve, and follow the construction rules: the carsick
    // extension keeps PC6 in the lead, and the screen-break routine opens local-and-kneaded at the
    // temple like the practitioner's head sequence.
    func testAugustAdditionsFollowTheConstructionRules() throws {
        let travel = try XCTUnwrap(Routine.all.first { $0.id == "travel-calm" })
        XCTAssertEqual(travel.steps.first?.pointId, "PC6", "the studied point keeps the lead")
        XCTAssertGreaterThan(travel.steps.count, 1, "the carsick request extended this routine")

        let neck = try XCTUnwrap(Routine.all.first { $0.id == "stiff-neck" })
        XCTAssertEqual(neck.steps.first?.pointId, "SI3", "Houxi is the classical 落枕 lead")

        let screen = try XCTUnwrap(Routine.all.first { $0.id == "screen-break" })
        XCTAssertEqual(screen.steps.first?.role, .local, "local anchor first, like head-ease")
        XCTAssertEqual(screen.steps.first?.technique, .knead, "temples are kneaded, not pressed")

        XCTAssertNotNil(Routine.all.first { $0.id == "settle-stomach" })
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
