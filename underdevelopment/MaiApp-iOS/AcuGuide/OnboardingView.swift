import SwiftUI

// First-run onboarding: three swipeable pages — what the app is (and is NOT: wellness framing up
// front), how the camera coach works, and the privacy story before any permission is ever asked.
// Shown once (AppSettings.seenOnboarding).
struct OnboardingView: View {
    var onDone: (_ quickTry: Bool) -> Void   // quickTry: launch one 30s coached round right away
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
                        title: AppLocale.pick("\(CoachPersona.name) 陪你按", "\(CoachPersona.name) coaches your press"),
                        text: AppLocale.pick(
                            "选择一个手部穴位，\(CoachPersona.name) 会在你的手上标出位置，陪你一轮一轮按 — 按 30 秒、松开呼吸、再来一轮。想停随时停。",
                            "Pick a hand point and \(CoachPersona.name) marks it on your hand, then keeps you company through the rounds — 30 seconds on, release and breathe, repeat. End whenever you like."))
                        .tag(1)
                    pageView(
                        icon: "lock.shield",
                        title: AppLocale.pick("一切都在设备上", "Everything stays on your device"),
                        text: AppLocale.pick(
                            "相机画面即时处理，不保存、不上传。没有账户、没有统计、没有服务器 — \(CoachPersona.name) 也完全在设备上运行。",
                            "Camera frames are processed live — never stored, never uploaded. No accounts, no analytics, no servers; even \(CoachPersona.name) runs entirely on-device."))
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(page < 2 ? AppLocale.pick("继续", "Continue") : AppLocale.pick("开始使用", "Get started")) {
                    if page < 2 { withAnimation { page += 1 } } else { onDone(false) }
                }
                .buttonStyle(GoldButtonStyle())
                .padding(.horizontal, 28).padding(.bottom, 4)

                // The first-success shortcut: straight into one 30-second coached round.
                if page == 2 {
                    Button(AppLocale.pick("先试一轮（30 秒）", "Try one round first (30s)")) { onDone(true) }
                        .font(.subheadline).tint(Ink.gold)
                        .padding(.bottom, 4)
                }

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
