import SwiftUI

// Sources & Evidence — a dedicated, honest citation screen. Raises the authoritativeness of the
// "effects" the app describes WITHOUT overclaiming: it shows how many controlled trials / reviews
// the OCOM AcuTrials database indexes per wellness concern, names one flagship review each, and
// separates that (contested efficacy) from point-LOCATION authority (WHO 2008, well established).
// Every string stays within the wellness-only posture — no treat/cure/heal/diagnose copy.
//
// Data sourced + adversarially verified: claude-deliverables/references/acuguide_source_upgrade.md.

struct EvidenceEntry: Identifiable {
    var id: String { conditionEn }
    let symptomZh: String, symptomEn: String   // the wellness concern as the app frames it
    let conditionEn: String                     // the AcuTrials condition label
    let count: Int                              // indexed studies in AcuTrials
    let citationZh: String, citationEn: String  // one flagship systematic review / meta-analysis
    let url: String                             // AcuTrials item page

    // Which atlas points this concern is traditionally associated with (for per-point deep links).
    let pointIds: [String]
}

struct SourceRef: Identifiable {
    var id: String { url }
    let nameZh: String, nameEn: String
    let noteZh: String, noteEn: String
    let url: String
}

enum Evidence {
    // AcuTrials indexed counts + one flagship review each (verified item URLs). Honest framing only.
    static let entries: [EvidenceEntry] = [
        EvidenceEntry(symptomZh: "恶心 / 反胃", symptomEn: "Nausea & queasiness", conditionEn: "Vomiting", count: 44,
            citationZh: "Cheong 等，《PLoS ONE》2013 — 内关(PC6)指压综述与荟萃分析。",
            citationEn: "Cheong et al., PLoS ONE 2013 — systematic review & meta-analysis of PC6 stimulation.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/10842", pointIds: ["PC6"]),
        EvidenceEntry(symptomZh: "头部紧张", symptomEn: "Head tension", conditionEn: "Headache Disorders", count: 88,
            citationZh: "Davis 等，《J Pain》2008 — 紧张性头痛随机对照试验荟萃分析。",
            citationEn: "Davis et al., J Pain 2008 — meta-analysis of RCTs for tension-type headache.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/9402", pointIds: ["TE3", "SJ5", "EX-HN5", "GV20"]),
        EvidenceEntry(symptomZh: "睡眠不安", symptomEn: "Restful sleep", conditionEn: "Sleep Disorders", count: 35,
            citationZh: "Shergis 等，《Complement Ther Med》2016 — 针刺与失眠睡眠质量综述。",
            citationEn: "Shergis et al., Complement Ther Med 2016 — review of acupuncture & sleep quality in insomnia.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/9086", pointIds: ["HT7", "PC8", "EX-HN3", "EX-HN1"]),
        EvidenceEntry(symptomZh: "情绪与压力", symptomEn: "Mood & stress", conditionEn: "Mental Disorders", count: 115,
            citationZh: "Chan 等，《J Affect Disord》2015 — 针刺联合抗抑郁药综述与荟萃分析。",
            citationEn: "Chan et al., J Affect Disord 2015 — review of acupuncture with antidepressant medication.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/10788", pointIds: ["HT7", "PC8", "EX-HN3"]),
        EvidenceEntry(symptomZh: "颈部不适", symptomEn: "Neck comfort", conditionEn: "Neck Pain", count: 50,
            citationZh: "Fu 等，《J Altern Complement Med》2009 — 颈部不适随机对照试验综述与荟萃分析。",
            citationEn: "Fu et al., J Altern Complement Med 2009 — systematic review & meta-analysis for neck pain.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/10657", pointIds: ["SI3", "SJ5"]),
        EvidenceEntry(symptomZh: "肩部不适", symptomEn: "Shoulder comfort", conditionEn: "Shoulder Pain", count: 32,
            citationZh: "Dong 等，《Medicine》2015 — 肩部不适网状荟萃分析。",
            citationEn: "Dong et al., Medicine 2015 — PRISMA network meta-analysis for shoulder impingement.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/11011", pointIds: ["SI3", "SJ5"]),
        EvidenceEntry(symptomZh: "经期舒适", symptomEn: "Menstrual comfort", conditionEn: "Menstruation Disturbances", count: 31,
            citationZh: "Xu 等，《BMC CAM》2017 — 穴位刺激与经期不适综述（19 项 RCT）。",
            citationEn: "Xu et al., BMC CAM 2017 — acupoint stimulation vs NSAIDs, 19 RCTs.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/10142", pointIds: ["SP10"]),
        EvidenceEntry(symptomZh: "消化舒适", symptomEn: "Digestive comfort", conditionEn: "Gastrointestinal Diseases", count: 65,
            citationZh: "Kim 等，《Complement Ther Med》2015 — 功能性消化不良综述与荟萃分析。",
            citationEn: "Kim et al., Complement Ther Med 2015 — review of acupuncture for functional dyspepsia.",
            url: "https://acutrials.ocom.edu/s/acutrials/item/10262", pointIds: ["ST36", "CV12", "ST25", "ST44"]),
    ]

