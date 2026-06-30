import SwiftUI

struct ChatMessage: Identifiable { let id = UUID(); let role: Role; let text: String
    var suggestions: [Acupoint] = []     // practiceable points offered as tappable "Practice" buttons
    enum Role { case user, coach } }

// A coach reply: prose + any practiceable points to surface as launch-the-coach buttons.
struct CoachAnswer { let text: String; let suggestions: [Acupoint] }

// One general-knowledge entry for the offline coach (ported from the verified research FAQ set).
struct CoachFAQ { let topic: String; let keywords: [String]; let aZh: String; let aEn: String
    var answer: String { AppLocale.pick(aZh, aEn) } }

// Fully OFFLINE bilingual acupressure helper. No network, no API key, no accounts, no
// telemetry — nothing to secure or leak. Replies are generated locally from the acupoint atlas,
// the meridian descriptions, and a verified general-knowledge FAQ. The wellness-only safety
// posture is enforced directly here: it never diagnoses/treats/cures, and red-flag symptoms
// always route to a stop-and-seek-care reply (matching the web app).
final class ChatService {
    // Order matters: SAFETY first, then the most specific lookup that matched, then general help.
    // Each branch may attach practiceable points the UI turns into "Practice with camera" buttons.
    func reply(to user: String, history: [ChatMessage]) async -> CoachAnswer {
        let raw = user
        let q = user.lowercased()
        if mentionsRedFlag(raw: raw, lowered: q) { return CoachAnswer(text: redFlagReply(), suggestions: []) }
        if let point = matchPoint(raw: raw, lowered: q) {
            return CoachAnswer(text: pointReply(point), suggestions: practiceable([point]))
        }
        if let pts = matchSymptom(raw: raw, lowered: q) {
            return CoachAnswer(text: symptomReply(pts), suggestions: pts)
        }
        if let mer = matchMeridian(raw: raw, lowered: q) {
            return CoachAnswer(text: meridianReply(mer), suggestions: practiceable(mer.points))
        }
        if let faq = matchFAQ(raw: raw, lowered: q) { return CoachAnswer(text: faq.answer, suggestions: []) }
        return CoachAnswer(text: generalReply(), suggestions: practiceable(headlinePoints))
    }

    // Practiceable = has a validated AR target. Dedup, cap a few so the bubble stays compact.
    private func practiceable(_ pts: [Acupoint]) -> [Acupoint] {
        var seen = Set<String>(); var out: [Acupoint] = []
        for p in pts where p.mediapipeTarget != nil && !seen.contains(p.id) {
            seen.insert(p.id); out.append(p); if out.count == 4 { break }
        }
        return out
    }
    private var headlinePoints: [Acupoint] {
        ["TE3", "PC6", "SI3", "HT7"].compactMap { Acupoint.byId[$0] }
    }

    // Map a wellness concern to gentle, practiceable self-care points (NOT a diagnosis). Runs after
    // a direct point lookup, so "PC6 for nausea" still resolves to the point itself.
    private func matchSymptom(raw: String, lowered: String) -> [Acupoint]? {
        let groups: [(kw: [String], ids: [String])] = [
            (["headache", "migraine", "tension head", "head ache", "头痛", "头疼", "偏头痛"], ["TE3", "SJ5"]),
            (["nausea", "queasy", "motion sick", "car sick", "seasick", "vomit", "sick to my", "恶心", "想吐", "晕车", "反胃", "孕吐"], ["PC6"]),
            (["neck", "stiff neck", "shoulder", "颈", "脖子", "肩", "落枕"], ["SI3", "SJ5"]),
            (["sleep", "insomnia", "anxiety", "anxious", "stress", "restless", "can't relax", "失眠", "焦虑", "压力", "心烦", "紧张", "安神", "睡不着"], ["HT7", "PC8"]),
            (["wrist", "carpal", "手腕", "腕"], ["TE4", "PC7"]),
        ]
        for g in groups where g.kw.contains(where: { lowered.contains($0) || raw.contains($0) }) {
            let pts = practiceable(g.ids.compactMap { Acupoint.byId[$0] })
            if !pts.isEmpty { return pts }
        }
        return nil
    }
    private func symptomReply(_ pts: [Acupoint]) -> String {
        let names = pts.map { "\($0.id) \(AppLocale.pick($0.zh, $0.en))" }
            .joined(separator: AppLocale.pick("、", ", "))
        return AppLocale.pick(
            "作为温和的自我保养，有些人会按压：\(names)。点按下方按钮即可用相机练习。如有不适，或症状严重、持续，请停止并咨询专业人士。仅供养生自我保养参考。",
            "As gentle self-care, some people press: \(names). Tap a button below to practice it with the camera. Stop if it’s uncomfortable, and see a professional if symptoms are severe or persistent. Wellness self-care only.")
    }

