import SwiftUI

// Remembers which points the user has located by feel before — so the locate step can collapse
// the how-to guide (rather than re-teach) on a repeat visit. Shares the id-set-in-UserDefaults
// base with Favorites. (The per-user COORDINATE lives separately, in PointCalibration — this
// store only records that the user confirmed the spot.)
final class LocatedStore: IDSetStore {
    static let shared = LocatedStore()
    init(defaults: UserDefaults = .standard) { super.init(key: "locatedPoints", defaults: defaults) }
    func markLocated(_ id: String) { insert(id) }
}

// The find-it-by-feel step, ON CAMERA (was a text-only screen — user-corrected: the point of the
// guidance is to fine-tune the computed spot for THIS user's hand, which needs the camera).
// The flow: the dashed ring marks the STANDARD spot and this card walks the user through finding
// the exact spot by feel; they press around with the other fingertip; the camera labels where
// they actually press; "This is my spot" saves that press as their personal correction
// (PointCalibration) and every future ring sits there. "Skip" starts coaching on the standard
// (or previously saved) spot. The confirm stays unlocked for a few seconds after the press lifts
// (the engine's confirm latch) — that lifted hand is the one that has to tap the button.
//
// Kept LEAN over the live camera (review-caught: the card could stack ~14 bottom-anchored text
// lines over exactly where a chest-height hand sits): the how-to guide lives behind a disclosure
// (expanded only for first-timers), Reset hides in the ellipsis menu, steady state ≈ header +
// cue + buttons.
struct LocateCard: View {
    let point: Acupoint
    @ObservedObject var engine: CoachEngine   // mode flips to .coach on confirm/skip — parent swaps cards
    @ObservedObject var voiceControl: LocateVoiceControl   // hands-free confirm (both hands are pressing)
    var hint: String?                          // ARCoachView's hintLine (occlusion + low-light)
    var onPause: () -> Void
    var onEnd: () -> Void
    var onConfirmed: () -> Void                // saved-feedback hook (voice/haptic/chip live in the parent)
    var onSkipped: () -> Void
    // THE SAME store the engine applies to the ring (injected there for test hermeticity) — a
    // hardcoded .shared here would show/reset a different table than the one moving the ring.
    @ObservedObject private var calibration: PointCalibration
    @ObservedObject private var settings = AppSettings.shared
    @State private var guideExpanded: Bool

