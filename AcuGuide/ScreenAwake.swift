import SwiftUI
import UIKit

// Keeps the screen awake while a practice session is actually running.
//
// A paced round is 30 seconds of holding still with both hands on a point and NOTHING touching the
// screen — which is exactly the condition iOS reads as "idle". The phone would dim and lock
// mid-round, taking the countdown ring, the live cue and (in the coach) the camera view with it.
// The user cannot tap to wake without letting go of the point they are being coached to hold.
//
// The flag is global UIApplication state, so the important part is not setting it — it is ALWAYS
// putting it back. This modifier releases on every exit path: the condition going false, the view
// disappearing, and the app leaving the foreground. Leaking it would leave a user's phone unable to
// auto-lock long after they left the app, which is a battery bug they would never attribute to us.
private struct KeepScreenAwake: ViewModifier {
    let active: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { apply(active) }
            .onChange(of: active) { apply($0) }
            // Backgrounding already stops the session clock; release the flag with it rather than
            // holding the system awake for an app the user has walked away from.
            .onChange(of: scenePhase) { apply(active && $0 == .active) }
            .onDisappear { apply(false) }
    }

    private func apply(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }
}

extension View {
    /// Hold the screen awake while `active` is true. Always released on disappear/background.
    func keepScreenAwake(while active: Bool) -> some View {
        modifier(KeepScreenAwake(active: active))
    }
}
