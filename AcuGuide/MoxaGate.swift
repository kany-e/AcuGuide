import SwiftUI

// THE MOXIBUSTION SCREEN — the one gate in this app that asks a question rather than asking for an
// acknowledgement.
//
// WHY IT EXISTS AT ALL. Every point in MoxaAtlas is lower-abdominal or lumbar, and the standard rule
// forbids warming those REGIONS in pregnancy — under 3 months the lower abdomen, from 3 months on
// the abdomen and the lumbosacral area both. That is a rule about a region, not about a point, so
// the trick the rest of the app uses (exclude LI4/SP6/GB21/BL60/BL67 outright and then need no
// screen at all — see ChatLLM.excludedPointsEn) cannot work here: the forbidden regions ARE the
// feature, and excluding them leaves nothing.
//
// WHY IT IS NOT A CHECKBOX. "I confirm I am not pregnant" is the shape everyone builds and it
// screens nobody: it is one tap, it reads as boilerplate, and it is answered by reflex. The
// questions below are answerable wrongly without harm precisely because a "yes" on any of them
// merely narrows what the tab offers rather than accusing the user of anything — so there is no
// incentive to click through. The heat questions matter at least as much as the pregnancy one and
// are asked first, so the screen does not read as being about pregnancy alone.
//
// WHY IT IS PER-VISIT AND NOT PERSISTED. The answers describe a state that changes — a pregnancy,
// a healing burn, a new numbness. The safety gate before the camera is acknowledged once because
// the red-flag list it shows is timeless; this is not that. It re-asks on every entry, which is
// cheap (four taps) against the thing it is preventing. That rule is enforced by
// MoxaScreeningVisit below, not by a comment: the completed screening can only be held inside a
// visit, and a visit ends when the user leaves the tab or the answers age out.
struct MoxaScreening: Equatable {
    /// Reduced feeling anywhere the box would sit. THE decisive one: the entire safety model of
    /// moxibustion is "move it away when it feels too hot", and this is the answer that says the
    /// loop is broken. A box makes it worse by removing the hand as well.
    var reducedFeeling: Bool?
    /// Diabetes or nerve damage — asked separately from `reducedFeeling` on purpose. Neuropathy is
    /// frequently present and unrecognised, so a person can honestly answer "no" to reduced feeling
    /// and still be at risk; the condition is the more reliable question of the two.
    var diabetesOrNerve: Bool?
    /// Pregnant, or trying to conceive. Both, because CV5 石门 sits inside the same box footprint and
    /// the classical caution there is specifically about conceiving.
    var pregnantOrTrying: Bool?
    /// Broken, irritated or recently burned skin where the box would go.
    var skinBroken: Bool?

    var complete: Bool {
        reducedFeeling != nil && diabetesOrNerve != nil && pregnantOrTrying != nil && skinBroken != nil
    }
    /// Any "yes" that rules out heat on these regions entirely.
    var blocksHeat: Bool {
        reducedFeeling == true || diabetesOrNerve == true || pregnantOrTrying == true || skinBroken == true
    }
}

// THE PER-ENTRY RULE, AS A TYPE. MoxaTab used to hold the completed screening in a bare @State —
// and because the tab lives inside RootView's TabView for the life of the process, "per session"
// silently meant "per process": answered on Monday, still trusted on Thursday, while the comments
// here and in MoxaTab promised a re-ask on every entry. This holder makes the promise structural:
// a completed screening is stored WITH the moment it was answered, `endVisit()` (wired to the
// tab's onDisappear) drops it whenever the user leaves, and `current(at:)` refuses to hand back
// answers older than `maxAge` — the backstop for the one path with no onDisappear, staying on the
// tab while the app sits in the background for days.
struct MoxaScreeningVisit {
    /// Long enough that a continuous sitting is never re-asked mid-read; far too short for the
    /// answers to cross into a different day, body, or pregnancy status.
    static let maxAge: TimeInterval = 30 * 60

    private var answered: MoxaScreening?
    private var answeredAt: Date?

