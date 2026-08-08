import Foundation

// 艾灸 — the moxibustion surface.
//
// WHY THIS IS A SEPARATE DATASET AND NOT `Acupoint.all`.
//
// The five points here are lower-abdominal and lumbar, and every one of them is pregnancy-restricted
// (the standard rule: under 3 months avoid the lower abdomen, from 3 months avoid abdomen AND
// lumbosacral points). The rest of the app deliberately runs WITHOUT a pregnancy screen — LI4, SP6,
// GB21, BL60 and BL67 are excluded outright precisely so that no gate is needed (see
// ChatLLM.excludedPointsEn/Zh). That trade only holds while no restricted point is reachable.
//
// `Acupoint.all` is enumerated by the atlas (AllPointsView.pointsByRegion), the meridian overlays,
// the 3D body, and — the one that matters most — the CHAT's point list (ChatLLM.swift). Appending
// these points there would put them in front of every user of every ungated surface, including the
// one that currently refuses to name SP6. So they are NOT in `Acupoint.all`, and a point that is not
// in `.all` cannot leak into a surface that enumerates `.all`. The separation is the safety
// mechanism; a `moxaOnly` flag filtered at twelve call sites would not be.
//
// SOURCING. Locations are from WHO 2008 (Standard Acupuncture Point Locations in the Western Pacific
// Region) and GB/T 12346—2021《经穴名称与定位》, then independently re-derived by a second pass. All
// five entries came back with corrections; two are worth recording because they are the kind of
// error that looks authoritative:
//
//   • The navel→pubis span is 5 cun in the MODERN standard. 《灵枢·骨度》 gives 天枢以下至横骨 =
//     6.5 cun for the same segment. Citing 灵枢 for "5" would be false provenance — and anyone who
//     "checked the source" and used 6.5 would place CV4 at 3/6.5 = 0.46 instead of 0.60, roughly
//     3 cm off on an adult torso. Cite GB/T for the number; 灵枢 only for the METHOD.
//   • A drafted "classical dosage: 艾炷灸 7–10 壮" was fabricated-plausible. 《扁鹊心书》 — the text
//     cited beside it — prescribes doses in the HUNDREDS of 壮. And 壮 counts cone-burns on skin,
//     which is not what a 艾灸盒 delivers at all. The unit does not apply to the device this tab
//     exists to serve, so no dose is stated in 壮 anywhere here.
//
// COPY RULES. Same as everywhere else: no treat / cure / heal / diagnose, no 治疗/治愈/根治/诊断/
// 医治/疗效. MoxaSafetyTests scans this file's strings the way testNoForbiddenMedicalClaims scans
// `Acupoint.all` — a new dataset is unguarded until it is explicitly added to the scan, which is how
// this one nearly shipped unscanned.

/// Where a point sits, expressed the way a person can actually find it on their own body: a
/// fraction along a span between two landmarks they mark themselves. This is 骨度分寸 (proportional
/// bone measurement) — the traditional method, not an approximation of it.
///
/// It exists because the camera coach cannot help here. Vision has a hand-pose model and no torso
/// model, so there are no landmarks to anchor to; the user supplies them instead. The tolerance
/// budget is what makes that acceptable: the acupressure ring is 0.12–0.24 hand-widths (~1.5–2 cm),
/// while a moxa box aperture is 5–6 cm for a single-hole and ≥10 cm for a multi-hole, so the target
/// is the size of the device, not the size of a fingertip.
struct MoxaAnchor {
    /// The two landmarks whose span defines the scale. Order matters: `fraction` is measured FROM
    /// `from` TOWARD `to`.
    let from: MoxaLandmark
    let to: MoxaLandmark
    /// Position along that span. 0 = at `from`, 1 = at `to`.
    let fraction: Double
    /// Sideways offset, as a fraction of a SEPARATE lateral span (see MoxaLandmark.lateralSpan).
    /// Zero for midline points. Non-zero points are bilateral — a plan that fires only one side is
    /// wrong, so `bilateral` is derived from this rather than stored twice.
    let lateral: Double
    var bilateral: Bool { lateral != 0 }
    /// Draw this as an AREA rather than a dot, because the landmark it derives from is not accurate
    /// enough to justify a dot.
    ///
    /// Only the lumbar points set this, and the reason is specific rather than general caution:
    /// palpating the iliac-crest line to find L4 carries a SYSTEMATIC UPWARD bias of one to two
    /// vertebral levels — roughly 3.5–7 cm — and the error is largest in women. A dot drawn from a
    /// landmark with that much bias is false precision, and false precision on a heat source is
    /// worse than an honest area. The abdominal points do not need it: the navel and the pubic
    /// border are static midline bone/scar landmarks, and marking error there propagates to about
    /// 1.3 cm.
    var drawAsArea: Bool { from == .iliacCrestLine }
}

