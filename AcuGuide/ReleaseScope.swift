import Foundation

// WHAT SHIPS IN THIS RELEASE — product scope decisions, kept apart from the features themselves so
// a feature can be finished, tested and held back without being deleted or left to rot.
enum ReleaseScope {
    /// MOXIBUSTION IS OUT OF v1, by decision (Oct 2026), and not because anything in it is unfinished.
    ///
    /// It is the riskiest feature in the app — an open flame, low-temperature burns that do not hurt
    /// while they happen, carbon monoxide in closed rooms, and a user base that skews older — and
    /// none of its safety design has been seen working on a phone: the camera marks on a real trunk,
    /// the background check notification, the clock in daily use. Its worst bug so far (a backgrounded
    /// app let a sitting run past the 15-minute cap, fixed in R32) was found by reading code, not by
    /// anyone using it. v1 ships the camera-coached acupressure that is the app's differentiator, and
    /// moxa returns once it has been verified on a device.
    ///
    /// The code stays compiled and every moxa test keeps running, so it cannot decay while hidden.
    /// The tab entry in RootView is the ONLY place the rest of the app reaches moxa — the store
    /// listing, privacy policy and onboarding never mention it — so this one flag is the whole cut.
    /// ReleaseScopeTests pins it: flipping it means editing that test, on purpose.
    static let moxaShipsInThisRelease = false

    #if DEBUG
    /// Debug builds only: Settings → Developer can show the unreleased tab, so moxa can be verified
    /// on a device before it ships. Never present in a Release build.
    static let devShowMoxaKey = "dev.showUnreleasedMoxaTab"
    #endif
}
