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
// or "stop"; none extends the sitting. There is no per-point dose, and the camera LOCATES only —
// MoxaCameraLocateView marks the abdominal midline by proportion and does not coach, time, or
// decide that a box may go on.
//
// THE TAB IS POINT-FIRST. Device report: "the user should tap on where they want to moxibate, and
// then guide them to find it, then the select timer and picture." It used to open with the clock
// and a finding walkthrough side by side at the top, either startable before a point had been
// chosen at all — an order that matched nothing a person actually does. Choosing now comes first
// (placement → point) and the two steps live ON the point's own card, in the order they happen.
struct MoxaTab: View {
    // NOT a bare `MoxaScreening?`. This view lives inside RootView's TabView for the life of the
    // process, so a plain answered-once flag here silently turned the documented per-entry gate
    // into a per-process one — pregnancy/burn/numbness answers trusted for days. The visit holder
    // (MoxaGate.swift) owns the re-ask rule and is what the tests pin.
    @State private var visit = MoxaScreeningVisit()
    @State private var selected: MoxaPoint? = nil
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
        // BOTH `?? true` defaults harden rather than relax: a card that somehow outlives the visit
        // degrades to the read-only copy, and the clock it can start inherits the required-checks
        // regime. The card carries `checksRequired` because the clock it opens must not re-decide a
        // screening answer for itself.
        .sheet(item: $selected) {
            MoxaPointCard(point: $0,
                          readOnly: visit.current()?.blocksHeat ?? true,
                          checksRequired: visit.current()?.checksRequired ?? true)
        }
        .sheet(item: $selectedPlacement) { p in
            MoxaPlacementCard(placement: p) { selected = $0 }
        }
    }

    private func list(readOnly: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // THE SAFETY COPY LEADS, and it is about time and skin rather than about buying a
                // better box. A well-made box strapped on for forty minutes causes the same
                // low-temperature burn as a badly-made one: the injury mode is duration plus absent
                // sensation, not build quality.
                MoxaNotice()

                // The practitioner round's product advice, HIGHLIGHTED by design: it is the one
                // purchasable difference that changes how fast heat comes off skin.
                MoxaStrapAdvice()

                if readOnly {
                    Text(AppLocale.pick("下面是这些穴位的位置与传统说明。",
                                        "Below are the point locations and the traditional notes."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
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
///
/// THE TITLE IS THE WHOLE RULE, so the paragraph starts COLLAPSED. Device report: "the moxibustion
/// tab is too dense with words, nobody is going to read it that thoroughly" — and a paragraph
/// nobody reads protects nobody. "Quick-release straps, never tape" is the instruction; the body is
/// the reasoning behind it, which is worth one tap and is not worth spending the top of the screen
/// on. Nothing is deleted: `allCopy` still enumerates every string for the claims scan.
struct MoxaStrapAdvice: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(Self.title, systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Ink.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppLocale.pick("展开或收起选盒的理由", "Shows or hides why"))

            if expanded {
                Text(Self.body_)
                    .font(.caption).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Ink.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.gold, lineWidth: 1))
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

/// The standing safety note, shown above the points every time — the thing it says is the thing
/// most box owners do not know.
///
/// TWO LINES ARE VISIBLE; THE OTHER FOUR ARE ONE TAP AWAY. Six bullets of authored prose at the top
/// of the tab, repeated in full at the bottom of every placement card, is a wall — device report:
/// "too dense with words, nobody is going to read it that thoroughly." A safety notice that is
/// skipped conveys nothing, so the two that carry the INJURY MECHANISM and the ACTION lead (the box
/// removes the hand that would have noticed; look at the skin on a timer and stop while it is
/// lightly pink) and the rest — the temperature band, closed rooms, reignition, strapping while
/// lying down — sit behind a labelled disclosure that says how many are there.
///
/// NOTHING IS DELETED, and nothing here is the safety GATE: MoxaGateView's five questions are
/// forced on every entry and MoxaClockView enforces the skin checks structurally. This is the
/// reminder beside them. `lines` still returns all six, in order, so the claims scan is unchanged.
struct MoxaNotice: View {
    /// WHERE this notice is being shown, which is what decides how much of it leads. The TAB is the
    /// first thing a box owner sees, so it leads with the pair: the mechanism and the action. A
    /// PLACEMENT CARD is reached only by passing the gate AND scrolling past that pair, so repeating
    /// all of it there was the duplication the density report was really about — the card leads with
    /// the ACTION alone, and the rest is the same one tap away.
    enum Surface { case tab, card }

    var surface: Surface = .tab
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AppLocale.pick("艾灸是明火", "Moxibustion is an open flame"), systemImage: "flame")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.terracotta)
            ForEach(Self.visibleLines(surface), id: \.self) { bullet($0) }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text(expanded ? Self.fewerLabel : Self.moreLabel(for: surface))
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Ink.gold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(Self.hiddenLines(surface), id: \.self) { bullet($0) }
            }
        }
        .padding(14).panel()
    }

    private func bullet(_ line: String) -> some View {
        Text("• " + line).font(.caption).foregroundStyle(Ink.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// WHAT LEADS, per surface. The tab shows the mechanism and the action; the card shows the
    /// action. Both are expressed as a selection FROM `lines`, and what is hidden is defined as
    /// everything else — so no arrangement of this can drop a line or show one twice, and the
    /// disclosure's count is always the truth about what is behind it.
    static func visibleLines(_ surface: Surface) -> [String] {
        switch surface {
        case .tab:  return Array(lines.prefix(2))            // mechanism, then the action it answers
        case .card: return Array(lines.dropFirst().prefix(1))  // the action alone
        }
    }
    static func hiddenLines(_ surface: Surface) -> [String] {
        let shown = visibleLines(surface)
        return lines.filter { !shown.contains($0) }
    }

    /// Derived from the split, never hardcoded — a count that disagrees with what unfolds is how a
    /// user learns to distrust the disclosure.
    static func moreLabel(for surface: Surface) -> String {
        let n = hiddenLines(surface).count
        return AppLocale.pick("还有 \(n) 条要注意的", "\(n) more things to watch for")
    }
    static var fewerLabel: String { AppLocale.pick("收起", "Show fewer") }

    /// The tab surface, named — the split the safety tests reason about. `lines` is what the claims
    /// scan reads, so it must stay the whole set; `allCopy` adds every label either surface can draw.
    static var leadLines: [String] { visibleLines(.tab) }
    static var moreLines: [String] { hiddenLines(.tab) }
    static var moreLabel: String { moreLabel(for: .tab) }
    static var allCopy: [String] { lines + [moreLabel(for: .tab), moreLabel(for: .card), fewerLabel] }

    // Every line is authored, not translated — the source material for this topic is saturated with
    // the banned stems (艾灸的功效与作用, 足浴治疗), so a translated version would fail the scan.
    static var lines: [String] {
        // THE TWO VISIBLE LINES ARE THE SHORTEST TRUE FORM OF THEMSELVES. Second device report on
        // this tab: "too dense with words, nobody is going to read it that thoroughly." Length is
        // not thoroughness here — these two lines are the ones a user who reads nothing else must
        // still take away, so every clause that was context rather than instruction is gone.
        [AppLocale.pick("盒子固定住热源，也就拿走了「觉得烫就拿开」的那只手——家用低温烫伤最常见的原因。",
                        "A box straps the heat on and removes the hand that would have noticed it — the commonest cause of low-temperature burns at home."),
         // SECOND, AND THEREFORE VISIBLE: the mechanism above is only useful next to the thing to
         // DO about it. These two are the pair a user who reads nothing else should still have.
         AppLocale.pick("定时看皮肤，别只靠感觉；只是微微发红时就该停。",
                        "Look at the skin on a timer, not by feel — stop while it is still only lightly pink."),
         AppLocale.pick("44到50度持续够久，会由浅入深地伤到皮肤，而且一开始不太痛、表面看不出来。所以「不觉得烫」并不代表安全，时间才是关键。",
                        "Held long enough, 44–50 °C injures progressively from the surface downward — and it barely hurts at first and looks like very little. So \"it doesn't feel too hot\" is not a sign that it is safe; the variable that matters is time."),
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
    /// From the screening — the clock this card starts must inherit it, not re-decide it.
    var checksRequired: Bool = true

    @State private var showCamera = false
    @State private var showWalkthrough = false
    @State private var showClock = false
    /// Set once the user has been through either finding route. It only changes emphasis: the clock
    /// is never BLOCKED on it, because someone who already knows where their own Qihai is should not
    /// have to walk a tutorial to reach the one screen that enforces the skin checks.
    @State private var found = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(point.name).font(.title3).foregroundStyle(Ink.gold)
                    field(AppLocale.pick("位置", "Location"), point.location)
                    if !readOnly { field(AppLocale.pick("怎么找", "Finding it"), point.find) }
                    if !readOnly { flowSteps }
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
        .sheet(isPresented: $showCamera) {
            MoxaCameraLocateView(focus: point) { showCamera = false; found = true }
        }
        .sheet(isPresented: $showWalkthrough) {
            MoxaLocateFlow { showWalkthrough = false; found = true }
        }
        .sheet(isPresented: $showClock) {
            MoxaClockView(checksRequired: checksRequired) { showClock = false }
        }
    }

    // THE ORDER THE JOB ACTUALLY HAS: find the place, then start the clock that makes you look at
    // the skin. It used to be the other way round by accident — the clock sat at the top of the tab
    // where it could be started before a point had been chosen at all, and finding was a separate
    // button beside it that belonged to no point in particular.
    @ViewBuilder private var flowSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MoxaFlowCopy.stepsTitle)
                .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)

            step(1, MoxaFlowCopy.step1Title, done: found) {
                if MoxaTorsoAcupoints.isLocatable(point) {
                    Text(MoxaFlowCopy.step1Body).font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { showCamera = true } label: {
                            Label(MoxaFlowCopy.showMeOnCamera, systemImage: "camera.viewfinder")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered).tint(Ink.gold)
                        Button { showWalkthrough = true } label: {
                            Label(MoxaFlowCopy.measureWithFingers, systemImage: "hand.point.up.left")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered).tint(Ink.gold)
                    }
                } else {
                    // The back points get NO camera step, and this says why rather than leaving a
                    // button conspicuously missing. See MoxaTorsoAcupoints: they are anchored to the
                    // iliac-crest line, they are behind you, and their own data already marks them
                    // as an area because that landmark runs one to two vertebral levels high.
                    Text(MoxaFlowCopy.step1BodyOnBack).font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(2, MoxaFlowCopy.step2Title, done: false) {
                Text(MoxaFlowCopy.step2Body).font(.caption).foregroundStyle(Ink.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showClock = true } label: {
                    Label(MoxaFlowCopy.openTheClock, systemImage: "timer")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(Ink.gold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).panel()
    }

    @ViewBuilder private func step<Content: View>(_ n: Int, _ title: String, done: Bool,
                                                 @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Ink.jade.opacity(0.25) : Ink.gold.opacity(0.18))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Ink.jade)
                } else {
                    Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(Ink.gold)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(done ? AppLocale.pick("第 \(n) 步，已完成：\(title)", "Step \(n), done: \(title)")
                                 : AppLocale.pick("第 \(n) 步：\(title)", "Step \(n): \(title)"))
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
            Text(value).font(.subheadline).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The two steps a point card puts in order, in one enumerable place — the claims scans walk
/// `allCopy`, so a string rendered by the flow cannot be an unscanned surface.
///
/// THE WORDING IS DELIBERATELY ABOUT PLACE AND TIME, NEVER ABOUT EFFECT. "Find it" and "start the
/// clock" are things the user does; neither says the heat will do anything, and step two describes
/// the clock as what makes you look at the skin rather than as a treatment length.
enum MoxaFlowCopy {
    static var stepsTitle: String { AppLocale.pick("接下来两步", "Two steps from here") }

    static var step1Title: String { AppLocale.pick("先找到位置", "First, find the place") }
    static var step1Body: String {
        AppLocale.pick("用相机按你自己的身体比例标出来，或者自己用手指量一遍。两种都可以，量一遍更准。",
                       "Have the camera mark it by your own body's proportions, or measure it yourself in finger-widths. Either works; measuring is the more accurate of the two.")
    }
    static var step1BodyOnBack: String {
        AppLocale.pick("这一处在背后，自己看不到，相机也帮不上——照着上面「怎么找」的步骤，请人帮你找、帮你放盒子。",
                       "This one is on your back, where you cannot see it and the camera cannot help either. Use the finding steps above, and have someone else find it and place the box for you.")
    }
    static var showMeOnCamera: String { AppLocale.pick("用相机看", "Show me on camera") }
    static var measureWithFingers: String { AppLocale.pick("用手指量", "Measure in finger-widths") }

    static var step2Title: String { AppLocale.pick("再开始看皮肤的钟", "Then start the skin-check clock") }
    static var step2Body: String {
        AppLocale.pick("在钟上选时长，也可以先拍一张皮肤的照片作对照。照片只留在这次里，不会保存。",
                       "The clock is where you pick how long, and where you can take a before photo of the skin to compare against. The photo stays in this sitting only and is never saved.")
    }
    static var openTheClock: String { AppLocale.pick("打开计时", "Open the clock") }

    static var allCopy: [String] {
        [stepsTitle, step1Title, step1Body, step1BodyOnBack, showMeOnCamera, measureWithFingers,
         step2Title, step2Body, openTheClock]
    }
}

/// One placement: what it is, and the points on it. Tapping a point opens its own card, so each
/// point's location and caution live in exactly one place (MoxaAtlas) and the placement text never
/// restates them — the restating is how the two drift.
/// (No `readOnly` here. It existed only to forward to MoxaNotice, which no longer takes one — and a
/// parameter that is threaded from the screening result but read by nothing reads like the card
/// varies with the screening when it does not. The point cards this one opens still take it.)
struct MoxaPlacementCard: View {
    let placement: MoxaPlacement
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

                    MoxaNotice(surface: .card)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