/// How much the placement is allowed to be off, in centimetres, before the point falls outside the
/// device's footprint.
///
/// THIS CORRECTS A PREMISE THE FEATURE WAS DESIGNED ON. The assumption was that a moxa box covers a
/// large area, so precision barely matters. Measured against real products it is tighter than that:
/// a common single-hole 艾灸盒 aperture is about 5–6 cm, giving ±2 cm, and a multi-hole lumbar box
/// gives about ±3.5 cm. That is only ~1.5–2× the acupressure ring's tolerance, not the large factor
/// assumed. The method works anyway — but because the abdominal landmarks are stable, not because
/// the target is forgiving.
enum MoxaBox {
    static let singleHoleToleranceCm = 2.0
    static let multiHoleToleranceCm = 3.5
}

/// The user's own body, used as its own ruler — 同身寸 supplying the unit for 骨度分寸.
///
/// WHY THERE IS NO CAMERA HERE. Everything else in this app locates things by pointing a camera at
/// them, and this deliberately does not. Two reasons, both decisive: the region is the abdomen, and
/// asking someone to photograph it is a privacy cost this feature has no need to impose; and the
/// posture this is actually done in is lying down with a box, where holding a phone at arm's length
/// to frame your own belly is not a thing anyone will do. The tradition's own method needs neither.
///
/// THE ARITHMETIC IS WHY THIS WORKS. The span from navel to pubic border is 5 cun BY DEFINITION —
/// that is what a proportional measure means: the span is divided into a fixed number of parts
/// whatever its physical length, so a tall person's cun is simply longer. Measure that span in any
/// unit at all and a point at fraction f of it sits at f × (the measurement). So if someone reports
/// their span as 7 of their own finger-widths, 关元 at 0.60 is 4.2 finger-widths below the navel —
/// and no absolute centimetre figure is ever needed, which is exactly the property that makes the
/// method survive different bodies.
struct MoxaSpan: Equatable {
    /// How many of the user's own finger-widths span navel → pubic border, as they measured it.
    let fingerWidths: Double

    /// 一夫法: four fingers held together, measured across at the crease of the middle finger's
    /// middle joint, is 3 cun. The navel→pubis span is 5 cun, so it should come to about 6.7 finger
    /// widths on anyone — the number is a property of the proportional system, not of body size.
    static let cunPerFourFingers = 3.0
    static let spanCun = 5.0
    static var expectedFingerWidths: Double { spanCun / (cunPerFourFingers / 4.0) }

    /// Finger-widths below the navel for a point at `fraction` of the span.
    func fingerWidths(at fraction: Double) -> Double { fingerWidths * fraction }

    /// A measurement far from `expectedFingerWidths` is not a differently-shaped person — the
    /// proportional system already absorbs body size — so it means the measurement itself went
    /// wrong. The usual causes are worth naming rather than just flagging a number: fingers held
    /// splayed or at the wrong level, or a pubic border missed because a full bladder pads it.
    /// Deliberately wide: this prompts a re-check, it does not block anything.
    var looksMismeasured: Bool { fingerWidths < 4.5 || fingerWidths > 9.5 }
}

