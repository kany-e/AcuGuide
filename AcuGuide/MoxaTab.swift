import SwiftUI

// 艾灸 — the moxibustion tab.
//
// WHO THIS IS FOR, because it decides everything else: someone who ALREADY OWNS a 艾灸盒 and does
// not know where to put it. Moxa boxes are ordinary consumer products in China; the person is going
// to use theirs whether or not this app exists, so the useful question is not "should they" but
// "what do they most need to know". The answer turned out not to be location — it is that the box
// is the form that removes the hand, and the hand is the safety mechanism.
//
// SO THIS TAB LOCATES, DESCRIBES, AND KEEPS THE SAFETY CLOCK; IT STILL NEVER DOSES. The original
// stance here was "no countdown at all" — a countdown reads as a prescription. The practitioner
// round (Aug 2026) moved that line on purpose: this tab's own safety copy tells people to look at
// the skin on a timer rather than by feel, and refusing to BE that timer left the one discipline
// that prevents the burn to whatever kitchen timer the user didn't set. The distinction that
// remains non-negotiable is dose vs. safety: MoxaClockView (MoxaSession.swift) never says how long
// moxa "should" take or that longer does more — it interrupts for skin checks on a fixed cadence
// and hard-stops the sitting at a cap. Every path out of a check is "continue under the same cap"
// or "stop"; none extends the sitting. There is still no camera targeting and no per-point dose.
struct MoxaTab: View {
    // NOT a bare `MoxaScreening?`. This view lives inside RootView's TabView for the life of the
    // process, so a plain answered-once flag here silently turned the documented per-entry gate
    // into a per-process one — pregnancy/burn/numbness answers trusted for days. The visit holder
    // (MoxaGate.swift) owns the re-ask rule and is what the tests pin.
    @State private var visit = MoxaScreeningVisit()
    @State private var selected: MoxaPoint? = nil
    @State private var showLocate = false
    @State private var showClock = false
    @State private var selectedPlacement: MoxaPlacement? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let s = visit.current() {
                    list(readOnly: s.blocksHeat)
                } else {
                    // The gate is FORCED and per-visit: there is no path into the content that
                    // does not pass through it, and it re-asks on every entry because the things it
                    // asks about change (a pregnancy, a healing burn, a new numbness).
                    MoxaGateView { visit.record($0) }
                }
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationTitle(AppLocale.pick("艾灸", "Moxibustion"))
            .navigationBarTitleDisplayMode(.inline)
        }
        // Leaving the tab ends the visit — switching back re-asks, which is the documented rule.
        .onDisappear { visit.endVisit() }
        // The backstop for never leaving: on return to the foreground, drop answers that aged out
        // while the app sat in the background (the mutation is what re-presents the gate — see
        // MoxaScreeningVisit.expireIfStale).
        .onChange(of: scenePhase) { if $0 == .active { visit.expireIfStale() } }
        // `?? true`: if a sheet somehow outlives the visit, it degrades to the read-only copy.
        .sheet(item: $selected) { MoxaPointCard(point: $0, readOnly: visit.current()?.blocksHeat ?? true) }
        .sheet(isPresented: $showLocate) { MoxaLocateFlow { showLocate = false } }
        // `?? true` mirrors the other sheets: a clock that outlives the visit hardens to the
        // required-checks regime rather than the lenient one.
        .sheet(isPresented: $showClock) {
            MoxaClockView(checksRequired: visit.current()?.checksRequired ?? true) { showClock = false }
        }
        .sheet(item: $selectedPlacement) { p in
            MoxaPlacementCard(placement: p, readOnly: visit.current()?.blocksHeat ?? true) { selected = $0 }
        }
    }

    private func list(readOnly: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // THE SAFETY COPY LEADS, and it is about time and skin rather than about buying a
                // better box. A well-made box strapped on for forty minutes causes the same
                // low-temperature burn as a badly-made one: the injury mode is duration plus absent
                // sensation, not build quality.
                MoxaNotice(readOnly: readOnly)

                // The practitioner round's product advice, HIGHLIGHTED by design: it is the one
                // purchasable difference that changes how fast heat comes off skin.
                MoxaStrapAdvice()

                if readOnly {
                    Text(AppLocale.pick("下面是这些穴位的位置与传统说明。",
                                        "Below are the point locations and the traditional notes."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                }

                if !readOnly {
                    Button { showClock = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "timer")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MoxaClockCopy.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(MoxaClockCopy.tabCaption)
                                    .font(.caption2).foregroundStyle(Ink.textDim)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .foregroundStyle(Ink.gold)
                        .padding(14).panel()
                    }
                    .buttonStyle(.plain)

                    Button { showLocate = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.point.up.left")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLocale.pick("在自己身上找位置", "Find it on yourself"))
                                    .font(.subheadline.weight(.semibold))
                                Text(AppLocale.pick("躺下，从肚脐量到耻骨上缘，用你自己的手指",
                                                    "Lie down and measure navel to pubic bone, in your own finger-widths"))
                                    .font(.caption2).foregroundStyle(Ink.textDim)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .foregroundStyle(Ink.gold)
                        .padding(14).panel()
                    }
                    .buttonStyle(.plain)
                }

                // THE PLACEMENT CARDS replace the two hand-written region sections. They route on
                // what the user can DO rather than on a symptom — see MoxaPlacements.
                Text(MoxaPlacements.routingQuestion)
                    .font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(MoxaPlacements.all) { placement in
                    Button { selectedPlacement = placement } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(placement.title)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.gold)
                                .multilineTextAlignment(.leading)
                            Text(pointNames(placement))
                                .font(.caption2).foregroundStyle(Ink.textDim)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).panel()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(placement.title)
                }
            }
            .padding()
        }
    }

    /// The point names a placement covers, moxa dataset and main atlas together — so the card says
    /// what it is about without duplicating either point's own copy.
    private func pointNames(_ p: MoxaPlacement) -> String {
        let moxa = p.points.map(\.name)
        let atlas = p.atlasPointIds.compactMap { Acupoint.byId[$0] }.map { AppLocale.pick($0.zh, $0.en) }
        return (moxa + atlas).joined(separator: " · ")
    }

}

