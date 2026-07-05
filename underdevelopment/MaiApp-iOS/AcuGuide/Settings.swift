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
                    Section(AppLocale.pick("AI 教练", "Coach AI")) {
                        Toggle(AppLocale.pick("设备端 AI 回答", "On-device AI answers"), isOn: $settings.llmChat)
                            .tint(Ink.gold)
                        Text(AppLocale.pick(
                            "在支持 Apple 智能的设备上，教练用完全离线的设备端模型回答图谱之外的自由提问。安全筛查始终优先，生成内容会明确标注。",
                            "On Apple Intelligence-capable devices, the coach answers free-form questions with a fully offline on-device model. The safety screen always runs first, and generated replies are labeled."))
                            .font(.footnote).foregroundStyle(Ink.textDim)
                    }
                    Section(AppLocale.pick("参考", "Reference")) {
                        NavigationLink {
                            SourcesView()
                        } label: {
                            Label(AppLocale.pick("来源与证据", "Sources & Evidence"), systemImage: "text.book.closed")
                        }
                    }
                    // Dev tool (M3): capture owned expert acupoint labels on real frames. English-only,
                    // shown to whoever runs the collection build.
                    Section("Developer") {
                        NavigationLink {
                            LabelCaptureView()
                        } label: {
                            Label("Label capture (\(LabelStore.shared.count))", systemImage: "hand.tap")
                        }
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