/// A body feature the user marks on themselves. Ranked by how reliably a non-expert finds the same
/// spot twice — which is the property that decides whether this method works at all.
enum MoxaLandmark: String {
    case navel              // 脐中 — unambiguous, and CV8 IS this point (fraction 0)
    case pubicBorder        // 耻骨联合上缘 — walk the fingers down the midline until bone stops them
    case sternocostal       // 胸剑联合中点 — where the ribs meet below the breastbone
    case iliacCrestLine     // 髂嵴最高点连线 — hands on hips; the line crosses the spine at L2 + 2 levels
    case lumbarL2           // derived, not marked: count UP two spinous processes from the crest line

    var zh: String {
        switch self {
        case .navel:          return "肚脐中心"
        case .pubicBorder:    return "耻骨上缘（小腹最下方摸到骨头的地方）"
        case .sternocostal:   return "胸骨下端、两侧肋骨交汇处"
        case .iliacCrestLine: return "两侧髂嵴最高点的连线"
        case .lumbarL2:       return "第2腰椎棘突下的凹陷"
        }
    }
    var en: String {
        switch self {
        case .navel:          return "the centre of your navel"
        case .pubicBorder:    return "the top edge of the pubic bone — walk your fingers down the midline until bone stops them"
        case .sternocostal:   return "where the ribs meet below the breastbone"
        case .iliacCrestLine: return "the line between the highest points of your hip bones"
        case .lumbarL2:       return "the hollow two spinous processes above that line"
        }
    }

    /// The lateral span a sideways offset is measured against, in cun, or nil for midline-only use.
    ///
    /// IMPLEMENTATION TRAP, recorded because re-deriving it wrongly is easy: the back's 3-cun
    /// half-span is defined at SCAPULAR level (posterior midline → medial border of the scapula) and
    /// is then used as a constant back-cun at every vertebral level. There is no scapula at L2. The
    /// scapular mark is consumed as an x-offset and reapplied at the L2 line — it is never measured
    /// on a horizontal line drawn at L2.
    var lateralSpanCun: Double? {
        switch self {
        case .lumbarL2, .iliacCrestLine: return 3.0   // midline → medial border of the scapula
        case .navel:                     return 4.0   // half of the 8-cun inter-nipple span
        default:                         return nil
        }
    }
}

/// A point this tab can direct a moxa box to. Deliberately NOT an `Acupoint` — see the file note.
struct MoxaPoint: Identifiable, Hashable {
    let id: String
    let zh: String
    let pinyin: String
    let anchor: MoxaAnchor
    let locationZh: String, locationEn: String
    /// How to find it on yourself, in the order the app asks for the landmarks.
    let findZh: String, findEn: String
    /// What the tradition groups this point with — in the CONCERN register `Acupoint.indications`
    /// already uses ("Traditionally associated with…"), never as an indication for a condition.
    let traditionZh: String, traditionEn: String
    /// Per-point safety note. Never empty in this dataset: every point here has one.
    let cautionZh: String, cautionEn: String
    /// On the back, where the user can neither see the site nor reach the box.
    let onBack: Bool

    static func == (a: MoxaPoint, b: MoxaPoint) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var location: String  { AppLocale.pick(locationZh, locationEn) }
    var find: String      { AppLocale.pick(findZh, findEn) }
    var tradition: String { AppLocale.pick(traditionZh, traditionEn) }
    var caution: String   { AppLocale.pick(cautionZh, cautionEn) }
    var name: String      { AppLocale.pick(zh, "\(zh) (\(pinyin))") }
}

