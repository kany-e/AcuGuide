import SwiftUI

// THE LIST OF THINGS YOU CAN SAY.
//
// Device report: "what's the voice prompt to freeze the camera screen? The user has no idea what
// the voice prompts are or what available actions there are." That was exactly right, and the
// freeze command was the worst case: the ONE string in the app that named it — `Or just say
// "continue"` — is rendered INSIDE the frozen screen, so you could only read it after guessing the
// phrase that got you there.
//
// Nothing here is spoken, so nothing here touches the pre-rendered clip set (VoiceScript.allLines
// covers CoachVoice's phrase tables and Acupoint.spokenInfo only) — on-screen copy is free to add.
//
// The phrases come from LocateVoiceCommand's own tables rather than being retyped, so this sheet
// cannot drift from what the recognizer actually accepts.
struct VoiceCommandsView: View {
    /// Held while the sheet is open so the recognizer ignores audio. The literal phrases are on
    /// screen, and VoiceOver may read them aloud into an open mic — the app must not be able to
    /// confirm a spot because it read its own help text out. LocateVoiceControl already has this
    /// gate for its own TTS (setAppSpeaking); this reuses it rather than inventing a second one.
    @ObservedObject var voiceControl: LocateVoiceControl
    var onClose: () -> Void

    private struct Row: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let phrases: [String]
        let icon: String
    }

    // First phrase in each table is the canonical one; the rest are accepted alternatives.
    private var rows: [Row] {
        let zh = AppLocale.isChinese
        return [
            Row(title: AppLocale.pick("定格画面，看完整说明", "Freeze the picture and read the guide"),
                detail: AppLocale.pick("把当前画面定住，旁边显示完整的找穴说明 — 两只手都占着也能看。",
                                       "Holds the current frame still and shows the full finding guide beside it — readable with both hands busy."),
                phrases: zh ? LocateVoiceCommand.studyZh : LocateVoiceCommand.studyEn,
                icon: "text.magnifyingglass"),
            Row(title: AppLocale.pick("继续", "Carry on"),
                detail: AppLocale.pick("解除定格，回到实时画面。", "Unfreezes and goes back to the live camera."),
                phrases: zh ? LocateVoiceCommand.resumeZh : LocateVoiceCommand.resumeEn,
                icon: "play.circle"),
            Row(title: AppLocale.pick("确认这个位置", "Save this spot"),
                detail: AppLocale.pick("和点「就是这里」一样 — 只在找位步骤、位置稳定后才有效。",
                                       "Same as tapping \"This is my spot\" — only during the locate step, once the press has settled."),
                phrases: zh ? LocateVoiceCommand.confirmZh : LocateVoiceCommand.confirmEn,
                icon: "checkmark.circle"),
            Row(title: AppLocale.pick("跳过找位", "Skip finding the spot"),
                detail: AppLocale.pick("直接开始按压引导。", "Starts the coaching without saving a spot."),
                phrases: zh ? ["跳过"] : ["skip"],
                icon: "forward"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(voiceControl.listening
                         ? AppLocale.pick("正在听。可以直接说：", "Listening. You can say:")
                         : AppLocale.pick("开启语音后可以说：", "With voice turned on, you can say:"))
                        .font(.subheadline).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.icon)
                                .font(.title3).foregroundStyle(Ink.gold).frame(width: 26)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.title).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                phraseChips(row.phrases)
                                Text(row.detail).font(.footnote).foregroundStyle(Ink.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        // ONE VoiceOver element per row, and it deliberately does NOT read the
                        // literal phrases — a matchable phrase coming out of the speaker while the
                        // mic is live is the self-trigger LocateStep already guards against. The
                        // recognizer is suspended while this sheet is up as well; both, not either.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.title). \(row.detail)")
                    }

                    Text(AppLocale.pick(
                        "说完整句会更容易听清；「不要…」「别…」开头的句子会被忽略。语音识别只在你开启麦克风时运行。",
                        "Say the whole phrase — it recognises more reliably. Anything prefixed with \"don't\" is ignored. Recognition only runs while you have the microphone on."))
                        .font(.caption).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle(AppLocale.pick("可以说的话", "What you can say"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("完成", "Done"), action: onClose)
                }
            }
        }
        // Suspend recognition for as long as the phrases are on screen (and a beat after, for the
        // recognizer's own lag) — setAppSpeaking is exactly this gate, already tested.
        .onAppear { voiceControl.setAppSpeaking(true) }
        .onDisappear { voiceControl.setAppSpeaking(false) }
    }

    // ONE phrase as a chip, the rest as a quiet "also" line. Chipping all six accepted phrasings
    // stacked the sheet three screens deep and gave them equal billing, which is the opposite of
    // useful — someone scanning this needs one phrase to remember, not a menu to choose from.
    private func phraseChips(_ phrases: [String]) -> some View {
        let quote: (String) -> String = { AppLocale.isChinese ? "「\($0)」" : "“\($0)”" }
        return VStack(alignment: .leading, spacing: 4) {
            if let first = phrases.first { chip(quote(first)) }
            if phrases.count > 1 {
                Text(AppLocale.pick("也可以说：", "also: ")
                     + phrases.dropFirst().map(quote).joined(separator: AppLocale.isChinese ? "、" : ", "))
                    .font(.caption2).foregroundStyle(Ink.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityHidden(true)   // read via the row's combined label instead (see above)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Ink.gold.opacity(0.12)))
            .overlay(Capsule().stroke(Ink.gold.opacity(0.35), lineWidth: 1))
    }
}