/// The practitioner's product advice, visually set apart from the running copy (gold border, its
/// own icon) because it is the single buying decision that changes outcomes: how a box fastens is
/// how fast it comes off. A product CATEGORY is named, never a brand — the app has nothing to sell.
struct MoxaStrapAdvice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Self.title, systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.gold)
            Text(Self.body_)
                .font(.caption).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.gold, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    static var title: String {
        AppLocale.pick("选盒建议：快拆绑带，不要胶布", "Box advice: quick-release straps, never tape")
    }
    static var body_: String {
        AppLocale.pick(
            "要把盒子固定在身上时，选带快拆扣的绑带式艾灸盒，不要用胶布把盒子粘在皮肤上——需要立刻拿开热源时，撕胶布最慢；对年长、较薄的皮肤，撕胶布本身就可能撕伤皮肤。躺着时什么盒都不要绑：直接放在身上，一抬手就能拿开。",
            "If a box fastens to the body at all, choose one with quick-release straps — never tape a box to the skin. Tape is the slowest thing to undo at the moment heat has to come off, and on older, thinner skin pulling tape can tear the skin by itself. Lying down, strap nothing: rest the box on the body, unfastened, where one hand lifts it straight off.")
    }
    /// For the claims scan, like every other moxa surface.
    static var allCopy: [String] { [title, body_] }
}