enum MoxaAtlas {
    /// THE ABDOMINAL SET — the payoff of the proportional method. Navel → pubic border is one 5-cun
    /// span, and 神阙 / 气海 / 关元 sit at 0.00 / 0.30 / 0.60 along it. Two marks place all three.
    /// (中脘 CV12 is NOT in this list: it belongs to the UPPER span, 胸剑联合中点 → 脐中 = 8 cun, and
    /// reusing the lower span's scale for it would be wrong. It is already in the acupressure atlas.)
    static let abdomen: [MoxaPoint] = [
        MoxaPoint(
            id: "CV8", zh: "神阙", pinyin: "Shénquè",
            anchor: MoxaAnchor(from: .navel, to: .pubicBorder, fraction: 0.00, lateral: 0),
            locationZh: "在脐区，脐中央。（GB/T 12346—2021；WHO 2008 同）",
            locationEn: "In the umbilical region, at the centre of the navel. (GB/T 12346—2021; WHO 2008)",
            findZh: "不用量——穴位就是肚脐中心本身。",
            findEn: "Nothing to measure — the point is the centre of the navel itself.",
            traditionZh: "传统上被视为最容易定位的一个穴位，也是腹部两段骨度的共同起点。",
            traditionEn: "Traditionally the easiest point on the body to locate, and the origin both abdominal spans are measured from.",
            cautionZh: "不要往肚脐里放任何东西。传统做法是隔盐灸——把干净的干盐填平脐窝，艾炷放在盐上燃烧，盐本身就是隔热的那一层（「隔」就是隔着的意思）。艾灸盒是另一种现代替代做法。",
            cautionEn: "Never put anything into the navel. The classical method is salt-partitioned moxa — the navel filled level with clean dry salt and the cone burned on the salt, which is itself the insulating layer that 隔 (\"separated by\") names. A box is a different modern substitute for it.",
            onBack: false),
        MoxaPoint(
            id: "CV6", zh: "气海", pinyin: "Qìhǎi",
            anchor: MoxaAnchor(from: .navel, to: .pubicBorder, fraction: 0.30, lateral: 0),
            locationZh: "在下腹部，脐中下1.5寸，前正中线上。（GB/T 12346—2021；WHO 2008 同）",
            locationEn: "On the lower abdomen, on the anterior midline, 1.5 cun below the centre of the navel — equivalently 3.5 cun above the top edge of the pubic bone.",
            findZh: "先标出肚脐与耻骨上缘，穴位在这段距离靠近肚脐的三成处。",
            findEn: "Mark the navel and the top of the pubic bone; the point sits three tenths of the way down, nearer the navel.",
            traditionZh: "与关元同在脐到耻骨这一段骨度上，同处任脉前正中线。石门（CV5）就在这两处之间，一个艾灸盒无法既罩住两处又避开它；古籍对石门有专门针对有生育打算的女性的告诫，若你在意这一条，就一次只对准一个穴位。",
            traditionEn: "On the same navel-to-pubis span as Guanyuan, and on the same Ren-vessel midline. Shimen CV5 lies between the two, so no single box covers both of them and stays off it; the classical texts single Shimen out for women who may want to conceive, and if that matters to you, place the box for one point at a time.",
            cautionZh: "下腹部穴位：怀孕期间避免。请先看本页开头的说明。",
            cautionEn: "A lower-abdomen point, avoided during pregnancy. See the note at the top of this tab before using it.",
            onBack: false),
        MoxaPoint(
            id: "CV4", zh: "关元", pinyin: "Guānyuán",
            anchor: MoxaAnchor(from: .navel, to: .pubicBorder, fraction: 0.60, lateral: 0),
            locationZh: "在下腹部，脐中下3寸，前正中线上。（GB/T 12346—2021；WHO 2008 同）",
            locationEn: "On the lower abdomen, on the anterior midline, 3 cun below the centre of the navel — equivalently 2 cun above the top edge of the pubic bone.",
            findZh: "同一段距离，穴位在靠近耻骨的六成处。量之前请先排空膀胱、平躺——膀胱充盈时会盖过耻骨上缘这个骨性标志。",
            findEn: "Same span, six tenths of the way down toward the pubic bone. Mark it lying flat with an empty bladder — a full bladder rises above the pubic border and pads the landmark you are measuring from.",
            traditionZh: "小肠募穴，足三阴与任脉的交会处。常被引来为它背书的《扁鹊心书》那一段，与气海、中脘同列的第四个穴位是命关——窦材自己指的是食窦（SP17，在胸壁上），不是命门；而且那段写的是在皮肤上烧数百壮艾炷，与艾灸盒不是一回事。这里列出它，是因为它与气海同在脐到耻骨这一段骨度上。",
            traditionEn: "The Front-Mu point of the Small Intestine and a meeting point of the three foot yin channels with the Ren vessel. The 《扁鹊心书》 passage often quoted for it names Qihai, Zhongwan and — as its fourth point — Mingguan, which Dou Cai's own gloss puts at Shidou SP17 on the chest wall, not Mingmen; and what that passage describes is hundreds of cones burned on the skin, which is not what a box does. It is listed here because it falls on the same navel-to-pubis span as Qihai.",
            cautionZh: "下腹部穴位：怀孕期间避免——正是这个交会的位置使传统上对孕期格外谨慎。请先看本页开头的说明。",
            cautionEn: "A lower-abdomen point lying over the uterus, and avoided during pregnancy — that same crossing is why the tradition flags it. See the note at the top of this tab.",
            onBack: false),
    ]