    // Red-flag screen → advise stopping / professional care; never "continue". Covers the web
    // app's RED_FLAGS (severe pain, numbness, dizziness, worsening, pregnancy, bleeding/blood
    // thinners, pacemaker, trouble breathing, broken skin / infection / swelling / injury).
    private func mentionsRedFlag(raw: String, lowered: String) -> Bool {
        // Multi-word phrases — substring is fine (low collision).
        let phrases = ["chest pain", "trouble breathing", "can't breathe", "cannot breathe",
                       "shortness of breath", "broken skin", "blood thinner"]
        if phrases.contains(where: { lowered.contains($0) }) { return true }
        // Single-word cues matched as WHOLE WORDS, so "numb" doesn't fire on "number" and the
        // "wound" homograph ("wound up") doesn't trip it. (Covered by injury/伤口 instead.)
        let words: Set<String> = [
            "severe", "numb", "numbness", "dizzy", "dizziness", "weak", "weakness",
            "worse", "worsening", "pregnant", "pregnancy", "bleeding", "pacemaker",
            "infection", "infected", "swelling", "swollen", "injury", "injured", "fracture", "fractured",
        ]
        let tokens = lowered.split { !$0.isLetter }.map(String.init)
        if tokens.contains(where: { words.contains($0) }) { return true }
        // Chinese cues — specific medical terms; substring is safe (and matchPoint guards prose).
        let zh = ["剧痛", "剧烈", "麻木", "头晕", "无力", "加重", "恶化", "胸痛",
                  "怀孕", "妊娠", "出血", "起搏器", "呼吸困难", "喘不过气",
                  "破损", "伤口", "感染", "肿胀", "受伤", "骨折"]
        return zh.contains { raw.contains($0) }
    }
    private func redFlagReply() -> String {
        AppLocale.pick(
            "如果出现剧烈或突然的疼痛、麻木或无力、头晕，或症状在加重，请停止并考虑就医。本应用仅供养生自我保养参考。",
            "If you notice severe or sudden pain, numbness or weakness, dizziness, or symptoms that are getting worse, please stop and consider seeing a professional. This is wellness self-care only.")
    }

    // Match a point by id / romanized name / Chinese name.
    private func matchPoint(raw: String, lowered: String) -> Acupoint? {
        // id and romanized name are latin and effectively unambiguous — substring is safe.
        if let p = Acupoint.all.first(where: {
            lowered.contains($0.id.lowercased()) || lowered.contains($0.en.lowercased())
        }) { return p }
        // The 2-char Chinese names embed in everyday words (外关 inside 对外关系, 内关 inside 国内关系),
        // so only match when the query is essentially just the name — a lookup, not prose.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Acupoint.all.first { trimmed.contains($0.zh) && trimmed.count <= $0.zh.count + 1 }
    }
    private func pointReply(_ p: Acupoint) -> String {
        let practice = p.mediapipeTarget != nil
            ? AppLocale.pick(" 你也可以在「引导」中用相机练习。", " You can also practice it with the camera in the Coach tab.")
            : ""
        let caution = p.caution.isEmpty ? "" : AppLocale.pick(" 注意：\(p.cautionZh)", " Caution: \(p.cautionEn)")
        return AppLocale.pick(
            "\(p.id) · \(p.zh)（\(p.en)，\(p.meridianZh)）。定位：\(p.locationZh) 传统用途：\(p.indicationsZh) 作为自我保养：放松身体，找到该处，用稳而舒适的力度配合缓慢呼吸按压约30–60秒；如有不适请停止。\(practice)\(caution) 仅供养生自我保养参考。",
            "\(p.id) · \(p.en) (\(p.zh), \(p.meridianEn)). Location: \(p.locationEn) Traditional uses: \(p.indicationsEn) As self-care: relax, find the spot, and apply firm-but-comfortable pressure with slow breathing for about 30–60 seconds; stop if it’s uncomfortable.\(practice)\(caution) Wellness self-care only.")
    }

