import SwiftUI

// Settings sheet — language toggle (中文 ⇄ English). Reached from the gear on the atlas.
struct SettingsSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var reminderDenied = false

    // Bridge reminderMinutes (minutes past midnight) ⇄ the hour-and-minute DatePicker.
    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.reminderMinutes / 60,
                                      minute: settings.reminderMinutes % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.reminderMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
            })
    }

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
                    Section(AppLocale.pick("小脉（AI 教练）", "Mai (Coach AI)")) {
                        Toggle(AppLocale.pick("设备端 AI 回答", "On-device AI answers"), isOn: $settings.llmChat)
                            .tint(Ink.gold)
                        Text(AppLocale.pick(
                            "在支持 Apple 智能的设备上，小脉用完全离线的设备端模型回答图谱之外的自由提问。安全筛查始终优先，生成内容会明确标注。",
                            "On Apple Intelligence-capable devices, Mai answers free-form questions with a fully offline on-device model. The safety screen always runs first, and generated replies are labeled."))
                            .font(.footnote).foregroundStyle(Ink.textDim)
                    }
                    Section(AppLocale.pick("练习提醒", "Practice reminder")) {
                        Toggle(AppLocale.pick("每日提醒", "Daily reminder"), isOn: $settings.reminderOn)
                            .tint(Ink.gold)
                            .onChange(of: settings.reminderOn) { on in
                                PracticeReminder.sync(on: on, minutes: settings.reminderMinutes) { granted in
                                    if on && !granted { settings.reminderOn = false; reminderDenied = true }
                                }
                            }
                        if settings.reminderOn {
                            DatePicker(AppLocale.pick("时间", "Time"), selection: reminderTime,
                                       displayedComponents: .hourAndMinute)
                                .onChange(of: settings.reminderMinutes) { m in
                                    PracticeReminder.sync(on: true, minutes: m)
                                }
                        }
                        if reminderDenied {
                            Text(AppLocale.pick("请在系统设置中允许 AcuGuide 发送通知。",
                                                "Allow notifications for AcuGuide in system Settings."))
                                .font(.footnote).foregroundStyle(Ink.terracotta)
                        }
                    }
                    Section(AppLocale.pick("参考", "Reference")) {
                        NavigationLink {
                            SourcesView()
                        } label: {
                            Label(AppLocale.pick("来源与证据", "Sources & Evidence"), systemImage: "text.book.closed")
                        }
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            Label(AppLocale.pick("隐私", "Privacy"), systemImage: "lock.shield")
                        }
                        NavigationLink {
                            CreditsView()
                        } label: {
                            Label(AppLocale.pick("许可与致谢", "Licenses & credits"), systemImage: "text.badge.checkmark")
                        }
                        // History lives only on this device (by design) — the export is the user's
                        // own backup path.
                        if !PracticeStore.shared.records.isEmpty {
                            ShareLink(item: PracticeStore.shared.exportJSON(),
                                      preview: SharePreview("AcuGuide practice history")) {
                                Label(AppLocale.pick("导出练习记录", "Export practice history"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    #if DEBUG
                    // Dev tool (M3): capture owned expert acupoint labels on real frames. English-only,
                    // debug builds only — must never ship to users.
                    Section("Developer") {
                        NavigationLink {
                            LabelCaptureView()
                        } label: {
                            Label("Label capture (\(LabelStore.shared.count))", systemImage: "hand.tap")
                        }
                    }
                    #endif
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