    /// THE LUMBAR PAIR. Vertically these are NOT a proportional fraction — the lumbar axis has no
    /// 骨度 span, and the standard locates them by counting vertebrae from the iliac-crest line.
    ///
    /// TWO LANDMARK ERRORS THE UI MUST RULE OUT EXPLICITLY, because both are popular shortcuts:
    ///   • "Level with the navel" is WRONG. Surface-anatomy data cluster the umbilicus at L4, so it
    ///     lands one to two levels low — near BL25 大肠俞, not L2.
    ///   • Counting down from the lower rib margin lands too high.
    /// Only the iliac-crest route is used.
    static let lumbar: [MoxaPoint] = [
        MoxaPoint(
            id: "GV4", zh: "命门", pinyin: "Mìngmén",
            anchor: MoxaAnchor(from: .iliacCrestLine, to: .lumbarL2, fraction: 1.0, lateral: 0),
            locationZh: "在脊柱区，第2腰椎棘突下凹陷中，后正中线上。（GB/T 12346—2021；WHO 2008 同）",
            locationEn: "In the lumbar region, on the posterior midline, in the depression just below the spinous process of the 2nd lumbar vertebra (L2).",
            findZh: "双手叉腰、拇指向后，两侧髂嵴最高点的连线大约横过第4腰椎；从那里沿脊柱向上数两个棘突，穴位在棘突下方的凹陷里，不在骨头凸起上。",
            findEn: "Hands on hips, thumbs pointing back: the line between the highest points of your hip bones crosses the spine at about L4. Count up two spinous processes; the point is in the hollow just below the bump, not on it.",
            traditionZh: "在后正中线上，与两侧肾俞同处第2腰椎这一水平。《针灸甲乙经·卷三》记命门在「十四椎节下间」，记肾俞在「第十四椎下，两傍各一寸五分」，同为十四椎，即今之第2腰椎。",
            traditionEn: "On the posterior midline, at the same vertebral level as the pair of Shenshu points either side. 《针灸甲乙经》 vol. 3 puts Mingmen below the 14th vertebra and Shenshu below the 14th vertebra, 1.5 cun either side — the same vertebra, which is L2 in the modern count.",
            cautionZh: "在背部——自己看不到、也够不着。需要另一个人放置并按时查看皮肤，必须计时。不要躺着使用绑带式艾灸盒：绑上以后取不下来，而这正是最糟的情况。",
            cautionEn: "On the back — you can neither see the site nor reach the box. It needs a second person to place it and check the skin at set intervals, and it needs a timer. Never use a strap-on box lying down: a strapped box cannot be got off quickly, which is the worst failure mode for a spot that is already out of reach.",
            onBack: true),
        MoxaPoint(
            id: "BL23", zh: "肾俞", pinyin: "Shènshū",
            anchor: MoxaAnchor(from: .iliacCrestLine, to: .lumbarL2, fraction: 1.0, lateral: 0.5),
            locationZh: "在脊柱区，第2腰椎棘突下，后正中线旁开1.5寸。左右各一。（GB/T 12346—2021；WHO 2008 同）",
            locationEn: "In the lumbar region, level with the lower border of the L2 spinous process, 1.5 cun either side of the posterior midline. A bilateral pair, on the soft muscular ridge beside the spine — not on bone.",
            // SELF-CONTAINED on purpose. An earlier draft said "find L2 as for Mingmen" and "same
            // risks as Mingmen" — but these are separate cards, read one at a time, so a
            // cross-reference means the user on this card sees neither the landmark nor the
            // mitigation. Pinned by MoxaAtlasTests.
            findZh: "双手叉腰、拇指向后，两侧髂嵴最高点的连线大约横过第4腰椎；沿脊柱向上数两个棘突到第2腰椎。再从脊柱正中线向两侧各量1.5寸——把食指与中指并拢，大约就是这个宽度，成年人约3.5到4厘米。左右都要。",
            findEn: "Hands on hips, thumbs pointing back: the line between the highest points of your hip bones crosses the spine at about L4. Count up two spinous processes to L2. Then measure 1.5 cun out either side of the midline — index and middle fingers held together is about that width, roughly 3.5–4 cm on an adult. Both sides, always.",
            traditionZh: "肾之背俞穴，左右成对。它与命门同处第2腰椎这一水平——《针灸甲乙经》把两者都记在十四椎——这是位置上的关系，不是一个组方。",
            traditionEn: "The Back-Shu point of the Kidney, a bilateral pair. It sits at the same vertebral level as Mingmen — 《针灸甲乙经》 records both at the 14th vertebra — which is a fact about where they are, not a prescribed set.",
            cautionZh: "在背部——自己看不到、也够不着，需要另一个人放置并按时查看皮肤，必须计时。不要躺着使用绑带式艾灸盒。受热皮肤是两侧、面积加倍，艾灸盒可能放偏而只烫到一边，每次都要两侧都查。宽的多孔腰部灸盒（≥10厘米）居中放置可以同时覆盖命门与两侧肾俞；常见的单孔小盒（约5–6厘米）够不到旁开4厘米的肾俞，只能居中对准命门。两侧若分开做，每一次都是一次单独的施灸，各自计时；覆盖的地方多，不等于更多的热或更长的时间。",
            cautionEn: "On the back — you can neither see the site nor reach the box, so it needs a second person to place it and check the skin at set intervals, and it needs a timer. Never use a strap-on box lying down. Being a pair it also puts twice the skin area under heat, where a box can sit unevenly and burn one side only, so check both sides every time. A wide multi-hole lumbar box (10 cm or more across) centred on the midline covers Mingmen and both sides at once; a common single-hole box of about 5–6 cm does not reach 4 cm out, so centre it for Mingmen alone. If the two sides are done separately, each turn is its own separate application, timed on its own; covering more places is not more heat and not more time.",
            onBack: true),
    ]

