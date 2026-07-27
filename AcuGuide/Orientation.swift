import SwiftUI
import UIKit

// PER-SCREEN ORIENTATION, which SwiftUI has no API for.
//
// Device report: "can you make the app rotate as the phone rotates — the vertical orientation of
// the camera coach when the user is using it horizontally is just awful." That is specifically the
// camera coach: it is the one screen where the physical posture (phone propped on a table, both
// hands in front of you) makes landscape the natural way to hold it. The atlas, the chat and the
// point list are portrait-shaped ink-and-parchment layouts, and the 3D atlas in particular would
// render small between wide empty gutters (its SceneKit camera has a fixed 50° vertical field of
// view). So the Info.plist declares the superset and this narrows it per screen.
//
// The mechanism is an app-delegate mask rather than a UIHostingController subclass. The coach is
// presented in a `.fullScreenCover`, so a hosting-controller override would have to be attached to
// the COVER's controller — the system asks the topmost presented controller — which means reaching
// through SwiftUI's presentation machinery for a view controller it does not hand out. The delegate
// callback is asked for the whole window and is unambiguous.
enum OrientationLock {
    /// What the app currently permits. Portrait everywhere except where `.landscapeCapable()` says
    /// otherwise. Upside-down is never allowed: it is the one orientation that makes a propped-up
    /// phone genuinely confusing, and iPhone apps conventionally exclude it.
    static var mask: UIInterfaceOrientationMask = .portrait

    static func set(_ new: UIInterfaceOrientationMask) {
        guard new != mask else { return }
        mask = new
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
        else { return }
        // Two calls, and both are needed. requestGeometryUpdate ROTATES a window that is currently
        // in an orientation the new mask forbids (leaving the coach in landscape must snap back to
        // portrait, not strand the atlas sideways). setNeedsUpdate… re-asks the delegate so the
        // system honours a WIDENED mask, which the geometry request alone does not do.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: new))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

// The delegate exists only to answer this one question; there was no AppDelegate before.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

extension View {
    /// Allow landscape while this view is on screen; return to portrait when it leaves.
    ///
    /// Paired on appear/disappear rather than set once, so any exit — Done, End, a swipe back, the
    /// recap, a crash into the parent — puts the rest of the app back in portrait. `active` lets a
    /// caller keep the lock while the view lives but the feature is not running (the coach drops
    /// back to portrait for the recap, which is a reading screen, not a camera one).
    func landscapeCapable(_ active: Bool = true) -> some View {
        modifier(LandscapeCapable(active: active))
    }
}

private struct LandscapeCapable: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: active) { _ in apply() }
            .onDisappear { OrientationLock.set(.portrait) }
    }
    private func apply() {
        OrientationLock.set(active ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait)
    }
}
