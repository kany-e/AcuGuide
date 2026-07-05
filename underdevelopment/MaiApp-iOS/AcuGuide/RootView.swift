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

            ChatView(startCoach: $startCoach)
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

// The Coach tab: pick any AR-coachable point (the 8 documented hand/wrist points), then launch
// the camera coach for it. TE3 leads — it's the validated routine.
struct ARCoachLauncher: View {
    @Binding var startCoach: Acupoint?
    @ObservedObject private var settings = AppSettings.shared
    private var coachable: [Acupoint] { Acupoint.all.filter { $0.mediapipeTarget != nil } }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocale.pick("相机引导", "Camera coach"))
                        .font(Typo.serif(22, weight: .semibold)).foregroundStyle(Ink.gold)
                        .frame(maxWidth: .infinity)
                    Text(AppLocale.pick("选择一个穴位，摄像头会引导你的按压。", "Pick a point — the camera guides your press."))
                        .font(.subheadline).foregroundStyle(Ink.textDim)
                        .frame(maxWidth: .infinity)

                    ForEach(coachable) { pt in
                        Button { startCoach = pt } label: {
                            HStack(spacing: 12) {
                                Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("\(pt.id) · \(pt.zh)")
                                            .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                                        Text(pt.en).font(Typo.code(14)).foregroundStyle(Ink.textDim)
                                        if pt.id == "TE3" {
                                            Text(AppLocale.pick("推荐", "suggested"))
                                                .font(.caption2).foregroundStyle(Ink.paperLight)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Ink.gold.opacity(0.9)))
                                        }
                                    }
                                    Text(pt.location)
                                        .font(.caption).foregroundStyle(Ink.text)
                                        .multilineTextAlignment(.leading).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "camera.viewfinder")
                                    .font(.callout).foregroundStyle(Ink.gold.opacity(0.8))
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                        .panel()
                    }

                    Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding()
            }
        }
    }
}

// Acupoint is already Identifiable via `id`; needed for .fullScreenCover(item:).
