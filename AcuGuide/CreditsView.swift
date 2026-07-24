import SwiftUI

// Licenses & credits — CC-BY attribution is a LEGAL requirement of the bundled Sketchfab models
// (verified against each GLB's embedded asset metadata), plus the open-source framework and the
// reference works behind the atlas copy. Linked from Settings.
struct CreditsView: View {
    private struct ModelCredit: Identifiable {
        let id = UUID()
        let title: String, author: String, authorURL: String, sourceURL: String
    }
    // Authors/links read from the GLBs' embedded Sketchfab metadata (asset.extras).
    private let models = [
        ModelCredit(title: "Arms, hands, head, legs and feet (low poly) — Female",
                    author: "pnhtuan", authorURL: "https://sketchfab.com/pnhtuan7",
                    sourceURL: "https://sketchfab.com/3d-models/arms-hands-head-legs-and-feet-low-poly-female-9ba2de9a0e4941da9ac55d43b8652a4b"),
        ModelCredit(title: "Hand (low poly)",
                    author: "scribbletoad", authorURL: "https://sketchfab.com/scribbletoad",
                    sourceURL: "https://sketchfab.com/3d-models/hand-low-poly-d6c802a74a174c8c805deb20186d1877"),
        ModelCredit(title: "Character Mannequin Male",
                    author: "muh.nurzidan", authorURL: "https://sketchfab.com/muh.nurzidan",
                    sourceURL: "https://sketchfab.com/3d-models/character-mannequin-male-41e10234ae604060964d137480e7f996"),
    ]

    var body: some View {
        ZStack {
            ShanshuiBackground()
            Form {
                Section(AppLocale.pick("3D 模型", "3D models")) {
                    ForEach(models) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.title).font(.subheadline).foregroundStyle(Ink.text)
                            HStack(spacing: 4) {
                                Link(m.author, destination: URL(string: m.authorURL)!)
                                    .font(.caption).tint(Ink.gold)
                                Text("·").font(.caption).foregroundStyle(Ink.textDim)
                                Link("CC-BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                                    .font(.caption).tint(Ink.gold)
                                Text("·").font(.caption).foregroundStyle(Ink.textDim)
                                Link("Sketchfab", destination: URL(string: m.sourceURL)!)
                                    .font(.caption).tint(Ink.gold)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text(AppLocale.pick("模型经过重新着色与缩放以用于展示。", "Models were recolored and rescaled for display."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                }
                Section(AppLocale.pick("开源软件", "Open-source software")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GLTFKit2").font(.subheadline).foregroundStyle(Ink.text)
                        HStack(spacing: 4) {
                            Link("Warren Moore", destination: URL(string: "https://github.com/warrenm/GLTFKit2")!)
                                .font(.caption).tint(Ink.gold)
                            Text("· MIT License").font(.caption).foregroundStyle(Ink.textDim)
                        }
                    }
                }
                Section(AppLocale.pick("数据与参考", "Data & references")) {
                    Text(AppLocale.pick(
                        "穴位定位遵循 WHO 西太平洋区标准（2008）。经典归类与英文名参考 Yin Yang House 与《Atlas of Acupuncture Points》。研究计数来自 OCOM 的 AcuTrials 数据库 — 详见「来源与证据」。",
                        "Point locations follow the WHO Standard (WPRO, 2008). Classical roles and English names reference Yin Yang House and the Atlas of Acupuncture Points. Study counts come from OCOM's AcuTrials database — see Sources & Evidence."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(AppLocale.pick("许可与致谢", "Licenses & credits"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Plain-language privacy statement — the whole story is "nothing leaves the device", stated
// specifically enough to be verifiable. Linked from Settings; mirrors docs/privacy-policy.md.
struct PrivacyView: View {
    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    row("iphone", AppLocale.pick("你的数据留在设备上", "Your data stays on this device"),
                        AppLocale.pick("没有账户，没有统计分析。应用不收集、不存储、也不向任何 AcuGuide 服务器发送个人数据。",
                                       "No accounts, no analytics. The app collects and stores no personal data, and sends none to any AcuGuide server."))
                    row("camera", AppLocale.pick("相机画面即时处理", "Camera frames are processed live"),
                        AppLocale.pick("相机引导在设备上实时识别手部关键点来标注穴位。画面不会被保存，也绝不会离开设备。",
                                       "The camera coach detects hand landmarks on-device, live, to mark point locations. Frames are never saved and never leave the device."))
                    row("cpu", AppLocale.pick("AI 也在设备上", "The AI runs on-device too"),
                        AppLocale.pick("\(CoachPersona.name) 的自由问答由 Apple 的设备端模型生成（仅在支持的设备上），不联网。",
                                       "\(CoachPersona.name)'s free-form answers are generated by Apple's on-device model (on supported devices) — no network involved."))
                    row("mic", AppLocale.pick("语音确认（可选）", "Voice confirm (optional)"),
                        AppLocale.pick("免提说「就是这里」用的是 Apple 的语音识别。如果你的语言有设备端识别，语音就留在设备上；否则这句短语会交给 Apple 的语音服务处理。默认关闭 — 你也可以随时改用点按。",
                                       "The hands-free “this is my spot” uses Apple's speech recognition. If your language has on-device recognition, audio stays on device; otherwise that short phrase is sent to Apple's speech service. It's off until you turn on the mic — you can always tap instead."))
                    row("clock.arrow.circlepath", AppLocale.pick("练习记录仅保存在本机", "Practice history is local only"),
                        AppLocale.pick("练习记录（穴位、轮数、时长、自评）只保存在你的手机里，删除应用即随之删除。",
                                       "Your practice history (point, rounds, duration, self-report) lives only on your phone and is deleted with the app."))
                    WellnessFooter()
                        .padding(.top, 6)
                }
                .padding()
            }
        }
        .navigationTitle(AppLocale.pick("隐私", "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Ink.gold).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                Text(text).font(.footnote).foregroundStyle(Ink.textDim)
            }
        }
        .padding(14).panel()
    }
}
