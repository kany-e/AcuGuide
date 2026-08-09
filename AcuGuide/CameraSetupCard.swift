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
    // Hands-free voice control, DISCLOSED here — the last screen before the camera starts and the
    // mic auto-starts with it (AppSettings.handsFreeVoice, default ON, device-requested). This card
    // is the honest place for it: it is already explaining that BOTH HANDS are busy, which is
    // exactly why voice control exists and why it comes on by itself — so the mic permission prompt
    // that follows arrives with its reason attached, and anyone who would rather not be listened to
    // can flip the toggle BEFORE any prompt appears. (This used to be a "turn it on?" offer, back
    // when the mic was opt-in; the copy outlived that behavior, and a stale disclosure is worse
    // than none. VoiceDisclosureTests now pins this copy to the shipped default.)
    var voiceControl: LocateVoiceControl? = nil
    @ObservedObject private var settings = AppSettings.shared

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

    // The voice-control disclosure, hoisted so the body and allCopyForTesting read the SAME strings
    // (the old inline version was invisible to the copy tests, which is how "skipping is completely
    // fine … switch it on later" shipped for weeks after the mic became auto-on).
    private var voiceTitle: String {
        AppLocale.pick("语音控制（默认开启）", "Voice control (on by default)")
    }
    private var voiceText: String {
        AppLocale.pick(
            "两只手都在用的时候，可以直接说话：确认位置、或把画面定住看完整说明，都不用腾出手。所以麦克风会随相机一起开启 — 下一屏 iOS 会询问一次麦克风权限。你的语言支持设备端识别时，声音不会离开手机；不支持时，聆听期间麦克风听到的内容会发送给 Apple 的语音服务。完整指令表在相机画面顶部的问号里。不想用？在这里关掉即可 — 点按始终可用，之后也能随时在设置里更改。",
            "With both hands busy you can just speak: confirm a spot, or freeze the picture to read the full guide — neither needs a free hand. So the microphone comes on with the camera — iOS will ask for mic access once on the next screen. With on-device recognition for your language, audio never leaves the phone; without it, what the mic hears while listening is sent to Apple's speech service. The full list of phrases lives behind the question mark at the top of the camera screen. Rather not? Turn it off here — tapping works everywhere, and Settings can change this anytime.")
    }
    private var voiceToggleLabel: String { AppLocale.pick("语音控制", "Voice control") }

    // Every user-facing string on this card, for the copy tests (banned words, the two claims the
    // card exists to make, and the voice-control disclosure). Reads the SAME strings the body
    // renders, so a copy edit that drops "both hands" — or resurrects the stale opt-in story —
    // fails the test rather than silently shipping.
    var allCopyForTesting: [String] {
        tips.flatMap { [$0.title, $0.text] } + [voiceTitle, voiceText, voiceToggleLabel]
    }

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
                    // The voice disclosure sits AFTER the tips, so "both hands are busy" has already
                    // been read by the time it explains why the mic comes on by itself. Only shown
                    // when speech recognition actually exists for this locale — never a dead toggle.
                    // The toggle binds the PERSISTED preference directly: flipping it off here is
                    // the same durable opt-out as Settings, and it lands before iOS ever asks for
                    // the permission.
                    if let vc = voiceControl, vc.available {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "mic")
                                .font(.title3).foregroundStyle(Ink.gold).frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(voiceTitle)
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                Text(voiceText)
                                    .font(.footnote).foregroundStyle(Ink.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                                Toggle(voiceToggleLabel, isOn: $settings.handsFreeVoice)
                                    .font(.caption.bold()).tint(Ink.gold)
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
