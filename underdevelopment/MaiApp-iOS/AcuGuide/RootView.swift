import SwiftUI

struct RootView: View {
    @State private var startCoach: Acupoint? = nil
    @ObservedObject private var settings = AppSettings.shared   // re-render tab labels on toggle

    var body: some View {
        // No separate "Hand" tab — the hand is a drill-down from the 3D body (web parity).
        TabView {
            AtlasTab(startCoach: $startCoach)
                .tabItem { Label(AppLocale.pick("图谱", "Atlas"), systemImage: "figure.stand") }

            ARCoachLauncher(startCoach: $startCoach)
                .tabItem { Label(AppLocale.pick("引导", "Coach"), systemImage: "camera.viewfinder") }

            ChatView()
                .tabItem { Label(AppLocale.pick("AI 教练", "Coach AI"), systemImage: "bubble.left.and.bubble.right") }
        }
        .tint(Ink.gold)
        // Launch the AR coach when a TE3 marker chooses "Practice with camera".
        .fullScreenCover(item: $startCoach) { pt in
            NavigationStack {
                ARCoachView(acupoint: pt)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button(AppLocale.pick("关闭", "Close")) { startCoach = nil }.tint(Ink.gold)
                    } }
            }
        }
    }
}

// Atlas tab: the 3D body IS the whole atlas (no 2D drill-down). Tap a region label to zoom the
// camera in-scene, tap a 3D acupoint marker for its details, and "Practice with camera" launches
// the AR coach for the validated TE3 point. The 2D HandAtlasView is retired as the primary path.
struct AtlasTab: View {
    @Binding var startCoach: Acupoint?
    var body: some View {
        // No .ignoresSafeArea here: the SceneKit view + projected-label overlay ignore the safe
        // area internally (so projectPoint coords line up), while the back button + point panel
        // stay inside the safe area and clear the status bar / tab bar.
        Body3DView(onPractice: { startCoach = $0 })
    }
}

// The Coach tab: defaults to the validated TE3 routine.
struct ARCoachLauncher: View {
    @Binding var startCoach: Acupoint?
    @ObservedObject private var settings = AppSettings.shared
    private var te3: Acupoint { Acupoint.all.first { $0.id == "TE3" } ?? Acupoint.all[0] }
    var body: some View {
        ZStack {
            ShanshuiBackground()
            VStack(spacing: 18) {
                Text(AppLocale.pick("紧张性头痛调理", "Tension-headache routine"))
                    .font(Typo.serif(20, weight: .semibold)).foregroundStyle(Ink.gold)
                Text(AppLocale.pick("中渚 TE3 — 在手背、无名指与小指掌指关节后方的凹沟处按压。",
                                    "TE3 · 中渚 — press the groove behind your ring and pinky knuckles, on the back of the hand."))
                    .foregroundStyle(Ink.text).multilineTextAlignment(.center).padding(.horizontal)
                Button(AppLocale.pick("开始相机引导", "Start camera coach")) { startCoach = te3 }
                    .buttonStyle(GoldButtonStyle())
                Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                    .font(.caption2).foregroundStyle(Ink.textDim)
            }.padding()
        }
    }
}

// Acupoint is already Identifiable via `id`; needed for .fullScreenCover(item:).