    static func forPoint(_ id: String) -> EvidenceEntry? { entries.first { $0.pointIds.contains(id) } }

    // Where the point LOCATIONS come from — the well-established, non-contested part.
    static let locationSources: [SourceRef] = [
        SourceRef(nameZh: "WHO 标准穴位定位 (2008)", nameEn: "WHO Standard Acupuncture Point Locations (2008)",
            noteZh: "361 个穴位的国际标准定位，本应用穴位定位的主要依据。",
            noteEn: "The international consensus standard for 361 point locations — the app's primary location authority.",
            url: "https://iris.who.int/items/f188654a-d8a7-4519-9979-8e2de713c060"),
        SourceRef(nameZh: "穴位定位图谱 (Atlas of Acupuncture Points)", nameEn: "Atlas of Acupuncture Points",
            noteZh: "十四经络的循行路线与穴位定位，用于经络图与定位说明。",
            noteEn: "Channel pathways and point locations for the fourteen meridians — used for the meridian drawings and location text.",
            url: "https://chiro.org/acupuncture/ABSTRACTS/FILES/Acupuncture_Points.pdf"),
        SourceRef(nameZh: "Yin Yang House 穴位数据库", nameEn: "Yin Yang House point database",
            noteZh: "穴位的经典归类（五输、原、络、募等）与传统作用，用于穴位卡片。© Chad J. Dupuis, L.Ac.",
            noteEn: "Classical point categories (Five-Shu, Yuan, Luo, Front-Mu …) and traditional roles — used for the point cards. © Chad J. Dupuis, L.Ac.",
            url: "https://yinyanghouse.com/theory/acupuncturepoints/"),
    ]

    // Cross-references we consulted but do not embed (why, honestly, on the screen).
    static let crossRefs: [SourceRef] = [
        SourceRef(nameZh: "TARA — 穴位研究拓扑图谱 (MGB / NCCIH)", nameEn: "TARA — Topological Atlas & Repository for Acupoint Research (MGB / NCCIH)",
            noteZh: "一个 3D 穴位/经络可视化图谱（Beta）。作为交叉参考，不并入本应用。",
            noteEn: "A 3D acupoint/meridian visualization atlas (beta). Consulted as a cross-reference; not embedded.",
            url: "https://tara-repository.mgb.org/visual_search"),
        SourceRef(nameZh: "AcuSim — 合成穴位数据集（《Nature Scientific Data》2025）", nameEn: "AcuSim — synthetic acupoint dataset (Nature Sci Data 2025)",
            noteZh: "头颈部穴位的合成 RGB-D 数据集，验证了“依解剖标志定位穴位”的思路。因需深度数据且许可为非商用，不并入。",
            noteEn: "A synthetic RGB-D head/neck acupoint dataset that validates the landmark-based localization approach. Needs depth data and is non-commercial-licensed, so it is not embedded.",
            url: "https://www.nature.com/articles/s41597-025-04934-9"),
        SourceRef(nameZh: "MetaAcuPoint — 合成手部穴位数据集（2025）", nameEn: "MetaAcuPoint — synthetic hand-acupoint dataset (2025)",
            noteZh: "开放许可(CC BY 4.0)的合成 RGB 手/前臂穴位定位数据集，且包含 TE3 与 TE5。仅需普通 RGB、部位相符，是未来端上穴位识别最可行的基础；本版本暂未并入。",
            noteEn: "An openly-licensed (CC BY 4.0) synthetic RGB dataset for hand/forearm acupoint localization that includes TE3 and TE5. RGB-only and on-region, so it is the most viable basis for a future on-device point-finder; not embedded in this build.",
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12691809/"),
        SourceRef(nameZh: "FAcupoint — 面部穴位数据集（《Expert Systems with Applications》2025）", nameEn: "FAcupoint — facial acupoint dataset (Expert Systems with Applications 2025)",
            noteZh: "首个密集面部穴位数据集（654 张图像、43 个穴位、医师标注），基于 RGB 面部关键点，印证了本应用面部定位所用的关键点方法。数据仅按需申请，故未并入。",
            noteEn: "The first dense facial-acupoint dataset (654 images, 43 points, physician-annotated) using RGB face landmarks — it validates the landmark approach our face locator uses. Available only on request, so not embedded.",
            url: "https://doi.org/10.1016/j.eswa.2025.126683"),
    ]
}

struct SourcesView: View {
    var focusPointId: String? = nil            // when opened from a point card, highlight its concern
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openURL) private var openURL