    // Match a meridian when the query clearly asks about a channel/meridian (gates English-organ
    // collisions like "my heart races"). Chinese prefers the longest organ alias so 心包(pc) wins
    // over 心(heart).
    private func matchMeridian(raw: String, lowered: String) -> Meridian? {
        // English: require an explicit "meridian"/"channel" cue, then match the full channel name —
        // so "lung meridian" works but a bare "heart"/"liver" in ordinary prose does not.
        if lowered.contains("meridian") || lowered.contains("channel") {
            if lowered.contains("conception") { return Meridian.by("ren") }
            if lowered.contains("governing") { return Meridian.by("du") }
            if let m = Meridian.all.first(where: { lowered.contains($0.en.lowercased()) }) { return m }
        }
        // Chinese: the full formal name (手太阴肺经), or the unambiguous <organ>经 / 任脉 / 督脉 forms.
        // Deliberately NO bare "经" gate and NO single-character organ aliases — those embed in
        // everyday words (已经 / 神经 / 月经 / 担心 / 胃口) and misfired on ordinary prose.
        if let m = Meridian.all.first(where: { raw.contains($0.zh) }) { return m }
        let zhForms: [(id: String, form: String)] = [
            ("lung", "肺经"), ("li", "大肠经"), ("stomach", "胃经"), ("spleen", "脾经"),
            ("heart", "心经"), ("si", "小肠经"), ("bladder", "膀胱经"), ("kidney", "肾经"),
            ("pc", "心包经"), ("sj", "三焦经"), ("gb", "胆经"), ("liver", "肝经"),
            ("ren", "任脉"), ("du", "督脉"),
        ]
        // A <organ>经 form must not be the start of a following compound (胃经常 / 心经过 / 肝经历…),
        // where 经 belongs to the next word, not the channel. Reject those; precision over recall is
        // fine here (worst case: a general reply instead of the meridian card).
        let jingCompounds: [Character] = ["常", "过", "历", "验", "理", "营", "济", "典", "费", "度", "纪", "销", "手"]
        func mentionsChannel(_ form: String) -> Bool {
            guard raw.contains(form) else { return false }
            for c in jingCompounds where raw.contains(form + String(c)) { return false }
            return true
        }
        // Longest matched form wins (defensive: keeps 心包经 from being shadowed by a shorter form).
        if let hit = zhForms.filter({ mentionsChannel($0.form) }).max(by: { $0.form.count < $1.form.count }) {
            return Meridian.by(hit.id)
        }
        return nil
    }
    private func meridianReply(_ m: Meridian) -> String {
        let pts = m.points
        let list = pts.isEmpty
            ? AppLocale.pick("（本图谱暂未收录此经的穴位。）", " (No points from this channel are in this atlas yet.)")
            : AppLocale.pick(" 本图谱中此经的穴位：" + pts.map { "\($0.id) \($0.zh)" }.joined(separator: "、") + "。",
                             " Points on this channel in this atlas: " + pts.map { "\($0.id) \($0.en)" }.joined(separator: ", ") + ".")
        return AppLocale.pick(
            "\(m.zh)（\(m.en)，\(m.ab)）。\(m.descZh)\(list) 仅供养生自我保养参考。",
            "\(m.en) Meridian (\(m.zh), \(m.ab)). \(m.descEn)\(list) Wellness self-care only.")
    }

    // General-knowledge FAQ: first entry whose keyword is in the query (English/pinyin via lowered,
    // Chinese via raw).
    private func matchFAQ(raw: String, lowered: String) -> CoachFAQ? {
        Self.faqs.first { f in
            f.keywords.contains { kw in lowered.contains(kw.lowercased()) || raw.contains(kw) }
        }
    }

