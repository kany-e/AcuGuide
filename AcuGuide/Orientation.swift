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

    /// HOW MANY views currently want landscape, not the last one to speak.
    ///
    /// A routine swaps steps with `.id(stepIndex)` (RoutinesUI) and step 2+ starts already
    /// acknowledged, so the incoming step widens the mask in onAppear while the OUTGOING step still
    /// has its onDisappear narrowing pending. SwiftUI promises nothing about that ordering: if the
    /// disappear lands last, landscape is dead for every step after the first and nothing ever
    /// re-widens it, because `active` never changes again for the new step. A count cannot be
    /// stomped by whichever callback happens to run second.
    private static var holders = 0

    static func addLandscape() { holders += 1; apply() }
    static func removeLandscape() { holders = max(0, holders - 1); apply() }

    private static func apply() {
        let new: UIInterfaceOrientationMask = holders > 0
            ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
        // NO `guard new != mask` DEDUPE. It used to sit ABOVE the scene lookup while `mask = new` sat
        // below it, so a call made while no scene was foregroundActive updated the static, applied
        // nothing, and then blocked every later call with the same value for the rest of the session.
        // Re-pushing an unchanged mask is cheap and is the only thing that repairs that.
        mask = new
        OrientationDriver.shared.wantsLandscape = (holders > 0)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })
        else { return }

        // THE WHOLE PRESENTATION CHAIN, not just the root. This is why the first attempt did
        // nothing on device: the camera coach is presented in a `.fullScreenCover`, and UIKit asks
        // the TOPMOST PRESENTED view controller — telling only the root to re-read its orientations
        // leaves the controller that is actually being consulted holding its stale answer. (A
        // widely-reported SwiftUI trap; the preference-key variants of this fix fail for the same
        // reason.) Walking the chain also covers sheets stacked on top of the cover.
        var vc = scene.keyWindow?.rootViewController
        while let current = vc {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = current.presentedViewController
        }

        // THEN the geometry request — after the system has re-read the mask, or it evaluates the
        // request against the old one. This is what snaps a window back when the mask NARROWS
        // (leaving the coach in landscape must return the atlas to portrait, not strand it sideways).
        //
        // Only on narrowing. Requesting the WIDE set was the bug that made two rounds of this fix
        // read as "landscape still doesn't work": the wide set contains .portrait and is requested at
        // the one moment the window is guaranteed to already BE portrait, so the system resolves it
        // to "you are already in a permitted orientation" and turns nothing. Widening only PERMITS
        // landscape; OrientationDriver is what actually turns the window.
        guard new == .portrait else { return }
        // The errorHandler is not decoration: this call fails SILENTLY otherwise.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
            print("[OrientationLock] portrait snap-back refused: \(error.localizedDescription)")
        }
    }
}

// FORCING the rotation, because PERMITTING it was demonstrably not enough on device.
//
// Widening the mask only tells iOS that landscape is allowed here; whether the window actually turns
// was then entirely up to the system's own autorotation, and the app had no trigger, no retry and no
// fallback — the only failure signal was a print the user never sees. Requesting a SINGLE
// orientation is the one form of requestGeometryUpdate the system cannot resolve to "already there".
//
// WHY UIDevice HERE, WHEN ARCoachView.syncRotation DELIBERATELY REFUSES IT. Those are different
// questions and the reasoning does not transfer. The CAPTURE ANGLE must never disagree with the
// layout, so it is driven by the view's own post-layout size — that comment stands untouched. This
// is the layout's TRIGGER, and a trigger has to come from somewhere the interface has not gone yet.
// The two properties that disqualified UIDevice for the capture angle are why it is right for this:
//   • it fires BEFORE the window turns — that is the point; we are the ones turning it;
//   • it reports .faceUp/.faceDown constantly for a phone propped on a table (the posture this whole
//     screen is built around) — and we ignore those, which buys the same flat-phone hysteresis free.
//
// NOTE this deliberately turns the window even under Portrait Orientation Lock, and only on the
// camera coach. That is the same bargain video players make, and it is the screen whose entire
// premise is a phone propped sideways with both of the user's hands in front of it.
final class OrientationDriver: ObservableObject {
    static let shared = OrientationDriver()

    /// The interface orientation the window is in or is being sent to.
    ///
    /// Published because landscapeLeft → landscapeRight changes NO SwiftUI size: the coach's
    /// `geo.size.width > geo.size.height` hook cannot see it, yet CaptureRotation puts those two a
    /// half-turn apart. Flipping a propped phone end-for-end left the video upside down under a
    /// layout that looked entirely correct, for the rest of the session.
    @Published private(set) var interfaceOrientation: UIInterfaceOrientation = .portrait

    var wantsLandscape = false {
        didSet {
            guard wantsLandscape != oldValue else { return }
            wantsLandscape ? start() : stop()
        }
    }

    /// Which interface orientation a physical device orientation should send the window to, or nil
    /// to hold the current one. Pure so the inversion below is unit-testable.
    ///
    /// THE SWAP IS NOT A TYPO. UIDeviceOrientation and UIInterfaceOrientation name the two landscapes
    /// from opposite ends — the device's left edge rotating down is the interface going right — so
    /// `.landscapeLeft` maps to `.landscapeRight`. Getting it backwards is a silent half-turn, and
    /// CaptureRotation puts those two 180° apart, so it would show as upside-down video.
    ///
    /// nil for .faceUp / .faceDown / .unknown: they say nothing about how the phone is being held,
    /// and a phone propped on a table (the posture this screen exists for) produces them constantly.
    /// Holding the last decision gives the same flat-phone hysteresis iOS has, for free.
    static func target(for device: UIDeviceOrientation) -> UIInterfaceOrientation? {
        switch device {
        case .portrait:       return .portrait
        case .landscapeLeft:  return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default:              return nil        // faceUp / faceDown / portraitUpsideDown / unknown
        }
    }

    private var observer: NSObjectProtocol?

    private func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.deviceTurned() }
        // The phone may ALREADY be sideways when the coach opens, so evaluate once on arrival — but
        // NOT synchronously. start() is reached from OrientationLock.apply() inside the view's
        // onAppear, and deviceTurned() assigns a @Published that ARCoachView observes: doing that
        // inside a view update is the "Publishing changes from within view updates" trap. The
        // notification path is already off the update cycle; only this first call needs the hop.
        DispatchQueue.main.async { [weak self] in self?.deviceTurned() }
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func deviceTurned() {
        guard wantsLandscape,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { return }

        guard let target = Self.target(for: UIDevice.current.orientation) else { return }
        if interfaceOrientation != target { interfaceOrientation = target }
        guard scene.interfaceOrientation != target else { return }

        let mask: UIInterfaceOrientationMask
        switch target {
        case .landscapeLeft:  mask = .landscapeLeft
        case .landscapeRight: mask = .landscapeRight
        default:              mask = .portrait
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            print("[OrientationDriver] rotate to \(target.rawValue) refused: \(error.localizedDescription)")
        }
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
    /// Whether THIS view currently holds a landscape claim. Tracked per-instance so add/remove stay
    /// balanced no matter what order SwiftUI runs appear/disappear across a view-identity swap —
    /// releasing a claim we never took would drop someone else's.
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: active) { _ in sync() }
            .onDisappear { if holding { holding = false; OrientationLock.removeLandscape() } }
    }

    private func sync() {
        guard active != holding else { return }
        holding = active
        active ? OrientationLock.addLandscape() : OrientationLock.removeLandscape()
    }
}
