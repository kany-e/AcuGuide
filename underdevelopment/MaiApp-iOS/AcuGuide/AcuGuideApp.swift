import SwiftUI

@main
struct AcuGuideApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)   // parchment-on-ink reads best dark
                .tint(Ink.gold)
        }
    }
}