    private func generalReply() -> String {
        AppLocale.pick(
            "你好 — 我可以介绍全身的安全穴位（手部如 中渚 TE3、内关 PC6；头部如 印堂、太阳；腿部如 足三里 ST36；足部如 太冲 LR3 等），讲解十四经络，并解答按压方法、时长、安全等常见问题。可按名称询问任意穴位或经络。仅供养生自我保养参考。",
            "Hi — I can explain safe acupoints across the body (hand points like TE3 / PC6, head points like Yintang / Taiyang, the leg point ST36 Zusanli, the foot point LR3 Taichong, and more), describe the fourteen meridians, and answer common questions about how to press, how long, and safety. Ask about any point or meridian by name. Wellness self-care only.")
    }

    // Verified general-knowledge FAQ (sourced + adversarially reviewed; wellness-only framing).
    static let faqs: [CoachFAQ] = [
        CoachFAQ(topic: "what-is-acupressure",
            keywords: ["what is acupressure", "what's acupressure", "acupressure meaning", "define acupressure", "什么是指压", "什么是穴位按压", "穴位按摩是什么"],
            aZh: "穴位按压是一种用指尖按压身体特定部位的传统自我保健方式。它属于放松与养生活动，不是医疗，也不能替代专业医护人员的建议。",
            aEn: "Acupressure is a traditional self-care practice of pressing points on the body with your fingertips. It's a wellness and relaxation activity, not medical care, and it does not replace advice from a medical professional."),
        CoachFAQ(topic: "what-it-is-not",
            keywords: ["does acupressure work", "is acupressure medical", "acupressure vs acupuncture", "no needles", "is it a cure", "replace doctor", "和针灸的区别", "能治病吗", "代替医生"],
            aZh: "穴位按压只用手指施压，不使用针。它不是医疗手段，也不对任何疾病作出承诺。请把它当作可以自己进行的温和放松练习，与正规医疗配合使用，而绝不能取而代之。",
            aEn: "Acupressure uses finger pressure only, with no needles. It is not a medical procedure and makes no promises about illness. Think of it as a gentle relaxation routine you can do for yourself, alongside (never instead of) proper medical care."),
        CoachFAQ(topic: "what-is-cun",
            keywords: ["what is cun", "cun measurement", "body inch", "finger width", "how to measure cun", "什么是寸", "同身寸", "一寸多长", "怎么量寸"],
            aZh: "寸是定位穴位用的“同身寸”，以你自己的身体为标准。一寸约为你拇指指间关节的宽度；四指并拢（在第二指节处）约为三寸。用自己的手测量，比例才适合你的身体。",
            aEn: "Cun is the traditional body-inch used to locate points, measured against your own body. One cun is the width of your thumb at the knuckle; the four fingers held together (at the second knuckle) are about three cun. Using your own hand keeps the proportions right for your body."),
        CoachFAQ(topic: "how-to-locate",
            keywords: ["how to find the point", "locate acupoint", "where is the point", "bony landmark", "tender spot", "how to find spot", "怎么找穴位", "穴位在哪", "定位"],
            aZh: "先按照穴位说明中的骨性标志和寸的量法找到大致区域，再用指尖轻按，寻找那个略有酸胀、按下去有轻微胀满感的点。请在光线充足时、不慌不忙地在自己身上定位。",
            aEn: "Use the bony landmarks and the cun measurement from the point's instructions to find the general area, then feel for the spot that is slightly tender or that gives a mild, full sensation under gentle pressure. Locate points on yourself, in good light, without rushing."),
        CoachFAQ(topic: "how-to-press",
            keywords: ["how to press", "how hard", "pressure technique", "small circles", "fingertip", "thumb pressure", "firm but comfortable", "怎么按", "按多重", "按压手法", "打圈"],
            aZh: "用拇指或食指指腹以“稳而舒适”的力度按压，然后缓慢打小圈或保持稳定按住。感觉应是轻微而舒服的酸胀，绝不应是尖锐疼痛。请剪短指甲，皮肤无破损。",
            aEn: "Press with the pad of your thumb or index fingertip using firm but comfortable pressure, then make small slow circles or a steady hold. It should feel like a mild, satisfying ache, never sharp pain. Keep nails short and skin unbroken."),
        CoachFAQ(topic: "how-long",
            keywords: ["how long", "how many seconds", "duration", "how long to press", "30 seconds", "one minute", "按多久", "多长时间", "几秒", "时长"],
            aZh: "常见做法是每个穴位约按 30 到 60 秒，配合缓慢呼吸。休息片刻后可重复。如果某个点感到不适而非舒服的酸胀，请提前停止。",
            aEn: "A common approach is about 30 to 60 seconds per point, breathing slowly. You can repeat after a short rest. Stop sooner if a point feels uncomfortable rather than pleasantly achy."),
        CoachFAQ(topic: "how-often",
            keywords: ["how often", "how many times a day", "frequency", "daily", "too much", "多久一次", "一天几次", "频率", "每天"],
            aZh: "作为自我保健，一天一次到几次较为常见，前提是保持温和舒适。如果按出淤青或过度用力，说明力度太大，请减轻并让该部位休息。",
            aEn: "Once or a few times a day is typical for a self-care routine, as long as it stays gentle and comfortable. Over-pressing or bruising means you are using too much force, so ease off and rest the area."),
        CoachFAQ(topic: "breathing",
            keywords: ["breathing", "breathe", "how to breathe", "relax breathing", "deep breath", "呼吸", "怎么呼吸", "深呼吸", "放松呼吸"],
            aZh: "按压时配合缓慢轻松的呼吸：用鼻吸气，呼气更柔和、稍长一些，让肩膀放松下来。平静的呼吸是穴位按压让人感到放松的重要原因。",
            aEn: "Pair each point with slow, easy breathing: inhale through the nose, exhale gently and a little longer, letting your shoulders soften. Calm breathing is a big part of why an acupressure pause feels relaxing."),
        CoachFAQ(topic: "evidence-honesty",
            keywords: ["is there evidence", "does it really work", "science", "proof", "research", "best evidence", "有没有科学依据", "真的有用吗", "证据", "科学", "研究"],
            aZh: "坦白说，大多数穴位源自传统，科学证据有限，很多研究规模较小。最有力的例外是用于恶心的内关（PC6），相关综述（例如腕带）显示其有真实但有限的益处。请把穴位按压当作放松来享受，并保持现实的期待。",
            aEn: "Honestly, most acupressure points come from tradition and have limited scientific evidence; many studies are small. The strongest exception is PC6 for nausea, where reviews of acupressure (for example wristbands) show a real but modest benefit. Enjoy acupressure as relaxation, and keep expectations realistic."),
        CoachFAQ(topic: "wellness-not-medical",
            keywords: ["medical advice", "is this medical", "disclaimer", "see a doctor", "not a substitute", "医疗建议", "这是医疗吗", "免责", "看医生", "不能替代"],
            aZh: "本应用仅用于一般养生与放松，不属于医疗建议，也无法对任何情况作出判断。任何健康疑虑、用药问题或症状加重，请咨询合格的医护人员。",
            aEn: "This app is for general wellness and relaxation only. It is not medical advice and cannot judge any condition. For any medical concern, medication question, or worsening symptom, please talk to a qualified medical professional."),
        CoachFAQ(topic: "avoid-where",
            keywords: ["where not to press", "avoid pressing", "wound", "bruise", "varicose", "swelling", "哪里不能按", "避免按压", "伤口", "淤青", "肿胀"],
            aZh: "请勿在破损或受刺激的皮肤、伤口、皮疹、痣、淤青、肿胀、静脉曲张或任何肿块上按压。绝不可用力按压眼球、咽喉前侧或两侧，或深按腹部。所有按压都应保持温和，且仅在健康皮肤上进行。",
            aEn: "Avoid pressing over broken or irritated skin, wounds, rashes, moles, bruises, swelling, varicose veins, or any lump. Never press hard on the eyeball, the front or side of the throat, or deep into the belly. Keep all pressure gentle and on intact, normal skin only."),
        CoachFAQ(topic: "pregnancy-caution",
            keywords: ["pregnancy", "pregnant", "expecting", "is it safe pregnant", "avoid pregnancy", "怀孕", "孕妇", "孕期", "孕妇能按吗"],
            aZh: "如果你已怀孕或可能怀孕，请先咨询你的医生或助产士，再决定是否进行穴位自我保健。部分传统穴位在孕期被特别提示需谨慎，因此本应用不提供孕期方案。如有疑问，请与你的产科护理人员确认。",
            aEn: "If you are pregnant or might be, do not use acupressure for self-care without first asking your own doctor or midwife. Some traditional points are specifically cautioned against during pregnancy, so this app does not offer pregnancy routines. When in doubt, check with your maternity care provider."),
        CoachFAQ(topic: "excluded-points",
            keywords: ["which points to avoid", "unsafe points", "li4", "hegu", "sp6", "gb21", "forbidden points", "哪些穴位要避开", "合谷", "三阴交", "肩井"],
            aZh: "本应用刻意不收录一些常见穴位，因为它们需要专业训练或筛查才能安全自按。已排除：合谷（LI4）、三阴交（SP6）、肩井（GB21）、昆仑（BL60）、至阴（BL67）（传统上孕期需谨慎），以及对眼球、颈动脉/咽喉或下腹深部的任何深压。本应用只提供适合一般成年人的温和指尖穴位。",
            aEn: "Some popular points are left out of this app because they need training or screening for safe self-pressure. Excluded: LI4 Hegu, SP6 Sanyinjiao, GB21 Jianjing, BL60 Kunlun, and BL67 Zhiyin (traditionally cautioned in pregnancy), and any deep pressure over the eyeball, the carotid/throat, or the deep lower abdomen. This app only offers gentle fingertip points safe for a general adult audience."),
    ]
}

