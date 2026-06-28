import SwiftUI

struct ChatMessage: Identifiable { let id = UUID(); let role: Role; let text: String
    enum Role { case user, coach } }

// Fully OFFLINE bilingual acupressure helper. No network, no API key, no accounts, no
// telemetry — nothing to secure or leak. Replies are generated locally from the acupoint atlas.
// The wellness-only safety posture is enforced directly here: it never diagnoses/treats/cures,
// and red-flag symptoms always route to a stop-and-seek-care reply (matching the web app).
final class ChatService {
    func reply(to user: String, history: [ChatMessage]) async -> String {
        let raw = user
        let q = user.lowercased()
        if mentionsRedFlag(raw: raw, lowered: q) { return redFlagReply() }
        if let point = matchPoint(raw: raw, lowered: q) { return pointReply(point) }
        return generalReply()
    }

    // Red-flag screen → advise stopping / professional care; never "continue". Covers the web
    // app's RED_FLAGS (severe pain, numbness, dizziness, worsening, pregnancy, bleeding/blood
    // thinners, pacemaker, trouble breathing, broken skin / infection / swelling / injury).
    private func mentionsRedFlag(raw: String, lowered: String) -> Bool {
        let en = ["severe", "numb", "dizzy", "dizziness", "weakness", "worse", "worsening",
                  "chest pain", "pregnan", "bleeding", "blood thinner", "pacemaker",
                  "trouble breathing", "can't breathe", "cannot breathe", "shortness of breath",
                  "broken skin", "wound", "infection", "swelling", "injury", "fracture"]
        let zh = ["剧痛", "剧烈", "麻木", "头晕", "无力", "加重", "恶化", "胸痛",
                  "怀孕", "妊娠", "出血", "起搏器", "呼吸困难", "喘不过气",
                  "破损", "伤口", "感染", "肿胀", "受伤", "骨折"]
        return en.contains { lowered.contains($0) } || zh.contains { raw.contains($0) }
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
        return AppLocale.pick(
            "\(p.id) · \(p.zh)（\(p.en)）。定位：\(p.locationZh) 传统用途：\(p.indicationsZh) 作为自我保养：放松手部，找到该处，用稳定的力度配合缓慢呼吸按压，约30秒；如有不适请停止。\(practice) 仅供养生自我保养参考。",
            "\(p.id) · \(p.en) (\(p.zh)). Location: \(p.locationEn) Traditional uses: \(p.indicationsEn) As self-care: relax the hand, find the spot, and apply firm, steady pressure with slow breathing for about 30 seconds; stop if it’s uncomfortable.\(practice) Wellness self-care only.")
    }

    private func generalReply() -> String {
        AppLocale.pick(
            "你好 — 我可以介绍手部穴位（如 中渚 TE3、内关 PC6、后溪 SI3、神门 HT7）以及如何作为自我保养来按压。可按名称询问任意穴位。仅供养生自我保养参考。",
            "Hi — I can explain hand acupoints (like TE3 中渚, PC6 内关, SI3 后溪, HT7 神门) and how to press them as self-care. Ask about any point by name. Wellness self-care only.")
    }
}

struct ChatView: View {
    @State private var messages: [ChatMessage] = [
        .init(role: .coach, text: "Hi — ask me about any hand acupoint, or how to press TE3 中渚. 你也可以用中文问我。")
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
                TextField("Ask the coach…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain).padding(10).panel()
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .tint(Ink.gold).disabled(sending || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send message")
            }.padding()
        }
        .background(Ink.paper.ignoresSafeArea())
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .coach { coachText(m.text); Spacer(minLength: 40) }
            else { Spacer(minLength: 40); userText(m.text) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((m.role == .coach ? "Coach" : "You") + ": " + m.text)
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
            await MainActor.run { messages.append(.init(role: .coach, text: r)); sending = false }
        }
    }
}
