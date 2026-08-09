import SwiftUI

// App-wide settings — the web app's `lang` state, ported. Single source of truth, persisted in
// UserDefaults. Views that show localized copy observe this singleton (@ObservedObject) so a
// language toggle re-renders them immediately. AppLocale.pick reads `lang` (see Acupoints.swift).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Lang: String, CaseIterable { case zh, en }

    @Published var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: Self.key) }
    }

    // On-device AI answers in the chat coach (FoundationModels; only used where available).
    // Default ON — the model is fully offline/private and the safety screen runs regardless.
    @Published var llmChat: Bool {
        didSet { UserDefaults.standard.set(llmChat, forKey: Self.llmKey) }
    }

    // First-run onboarding shown once.
    @Published var seenOnboarding: Bool {
        didSet { UserDefaults.standard.set(seenOnboarding, forKey: Self.onboardingKey) }
    }

    // How many camera-coach sessions have been started. Drives the voice hint's DECAY: research on
    // voice discoverability (NN/g) finds users abandon within the first few interactions when they
    // cannot tell what to say, so the hint has to be loud EARLY — and Google's conversation-design
    // guidance puts the first-run set at two or three intents, not one and not a menu. After that it
    // shrinks to a single contextual line so a fluent user is not lectured every session.
    @Published var coachSessions: Int {
        didSet { UserDefaults.standard.set(coachSessions, forKey: Self.coachSessionsKey) }
    }

    // Hands-free voice control in the camera coach: when ON, each camera session auto-starts the
    // mic (LocateVoiceControl.autoStartIfEnabled). Default ON — device-requested ("the allow
    // microphone should be immediately enabled … no more pressing the microphone button") — and the
    // disclosure surfaces (docs/privacy-policy.md, PrivacyView, the setup card) all say "on by
    // default" and point at Settings as the durable off switch. VoiceDisclosureTests pins the
    // default and that copy to each other; flip one without the other and it fails.
    @Published var handsFreeVoice: Bool {
        didSet { UserDefaults.standard.set(handsFreeVoice, forKey: Self.handsFreeVoiceKey) }
    }

    // Physical-setup card before the FIRST camera session (prop the phone, both hands are busy).
    // Setup knowledge, not a warning — shown once, then never again. Settings can reset it.
    @Published var seenCameraSetup: Bool {
        didSet { UserDefaults.standard.set(seenCameraSetup, forKey: Self.cameraSetupKey) }
    }

    // Spoken coach cues muted — persisted so the choice survives sessions (was per-session state).
    @Published var voiceMuted: Bool {
        didSet { UserDefaults.standard.set(voiceMuted, forKey: Self.voiceKey) }
    }

    // Optional daily practice reminder (local notification), minutes past midnight (default 20:00).
    @Published var reminderOn: Bool {
        didSet { UserDefaults.standard.set(reminderOn, forKey: Self.reminderOnKey) }
    }
    @Published var reminderMinutes: Int {
        didSet { UserDefaults.standard.set(reminderMinutes, forKey: Self.reminderMinKey) }
    }

    private static let key = "appLang"
    private static let llmKey = "llmChat"
    private static let onboardingKey = "seenOnboarding"
    private static let cameraSetupKey = "seenCameraSetup"
    // Internal, not private: VoiceDisclosureTests round-trips the key directly.
    static let handsFreeVoiceKey = "handsFreeVoice"
    private static let coachSessionsKey = "coachSessions"
    private static let voiceKey = "voiceMuted"
    private static let reminderOnKey = "reminderOn"
    private static let reminderMinKey = "reminderMinutes"

    private init() {
        if let s = UserDefaults.standard.string(forKey: Self.key), let l = Lang(rawValue: s) {
            lang = l
        } else {
            // First launch: follow the device locale.
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            lang = code.hasPrefix("zh") ? .zh : .en
        }
        llmChat = UserDefaults.standard.object(forKey: Self.llmKey) as? Bool ?? true
        seenOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        seenCameraSetup = UserDefaults.standard.bool(forKey: Self.cameraSetupKey)
        handsFreeVoice = Self.resolveHandsFreeVoice(from: UserDefaults.standard)
        coachSessions = UserDefaults.standard.integer(forKey: Self.coachSessionsKey)
        voiceMuted = UserDefaults.standard.bool(forKey: Self.voiceKey)
        reminderOn = UserDefaults.standard.bool(forKey: Self.reminderOnKey)
        reminderMinutes = UserDefaults.standard.object(forKey: Self.reminderMinKey) as? Int ?? 20 * 60
    }

    /// Absent key → ON. Hoisted out of init so the disclosure test can pin the default against the
    /// copy's "on by default" claim without re-initializing the UserDefaults.standard singleton.
    static func resolveHandsFreeVoice(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: handsFreeVoiceKey) as? Bool ?? true
    }
}
