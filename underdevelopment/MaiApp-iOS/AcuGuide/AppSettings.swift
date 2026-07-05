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

    private static let key = "appLang"
    private static let llmKey = "llmChat"

    private init() {
        if let s = UserDefaults.standard.string(forKey: Self.key), let l = Lang(rawValue: s) {
            lang = l
        } else {
            // First launch: follow the device locale.
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            lang = code.hasPrefix("zh") ? .zh : .en
        }
        llmChat = UserDefaults.standard.object(forKey: Self.llmKey) as? Bool ?? true
    }
}
