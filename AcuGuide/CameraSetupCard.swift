import SwiftUI

// One-time physical-setup card, shown between the safety gate and the first camera session.
//
// The camera coach needs BOTH hands — one receives the press, the other presses — which leaves
// nobody holding the phone. Nothing in the app ever said so. A first-timer would tap into the
// coach still holding the phone, find they had no hand to press with, and sit in `.noHand`
// hearing "Bring your hand into view" with no idea that the fix is to put the phone down. That is
// the single most likely first-run dead end, and it costs one screen to remove.
//
// Shown ONCE per install (AppSettings.seenCameraSetup) — it is setup knowledge, not a warning, so
// it must not become a toll booth on every session the way an un-dismissable gate would. It is
// deliberately NOT folded into the safety gate: that gate is a forced medical-safety
// acknowledgement, and padding it with ergonomics teaches people to skim the part that matters.
// Settings can bring this card back (nothing one-time should be unrecoverable).
struct CameraSetupCard: View {
    let onContinue: () -> Void
    // Hands-free voice confirm, offered HERE rather than deep in the locate step. Device report:
    // "it should prompt the user to allow microphone at entrance to the camera guide." Requesting
    // it unconditionally on entry is the one thing not done — a refusal is permanent (iOS never
    // asks twice) and would kill the feature for someone who simply had not read what it was for.
    // This card is the honest middle: it is already explaining that BOTH HANDS are busy, which is
    // exactly why a spoken confirm exists, so the offer arrives with its reason attached and the
    // user chooses. Declining costs nothing — the button is still there in the locate step.
    var voiceControl: LocateVoiceControl? = nil
    @State private var voiceRequested = false

    private struct Tip: Identifiable {
        let id = UUID()
        let icon: String, title: String, text: String
    }

    private var tips: [Tip] {
        [
            Tip(icon: "iphone.gen3.landscape",
                title: AppLocale.pick("把手机放稳", "Prop your phone up"),
                text: AppLocale.pick(
                    "按压时两只手都会用上 — 一只手接受按压，另一只手按 — 所以没有手拿手机。把它靠在杯子、书本或支架上就行。",
                    "You'll be using both hands — one receives the press, the other presses — so neither is free to hold the phone. Lean it against a cup, a book, or a stand.")),
            Tip(icon: "hand.raised.fingers.spread",
                title: AppLocale.pick("让双手进入画面", "Keep both hands in frame"),
                text: AppLocale.pick(
                    "坐着，手放在胸前的桌面或膝上，距离手机大约一臂长。光线充足时识别最准。",
                    "Sit with your hands in front of you — on a table or in your lap, about an arm's length from the phone. Good light helps it see them.")),
            Tip(icon: "speaker.wave.2",
                title: AppLocale.pick("跟着语音就行", "Listen, don't stare"),
                text: AppLocale.pick(
                    "语音会一路提示你 — 找到位置、按压、每一轮的计时，所以你不用一直盯着屏幕。",
                    "The voice walks you through finding the spot, pressing, and timing each round — so you don't have to watch the screen the whole time.")),
            Tip(icon: "arrow.triangle.2.circlepath.camera",
                title: AppLocale.pick("也可以帮别人按", "Coaching someone else?"),
                text: AppLocale.pick(
                    "用画面里的切换按钮改用后置摄像头，对准对方的手即可。",
                    "Use the switch-camera button on the camera screen to flip to the back camera and point it at their hand.")),
        ]
    }

    // Every user-facing string on this card, for the copy tests (banned words, and the two claims
    // the card exists to make). Reads the SAME `tips` the body renders, so a copy edit that drops
    // "both hands" fails the test rather than silently shipping.
    var allCopyForTesting: [String] { tips.flatMap { [$0.title, $0.text] } }

    var body: some View {
        // Same structure as the safety gate: content SCROLLS, the single exit stays PINNED, so
        // large Dynamic Type can never push the button out of reach.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AppLocale.pick("摆好姿势", "Getting set up"))
                        .font(.title2).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("只说一次 — 之后直接开始。",
                                        "Just this once — after this you'll go straight in."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.icon)
                                .font(.title3).foregroundStyle(Ink.gold).frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tip.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                Text(tip.text).font(.footnote).foregroundStyle(Ink.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14).panel()
                        // One VoiceOver stop per tip, read as a sentence rather than icon + two labels.
                        .accessibilityElement(children: .combine)
                    }
                    // The voice offer sits AFTER the tips, so "both hands are busy" has already been
                    // read by the time it explains the way around that. Only shown when speech
                    // recognition actually exists for this locale — never a dead button.
                    if let vc = voiceControl, vc.available {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mic")
                                .font(.title3).foregroundStyle(Ink.gold).frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppLocale.pick("用说的确认（可选）", "Confirm by voice (optional)"))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                Text(AppLocale.pick(
                                    "两只手都在用的时候，说一句「就是这里」就能确认，不用腾出手来点屏幕。现在开启会问你一次麦克风权限 — 不开也完全没问题，之后随时能在画面里打开。",
                                    "With both hands busy, saying \"this is my spot\" confirms without freeing a hand. Turning it on now asks for microphone access once — skipping is completely fine, and you can switch it on later from the camera screen."))
                                    .font(.footnote).foregroundStyle(Ink.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                                if voiceRequested {
                                    Text(vc.denied
                                         ? AppLocale.pick("没有授权 — 用点按确认就好。",
                                                          "Not allowed — tapping to confirm works fine.")
                                         : AppLocale.pick("已开启。", "Turned on."))
                                        .font(.caption2)
                                        .foregroundStyle(vc.denied ? Ink.warn : Ink.jade)
                                } else {
                                    Button(AppLocale.pick("开启语音确认", "Turn on Voice confirm")) {
                                        voiceRequested = true
                                        vc.toggle()     // requests permission in context, once
                                    }
                                    .font(.caption.bold()).tint(Ink.gold)
                                    .frame(minHeight: 44)
                                }
                            }
                        }
                        .padding(14).panel()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            Button(AppLocale.pick("知道了", "Got it"), action: onContinue)
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 20)
        }
    }
}
