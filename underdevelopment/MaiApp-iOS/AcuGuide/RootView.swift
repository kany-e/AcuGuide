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

// Atlas tab: the 3D body → tap the hand hotspot → hand acupoint map → back (mirrors the web
// onEnterHand / onBack). The body fills the screen (nav bar hidden); the hand view shows a
// back button + title.
struct AtlasTab: View {
    @Binding var startCoach: Acupoint?
    @State private var showHand = false

    var body: some View {
        NavigationStack {
            Body3DView(onEnterHand: { showHand = true })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showHand) {
                    HandAtlasView(startCoach: $startCoach)
                        .navigationTitle(AppLocale.pick("手部穴位", "Hand points"))
                        .navigationBarTitleDisplayMode(.inline)
                }
        }
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
