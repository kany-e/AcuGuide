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
                // The parchment/ink palette is a fixed LIGHT design; without this, system dark
                // mode darkens the surrounding chrome (Form, sheets, keyboard) while the Ink
                // colors stay light — a broken mix. A true "night ink" theme can lift this later.
                .preferredColorScheme(.light)
        }
    }
}
