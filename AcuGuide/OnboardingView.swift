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
                        // Promises the one thing no chart, video or timer app can do: the app marks
                        // the point, YOU fine-tune it by feel, and it remembers where that point is
                        // on your hand. (This is also the sentence the store listing leads with.)
                        text: AppLocale.pick(
                            "\(CoachPersona.name) 在你的手上标出穴位，你按感觉微调到最准的位置 — 它会记住这个属于你的位置，以后每次都用它，并陪你一轮一轮按。想停随时停。",
                            "\(CoachPersona.name) marks the point on your hand, you fine-tune it by feel — and it remembers where that point is on YOUR hand for every session after. Then it keeps you company through the rounds. End whenever you like."))
                        .tag(1)
                    pageView(
                        icon: "lock.shield",
                        title: AppLocale.pick("一切都在设备上", "Everything stays on your device"),
                        text: AppLocale.pick(
                            "相机画面即时处理，不保存、不上传。没有账户、没有统计；相机与 \(CoachPersona.name) 都在你的设备上运行。（可选的语音控制可能会用到 Apple 的语音服务。）",
                            "Camera frames are processed live — never stored, never uploaded. No accounts, no analytics; the camera and \(CoachPersona.name) run on your device. (The optional voice control can use Apple's speech service.)"))
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

                WellnessFooter()
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
