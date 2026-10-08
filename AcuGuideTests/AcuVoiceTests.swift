import XCTest
@testable import AcuGuide

// ACU'S VOICE, PINNED WHERE IT CAN BE (docs/acu-voice.md). Taste cannot be unit-tested; these are the
// rules underneath it that can — helpful first, honest about what was verified, never pushing for
// more — checked on every point in both languages rather than on a hand-picked example.
final class AcuVoiceTests: XCTestCase {

    private func inLanguage<T>(_ lang: AppSettings.Lang, _ body: () async throws -> T) async rethrows -> T {
        let was = AppSettings.shared.lang
        AppSettings.shared.lang = lang
        defer { AppSettings.shared.lang = was }
        return try await body()
    }

    // HELPFUL FIRST (有用). The old answer was a record — id, meridian, role, the WHO location string,
    // uses, disclaimer — and never said how to FIND the spot, though every point has a plain guide.
    // Now: the name, then how to find it, before anything about pressing; the caution is never
    // dropped; and it ends with the self-care line.
    func testEveryPointAnswerLeadsWithHowToFindIt() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                for p in Acupoint.all {
                    let a = await ChatService().reply(to: p.id, history: []).text
                    XCTAssertTrue(a.hasPrefix(zh ? p.zh : p.en), "[\(lang)] \(p.id): the answer must open with the point's name — got: \(a.prefix(40))")
                    let press = zh ? "有任何不舒服就停" : "stop if anything feels wrong"
                    guard let pressAt = a.range(of: press) else {
                        XCTFail("[\(lang)] \(p.id): the press-gently-and-stop line is missing"); continue
                    }
                    if p.hasFindGuide {
                        let guide = String(p.findHow.prefix(14))
                        guard let findAt = a.range(of: guide) else {
                            XCTFail("[\(lang)] \(p.id): the plain finding guide is missing"); continue
                        }
                        XCTAssertLessThan(findAt.lowerBound, pressAt.lowerBound,
                                          "[\(lang)] \(p.id): how to FIND it comes before how to press it")
                    }
                    if !p.caution.isEmpty {
                        let c = String((zh ? p.cautionZh : p.cautionEn).prefix(12))
                        XCTAssertTrue(a.contains(c), "[\(lang)] \(p.id): the point's caution must never be dropped")
                    }
                    XCTAssertTrue(a.hasSuffix(zh ? "仅供养生自我保养参考。" : "Wellness self-care only."),
                                  "[\(lang)] \(p.id): the answer ends with the self-care line")
                }
            }
        }
    }

    // There is no "Coach tab". The answer used to send people to one (「引导」); the camera lives in
    // the Practice tab (练习). A wrong pointer is a small lie about the app itself.
    func testCameraPointsSendPeopleToATabThatExists() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                for p in Acupoint.all {
                    let a = await ChatService().reply(to: p.id, history: []).text
                    XCTAssertFalse(a.contains("Coach tab") || a.contains("「引导」"),
                                   "[\(lang)] \(p.id): there is no Coach tab")
                    if p.mediapipeTarget != nil {
                        XCTAssertTrue(a.contains(zh ? "「练习」" : "Practice tab"),
                                      "[\(lang)] \(p.id) is camera-coached: point to the Practice tab")
                    }
                }
            }
        }
    }

    // Chinese is set as Chinese: sentences assembled from parts must not leave a space after 。
    func testChineseAnswersAreNotSetWithEnglishSpacing() async {
        await inLanguage(.zh) {
            for p in Acupoint.all {
                let a = await ChatService().reply(to: p.id, history: []).text
                XCTAssertFalse(a.contains("。 ") || a.contains("  "),
                               "\(p.id): a space after 。 is English spacing inside Chinese")
            }
        }
    }

    // 信: the greeting promises only what the answers can do in BOTH languages. "What its name means"
    // waits for the sourced name notes — the Chinese answer cannot gloss a name yet.
    func testTheGreetingPromisesOnlyWhatTheAnswersDo() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let g = ChatView.greetingMessage().text
                XCTAssertFalse(g.contains("name means") || g.contains("名字什么意思"),
                               "[\(lang)] no name-meaning promise until the sourced notes exist")
                XCTAssertTrue(g.contains(AppLocale.isChinese ? "孕期" : "pregnancy"),
                              "[\(lang)] safety, pregnancy included, stays discoverable from the greeting")
            }
        }
    }

    // The "what can you do" count is read from the atlas, so it cannot drift when points change.
    func testTheGeneralReplyCountsThePointsItKnows() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let a = await ChatService().reply(to: "zzqx", history: []).text
                XCTAssertTrue(a.contains("\(Acupoint.all.count)"),
                              "[\(lang)] the general reply must state the real number of points")
            }
        }
    }

    // THE SUMMARY. Two rules: "steady press" only when the camera verified the hold (the timer could
    // not see the hand), and the closing line never asks for more — a finished session gets the
    // constancy note, an early stop gets permission.
    func testTheSummaryClaimsOnlyWhatWasVerifiedAndNeverAsksForMore() async {
        guard let te3 = Acupoint.all.first(where: { $0.id == "TE3" }) else { return XCTFail("TE3 missing") }
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                let steady = zh ? "稳定按压" : "steady press"
                for verified in [true, false] {
                    for finished in [true, false] {
                        let s = SessionRecapView.summaryText(point: te3, roundsDone: finished ? 3 : 1,
                                                             roundsTarget: 3, held: 42,
                                                             verifiedHold: verified, finished: finished)
                        XCTAssertEqual(s.contains(steady), verified,
                                       "[\(lang)] 'steady press' is claimed if and only if the camera verified it")
                        let close = finished ? (zh ? "细水长流" : "a little, often") : (zh ? "想停就停" : "stopping when you like")
                        XCTAssertTrue(s.lowercased().contains(close.lowercased()),
                                      "[\(lang)] finished=\(finished): wrong closing line — \(s)")
                        for nudge in ["keep going", "don't stop", "one more", "继续", "别停", "再来"] {
                            XCTAssertFalse(s.lowercased().contains(nudge),
                                           "[\(lang)] the summary must never push for more ('\(nudge)')")
                        }
                    }
                }
            }
        }
    }
}
