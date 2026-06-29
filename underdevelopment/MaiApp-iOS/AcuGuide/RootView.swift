import SwiftUI

struct RootView: View {
    @State private var startCoach: Acupoint? = nil

    var body: some View {
        // No separate "Hand" tab — the hand is a drill-down from the 3D body (web parity).
        TabView {
            AtlasTab(startCoach: $startCoach)
                .tabItem { Label("Atlas", systemImage: "figure.stand") }

            ARCoachLauncher(startCoach: $startCoach)
                .tabItem { Label("Coach", systemImage: "camera.viewfinder") }

            ChatView()
                .tabItem { Label("Coach AI", systemImage: "bubble.left.and.bubble.right") }
        }
        .tint(Ink.gold)
        // Launch the AR coach when a point is chosen from the hand atlas.
        .fullScreenCover(item: $startCoach) { pt in
            NavigationStack {
                ARCoachView(acupoint: pt)
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { startCoach = nil }.tint(Ink.gold)
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
    private var te3: Acupoint { Acupoint.all.first { $0.id == "TE3" } ?? Acupoint.all[0] }
    var body: some View {
        ZStack {
            ShanshuiBackground()
            VStack(spacing: 18) {
                Text("Tension-headache routine").font(.title3).foregroundStyle(Ink.gold)
                Text("TE3 · 中渚 — press the groove behind your ring and pinky knuckles, on the back of the hand.")
                    .foregroundStyle(Ink.text).multilineTextAlignment(.center).padding(.horizontal)
                Button("Start camera coach") { startCoach = te3 }.buttonStyle(GoldButtonStyle())
                Text("Wellness self-care only — not medical advice.")
                    .font(.caption2).foregroundStyle(Ink.textDim)
            }.padding()
        }
    }
}

// Acupoint is already Identifiable via `id`; needed for .fullScreenCover(item:).
