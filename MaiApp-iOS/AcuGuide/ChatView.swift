import SwiftUI

struct ChatMessage: Identifiable { let id = UUID(); let role: Role; let text: String
    enum Role { case user, coach } }

// Themed bilingual acupressure coach. Plug your endpoint + key in ChatService.
// Safety guardrail is in the system prompt: wellness coaching only, never diagnosis.
final class ChatService {
    // TODO: set these (e.g. OpenAI-compatible). Leave key empty to use the offline stub.
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let apiKey = ""   // <- paste key; keep out of git
    private let model = "gpt-4o-mini"

    private let system = """
    You are AcuGuide, a warm, concise acupressure wellness coach. You explain hand/wrist
    acupoints (e.g. TE3 中渚) and how to press them as self-care. You are bilingual (中文 / English)
    and answer in the user's language. You NEVER diagnose, treat, cure, or heal; you never claim
    medical effects. If a user describes red-flag symptoms (severe pain, numbness, dizziness,
    worsening), gently suggest they stop and consider professional care.
    """

    func reply(to user: String, history: [ChatMessage]) async -> String {
        guard !apiKey.isEmpty else {
            return "(offline) For \(user.isEmpty ? "TE3" : "that"): press the point on the back of the hand, in the groove behind the ring and pinky knuckles — firm, steady pressure with slow breathing. Add your API key in ChatService to enable live answers."
        }
        var msgs: [[String: String]] = [["role": "system", "content": system]]
        for m in history.suffix(8) { msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.text]) }
        msgs.append(["role": "user", "content": user])
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "temperature": 0.6])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return (message?["content"] as? String) ?? "Sorry, I couldn't reach the coach."
        } catch { return "Network error — try again." }
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
            }.padding()
        }
        .background(Ink.paper.ignoresSafeArea())
    }

    private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.role == .coach { coachText(m.text); Spacer(minLength: 40) }
            else { Spacer(minLength: 40); userText(m.text) }
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
            await MainActor.run { messages.append(.init(role: .coach, text: r)); sending = false }
        }
    }
}
