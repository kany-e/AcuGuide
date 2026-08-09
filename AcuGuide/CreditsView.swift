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
                // The app BUNDLES both fonts, so their licences travel with it. SIL OFL requires the
                // copyright notice and licence to accompany the fonts — this screen is where that
                // obligation is met, alongside the CC-BY model attributions above.
                Section(AppLocale.pick("字体", "Fonts")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ma Shan Zheng 马善政").font(.subheadline).foregroundStyle(Ink.text)
                        HStack(spacing: 4) {
                            Link("Google Fonts", destination: URL(string: "https://fonts.google.com/specimen/Ma+Shan+Zheng")!)
                                .font(.caption).tint(Ink.gold)
                            Text("·").font(.caption).foregroundStyle(Ink.textDim)
                            Link("SIL OFL 1.1", destination: URL(string: "https://scripts.sil.org/OFL")!)
                                .font(.caption).tint(Ink.gold)
                        }
                    }
                    .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cormorant Garamond").font(.subheadline).foregroundStyle(Ink.text)
                        HStack(spacing: 4) {
                            Text(AppLocale.pick("Christian Thalmann · Catharsis Fonts",
                                                "Christian Thalmann · Catharsis Fonts"))
                                .font(.caption).foregroundStyle(Ink.textDim)
                            Text("·").font(.caption).foregroundStyle(Ink.textDim)
                            Link("SIL OFL 1.1", destination: URL(string: "https://scripts.sil.org/OFL")!)
                                .font(.caption).tint(Ink.gold)
                        }
                    }
                    .padding(.vertical, 2)
                }
                // The spoken audio SHIPS as 102 rendered clips, so the model that produced it is
                // credited even though the model itself is not bundled — the output is what travels.
                Section(AppLocale.pick("语音", "Voice")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocale.pick("预渲染语音 · Kokoro-82M v1.1", "Pre-rendered voice · Kokoro-82M v1.1"))
                            .font(.subheadline).foregroundStyle(Ink.text)
                        HStack(spacing: 4) {
                            Link("Apache-2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
                                .font(.caption).tint(Ink.gold)
                            Text("·").font(.caption).foregroundStyle(Ink.textDim)
                            Link("sherpa-onnx", destination: URL(string: "https://github.com/k2-fsa/sherpa-onnx")!)
                                .font(.caption).tint(Ink.gold)
                        }
                        Text(AppLocale.pick("每句台词都是固定文本，离线渲染为音频随应用一起发布；模型本身不包含在应用内。",
                                            "Every spoken line is fixed text, rendered to audio offline and shipped with the app; the model itself is not bundled."))
                            .font(.footnote).foregroundStyle(Ink.textDim)
                    }
                    .padding(.vertical, 2)
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
// specifically enough to be verifiable, with the ONE exception (hands-free voice control) stated
// just as specifically: the mic is on by default with the camera, and on devices without on-device
// recognition what it hears goes to Apple's speech service. Linked from Settings; mirrors
// docs/privacy-policy.md. The rows are data, not inline views, so VoiceDisclosureTests can hold
// this copy to the actual mic behavior — this screen is where "off until you turn on the mic"
// survived long after the auto-start shipped.
struct PrivacyView: View {
    private var rows: [(icon: String, title: String, text: String)] {
        [
            ("iphone", AppLocale.pick("你的数据留在设备上", "Your data stays on this device"),
             AppLocale.pick("没有账户，没有统计分析。应用不收集、不存储、也不向任何 AcuGuide 服务器发送个人数据。",
                            "No accounts, no analytics. The app collects and stores no personal data, and sends none to any AcuGuide server.")),
            ("camera", AppLocale.pick("相机画面即时处理", "Camera frames are processed live"),
             AppLocale.pick("相机引导在设备上实时识别手部关键点来标注穴位。画面不会被保存，也绝不会离开设备。",
                            "The camera coach detects hand landmarks on-device, live, to mark point locations. Frames are never saved and never leave the device.")),
            ("cpu", AppLocale.pick("AI 也在设备上", "The AI runs on-device too"),
             AppLocale.pick("\(CoachPersona.name) 的自由问答由 Apple 的设备端模型生成（仅在支持的设备上），不联网。",
                            "\(CoachPersona.name)'s free-form answers are generated by Apple's on-device model (on supported devices) — no network involved.")),
            ("mic", AppLocale.pick("语音控制（默认开启）", "Voice control (on by default)"),
             AppLocale.pick("为了让你不用腾出手，相机引导会自动打开麦克风，聆听几句短指令（确认位置、定住画面、继续）— iOS 会先询问一次权限。识别用的是 Apple 的语音识别：你的语言支持设备端识别时，声音不会离开手机；不支持时，聆听期间麦克风听到的内容会发送给 Apple 的语音服务（适用 Apple 的隐私政策）。画面上的麦克风按钮可关闭本次聆听，「设置」里可以彻底关闭 — 点按操作始终可用。",
                            "So you never need a free hand, camera sessions turn the microphone on automatically to listen for a few short commands (confirm a spot, freeze the picture, continue) — iOS asks your permission first. Recognition uses Apple's speech recognition: with on-device recognition for your language, audio never leaves the phone; without it, what the microphone hears while listening is sent to Apple's speech service (Apple's privacy policy applies). The mic button on the camera screen stops listening for the session; Settings turns hands-free voice control off entirely — tapping always works.")),
            ("clock.arrow.circlepath", AppLocale.pick("练习记录仅保存在本机", "Practice history is local only"),
             AppLocale.pick("练习记录（穴位、轮数、时长、自评）只保存在你的手机里，删除应用即随之删除。",
                            "Your practice history (point, rounds, duration, self-report) lives only on your phone and is deleted with the app.")),
        ]
    }

    /// Every user-facing string on this screen, for the disclosure and banned-word tests.
    var allCopyForTesting: [String] { rows.flatMap { [$0.title, $0.text] } }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows, id: \.icon) { r in
                        row(r.icon, r.title, r.text)
                    }
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
