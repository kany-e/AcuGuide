import SwiftUI

// 艾灸 — the moxibustion tab.
//
// WHO THIS IS FOR, because it decides everything else: someone who ALREADY OWNS a 艾灸盒 and does
// not know where to put it. Moxa boxes are ordinary consumer products in China; the person is going
// to use theirs whether or not this app exists, so the useful question is not "should they" but
// "what do they most need to know". The answer turned out not to be location — it is that the box
// is the form that removes the hand, and the hand is the safety mechanism.
//
// SO THIS TAB LOCATES AND DESCRIBES; IT NEVER DOSES. There is no countdown, no camera targeting and
// no "hold it here for N minutes". Telling someone where 关元 is, is not instructing moxibustion —
// the app already locates 33 points and a point's location does not change with what you do to it.
// Starting a timer is a different act, and it is the one that would make the app the author of the
// session rather than of the map.
struct MoxaTab: View {
    @State private var screening: MoxaScreening? = nil
    @State private var selected: MoxaPoint? = nil
    @State private var showLocate = false

    var body: some View {
        NavigationStack {
            Group {
                if let s = screening {
                    list(readOnly: s.blocksHeat)
                } else {
                    // The gate is FORCED and per-session: there is no path into the content that
                    // does not pass through it, and it re-asks on every entry because the things it
                    // asks about change (a pregnancy, a healing burn, a new numbness).
                    MoxaGateView { screening = $0 }
                }
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationTitle(AppLocale.pick("艾灸", "Moxibustion"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { MoxaPointCard(point: $0, readOnly: screening?.blocksHeat ?? true) }
        .sheet(isPresented: $showLocate) { MoxaLocateFlow { showLocate = false } }
    }

    private func list(readOnly: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // THE SAFETY COPY LEADS, and it is about time and skin rather than about buying a
                // better box. A well-made box strapped on for forty minutes causes the same
                // low-temperature burn as a badly-made one: the injury mode is duration plus absent
                // sensation, not build quality.
                MoxaNotice(readOnly: readOnly)

                if readOnly {
                    Text(AppLocale.pick("下面是这些穴位的位置与传统说明。",
                                        "Below are the point locations and the traditional notes."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                }

                if !readOnly {
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

                section(AppLocale.pick("下腹部", "Lower abdomen"),
                        note: AppLocale.pick("只要标出肚脐和耻骨上缘两个位置，这三个穴位就都能定出来。",
                                             "Mark two places — your navel and the top of the pubic bone — and all three of these are placed."),
                        points: MoxaAtlas.abdomen)

                section(AppLocale.pick("腰部", "Lower back"),
                        note: AppLocale.pick("背部的位置只能给出大致范围：靠摸髂嵴来数腰椎，通常会偏高一到两节。这两个穴位都需要另一个人帮忙。",
                                             "The back can only be given as an area: finding the vertebrae by feeling for the hip bones runs one to two levels high. Both of these need a second person."),
                        points: MoxaAtlas.lumbar)
            }
            .padding()
        }
    }

    private func section(_ title: String, note: String, points: [MoxaPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Ink.gold)
            Text(note).font(.caption).foregroundStyle(Ink.textDim)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(points) { p in
                Button { selected = p } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                            Text(p.location).font(.caption2).foregroundStyle(Ink.textDim)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if p.onBack {
                            Text(AppLocale.pick("需人帮忙", "needs help"))
                                .font(.caption2.weight(.semibold)).foregroundStyle(Ink.warn)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ink.textDim)
                    }
                    .padding(12).panel()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.name). \(p.location)")
            }
        }
    }
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
                    Text(AppLocale.pick("本应用不会带你实际操作艾灸，也不计时。若想尝试，请当面找有资质的专业人士。",
                                        "AcuGuide does not run a moxibustion session or time one. If you want to try it, do that in person with a qualified practitioner."))
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
