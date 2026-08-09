import XCTest
import UIKit
@testable import AcuGuide

// The skin-check clock — the practitioner round's core. These tests drive MoxaClock's tick core
// deterministically (no Timer), the way TimerSession's tests do, and pin the properties that make
// the clock a SAFETY device rather than a dose:
//   the cap cannot be exceeded or extended, checks interrupt on schedule and freeze heat-time
//   until answered, the higher-risk regime structurally lacks the skip path, the stop answer is
//   terminal, and the photos never outlive the sitting.
final class MoxaClockTests: XCTestCase {

    private func drive(_ c: MoxaClock, seconds: Double, step: Double = 1) {
        var t = 0.0
        while t < seconds { c.tick(step); t += step }
    }

    // The first look comes EARLY (2.5 min, not the repeating 5): the measured under-box worst case
    // (>49 °C at 3 cm) injures on a ~10-minute timescale, so the first look must sit well inside it.
    func testFirstCheckFiresAtTwoAndAHalfMinutes() {
        let c = MoxaClock(minutes: 10, checksRequired: false)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds - 1)
        XCTAssertEqual(c.phase, .running, "no check before the first boundary")
        c.tick(1)
        XCTAssertEqual(c.phase, .checking, "the first look is due at \(Int(MoxaClockPlan.firstCheckSeconds)) s")
    }

    // While a check is due, the clock is FROZEN: heat-time must never be credited past a look the
    // user hasn't done. Ticks during .checking are dropped, not banked.
    func testHeatTimeFreezesUntilACheckIsAnswered() {
        let c = MoxaClock(minutes: 10, checksRequired: false)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
        XCTAssertEqual(c.phase, .checking)
        let atCheck = c.elapsed
        drive(c, seconds: 600)
        XCTAssertEqual(c.elapsed, atCheck, "time must not accrue while the box is meant to be lifted")
        c.answer(.lookedClear)
        XCTAssertEqual(c.phase, .running)
        XCTAssertEqual(c.checksAnswered, 1)
    }

    // After the early first look the cadence settles to every 5 minutes.
    func testChecksRepeatOnTheFiveMinuteCadence() {
        let c = MoxaClock(minutes: 15, checksRequired: false)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
        c.answer(.lookedClear)
        drive(c, seconds: MoxaClockPlan.checkEverySeconds - 1)
        XCTAssertEqual(c.phase, .running)
        c.tick(1)
        XCTAssertEqual(c.phase, .checking, "second look at first + 5 min")
        c.answer(.lookedClear)
        drive(c, seconds: MoxaClockPlan.checkEverySeconds)
        XCTAssertEqual(c.phase, .checking, "third look 5 min after that")
    }

    // THE CAP. Whatever was planned, whatever is answered, elapsed never passes the plan and the
    // sitting ends AT it — there is no input that extends a sitting.
    func testTheCapEndsTheSittingAndCannotBeExceeded() {
        let c = MoxaClock(minutes: 10, checksRequired: false)
        c.start()
        var guard_ = 0
        while c.phase != .endedByCap && guard_ < 10_000 {
            if c.phase == .checking { c.answer(.lookedClear) } else { c.tick(1) }
            guard_ += 1
        }
        XCTAssertEqual(c.phase, .endedByCap)
        XCTAssertEqual(c.elapsed, 600, accuracy: 0.001, "a 10-minute plan ends at exactly 10 minutes")
        XCTAssertLessThanOrEqual(c.elapsed, c.plannedSeconds, "elapsed may never pass the plan")
        // Nothing restarts a finished sitting.
        c.tick(60); c.answer(.lookedClear); c.start()
        XCTAssertEqual(c.phase, .endedByCap)
    }

    func testThePlanIsClampedToTheCap() {
        let c = MoxaClock(minutes: 60, checksRequired: false)
        XCTAssertEqual(c.plannedSeconds, MoxaClockPlan.capSeconds,
                       "an hour cannot be planned — the cap clamps construction")
        let c2 = MoxaClock(minutes: 10, checksRequired: false)
        c2.plan(minutes: 999)
        XCTAssertEqual(c2.plannedSeconds, MoxaClockPlan.capSeconds, "…and the setup knob")
        c2.start()
        c2.plan(minutes: 5)
        XCTAssertEqual(c2.plannedSeconds, MoxaClockPlan.capSeconds,
                       "the plan is setup-only — a running sitting cannot be re-planned")
    }

    // THE HIGHER-RISK REGIME IS STRUCTURAL. When checks are required there is no skip in the choice
    // set at all — not a disabled button, no member to render — and answering .skip anyway is inert.
    func testRequiredChecksHaveNoSkipPath() {
        let c = MoxaClock(minutes: 10, checksRequired: true)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
        XCTAssertEqual(c.phase, .checking)
        XCTAssertFalse(c.checkChoices.contains(.skip),
                       "the skip choice must not exist for a 65+/fragile-skin sitting")
        c.answer(.skip)
        XCTAssertEqual(c.phase, .checking, "a skip that isn't offered must also not work")
        XCTAssertEqual(c.checksAnswered, 0)
        c.answer(.lookedClear)
        XCTAssertEqual(c.phase, .running)
    }

    func testOrdinaryRegimeOffersSkipAndItCounts() {
        let c = MoxaClock(minutes: 10, checksRequired: false)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
        XCTAssertTrue(c.checkChoices.contains(.skip))
        c.answer(.skip)
        XCTAssertEqual(c.phase, .running, "the younger user may skip a look that feels fine")
    }

    // STOP IS TERMINAL and routes to the burn-guidance phase. Nothing revives the sitting.
    func testStopAtACheckIsTerminal() {
        let c = MoxaClock(minutes: 10, checksRequired: true)
        c.start()
        drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
        c.answer(.stop)
        XCTAssertEqual(c.phase, .stoppedForSkin)
        c.tick(60); c.start(); c.answer(.lookedClear)
        XCTAssertEqual(c.phase, .stoppedForSkin)
    }

    // A BACKGROUND GAP NEVER SAILS PAST A LOOK. Ten minutes away lands the clock exactly ON the
    // first unanswered boundary, with the check due — not past it with heat-time silently credited.
    func testSceneGapLandsOnTheCheckBoundaryNotPastIt() {
        let c = MoxaClock(minutes: 15, checksRequired: false)
        c.start()
        c.scenePaused()
        c.sceneResumed(after: 600)
        XCTAssertEqual(c.phase, .checking)
        XCTAssertEqual(c.elapsed, MoxaClockPlan.firstCheckSeconds, accuracy: 0.001,
                       "the gap credits time only up to the first missed look")
    }

    // The photos live exactly as long as the sitting — every exit wipes both. (In-memory-only is a
    // stated privacy promise on the setup card; this is the discard half of it.)
    func testPhotosDoNotOutliveTheSitting() {
        for exit_ in ["cap", "user", "skin"] {
            let c = MoxaClock(minutes: 5, checksRequired: false)
            c.baselinePhoto = UIImage()
            c.start()
            drive(c, seconds: MoxaClockPlan.firstCheckSeconds)
            c.checkPhoto = UIImage()
            switch exit_ {
            case "cap":
                c.answer(.lookedClear)
                var guard_ = 0
                while c.phase != .endedByCap && guard_ < 10_000 {
                    if c.phase == .checking { c.answer(.lookedClear) } else { c.tick(1) }
                    guard_ += 1
                }
            case "user": c.endNow()
            default:     c.answer(.stop)
            }
            XCTAssertNil(c.baselinePhoto, "\(exit_): baseline photo must be discarded")
            XCTAssertNil(c.checkPhoto, "\(exit_): check photo must be discarded")
        }
    }

    // A 5-minute plan still gets its first look (2.5 < 5); the answered check then meets the cap.
    func testShortestPlanStillGetsItsFirstLook() {
        let c = MoxaClock(minutes: 5, checksRequired: true)
        c.start()
        drive(c, seconds: 300)
        XCTAssertEqual(c.phase, .checking, "2.5-minute look happens inside even the shortest plan")
        c.answer(.lookedClear)
        drive(c, seconds: 300)
        XCTAssertEqual(c.phase, .endedByCap)
    }

    // The copy contract: the plan's numbers appear in the copy the user reads. If the constants
    // move, the sentences quoting them move with them (they interpolate) — but the CLAIMED cadence
    // ("2½ minutes", then every N) must match the code's boundaries, so pin the constants the copy
    // is written against.
    func testCopyQuotesTheActualPlan() {
        XCTAssertEqual(MoxaClockPlan.firstCheckSeconds, 150)
        XCTAssertEqual(MoxaClockPlan.checkEveryMinutes, 5)
        XCTAssertEqual(MoxaClockPlan.capMinutes, 15)
        XCTAssertTrue(MoxaClockCopy.setupIntro.contains("2½") || MoxaClockCopy.setupIntro.contains("2 分半"),
                      "the setup copy claims the early first look — keep it true")
    }
}