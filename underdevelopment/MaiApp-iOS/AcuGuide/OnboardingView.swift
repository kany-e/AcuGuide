import SwiftUI

// First-run onboarding: three swipeable pages — what the app is (and is NOT: wellness framing up
// front), how the camera coach works, and the privacy story before any permission is ever asked.
// Shown once (AppSettings.seenOnboarding).
struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0

    var body: some View {
        ZStack {
            ShanshuiBackground()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageView(
                        icon: "figure.stand",
                        title: AppLocale.pick("欢迎使用 AcuGuide", "Welcome to AcuGuide"),
                        text: AppLocale.pick(
                            "探索全身安全穴位与十四经络 — 3D 图谱、双语讲解、来源可查。这是一款养生自我保养应用，不是医疗工具，也不提供医疗建议。",
                            "Explore safe acupoints and the fourteen meridians — a 3D atlas, bilingual guidance, and checkable sources. This is a wellness self-care app: not a medical tool, and not medical advice."))
                        .tag(0)
                    pageView(
                        icon: "camera.viewfinder",
                        title: AppLocale.pick("相机引导按压", "The camera coaches your press"),
                        text: AppLocale.pick(
                            "选择一个手部穴位，摄像头会在你的手上标出位置，引导你分轮按压 — 按 30 秒、松开呼吸、再来一轮。随时可以结束。",
                            "Pick a hand point and the camera marks it on your hand, then coaches rounds of pressing — 30 seconds on, release and breathe, repeat. End whenever you like."))
                        .tag(1)
                    pageView(
                        icon: "lock.shield",
                        title: AppLocale.pick("一切都在设备上", "Everything stays on your device"),
                        text: AppLocale.pick(
                            "相机画面即时处理，不保存、不上传。没有账户、没有统计、没有服务器 — AI 教练也在设备上运行。",
                            "Camera frames are processed live — never stored, never uploaded. No accounts, no analytics, no servers; even the Coach AI runs on-device."))
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(page < 2 ? AppLocale.pick("继续", "Continue") : AppLocale.pick("开始使用", "Get started")) {
                    if page < 2 { withAnimation { page += 1 } } else { onDone() }
                }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 28).padding(.bottom, 8)

                Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                    .font(.caption2).foregroundStyle(Ink.textDim)
                    .padding(.bottom, 18)
            }
        }
    }

    private func pageView(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(Ink.gold)
            Text(title).font(Typo.serif(24, weight: .semibold)).foregroundStyle(Ink.gold)
                .multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(Ink.text)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
    }
}
