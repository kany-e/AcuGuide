import SwiftUI

// Settings sheet — language toggle (中文 ⇄ English). Reached from the gear on the atlas.
struct SettingsSheet: View {
    @ObservedObject private var settings = AppSettings.shared
    // Observed so the export/delete row appears and disappears with the data itself.
    @ObservedObject private var practice = PracticeStore.shared
    @State private var confirmDeleteHistory = false
    @Environment(\.dismiss) private var dismiss
    @State private var reminderDenied = false
    @State private var setupTipsReset = false

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
                        // The scheduled reminder's body text was rendered at schedule time — a
                        // language toggle must re-render it or tomorrow's nudge arrives in the
                        // old language.
                        .onChange(of: settings.lang) { _ in
                            if settings.reminderOn {
                                PracticeReminder.sync(on: true, minutes: settings.reminderMinutes)
                            }
                        }
                    }
                    Section(AppLocale.pick("\(CoachPersona.name)（AI 教练）", "\(CoachPersona.name) (Coach AI)")) {
                        Toggle(AppLocale.pick("设备端 AI 回答", "On-device AI answers"), isOn: $settings.llmChat)
                            .tint(Ink.gold)
                        Text(AppLocale.pick(
                            "在支持 Apple 智能的设备上，\(CoachPersona.name) 用完全离线的设备端模型回答图谱之外的自由提问。安全筛查始终优先，生成内容会明确标注。",
                            "On Apple Intelligence-capable devices, \(CoachPersona.name) answers free-form questions with a fully offline on-device model. The safety screen always runs first, and generated replies are labeled."))
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
                                    // Same grant handling as the toggle: authorization can be
                                    // revoked between syncs, and silently discarding the result
                                    // left the toggle ON with no reminder scheduled.
                                    PracticeReminder.sync(on: true, minutes: m) { granted in
                                        if !granted { settings.reminderOn = false; reminderDenied = true }
                                    }
                                }
                        }
                        if reminderDenied {
                            Text(AppLocale.pick("请在系统设置中允许 AcuGuide 发送通知。",
                                                "Allow notifications for AcuGuide in system Settings."))
                                .font(.footnote).foregroundStyle(Ink.terracotta)
                        }
                    }
                    // Nothing shown once should be unrecoverable — the setup card teaches the
                    // physical arrangement (prop the phone, both hands busy), which is exactly
                    // what someone wants back when a later session isn't working.
                    // `|| setupTipsReset` keeps the section on screen after the tap: the button's
                    // own action clears seenCameraSetup, so gating on that alone would delete the
                    // row and its confirmation in the same frame — the user taps and sees nothing.
                    if settings.seenCameraSetup || setupTipsReset {
                        Section(AppLocale.pick("相机引导", "Camera coach")) {
                            if setupTipsReset {
                                Label(AppLocale.pick("下次打开相机引导时会再显示摆放提示。",
                                                     "Setup tips will show next time you open the camera coach."),
                                      systemImage: "checkmark.circle")
                                    .font(.footnote).foregroundStyle(Ink.textDim)
                            } else {
                                Button {
                                    settings.seenCameraSetup = false
                                    setupTipsReset = true
                                } label: {
                                    Label(AppLocale.pick("再看一次摆放提示", "Show setup tips again"),
                                          systemImage: "iphone.gen3.landscape")
                                }
                                .tint(Ink.gold)
                            }
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
                        if !practice.records.isEmpty {
                            ShareLink(item: PracticeExport(),
                                      preview: SharePreview("AcuGuide practice history")) {
                                Label(AppLocale.pick("导出练习记录", "Export practice history"), systemImage: "square.and.arrow.up")
                            }
                            // Deletion sits right beside export, and export comes FIRST — if you are
                            // about to erase something, the way to keep a copy should already be in
                            // view. The privacy copy promised this history "is deleted when you
                            // delete the app"; uninstalling was the only way to act on that.
                            Button(role: .destructive) { confirmDeleteHistory = true } label: {
                                Label(AppLocale.pick("删除练习记录", "Delete practice history"),
                                      systemImage: "trash")
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
                        WellnessFooter()
                    }
                }
                .scrollContentBackground(.hidden)   // let the shanshui ground show through
            }
            .navigationTitle(AppLocale.pick("设置", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            // Destructive and irreversible, so it is confirmed and the message says exactly what
            // goes and what stays — saved spots and custom routines are separate data and survive.
            .confirmationDialog(AppLocale.pick("删除全部练习记录？", "Delete all practice history?"),
                                isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
                Button(AppLocale.pick("删除", "Delete"), role: .destructive) {
                    practice.deleteAllRecords()
                }
                Button(AppLocale.pick("取消", "Cancel"), role: .cancel) { }
            } message: {
                Text(AppLocale.pick(
                    "将永久删除本机上的全部练习记录（穴位、轮数、时长与自评）。此操作无法撤销 —— 如需保留，请先「导出练习记录」。你保存的穴位位置与自定义套组不受影响。",
                    "This permanently removes every practice record on this device (point, rounds, duration and self-report). It cannot be undone — export first if you want a copy. Your saved spots and custom routines are not affected."))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("完成", "Done")) { dismiss() }.tint(Ink.gold)
                }
            }
        }
    }
}