    static let all: [MoxaPoint] = abdomen + lumbar

    /// Every point in this dataset is pregnancy-restricted, which is why the tab is gated rather
    /// than the points being individually flagged. Kept as an explicit list so the gate test can
    /// assert it covers all of them rather than trusting a comment.
    static var allRestrictedInPregnancy: Bool { all.allSatisfy { !$0.cautionEn.isEmpty } }
}

/// Terms that PASS `testNoForbiddenMedicalClaims` and are still health claims.
///
/// The four stems (treat/cure/heal/diagnos) are the necessary test. This is the part that test
/// cannot see, and the moxa surfaces are where the gap bites hardest: "improves circulation" clears
/// the existing scan, and it is the documented proximate cause of the burns in the foot-soak case
/// series — because a reason to believe the heat is DOING something is a reason to leave it on
/// longer, which is the injury mechanism. A claim that passes the suite is more dangerous than one
/// that fails it, since the green run says it is fine.
///
/// SCOPED TO THE MOXA SURFACES on purpose. Several of these terms ship today in `Acupoint.all`
/// beside a THUMB, where they are defensible — "vitality" on ST36, 缓解 on a chest point, 活血,
/// 补益, 调理 — and widening the scan to the whole atlas would fail on that existing copy. Widening
/// is the right eventual move; it is a separate edit to existing strings, not a thing to smuggle in
/// with a new feature.
///
/// NOT scanned against itself: like `ChatLLM.instructions`, this array quotes what it forbids.
enum MoxaSafety {
    static let extendedBannedEn: [String] = [
        "circulat",     // mechanism claim, and the most dose-escalating one available: it supplies
                        // the reason to apply more heat for longer, and contradicts MoxaNotice's own
                        // line that the variable which matters is TIME.
        "blood flow",   // the same claim in phrasal form — "circulat" does not catch it.
        "reliev", "relief",   // outcome verbs taking a symptom as object; separate stems.
        "alleviat",     // the same verb in a clinical coat.
        "improv",       // asserted change of state. Stem, so it also catches "improving".
        "boost", "enhance", "strengthen",   // betterment verbs pointed at a heat source.
        "detox",        // unfalsifiable internal mechanism with no defined referent.
        "immun",        // immune claims are treated as medicinal.
        "therap",       // closes a bilingual hole: zh 疗效 is banned while EN "therapy" sailed through.
        "remedy",       // places the app in the medical-intervention register.
        "restor",       // "restores balance" and family.
    ]

