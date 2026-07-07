import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// On-device LLM layer for the chat coach — Apple's FoundationModels (iOS 26+, the Apple
// Intelligence ~3B model): fully offline/private, zero bundle size. It handles ONLY the free-form
// questions the deterministic ChatService pipeline can't (its final fallback); the safety posture
// stays deterministic around it:
//   INPUT:  the red-flag screen runs BEFORE the model and can never be overridden by it.
//   OUTPUT: ChatSafety.allowed rejects any reply containing the banned medical-claim terms
//           (same substring rule the unit tests enforce on authored copy) → falls back to the
//           canned general reply. Every generative reply is labeled as on-device AI.
// On devices without Apple Intelligence (or with the Settings toggle off) the generator reports
// unavailable and the chat behaves exactly as before.

protocol ChatGenerator {
    var isAvailable: Bool { get }
    func generate(query: String, history: [ChatMessage]) async throws -> String
}

enum ChatSafety {
    // Same rule as AcuGuideTests.testNoForbiddenMedicalClaims: substring match, so "heal" also
    // rejects "health(y)" — conservative by design; a rejected reply just falls back to canned copy.
    static let bannedEn = ["treat", "cure", "heal", "diagnos"]
    static let bannedZh = ["治疗", "治愈", "根治", "诊断", "医治", "疗效"]

    // Points deliberately excluded from the app (pregnancy-cautioned / screening-dependent). The
    // app skips pregnancy screening precisely BECAUSE these can never appear — so a generated
    // reply that names one must never surface (review-caught: the filter only checked claim
    // terms). Substring match like the banned terms; a rejected reply falls back to canned copy.
    static let excludedPointsEn = ["li4", "hegu", "sp6", "sanyinjiao", "gb21", "jianjing",
                                   "bl60", "kunlun", "bl67", "zhiyin"]
    static let excludedPointsZh = ["合谷", "三阴交", "肩井", "昆仑", "至阴"]

    static func allowed(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let l = text.lowercased()
        if bannedEn.contains(where: { l.contains($0) }) { return false }
        if bannedZh.contains(where: { text.contains($0) }) { return false }
        if excludedPointsEn.contains(where: { l.contains($0) }) { return false }
        if excludedPointsZh.contains(where: { text.contains($0) }) { return false }
        return true
    }

    // Honest labeling: every generative reply carries the on-device-AI + wellness-only tag.
    static func labeled(_ text: String) -> String {
        text + "\n" + AppLocale.pick("（设备端 AI 生成 · 仅供养生自我保养参考。）",
                                     "(On-device AI · wellness self-care only.)")
    }
}

enum ChatLLM {
    // The default generator for this device/OS, or nil (→ ChatService keeps its old behavior).
    static func makeDefault() -> ChatGenerator? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return FoundationModelGenerator() }
        #endif
        return nil
    }

    // Whether THIS device/OS can run the on-device model at all — ignores the Settings toggle.
    // Drives the chat's one-line "why is there no AI here" note: the note shows only when the
    // capability is missing (nothing the user can flip), never when they chose to turn it off.
    static var deviceSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    // Compact grounding: the whole atlas as one line per point + the fixed technique guidance.
    // Kept terse — the on-device model has a small context window.
    static func instructions() -> String {
        let points = Acupoint.all.map { p in
            "\(p.id) \(p.zh) \(p.en) — \(p.region)\(p.mediapipeTarget != nil ? " (camera-coachable)" : "")"
        }.joined(separator: "\n")
        return """
        You are \(CoachPersona.name), the friendly coach inside AcuGuide, a bilingual
        (中文/English) acupressure wellness app. Warm and encouraging, never clinical or stiff;
        call yourself \(CoachPersona.name) in either language if you refer to yourself.
        Hard rules — never break them:
        - Wellness self-care only. Never claim or imply medical benefit; never use the words \
        treat, cure, heal, diagnose (nor 治疗/治愈/根治/诊断) or promise outcomes.
        - Anything medical, severe, worsening, or involving pregnancy or medication: advise \
        talking to a qualified professional, nothing more.
        - Answer in the user's language (Chinese or English). Stay under 120 words. Warm, practical.
        - Ground answers ONLY in this app's atlas and techniques below. If asked about a point or \
        practice outside them, say the app doesn't cover it.
        Atlas points (id 名称 name — region):
        \(points)
        Technique: firm-but-comfortable fingertip pressure on intact skin, about 30–60 seconds per \
        point with slow breathing, gentle small circles; stop if uncomfortable. Pregnancy-cautioned \
        points are excluded from this app on purpose — NEVER name or suggest LI4/Hegu, SP6, GB21, \
        BL60, or BL67 in a reply; if asked about them, say the app leaves them out deliberately \
        and suggest a point from the atlas instead.
        """
    }

    // Serialize the last few turns so the model has conversational context (the deterministic
    // pipeline ignores history entirely — this is what makes follow-up questions work).
    static func prompt(query: String, history: [ChatMessage]) -> String {
        let turns = history.suffix(6).map { m in
            (m.role == .user ? "User: " : "Coach: ") + m.text
        }.joined(separator: "\n")
        return turns.isEmpty ? query : turns + "\nUser: " + query
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct FoundationModelGenerator: ChatGenerator {
    // Built once — the full-atlas grounding string was being rebuilt (map+join over every point)
    // on every message. The SESSION stays per-call on purpose: a reused LanguageModelSession
    // accumulates its own transcript on top of the history we already carry in the prompt, so it
    // would double-count context and eventually overflow the small on-device window.
    private static let cachedInstructions = ChatLLM.instructions()

    var isAvailable: Bool {
        guard AppSettings.shared.llmChat else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func generate(query: String, history: [ChatMessage]) async throws -> String {
        let session = LanguageModelSession(instructions: Self.cachedInstructions)
        let response = try await session.respond(to: ChatLLM.prompt(query: query, history: history))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
