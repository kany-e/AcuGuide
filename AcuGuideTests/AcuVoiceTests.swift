import XCTest
@testable import AcuGuide

// ACU'S VOICE, PINNED WHERE IT CAN BE (docs/acu-voice.md). Taste cannot be unit-tested; these are the
// rules underneath it that can — concise, helpful first, honest about what was verified, never pushing
// for more — checked on every point in both languages rather than on a hand-picked example.
final class AcuVoiceTests: XCTestCase {

    private func inLanguage<T>(_ lang: AppSettings.Lang, _ body: () async throws -> T) async rethrows -> T {
        let was = AppSettings.shared.lang
        AppSettings.shared.lang = lang
        defer { AppSettings.shared.lang = was }
        return try await body()
    }

    /// Things a point answer must NOT carry (device feedback: concise, no commentary on sources). They
    /// live on the atlas card, the Sources screen, the Practice button, and the chat screen's footer.
    private let extras = ["AcuTrials", "Classical role", "传统归类", "研究方面", "Practice tab", "「练习」",
                          "self-care only", "仅供养生", "Coach tab", "「引导」"]

    // HELPFUL FIRST, AND NOTHING ELSE: how to find it, what the tradition links it with, how to press
    // and when to stop, the point's own caution. In that order, and the caution is never dropped. (An
    // asterisked point's notice follows the caution: SafetyInvariantTests pins that half.)
    func testEveryPointAnswerIsFindUsesPressCaution() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                for p in Acupoint.all {
                    let a = await ChatService().reply(to: p.id, history: []).text
                    let lead = zh ? "找\(p.zh)\(p.asterisk)（\(p.id)）：" : "To find \(p.en)\(p.asterisk) (\(p.id)): "
                    XCTAssertTrue(a.hasPrefix(lead), "[\(lang)] \(p.id): must open with how to find it — got: \(a.prefix(30))")
                    let press = zh ? "不舒服就停" : "stop if it feels wrong"
                    guard let pressAt = a.range(of: press) else {
                        XCTFail("[\(lang)] \(p.id): the press-gently-and-stop line is missing"); continue
                    }
                    if p.hasFindGuide, let findAt = a.range(of: String(p.findHow.prefix(14))) {
                        XCTAssertLessThan(findAt.lowerBound, pressAt.lowerBound,
                                          "[\(lang)] \(p.id): how to FIND it comes before how to press it")
                    } else if p.hasFindGuide {
                        XCTFail("[\(lang)] \(p.id): the plain finding guide is missing")
                    }
                    if !p.caution.isEmpty {
                        let c = String((zh ? p.cautionZh : p.cautionEn).prefix(12))
                        XCTAssertTrue(a.contains(c), "[\(lang)] \(p.id): the point's caution must never be dropped")
                    }
                    for x in extras where a.contains(x) {
                        XCTFail("[\(lang)] \(p.id): answer carries '\(x)' — not part of a concise answer")
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

    // THE DATA THE ANSWERS READ FROM. Every Chinese "uses" line keeps its 传统上 hedge (信 — tradition
    // reported as tradition), and none slides back into the stacked 「与……的……感相关联」 /
    // 「……等相关调理」 formula that read as translated.
    func testChineseUsesLinesAreHedgedAndNatural() {
        for p in Acupoint.all {
            XCTAssertTrue(p.indicationsZh.hasPrefix("传统上"), "\(p.id): the traditional hedge must lead")
            XCTAssertFalse(p.indicationsZh.contains("相关联") || p.indicationsZh.contains("相关调理"),
                           "\(p.id): the stacked formula is back — \(p.indicationsZh)")
        }
    }

    // A symptom answer is concise but keeps its safety half whole: stop if uncomfortable, see someone
    // if it is severe or does not settle.
    func testSymptomAnswersKeepTheSafetyHalf() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                let a = await ChatService().reply(to: zh ? "头痛" : "I have a tension headache", history: []).text
                XCTAssertTrue(a.contains(zh ? "不舒服就停" : "Stop if it's uncomfortable"), "[\(lang)] stop line missing: \(a)")
                XCTAssertTrue(a.contains(zh ? "专业人士" : "professional"), "[\(lang)] see-a-professional line missing: \(a)")
                XCTAssertFalse(a.contains("Tap a button") || a.contains("点按下方按钮"),
                               "[\(lang)] the buttons are right there; the answer need not say so")
            }
        }
    }

    // The greeting is short, and does not raise pregnancy (or anything else) unprompted. It is answered
    // when someone asks; a greeting that brings it up reads as if the app expects it.
    func testTheGreetingIsConciseAndRaisesNothingUnprompted() async {
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let g = ChatView.greetingMessage().text
                XCTAssertFalse(g.contains("孕") || g.lowercased().contains("pregnan"),
                               "[\(lang)] no unprompted pregnancy mention")
                XCTAssertFalse(g.contains("name means") || g.contains("名字什么意思"),
                               "[\(lang)] no name-meaning promise until the sourced notes exist")
                XCTAssertLessThanOrEqual(g.count, AppLocale.isChinese ? 50 : 100,
                                         "[\(lang)] the greeting should stay short — \(g.count) chars")
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

    // THE SUMMARY. "Steady press" only when the camera verified the hold (the timer could not see the
    // hand), and the closing line never asks for more.
    func testTheSummaryClaimsOnlyWhatWasVerifiedAndNeverAsksForMore() async {
        guard let te3 = Acupoint.all.first(where: { $0.id == "TE3" }) else { return XCTFail("TE3 missing") }
        for lang in AppSettings.Lang.allCases {
            await inLanguage(lang) {
                let zh = AppLocale.isChinese
                for verified in [true, false] {
                    for finished in [true, false] {
                        let s = SessionRecapView.summaryText(point: te3, roundsDone: finished ? 3 : 1,
                                                             roundsTarget: 3, held: 42,
                                                             verifiedHold: verified, finished: finished)
                        XCTAssertEqual(s.contains(zh ? "稳稳按住" : "steady press"), verified,
                                       "[\(lang)] 'steady' is claimed if and only if the camera verified it")
                        let close = finished ? (zh ? "每天按一会儿就好" : "a little each day is plenty")
                                             : (zh ? "想停就停" : "stopping whenever you like")
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
