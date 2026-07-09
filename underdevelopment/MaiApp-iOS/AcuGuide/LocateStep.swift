import SwiftUI

// Remembers which points the user has located by feel before — so the locate step can greet a
// repeat visit warmly ("you've found this before") rather than re-teaching from scratch. Shares the
// id-set-in-UserDefaults base with Favorites. This is the honest version of "save the spot for
// later": we record that you confirmed it, not a fake per-user coordinate.
final class LocatedStore: IDSetStore {
    static let shared = LocatedStore()
    init(defaults: UserDefaults = .standard) { super.init(key: "locatedPoints", defaults: defaults) }
    func markLocated(_ id: String) { insert(id) }
}

// The find-it-by-feel step, shown BETWEEN the safety gate and the live camera for every coached
// point that has a plain-language guide. The flow the user asked for: describe how to find the
// spot in plain words → the user presses around and feels for it → "yes, I found it" → into the
// camera, where the marker now just confirms a spot already under their finger (a more accurate
// press than chasing the dot cold). "Guide me on camera instead" skips straight in.
struct LocateStep: View {
    let point: Acupoint
    var onFound: () -> Void
    var onSkip: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    private var seenBefore: Bool { LocatedStore.shared.contains(point.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocale.pick("先找到位置", "Find the spot first"))
                        .font(Typo.serif(24, weight: .semibold)).foregroundStyle(Ink.gold)
                    HStack(spacing: 8) {
                        Circle().fill(MeridianColors.color(point.meridian)).frame(width: 10, height: 10)
                        Text("\(point.id) · \(point.zh)").font(Typo.serif(18, weight: .semibold)).foregroundStyle(Ink.text)
                        Text(point.en).font(Typo.code(14)).foregroundStyle(Ink.textDim)
                    }
                }

                if seenBefore {
                    Text(AppLocale.pick("你之前找到过这个穴位 — 快速回忆一下位置。",
                                        "You've found this one before — a quick refresher on where it is."))
                        .font(.footnote).foregroundStyle(Ink.jade)
                }

                // How to find it — the plain-language guide.
                guideCard(AppLocale.pick("这样找", "How to find it"), icon: "hand.point.up.left") {
                    Text(point.findHow).font(.body).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The sensation that confirms it — the "do you feel the indent?" prompt.
                guideCard(AppLocale.pick("感觉一下", "Feel for it"), icon: "sparkle.magnifyingglass") {
                    Text(point.findFeel).font(.subheadline).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("轻轻按一按，找到略有胀感的那一点 — 那就是它。",
                                        "Press gently around it and settle on the point that feels slightly tender — that's the one."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(AppLocale.pick("找到了 · 打开相机", "Found it · open the camera")) { onFound() }
                    .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                Button(AppLocale.pick("直接用相机引导", "Just guide me on camera")) { onSkip() }
                    .font(.subheadline).tint(Ink.gold).frame(maxWidth: .infinity)

                Text(AppLocale.pick("接下来相机会在同一位置标出圆圈，帮你确认并稳定按压。",
                                    "Next, the camera marks a ring on that same spot to confirm it and steady your press."))
                    .font(.caption2).foregroundStyle(Ink.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                WellnessFooter()
            }
            .padding(28)
        }
    }

    // One panel card: a small captioned header + its content (both guide cards share it).
    @ViewBuilder private func guideCard<Content: View>(_ title: String, icon: String,
                                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