/// The standing safety note. Shown above the points every time rather than behind a disclosure,
/// because the thing it says is the thing most box owners do not know.
struct MoxaNotice: View {
    let readOnly: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppLocale.pick("艾灸是明火", "Moxibustion is an open flame"), systemImage: "flame")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.terracotta)
            ForEach(Self.lines, id: \.self) { line in
                Text("• " + line).font(.caption).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14).panel()
    }

    // Every line is authored, not translated — the source material for this topic is saturated with
    // the banned stems (艾灸的功效与作用, 足浴治疗), so a translated version would fail the scan.
    static var lines: [String] {
        [AppLocale.pick("艾灸盒把热源固定在身上，也就把「觉得烫就拿开」的那只手拿走了——这正是家用艾灸低温烫伤最常见的原因。",
                        "A box straps the heat on and, in doing so, removes the hand that would have noticed it — which is why boxes are the commonest source of low-temperature burns at home."),
         AppLocale.pick("44到50度持续够久，会由浅入深地伤到皮肤，而且一开始不太痛、表面看不出来。所以「不觉得烫」并不代表安全，时间才是关键。",
                        "Held long enough, 44–50 °C injures progressively from the surface downward — and it barely hurts at first and looks like very little. So \"it doesn't feel too hot\" is not a sign that it is safe; the variable that matters is time."),
         AppLocale.pick("看皮肤，别只靠感觉，定时查看。皮肤只是微微发红就该停。",
                        "Look at the skin on a timer rather than going by feel. Stop while it is no more than lightly pink."),
         AppLocale.pick("别在密闭房间里用，冬天关窗最容易积聚一氧化碳。",
                        "Not in a closed room — a sealed room in winter is how carbon monoxide builds up."),
         AppLocale.pick("艾条内部会阴燃，看不到火星也可能复燃，泡过水后重新接触空气仍会冒火星。用密封灭火管，或把燃烧端深埋在干沙里。",
                        "Moxa smoulders inside with no visible spark and can reignite — sparks have been seen returning after ten minutes in water, once it met air again. Seal it in an airtight tube, or bury the lit end in dry sand."),
         AppLocale.pick("绑带式的盒子不要躺着用——绑上以后取不下来，正是最不该发生的情况。",
                        "Don't use a strap-on box lying down: once strapped it cannot be got off quickly, which is the worst way for this to go wrong.")]
    }
}

/// One point: where it is, how to find it on yourself, what the tradition groups it with, and its
/// caution. `readOnly` drops the find-it steps and keeps the reading material, for a user whose
/// screening ruled heat out.
struct MoxaPointCard: View {
    let point: MoxaPoint
    let readOnly: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(point.name).font(.title3).foregroundStyle(Ink.gold)
                    field(AppLocale.pick("位置", "Location"), point.location)
                    if !readOnly { field(AppLocale.pick("怎么找", "Finding it"), point.find) }
                    field(AppLocale.pick("传统说法", "Traditionally"), point.tradition)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(AppLocale.pick("注意", "Take care"), systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.terracotta)
                        Text(point.caution).font(.footnote).foregroundStyle(Ink.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).panel()
                    Text(AppLocale.pick("本应用不衡量艾灸「该」做多久，也不给出剂量；灸盒页的计时只做两件事——按时提醒你看皮肤、到点提醒你结束。初次尝试，请当面请教有资质的专业人士。",
                                        "AcuGuide never measures how long moxa \"should\" take and gives no dose; the clock on the moxa tab exists only to make the skin get looked at on schedule and to end the sitting on time. For a first time, learn in person from a qualified practitioner."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
            Text(value).font(.subheadline).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One placement: what it is, and the points on it. Tapping a point opens its own card, so each
/// point's location and caution live in exactly one place (MoxaAtlas) and the placement text never
/// restates them — the restating is how the two drift.
struct MoxaPlacementCard: View {
    let placement: MoxaPlacement
    let readOnly: Bool
    let onPoint: (MoxaPoint) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(placement.title).font(.title3).foregroundStyle(Ink.gold)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(placement.body).font(.subheadline).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !placement.points.isEmpty {
                        Text(AppLocale.pick("这一处的穴位", "The points here"))
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                        ForEach(placement.points) { p in
                            Button { onPoint(p) } label: {
                                HStack {
                                    Text(p.name).font(.subheadline).foregroundStyle(Ink.text)
                                    Spacer()
                                    if p.onBack {
                                        Text(AppLocale.pick("需人帮忙", "needs help"))
                                            .font(.caption2.weight(.semibold)).foregroundStyle(Ink.warn)
                                    }
                                    Image(systemName: "chevron.right").font(.caption2)
                                        .foregroundStyle(Ink.textDim)
                                }
                                .padding(12).panel()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.name)
                        }
                    }

                    // Points that live in the MAIN atlas are named, never copied. ST36's find guide
                    // and caution already exist there; a second version here would be the thing that
                    // goes stale.
                    if !placement.atlasPointIds.isEmpty {
                        Text(AppLocale.pick("已在主穴位图中的穴位", "Already in the main point atlas"))
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                        ForEach(placement.atlasPointIds, id: \.self) { id in
                            if let a = Acupoint.byId[id] {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(a.id) · \(AppLocale.pick(a.zh, a.en))")
                                        .font(.subheadline).foregroundStyle(Ink.text)
                                    Text(a.location).font(.caption2).foregroundStyle(Ink.textDim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).panel()
                            }
                        }
                    }

                    MoxaNotice(readOnly: readOnly)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
