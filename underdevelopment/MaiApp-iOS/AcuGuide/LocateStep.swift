import SwiftUI

// Remembers which points the user has located by feel before — so the locate step can greet a
// repeat visit warmly ("you've found this before") rather than re-teaching from scratch. Shares the
// id-set-in-UserDefaults base with Favorites. (The per-user COORDINATE lives separately, in
// PointCalibration — this store only records that the user confirmed the spot.)
final class LocatedStore: IDSetStore {
    static let shared = LocatedStore()
    init(defaults: UserDefaults = .standard) { super.init(key: "locatedPoints", defaults: defaults) }
    func markLocated(_ id: String) { insert(id) }
}

// The find-it-by-feel step, ON CAMERA (was a text-only screen — user-corrected: the point of the
// guidance is to fine-tune the computed spot for THIS user's hand, which needs the camera).
// The flow: the dashed ring marks "about here" and this card walks the user through finding the
// exact spot by feel; they press around with the other fingertip; the camera labels where they
// actually press; "This is my spot" saves that press as their personal correction
// (PointCalibration) and every future ring sits there. "Skip" starts coaching on the standard
// (or previously saved) spot. The confirm stays unlocked for a few seconds after the press lifts
// (the engine's confirm latch) — that lifted hand is the one that has to tap the button.
struct LocateCard: View {
    let point: Acupoint
    @ObservedObject var engine: CoachEngine   // mode flips to .coach on confirm/skip — parent swaps cards
    var hint: String?                          // ARCoachView's hintLine (occlusion + low-light)
    var onPause: () -> Void
    var onEnd: () -> Void
    // THE SAME store the engine applies to the ring (injected there for test hermeticity) — a
    // hardcoded .shared here would show/reset a different table than the one moving the ring.
    @ObservedObject private var calibration: PointCalibration
    @ObservedObject private var settings = AppSettings.shared
    private var seenBefore: Bool { LocatedStore.shared.contains(point.id) }

    init(point: Acupoint, engine: CoachEngine, hint: String? = nil,
         onPause: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.point = point
        self.hint = hint
        self.onPause = onPause
        self.onEnd = onEnd
        _engine = ObservedObject(wrappedValue: engine)
        _calibration = ObservedObject(wrappedValue: engine.calibration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(MeridianColors.color(point.meridian)).frame(width: 8, height: 8)
                Text(AppLocale.pick("先找到位置", "Find the spot first"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                Text("\(point.id) · \(point.zh)").font(.caption).foregroundStyle(Ink.textDim)
                Spacer()
                // The session controls stay reachable during locate (the camera runs behind this
                // card too): pause stops the capture session, End goes to the recap path.
                Button { onPause() } label: {
                    Image(systemName: "pause.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Ink.textDim)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Capsule().stroke(Ink.line, lineWidth: 1))
                }
                .accessibilityLabel(AppLocale.pick("暂停", "Pause"))
                Button(AppLocale.pick("结束", "End")) { onEnd() }
                    .font(.caption2.weight(.semibold)).foregroundStyle(Ink.textDim)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().stroke(Ink.line, lineWidth: 1))
                    .accessibilityHint(AppLocale.pick("结束本次练习", "End this session"))
            }

            // The plain-language guide + the confirming sensation, compact over the camera.
            Text(point.findHow).font(.footnote).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(point.findFeel).font(.caption).foregroundStyle(Ink.gold)
                .fixedSize(horizontal: false, vertical: true)

            // Live status from the engine's locate tracker (what the camera sees right now).
            Text(engine.cue).font(.subheadline).foregroundStyle(Ink.text)
                .lineLimit(3).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.updatesFrequently)
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(Ink.warn)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            if seenBefore && engine.locateState == .noPress {
                Text(AppLocale.pick("你之前找到过这个穴位 — 快速回忆一下。",
                                    "You've found this one before — a quick refresher."))
                    .font(.caption2).foregroundStyle(Ink.jade)
            }

            HStack(spacing: 10) {
                Button(AppLocale.pick("就是这里", "This is my spot")) {
                    if engine.confirmLocate(point: point) {
                        LocatedStore.shared.markLocated(point.id)
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(engine.locateState != .ready)
                .opacity(engine.locateState == .ready ? 1 : 0.5)

                Button(AppLocale.pick("先跳过", "Skip")) {
                    engine.endLocate()
                }
                .font(.subheadline).tint(Ink.gold)
                .accessibilityHint(AppLocale.pick("直接开始按压引导", "Start coaching without saving a spot"))
            }

            // The honest line about what's saved: a stored personal spot is used and can be reset.
            if calibration.hasCalibration(point.id) {
                HStack(spacing: 8) {
                    Text(AppLocale.pick("圆圈已按你上次确认的位置微调。",
                                        "The ring is fine-tuned to the spot you confirmed before."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                    Button(AppLocale.pick("恢复标准位置", "Reset to standard")) {
                        calibration.clear(point.id)
                    }
                    .font(.caption2.weight(.semibold)).tint(Ink.gold)
                }
            }
        }
        .padding(14).panel().padding()
        .accessibilityElement(children: .contain)
    }
}
