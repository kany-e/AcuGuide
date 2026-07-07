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
                    row("iphone", AppLocale.pick("一切都在设备上", "Everything stays on this device"),
                        AppLocale.pick("本应用没有账户、没有分析统计、没有服务器。它不收集、不存储、也不发送任何个人数据。",
                                       "There are no accounts, no analytics, and no servers. The app collects, stores, and sends no personal data."))
                    row("camera", AppLocale.pick("相机画面即时处理", "Camera frames are processed live"),
                        AppLocale.pick("相机引导在设备上实时识别手部关键点来标注穴位。画面不会被保存，也绝不会离开设备。",
                                       "The camera coach detects hand landmarks on-device, live, to mark point locations. Frames are never saved and never leave the device."))
                    row("cpu", AppLocale.pick("AI 也在设备上", "The AI runs on-device too"),
                        AppLocale.pick("小脉的自由问答由 Apple 的设备端模型生成（仅在支持的设备上），不联网。",
                                       "Mai's free-form answers are generated by Apple's on-device model (on supported devices) — no network involved."))
                    row("clock.arrow.circlepath", AppLocale.pick("练习记录仅保存在本机", "Practice history is local only"),
                        AppLocale.pick("练习记录（穴位、轮数、时长、自评）只保存在你的手机里，删除应用即随之删除。",
                                       "Your practice history (point, rounds, duration, self-report) lives only on your phone and is deleted with the app."))
                    Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                        .frame(maxWidth: .infinity)
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