    init(point: Acupoint, engine: CoachEngine, voiceControl: LocateVoiceControl, hint: String? = nil,
         onPause: @escaping () -> Void, onEnd: @escaping () -> Void,
         onConfirmed: @escaping () -> Void = {}, onSkipped: @escaping () -> Void = {}) {
        self.point = point
        self.hint = hint
        self.onPause = onPause
        self.onEnd = onEnd
        self.onConfirmed = onConfirmed
        self.onSkipped = onSkipped
        _engine = ObservedObject(wrappedValue: engine)
        _voiceControl = ObservedObject(wrappedValue: voiceControl)
        _calibration = ObservedObject(wrappedValue: engine.calibration)
        // First visit teaches; a repeat visit starts collapsed (the guide is one tap away).
        _guideExpanded = State(initialValue: !LocatedStore.shared.contains(point.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(MeridianColors.color(point.meridian)).frame(width: 8, height: 8)
                Text(AppLocale.pick("先找到位置", "Find the spot first"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                Text("\(point.id) · \(point.zh)").font(.caption).foregroundStyle(Ink.textDim)
                Spacer()
                if calibration.hasCalibration(point.id) {
                    Menu {
                        Button(AppLocale.pick("恢复标准位置", "Reset to standard")) {
                            calibration.clear(point.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
                            .padding(.horizontal, 4).padding(.vertical, 6)
                    }
                    .accessibilityLabel(AppLocale.pick("更多选项", "More options"))
                }
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

            // The plain-language guide + the confirming sensation, behind a disclosure so the
            // steady-state card stays low over the camera.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { guideExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: guideExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(AppLocale.pick("这样找", "How to find it"))
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Ink.gold)
            }
            .accessibilityHint(AppLocale.pick("展开或收起找穴说明", "Shows or hides the finding guide"))
            // Open when the user asked for it OR when the engine is actively telling them to hunt.
            // The .noPress / .offGuide cues literally say to follow the guide — collapsing the guide
            // at exactly that moment is what made the spoken prompt reference text the user could not
            // see. `guideExpanded` stays a real user override for the states where they are on target.
            if guideExpanded || engine.locateState == .noPress || engine.locateState == .offGuide {
                Text(point.findHow).font(.footnote).foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(point.findFeel).font(.caption).foregroundStyle(Ink.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // WRONG FACE gets its own banner rather than a line of status text. It is the one
            // locate state that both BLOCKS confirm and has a specific physical fix, and as plain
            // .subheadline prose under a greyed-out button it read as background chatter: device
            // report was "I had my 手心 side in the camera, it didn't ask me to flip or anything, it
            // just shows that 就是这里 is unavailable to click". The cue was there; it just did not
            // look like an instruction. Icon + warn colour + the reason the button is dead.
            if engine.locateState == .wrongFace {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.subheadline).foregroundStyle(Ink.warn)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.cue).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.warn)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(AppLocale.pick("这一面对着镜头时才能确认。",
                                            "Confirm unlocks once that side is facing the camera."))
                            .font(.caption2).foregroundStyle(Ink.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            } else {
                // Live status from the engine's locate tracker (what the camera sees right now).
                Text(engine.cue).font(.subheadline).foregroundStyle(Ink.text)
                    .lineLimit(3).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(Ink.warn)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }

            HStack(spacing: 10) {
                Button(AppLocale.pick("就是这里", "This is my spot")) {
                    if engine.confirmLocate(point: point) {
                        LocatedStore.shared.markLocated(point.id)
                        onConfirmed()
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(engine.locateState != .ready)
                .opacity(engine.locateState == .ready ? 1 : 0.5)

                Button(AppLocale.pick("先跳过", "Skip")) {
                    engine.endLocate()
                    onSkipped()
                }
                .font(.subheadline).tint(Ink.gold)
                .accessibilityHint(AppLocale.pick("直接开始按压引导", "Start coaching without saving a spot"))

                Spacer(minLength: 0)
                // Hands-free confirm: both hands are pressing, so the confirm can be SPOKEN.
                // Opt-in per session; on-device recognition only (hidden when unsupported).
                if voiceControl.available {
                    // NAMED, not a bare icon. This was an unlabeled mic glyph in a small circle,
                    // last in the row behind a Spacer — the weakest element on the card — so new
                    // users never discovered that the confirm can be spoken at all (user-reported).
                    // A capsule with a visible word and a >=44 pt target says what it does.
                    Button { voiceControl.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: voiceControl.listening ? "mic.fill" : "mic")
                            // Says what it DOES. Was 免提 / "Hands-free" — 免提 is speakerphone
                            // jargon and told the user nothing ("what does 免提 mean???"), while
                            // the accessibility label right below already said 语音确认. The
                            // visible label now matches that intent in both languages.
                            Text(voiceControl.listening ? AppLocale.pick("在听", "Listening")
                                                        : AppLocale.pick("语音确认", "Voice confirm"))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(voiceControl.listening ? Ink.gold : Ink.textDim)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 44)
                        .background(Capsule().stroke(voiceControl.listening ? Ink.gold : Ink.line,
                                                     lineWidth: 1))
                    }
                    .contentShape(Capsule())
                    .accessibilityLabel(voiceControl.listening
                        ? AppLocale.pick("停止语音确认", "Stop voice confirm")
                        : AppLocale.pick("开启语音确认", "Enable voice confirm"))
                    // Generic (no literal phrase): VoiceOver reads this on focus, possibly while
                    // the mic is live — a matchable phrase here could self-trigger.
                    .accessibilityHint(AppLocale.pick("开启后用一句话即可确认，无需腾出手",
                                                      "When on, a short spoken phrase confirms without freeing a hand"))
                }
            }
            if voiceControl.denied {
                Text(AppLocale.pick("语音确认需要麦克风与语音识别权限（设置中开启）。",
                                    "Voice confirm needs mic + speech permission (enable in Settings)."))
                    .font(.caption2).foregroundStyle(Ink.warn)
            } else if voiceControl.unavailable {
                Text(AppLocale.pick("语音识别暂时不可用 — 请用按钮确认。",
                                    "Voice recognition is unavailable right now — use the button to confirm."))
                    .font(.caption2).foregroundStyle(Ink.warn)
            }
            // Further from the standard estimate than a typical fine-tune. This is a NOTE, never a
            // block: the point of the locate step is to record where the user's point actually is,
            // and pressing outside the ring used to leave them with "a little far" and a dead
            // button (device-reported). Say what we noticed, then let them decide.
            if engine.locateState == .ready, engine.locateFarFromStandard {
                Text(AppLocale.pick("这个位置离标准位置比较远 — 如果按着就是对的，照样可以确认。",
                                    "That's further from the standard location than usual — if it's the spot that feels right, confirm it anyway."))
                    .font(.caption2).foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The offer is time-boxed (the engine's confirm latch) — say so while it's live, so a
            // silent lapse mid-reach isn't a mystery (the lapsed cue then explains re-arming).
            if engine.locateState == .ready {
                Text(voiceControl.listening
                     ? AppLocale.pick("几秒内点击，或直接说「就是这里」。",
                                      "Tap within a few seconds — or just say \"this is my spot\".")
                     // OFF state now NAMES the hands-free option, so it is discoverable without
                     // having to switch it on first. Deliberately GENERIC — no literal confirm
                     // phrase here: VoiceOver may read this aloud while the mic is live, and a
                     // matchable phrase coming out of the speaker would self-confirm.
                     : AppLocale.pick("几秒内点击即可 — 或开启「语音确认」，不用腾出手也能确认。",
                                      "Tap within a few seconds — or turn on Voice confirm to confirm without freeing a hand."))
                    .font(.caption2).foregroundStyle(Ink.textDim)
            } else if calibration.hasCalibration(point.id) {
                Text(AppLocale.pick("确认后会替换你保存的位置（小圆点）。",
                                    "Confirming replaces your saved spot (the small dot)."))
                    .font(.caption2).foregroundStyle(Ink.textDim)
            }
        }
        .padding(14).panel().padding()
        .accessibilityElement(children: .contain)
    }
}