    private var focusCondition: String? { focusPointId.flatMap { Evidence.forPoint($0)?.conditionEn } }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    section(AppLocale.pick("效果的研究证据", "Research on the effects")) {
                        Text(AppLocale.pick(
                            "以下为 OCOM 的 AcuTrials 数据库中针对每类养生需求所收录的随机对照试验与系统综述数量，并各列一篇代表性综述。研究文献确实存在，但个体反应因人而异，并不等于确定有效。",
                            "Below is how many randomized trials and systematic reviews OCOM's AcuTrials database indexes for each wellness concern, with one flagship review each. A research literature exists, but individual results vary — this is not assured relief."))
                            .font(.footnote).foregroundStyle(Ink.textDim)
                        ForEach(Evidence.entries) { e in evidenceCard(e) }
                    }
                    section(AppLocale.pick("穴位定位的依据", "Where the point locations come from")) {
                        ForEach(Evidence.locationSources) { s in sourceRow(s) }
                    }
                    section(AppLocale.pick("交叉参考", "Cross-references consulted")) {
                        ForEach(Evidence.crossRefs) { s in sourceRow(s) }
                    }
                    Text(AppLocale.pick(
                        "仅供养生自我保养参考，非医疗建议，也不能替代专业医疗。",
                        "Wellness self-care reference only — not medical advice, and not a substitute for professional care."))
                        .font(.caption2).foregroundStyle(Ink.textDim).padding(.top, 4)
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(AppLocale.pick("来源与证据", "Sources & Evidence"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocale.pick("我们如何看待“效果”", "How we talk about “effects”"))
                .font(Typo.serif(18, weight: .semibold)).foregroundStyle(Ink.gold)
            Text(AppLocale.pick(
                "穴位定位有充分的国际标准依据；而“是否有效”在科学上仍有争议——多数穴位源自传统、证据有限，最有力的例外是用于恶心的内关(PC6)。我们把它视为温和的放松性自我保养。",
                "Point locations are well supported by an international standard; whether pressing them is effective is still scientifically contested — most points are traditional with limited evidence, the strongest exception being PC6 for nausea. We frame it as gentle, relaxing self-care."))
                .font(.subheadline).foregroundStyle(Ink.text).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding().panel()
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(Ink.gold).textCase(.uppercase)
            content()
        }
    }

    private func evidenceCard(_ e: EvidenceEntry) -> some View {
        let highlight = e.conditionEn == focusCondition
        return Button { if let u = URL(string: e.url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(AppLocale.pick(e.symptomZh, e.symptomEn))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                    Spacer()
                    Text(AppLocale.pick("\(e.count) 项研究", "\(e.count) studies"))
                        .font(.caption2.weight(.bold)).foregroundStyle(Ink.gold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Ink.jade.opacity(0.16)))
                }
                Text(AppLocale.pick(e.citationZh, e.citationEn))
                    .font(.caption).foregroundStyle(Ink.textDim).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square").font(.caption2)
                    Text(AppLocale.pick("在 AcuTrials 查看", "View on AcuTrials")).font(.caption2)
                }.foregroundStyle(Ink.gold)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Ink.paperLight))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(highlight ? Ink.gold : Ink.line, lineWidth: highlight ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocale.pick("\(e.symptomZh)，\(e.count) 项研究，在 AcuTrials 查看",
                                           "\(e.symptomEn), \(e.count) studies, view on AcuTrials"))
    }

    private func sourceRow(_ s: SourceRef) -> some View {
        Button { if let u = URL(string: s.url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(AppLocale.pick(s.nameZh, s.nameEn)).font(.subheadline.weight(.medium)).foregroundStyle(Ink.text)
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(Ink.gold)
                }
                Text(AppLocale.pick(s.noteZh, s.noteEn))
                    .font(.caption).foregroundStyle(Ink.textDim).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.paperLight))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
