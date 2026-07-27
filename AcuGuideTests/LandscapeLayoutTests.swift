import XCTest
import SwiftUI
@testable import AcuGuide

// LANDSCAPE LAYOUT, measured rather than assumed.
//
// The camera coach can now be held sideways, which puts its chrome in a viewport ~390 pt TALL — and
// the tallest thing it renders, LocateCard with the finding guide expanded, was drawn for a
// full-height portrait screen. The risk is specific and it is silent: a card that overruns the
// viewport takes the confirm button off the bottom with it, and the coach's own dynamic-type cap
// (accessibility2) exists because that budget was already tight in PORTRAIT.
//
// The Simulator cannot be rotated from a unit test (XCUIDevice needs a UI-test bundle) and the
// camera does not run there at all, so this measures the card the way the layout does — at the
// landscape column width — and writes a render to look at.
final class LandscapeLayoutTests: XCTestCase {

    /// Width of the landscape side column in ARCoachView, and the shortest viewport it must live in
    /// (iPhone 17 Pro is 874×402; the safe area takes a little more).
    private let columnWidth: CGFloat = 380
    private let landscapeHeight: CGFloat = 402

    @MainActor
    private func render(_ view: some View, width: CGFloat, name: String) -> CGSize {
        let renderer = ImageRenderer(content: view.frame(width: width).background(Color.black))
        renderer.scale = 2
        let size = renderer.uiImage?.size ?? .zero
        if let data = renderer.uiImage?.pngData() {
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("landscape_\(name).png")
            try? data.write(to: out)
            print("LANDSCAPE wrote \(out.path)  intrinsic \(Int(size.width))×\(Int(size.height)) @1x")
        }
        return size   // ImageRenderer reports POINTS; `scale` only affects the backing pixels
    }

    @MainActor
    func testTheTallestCardFitsTheLandscapeColumn() throws {
        let point = Acupoint.byId["TE3"]!
        let engine = CoachEngine(startLocating: true, calibration: .ephemeral())
        defer { PointCalibration.purgeEphemeral() }
        let card = LocateCard(point: point, engine: engine, voiceControl: LocateVoiceControl(),
                              hint: nil, onPause: {}, onEnd: {})

        let size = render(card, width: columnWidth, name: "locate_card")
        XCTAssertLessThanOrEqual(size.width, columnWidth + 1,
                                 "the card overflows the landscape column horizontally")
        // NOT an assertion that it fits the viewport: at large Dynamic Type it legitimately will
        // not, which is exactly why ARCoachView wraps the landscape column in a ScrollView. What
        // must hold is that it is in the same order of magnitude — a card several times the
        // viewport means something is laying out unbounded rather than merely being long.
        XCTAssertLessThan(size.height, landscapeHeight * 2,
                          "the locate card is \(Int(size.height)) pt tall in a \(Int(landscapeHeight)) pt viewport — too tall to scroll comfortably")
        print("LANDSCAPE locate card: \(Int(size.width))×\(Int(size.height)) pt in a \(Int(landscapeHeight)) pt viewport")
    }

    // The recap is the other screen that ends a session, and it had NO vertical escape at all
    // before this branch — its own comments record the button row already overflowing horizontally
    // at 375 pt. It is portrait-only (the coach drops the landscape lock for it), so the bar is
    // just "fits a portrait phone", but the stop guidance and the next-step button are the two
    // things that must never be unreachable.
    @MainActor
    func testRecapFitsAPortraitPhoneOrScrolls() throws {
        var feeling: String? = "uncomfortable"      // the arm that adds the stop guidance
        let binding = Binding(get: { feeling }, set: { feeling = $0 })
        let recap = SessionRecapView(point: Acupoint.byId["TE3"]!, roundsDone: 4, roundsTarget: 4,
                                     heldS: 128, roundTimes: [30, 33, 31, 34], verifiedHold: true,
                                     sessionComplete: true, feeling: binding, onFeeling: { _ in },
                                     onNext: (label: "Next point", action: {}))
        let size = render(recap, width: 375, name: "recap")
        XCTAssertLessThanOrEqual(size.width, 376, "the recap overflows a 375 pt screen horizontally")
        print("LANDSCAPE recap: \(Int(size.width))×\(Int(size.height)) pt")
    }
}

// THE IN-FLOW VOICE HINT, rendered. The Simulator has no microphone, so `listening` never becomes
// true there and the chip cannot be reached by driving the UI — but it is the thing the user
// rejected the last version of, so it gets looked at rather than assumed.
final class VoiceHintRenderTests: XCTestCase {
    @MainActor
    private func render(_ lines: [String], name: String) -> CGSize {
        let renderer = ImageRenderer(content:
            VoiceHintChip(lines: lines).padding(16).background(Color(white: 0.25)))
        renderer.scale = 2
        if let data = renderer.uiImage?.pngData() {
            let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("voicehint_\(name).png")
            try? data.write(to: out)
            print("VOICEHINT wrote \(out.path)")
        }
        return renderer.uiImage?.size ?? .zero
    }

    @MainActor
    func testHintFitsTheCameraScreen() {
        // First contact: the two-line form (Google's conversation-design guidance puts the
        // first-run set at two or three intents, not one and not a menu).
        let two = render(["Say “show me” to freeze and read the guide",
                          "Say “what can I say” for all commands"], name: "firstrun")
        // Later sessions: one contextual line.
        let one = render(["Say “show me” to freeze and read the guide"], name: "settled")

        // It sits over a live camera in a 402 pt-wide portrait viewport and must not crowd the
        // hands. Width bound is generous; the real constraint is that it stays a CHIP, not a panel.
        XCTAssertLessThan(two.width, 402, "the first-run hint is wider than the screen")
        XCTAssertLessThan(two.height, 90, "the first-run hint has grown into a panel")
        XCTAssertLessThan(one.height, two.height, "the settled hint must be shorter than first-run")
        print("VOICEHINT first-run \(Int(two.width))×\(Int(two.height)) pt · settled \(Int(one.width))×\(Int(one.height)) pt")
    }
}