struct ChatView: View {
    @Binding var startCoach: Acupoint?     // tapping a suggested point launches the AR coach
    @ObservedObject private var settings = AppSettings.shared
    @State private var messages: [ChatMessage] = [
        .init(role: .coach, text: AppLocale.pick(
            "你好 — 可以问我任意穴位或经络（如 足三里、肺经），以及按压方法、时长、孕期与安全等问题。",
            "Hi — ask me about any acupoint or meridian (e.g. Zusanli, the Lung meridian), or about how to press, how long, pregnancy, and safety."))
    ]
    @State private var input = ""
    @State private var sending = false
    private let service = ChatService()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { m in bubble(m).id(m.id) }
                    }.padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            HStack(spacing: 10) {
                TextField(AppLocale.pick("问问教练…", "Ask the coach…"), text: $input, axis: .vertical)
                    .textFieldStyle(.plain).padding(10).panel()
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .tint(Ink.gold).disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send message")
            }.padding()
        }
        .background(ShanshuiBackground())
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if m.role == .coach {
                VStack(alignment: .leading, spacing: 8) {
                    coachText(m.text)
                    if !m.suggestions.isEmpty { suggestionRow(m.suggestions) }
                }
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40); userText(m.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((m.role == .coach ? "Coach" : "You") + ": " + m.text)
    }

    // Tappable "Practice with camera" buttons under a coach reply — launch the AR coach.
    private func suggestionRow(_ pts: [Acupoint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pts) { p in
                Button { startCoach = p } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder").font(.caption)
                        Text(AppLocale.pick("用相机练习 \(p.id) · \(p.zh)", "Practice \(p.id) · \(p.en)"))
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Ink.jade.opacity(0.16))
                        .overlay(Capsule().stroke(Ink.gold.opacity(0.55), lineWidth: 1)))
                    .foregroundStyle(Ink.gold)
                }
                .accessibilityLabel(AppLocale.pick("用相机练习 \(p.id) \(p.zh)", "Practice \(p.id) \(p.en) with the camera"))
            }
        }
    }
    private func coachText(_ t: String) -> some View {
        Text(t).padding(12).foregroundStyle(Ink.text)
            .background(RoundedRectangle(cornerRadius: 14).fill(Ink.paperLight))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1))
    }
    private func userText(_ t: String) -> some View {
        Text(t).padding(12).foregroundStyle(Ink.paperLight)
            .background(RoundedRectangle(cornerRadius: 14).fill(Ink.jade))
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespaces); guard !q.isEmpty else { return }
        messages.append(.init(role: .user, text: q)); input = ""; sending = true
        let hist = messages
        Task {
            let r = await service.reply(to: q, history: hist)
            await MainActor.run {
                messages.append(.init(role: .coach, text: r.text, suggestions: r.suggestions)); sending = false
            }
        }
    }
}