    mutating func record(_ s: MoxaScreening, at now: Date = Date()) {
        answered = s
        answeredAt = now
    }
    /// The user left the tab — the next entry starts at the gate again.
    mutating func endVisit() {
        answered = nil
        answeredAt = nil
    }
    /// Actually DROPS an aged-out screening rather than merely not returning it. The distinction
    /// matters to SwiftUI: `current(at:)` is a read and cannot trigger a re-render, so the view
    /// calls this on foregrounding — the mutation (when something expired) is what re-presents
    /// the gate.
    mutating func expireIfStale(at now: Date = Date()) {
        if answered != nil, current(at: now) == nil { endVisit() }
    }
    /// The screening, only while it is still fresh.
    func current(at now: Date = Date()) -> MoxaScreening? {
        guard let s = answered, let t = answeredAt,
              now.timeIntervalSince(t) < Self.maxAge else { return nil }
        return s
    }
}

struct MoxaGateView: View {
    /// Called with the completed screening. `blocksHeat` decides whether the tab shows the reading
    /// surface only or the full locate flow — the caller never re-derives that rule.
    let onAnswered: (MoxaScreening) -> Void
    @State private var s = MoxaScreening()

    private struct Q: Identifiable {
        let id: String, zh: String, en: String
        let path: WritableKeyPath<MoxaScreening, Bool?>
    }
    private static let questions: [Q] = [
        Q(id: "feeling",
          zh: "下腹部或腰背部，有没有感觉减退、发麻的地方？",
          en: "Is there anywhere on your lower belly or lower back where the feeling is reduced, or numb?",
          path: \.reducedFeeling),
        Q(id: "nerve",
          zh: "有糖尿病，或者医生说过神经受损吗？",
          en: "Do you have diabetes, or has a doctor mentioned nerve damage?",
          path: \.diabetesOrNerve),
        Q(id: "pregnancy",
          zh: "怀孕了，或者正在备孕吗？",
          en: "Are you pregnant, or trying to conceive?",
          path: \.pregnantOrTrying),
        Q(id: "skin",
          zh: "打算放艾灸盒的地方，皮肤有破损、发炎，或最近烫伤过吗？",
          en: "Is the skin where the box would sit broken, irritated, or recently burned?",
          path: \.skinBroken),
    ]

    /// Every user-facing string in this gate, so the claims scan can reach it. A screen whose copy
    /// is not enumerable is a screen the scan silently does not cover — which is how an unscanned
    /// surface ships, and it had already happened once to MoxaAtlas.
    static var allCopy: [String] { questions.flatMap { [$0.zh, $0.en] } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AppLocale.pick("关于艾灸", "About moxibustion"))
                        .font(.title2).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick(
                        "艾灸是明火。这一页只在你已经有艾灸盒时，帮你找到位置——先问四个问题，因为有些情况下不适合用热。",
                        "Moxibustion is an open flame. This tab helps you find the spot if you already have a box — four questions first, because there are situations where heat is not the right idea."))
                        .foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.questions) { q in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLocale.pick(q.zh, q.en))
                                .font(.subheadline).foregroundStyle(Ink.text)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                answerButton(q, value: false, label: AppLocale.pick("没有", "No"))
                                answerButton(q, value: true, label: AppLocale.pick("有", "Yes"))
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                    }

                    // Shown as soon as any answer rules heat out, rather than after the last tap —
                    // there is no reason to make someone finish a form to be told the answer.
                    if s.blocksHeat {
                        Text(AppLocale.pick(
                            "这些情况下，把热源放在这些位置不合适——皮肤感觉不可靠时，疼痛就不再是可靠的警告。你仍然可以继续阅读这些穴位的位置和传统说明。",
                            "With any of these, heat on these areas isn't the right idea — when skin feeling is unreliable, pain stops being a usable warning. You can still read the point locations and the traditional notes."))
                            .font(.footnote).foregroundStyle(Ink.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Button(s.blocksHeat ? AppLocale.pick("只看说明", "Read only")
                                : AppLocale.pick("继续", "Continue")) { onAnswered(s) }
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                .disabled(!s.complete)
                .opacity(s.complete ? 1 : 0.5)
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
        }
    }

    private func answerButton(_ q: Q, value: Bool, label: String) -> some View {
        let selected = s[keyPath: q.path] == value
        return Button { s[keyPath: q.path] = value } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black : Ink.text)
                .padding(.horizontal, 22).frame(height: 44)
                .background(Capsule().fill(selected ? Ink.gold : .clear))
                .overlay(Capsule().stroke(selected ? Ink.gold : Ink.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
