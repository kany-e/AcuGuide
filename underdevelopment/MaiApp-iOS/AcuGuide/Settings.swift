import SwiftUI

// Settings sheet — language toggle (中文 ⇄ English). Reached from the gear on the atlas.
struct SettingsSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                Form {
                    Section(AppLocale.pick("语言", "Language")) {
                        Picker(AppLocale.pick("语言", "Language"), selection: $settings.lang) {
                            Text("中文").tag(AppSettings.Lang.zh)
                            Text("English").tag(AppSettings.Lang.en)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        Text(AppLocale.pick("仅供养生自我保养，非医疗建议。",
                                            "Wellness self-care only — not medical advice."))
                            .font(.footnote).foregroundStyle(Ink.textDim)
                    }
                }
                .scrollContentBackground(.hidden)   // let the shanshui ground show through
            }
            .navigationTitle(AppLocale.pick("设置", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("完成", "Done")) { dismiss() }.tint(Ink.gold)
                }
            }
        }
    }
}
