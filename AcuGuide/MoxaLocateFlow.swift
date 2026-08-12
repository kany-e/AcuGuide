import SwiftUI

// FINDING THE SPOT ON YOUR OWN BODY — the navel-and-pubic-bone walkthrough.
//
// Four steps, in the order the body wants them: get into the position that makes the landmarks
// honest, find the two landmarks, measure the span between them in your own finger-widths, then read
// off where each point falls. The whole method is 骨度分寸 with 同身寸 supplying the unit, which is
// what the tradition actually does; the app's contribution is the arithmetic and the sanity check,
// not a new technique.
//
// THE POSITION STEP IS NOT PADDING. Both landmarks move if you get it wrong: a full bladder rises
// above the pubic symphysis and pads the one bony reference the whole span depends on, and standing
// versus lying changes the soft-tissue distance between the two. Skipping it would give a confidently
// computed answer built on a mismeasured span, which is worse than no answer.
struct MoxaLocateFlow: View {
    let onFinished: () -> Void

    private enum Step: Int, CaseIterable { case position, navel, pubis, measure, result }
    @State private var step: Step = .position
    @State private var fingerWidths: Double? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progress
                    switch step {
                    case .position: positionStep
                    case .navel:    navelStep
                    case .pubis:    pubisStep
                    case .measure:  measureStep
                    case .result:   resultStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            footer
        }
        .background(ShanshuiBackground().ignoresSafeArea())
    }

    // MARK: - Steps

    private var positionStep: some View {
        stepBody(
            title: AppLocale.pick("先躺下", "Lie down first"),
            lines: [
                AppLocale.pick("平躺，膝盖可以微微屈起，让肚子放松。",
                               "Lie flat, knees bent a little if that is comfortable, so the belly is relaxed."),
                AppLocale.pick("先去一趟洗手间。膀胱是胀的时候会盖过耻骨上缘——而整段距离就是从那里量起的。",
                               "Empty your bladder first. A full one rises above the pubic bone and pads the very landmark the whole measurement is taken from."),
                AppLocale.pick("站着和躺着量出来不一样，所以从头到尾都保持躺着。",
                               "Standing and lying give different answers, so stay lying down for all of it."),
            ])
    }

    private var navelStep: some View {
        stepBody(
            title: AppLocale.pick("第一处：肚脐", "First mark: your navel"),
            lines: [
                AppLocale.pick("把一根手指放在肚脐正中心。这一处不用找——它本身就是神阙穴。",
                               "Put one finger in the centre of your navel. Nothing to hunt for — this one is itself the point called Shenque."),
                AppLocale.pick("整段距离的起点就在这里。",
                               "This is where the span starts."),
            ])
    }

    private var pubisStep: some View {
        stepBody(
            title: AppLocale.pick("第二处：耻骨上缘", "Second mark: the top of the pubic bone"),
            lines: [
                AppLocale.pick("从肚脐沿着身体正中线，用手指一点一点向下滑。",
                               "From the navel, walk your fingers down the midline of your belly, a little at a time."),
                AppLocale.pick("滑到某一处会被骨头挡住——那道硬硬的横向骨缘就是耻骨上缘。停在那里。",
                               "At some point bone stops you — a firm ridge running across. That ridge is the top edge of the pubic bone. Stop there."),
                AppLocale.pick("这是整段距离的终点。中间这一段，传统上定为5寸，不论高矮胖瘦都一样——所以下面用你自己的手指来量它。",
                               "That is where the span ends. The tradition fixes this stretch at 5 cun for everyone, tall or short — which is why the next step measures it with your own fingers."),
            ])
    }

    private var measureStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocale.pick("量一量这段有多长", "Measure that stretch"))
                .font(.title3).foregroundStyle(Ink.gold)
            Text(AppLocale.pick(
                "把食指、中指、无名指、小指并拢，以中指第二个关节的横纹处为准——这四指并拢的宽度，传统上算作3寸。用它从肚脐一路量到耻骨上缘，大约是几个四指宽？可以按半格来选。",
                "Hold your index, middle, ring and little fingers together, measured across at the crease of your middle finger's middle joint. That four-finger width is counted as 3 cun. Step it from your navel down to the pubic bone — how many finger-widths is it? Half-steps are fine."))
                .font(.subheadline).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)

            // Offered as taps rather than a free number field: this is being done one-handed, lying
            // down, with the other hand still on the body holding the place.
            let options: [Double] = [5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { n in
                    Button { fingerWidths = n } label: {
                        Text(fmt(n))
                            .font(.subheadline.weight(fingerWidths == n ? .semibold : .regular))
                            .foregroundStyle(fingerWidths == n ? .black : Ink.text)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Capsule().fill(fingerWidths == n ? Ink.gold : .clear))
                            .overlay(Capsule().stroke(fingerWidths == n ? Ink.gold : Ink.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .accessibilityLabel(AppLocale.pick("\(fmt(n)) 个手指宽", "\(fmt(n)) finger widths"))
                    .accessibilityAddTraits(fingerWidths == n ? [.isSelected] : [])
                }
            }

            if let f = fingerWidths, MoxaSpan(fingerWidths: f).looksMismeasured {
                Text(AppLocale.pick(
                    "这个数字偏离常见范围不少。通常不是身材的关系——按比例量本来就已经把高矮算进去了——多半是手指没并拢、或者没真的摸到耻骨上缘（膀胱胀的时候尤其容易）。再量一次看看。",
                    "That is well outside the usual range. It is generally not body size — measuring by proportion already accounts for that — so it is more often fingers held apart, or the pubic ridge not quite reached, which a full bladder makes easy. Worth measuring again."))
                    .font(.caption).foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resultStep: some View {
        let span = MoxaSpan(fingerWidths: fingerWidths ?? MoxaSpan.expectedFingerWidths)
        return VStack(alignment: .leading, spacing: 16) {
            Text(AppLocale.pick("你的三个位置", "Your three spots"))
                .font(.title3).foregroundStyle(Ink.gold)
            Text(AppLocale.pick(
                "都是从肚脐往下量，用你刚才那个四指宽。",
                "All measured downward from the navel, in the finger-width you just used."))
                .font(.subheadline).foregroundStyle(Ink.text)

            ForEach(MoxaAtlas.abdomen) { p in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                        Spacer()
                        Text(distanceText(p, span)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.gold).monospacedDigit()
                    }
                    Text(p.tradition).font(.caption2).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).panel()
            }

            Text(AppLocale.pick(
                "如果只用一个艾灸盒同时覆盖气海和关元，请以气海为中心——正好放在两者中间，热源会落在石门上。",
                "If one box is covering both Qihai and Guanyuan, centre it on Qihai — centring it midway between them puts the heat on Shimen instead."))
                .font(.caption).foregroundStyle(Ink.textDim)
                .fixedSize(horizontal: false, vertical: true)

            MoxaNotice()
        }
    }

    /// "at the navel" for the origin, otherwise N finger-widths below it. Saying "0.0 finger-widths
    /// below the navel" for 神阙 would be arithmetically true and useless.
    private func distanceText(_ p: MoxaPoint, _ span: MoxaSpan) -> String {
        let f = span.fingerWidths(at: p.anchor.fraction)
        guard f > 0.05 else { return AppLocale.pick("就是肚脐", "the navel itself") }
        return AppLocale.pick("肚脐下 \(fmt(f)) 指", "\(fmt(f)) finger-widths below")
    }

    private func fmt(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n)
    }

    // MARK: - Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Ink.gold : Ink.line)
                    .frame(height: 3)
            }
        }
        .accessibilityLabel(AppLocale.pick("第 \(step.rawValue + 1) 步，共 \(Step.allCases.count) 步",
                                           "Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    private func stepBody(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).foregroundStyle(Ink.gold)
            ForEach(lines, id: \.self) { l in
                Text(l).font(.subheadline).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .position {
                Button(AppLocale.pick("上一步", "Back")) {
                    step = Step(rawValue: step.rawValue - 1) ?? .position
                }
                .font(.subheadline).tint(Ink.gold)
            }
            Spacer(minLength: 0)
            Button(step == .result ? AppLocale.pick("完成", "Done")
                                   : AppLocale.pick("下一步", "Next")) {
                if step == .result { onFinished() }
                else { step = Step(rawValue: step.rawValue + 1) ?? .result }
            }
            .buttonStyle(GoldButtonStyle())
            // The measure step is the only one with something to supply, so it is the only one that
            // can block: everything else is read-and-continue.
            .disabled(step == .measure && fingerWidths == nil)
            .opacity(step == .measure && fingerWidths == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
    }
}
