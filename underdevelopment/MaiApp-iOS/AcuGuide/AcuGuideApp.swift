import SwiftUI

@main
struct AcuGuideApp: App {
    init() {
        Diagnostics.shared.start()   // local-only MetricKit crash/hang capture (see Diagnostics)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Ink.gold)
        }
    }
}
