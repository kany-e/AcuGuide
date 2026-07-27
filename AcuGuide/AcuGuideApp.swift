import SwiftUI

@main
struct AcuGuideApp: App {
    // Answers supportedInterfaceOrientationsFor from OrientationLock — the app ships the landscape
    // orientations in its plist but permits them only on the camera coach. See Orientation.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Diagnostics.shared.start()   // local-only MetricKit crash/hang capture (see Diagnostics)
        ReminderPresentation.shared.install()   // reminders must present in the foreground too
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