    static let extendedBannedZh: [String] = [
        "调理",          // the tradition's own "regulate", taking a complaint as object — 主治 softened.
        "功效", "主治",   // pharmacopoeia headings: "actions/efficacy" and "indicated for". 主治
                        // contains 治 but the base list holds only two-character compounds, so the
                        // most prescription-shaped word in the vocabulary was otherwise unguarded.
        "疗程",          // "course of treatment" — implies dosing, which this tab never does.
        "驱寒", "祛湿",   // mechanism plus an agent acting on the body; 祛湿 asserts removal of a
                        // substance nobody can point to. Dose-escalating like "circulation".
        "温补", "温阳", "补益",     // supplementation mechanism.
        "排毒", "免疫",             // unfalsifiable / medicinal.
        "保健",          // literally "health care" — the zh route back to the English string "heal".
                        // 保养 and 温养 are the clean alternatives.
        "血液循环", "活血",         // the zh twins of "circulation".
        "缓解",          // the zh "relieve".
        "改善", "增强",             // the standard zh betterment verbs.
        "冬病夏治", "治未病",       // pass the literal test and MEAN "treat winter disease in summer"
                        // and "treat disease before it arises". Semantic claims.
        "长寿",          // the 长寿穴 framing that attaches itself to ST36.
        "三里常不干",     // a provenance trap rather than a claim: 不干 means keeping a moxa sore
                        // RUNNING. Beside a warm box it asserts continuity with a scarring practice,
                        // and it reads as a harmless proverb, so it survives review more easily
                        // than an explicit dose would.
    ]

    /// 养生 is deliberately absent: as a zh category label it carries no object and no outcome, so it
    /// asserts nothing. The claim enters at TRANSLATION — which is why it must never be rendered
    /// word-for-word into English. Likewise 温养 survives: warm-and-nourish with no pathogen expelled
    /// and no organ supplemented, and its English twin "warming" describes what the device does.
    ///
    /// Also deliberately absent: bare 疗 (it would ban 医疗, and 「并非医疗工具」 is a DISCLAIMER — the
    /// sentence that disclaims must stay writable), 作用 (bans 副作用, legitimate safety copy), and
    /// "prevent" (needed for ordinary sentences about the box sliding).
    static let deliberatelyPermitted = ["养生", "温养", "保养", "医疗", "副作用"]
}
