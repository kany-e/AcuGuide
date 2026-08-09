import SwiftUI
import UserNotifications

// 艾灸计时 — the skin-check clock.
//
// WHAT THIS IS, AND WHAT IT REFUSES TO BE. MoxaTab's original stance was "locate and describe,
// never dose" — no countdown at all, because a countdown reads as a prescription. The practitioner
// round (Aug 2026) moved the line, deliberately: the tab's own safety copy says "look at the skin
// on a timer, not by feel", and an app that says that while refusing to BE the timer was preaching
// a discipline it declined to provide. So the clock exists now — but it only ever runs in the
// SAFETY direction:
//
//   • it never says how long moxa "should" take, or that longer is better — the duration picker is
//     capped, and the cap closes the sitting whatever the user picked;
//   • it interrupts to make the user LIFT THE BOX AND LOOK, which is the one behavior that
//     prevents the low-temperature burn (the injury mode is time + absent sensation);
//   • every path out of a check is either "continue under the same cap" or "stop now" — no path
//     extends the sitting.
//
// THE NUMBERS, and where they come from (full citations:
// claude-deliverables/references/moxa_timing_research.md). The practitioner's guidance was 10–15
// minutes with a look at the skin about every 5. The literature check found: RCT box protocols
// cluster at 15–30 min (so a 15-min cap is the CONSERVATIVE END of practice, kept deliberately);
// NO published check interval exists anywhere — 5 minutes is practice wisdom — but it is
// physics-consistent: skin under a real box measures 44–49 °C (Xu 2012, PMID 22997790), where the
// Moritz–Henriques curve puts epidermal injury at ~45 min at 47 °C down to ~11 min at 49 °C. The
// FIRST check comes earlier (2½ min) because the measured worst case (>49 °C at 3 cm) makes the
// first minutes the least certain, and one early look costs a single tap. These are design choices
// grounded in burn physics and burn epidemiology, NOT citations to a standard — no standard
// states either number, and the Sources note says so plainly.
//
// THE OLDER-ADULT RULE. Screening question five (65+ / thin fragile skin) does not block heat —
// it removes the "feels fine, skip this look" shortcut. Epidermis thins ~6% per decade, warm-
// detection thresholds converge with age until heat that injures is heat that was never felt, and
// the burn-surgery case series' mean age is 64.5. "It feels fine" is exactly the signal that
// cannot be trusted, so for that user every check requires having looked. Enforced structurally:
// `MoxaClock.checkChoices` simply does not include `.skip` when checks are required — there is no
// flag a view could forget to read.
enum MoxaClockPlan {
    /// The most one sitting may run, whatever was picked. The practitioner's band was 10–15; the
    /// trial corpus would defend up to 30; the cap stays at the practitioner's top — conservative
    /// by construction, and the same for everyone (the higher-risk regime tightens CHECKS, and a
    /// shared low cap beats a split one for being impossible to pick wrongly).
    static let capMinutes = 15
    static let defaultMinutes = 10
    static let choicesMinutes = [5, 10, 15]
    /// First look 2½ minutes in — the measured under-box worst case (>49 °C) injures on a
    /// ~10-minute timescale, so the first look must come well inside it.
    static let firstCheckSeconds: Double = 150
    /// Repeating look-at-the-skin cadence after the first: the practitioner's 5 minutes, inside
    /// every published time-to-injury figure for the 44–48 °C range a functioning box sits in.
    static let checkEveryMinutes = 5

    static var capSeconds: Double { Double(capMinutes) * 60 }
    static var checkEverySeconds: Double { Double(checkEveryMinutes) * 60 }
}

/// What the user may do at a check. Derived, never stored: the available set IS the policy.
enum MoxaCheckChoice: Equatable {
    case lookedClear      // lifted the box, skin no more than lightly pink → continue
    case stop             // any doubt at all → end the sitting
    case notSure          // open the side-by-side photo compare, then decide
    case skip             // "feels fine" without looking — ABSENT when checks are required
}

// The clock itself. Deterministic core (tick-driven, like TimerSession) so tests can drive a whole
// sitting without a Timer; the wall-clock Timer and the notification scheduling sit at the edges.
final class MoxaClock: ObservableObject {
    enum Phase: Equatable {
        case ready
        case running
        case checking            // a look-at-the-skin stop: clock frozen until answered
        case endedByCap          // the sitting reached the cap
        case endedByUser         // ended from the End control
        case stoppedForSkin      // ended because the skin said stop → burn-guidance card
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var checksAnswered = 0

    /// True when screening said 65+/fragile skin: every check must be answered by looking.
    let checksRequired: Bool
    private(set) var plannedSeconds: Double
    private var nextCheckAt: Double
    private var ticker: Timer?

    /// The baseline photo, held IN MEMORY ONLY for the life of the sitting — never written to
    /// disk, never added to the photo library, discarded the moment the sitting ends. Optional;
    /// the compare card degrades to the single fresh photo without it.
    @Published var baselinePhoto: UIImage?
    @Published var checkPhoto: UIImage?

    init(minutes: Int = MoxaClockPlan.defaultMinutes, checksRequired: Bool) {
        let clamped = min(minutes, MoxaClockPlan.capMinutes)
        self.plannedSeconds = Double(clamped) * 60
        self.checksRequired = checksRequired
        self.nextCheckAt = MoxaClockPlan.firstCheckSeconds
    }

    /// The choices the check card renders, in display order. Policy lives here and only here.
    var checkChoices: [MoxaCheckChoice] {
        checksRequired ? [.lookedClear, .stop, .notSure]
                       : [.lookedClear, .stop, .notSure, .skip]
    }

    var remaining: Double { max(0, plannedSeconds - elapsed) }
    var secondsToNextCheck: Double { max(0, min(nextCheckAt, plannedSeconds) - elapsed) }
    /// What the background notification should ring for: the next boundary (check or end).
    var nextEventIn: Double? {
        guard phase == .running else { return nil }
        let dt = min(nextCheckAt, plannedSeconds) - elapsed
        return dt > 0 ? dt : nil
    }

    /// Setup-only knob: the picker writes the planned minutes right before `start()`, clamped to
    /// the cap exactly like init.
    func plan(minutes: Int) {
        guard phase == .ready else { return }
        plannedSeconds = Double(min(minutes, MoxaClockPlan.capMinutes)) * 60
    }

    func start() {
        guard phase == .ready else { return }
        phase = .running
        run()
    }

    /// Answer the current check. `.notSure` keeps the card up (the view opens the photo compare);
    /// the others resolve it.
    func answer(_ choice: MoxaCheckChoice) {
        guard phase == .checking, checkChoices.contains(choice) else { return }
        switch choice {
        case .lookedClear, .skip:
            checksAnswered += 1
            checkPhoto = nil
            nextCheckAt += MoxaClockPlan.checkEverySeconds
            if elapsed >= plannedSeconds { finish(.endedByCap) } else { phase = .running; run() }
        case .stop:
            finish(.stoppedForSkin)
        case .notSure:
            break
        }
    }

    func endNow() {
        guard phase == .running || phase == .checking else { return }
        finish(.endedByUser)
    }

    func scenePaused() { ticker?.invalidate(); ticker = nil }
    func sceneResumed(after wallSeconds: Double) {
        guard phase == .running else { return }
        // Credit real elapsed time across the background gap, but never sail past a due check or
        // the cap: the clock lands ON the boundary and the same rules fire as if it had ticked there.
        tick(wallSeconds)
        if phase == .running { run() }
    }

    private func finish(_ p: Phase) {
        phase = p
        ticker?.invalidate(); ticker = nil
        baselinePhoto = nil
        checkPhoto = nil
    }

    private func run() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick(0.5) }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// Advance the clock. Public so tests drive a sitting deterministically. A single call may
    /// cover a long gap (scene resume); the clock stops AT the first boundary it crosses — a due
    /// check freezes time until it is answered, so heat-time is never silently credited past a look.
    func tick(_ dt: Double) {
        guard phase == .running else { return }
        let boundary = min(nextCheckAt, plannedSeconds)
        elapsed = min(elapsed + dt, boundary)
        guard elapsed >= boundary else { return }
        ticker?.invalidate(); ticker = nil
        if elapsed >= plannedSeconds, plannedSeconds <= nextCheckAt {
            // The sitting ends here. If a check falls on the same moment, ending wins — the box is
            // coming off anyway, which is what the check exists to make possible.
            finish(.endedByCap)
        } else {
            phase = .checking
            MoxaHaptic.checkDue()
        }
    }
}

/// One transient haptic cue when a check comes due — the box wearer may not be watching the
/// screen. Kept apart from the coach's Haptics engine: this is a single notification-style event,
/// not a session-long pattern player.
enum MoxaHaptic {
    static func checkDue() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// Local notification for the one path the in-app cue cannot reach: the user backgrounds the app
// mid-sitting. Scheduled on background with the seconds to the next event, cancelled on return —
// the same on-device, no-server posture as PracticeReminder.
enum MoxaCheckNotification {
    static let requestId = "acuguide.moxa.check"

    static func schedule(in seconds: Double) {
        guard seconds > 1 else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
        let content = UNMutableNotificationContent()
        content.title = "AcuGuide"
        content.body = MoxaClockCopy.notificationBody
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: requestId, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestId])
    }

    /// Ask once, on first clock start. Not asking would silently lose the one reminder that
    /// matters; asking earlier (at the gate) would be permission-begging before the user has shown
    /// they want the clock at all.
    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }
}

// ————————————————————————————————————————————————————————————————————————————————————————————————
// EVERY user-facing string of the clock, defined ONCE and referenced by the views below — the
// claims scans walk `allCopy`, and a string a view renders that the scan cannot reach is an
// unscanned surface (the trap MoxaGateView.allCopy exists for). Adding a string to a view without
// routing it through here is the drift this layout makes impossible.
enum MoxaClockCopy {
    static var title: String { AppLocale.pick("看皮肤的钟", "The skin-check clock") }
    static var tabCaption: String { AppLocale.pick(
        "开始后 2 分半先看一次皮肤，之后每 \(MoxaClockPlan.checkEveryMinutes) 分钟一次；最长 \(MoxaClockPlan.capMinutes) 分钟到点就停",
        "First look at the skin 2½ minutes in, then every \(MoxaClockPlan.checkEveryMinutes); a hard stop at \(MoxaClockPlan.capMinutes)") }
    static var setupIntro: String { AppLocale.pick(
        "它不衡量艾灸「该」做多久——它只做两件事：按时停下来提醒你掀开盒子看皮肤（开始后 2 分半先看一次，之后每 \(MoxaClockPlan.checkEveryMinutes) 分钟一次），到时间提醒你结束。皮肤只要超过微微发红，就该停。",
        "This clock never measures how long moxa \"should\" take. It does two things only: it stops so the skin gets looked at — a first look 2½ minutes in, then every \(MoxaClockPlan.checkEveryMinutes) minutes — and it closes the sitting when the window ends. Anything past lightly pink means stop.") }
    static var requiredNote: String { AppLocale.pick(
        "本次为 65 岁以上或皮肤较脆弱的人施灸：每次查看都需要掀开盒子看过再继续，不能跳过——变薄的皮肤在同样温度下更快受伤，而且往往感觉不到。",
        "This sitting is for someone 65+ or with fragile skin: every check needs an actual look before going on — no skipping. Thinner skin is injured sooner at the same temperature, and often without feeling it.") }
    static var drowsyNote: String { AppLocale.pick(
        "别在困倦、可能睡着的场合用——睡着的人一次查看也做不了。躺着时盒子只放不绑。",
        "Not when drowsy, and never where you might fall asleep — a sleeper cannot do a single check. Lying down, the box rests on the body, never fastened.") }
    static var durationLabel: String { AppLocale.pick("这一次坐多久", "This sitting") }
    static var capNote: String { AppLocale.pick(
        "最长 \(MoxaClockPlan.capMinutes) 分钟——到点就结束，这个上限不能延长。",
        "\(MoxaClockPlan.capMinutes) minutes is the most a sitting runs — the window closes there and cannot be extended.") }
    static var baselineOffer: String { AppLocale.pick("先拍一张现在的皮肤（可选）", "Photo of the skin now (optional)") }
    static var baselineTaken: String { AppLocale.pick("已拍好对照照片", "Before-photo taken") }
    static var photoPrivacy: String { AppLocale.pick(
        "只留在这个界面里对照用，不存入相册、不上传，结束就丢弃。",
        "Kept only on this screen for comparing — never saved to your library, never uploaded, discarded when the sitting ends.") }
    static var notifDenied: String { AppLocale.pick(
        "通知未开启：请让应用保持打开，提醒才不会错过。",
        "Notifications are off — keep the app open so the check reminders can reach you.") }
    static var startButton: String { AppLocale.pick("开始计时", "Start the clock") }
    static var hotAnyTime: String { AppLocale.pick(
        "觉得烫就直接拿开，不用等提醒。",
        "If it ever feels hot, take the box off — don't wait for the chime.") }
    static var endEarly: String { AppLocale.pick("提前结束", "End the sitting") }
    static var notificationBody: String { AppLocale.pick(
        "该看皮肤了——掀开盒子看一眼再继续。",
        "Time to look at the skin — lift the box for a look before going on.") }

    static var checkTitle: String { AppLocale.pick("掀开盒子，看皮肤", "Lift the box. Look at the skin.") }
    static var checkBody: String { AppLocale.pick(
        "把盒子整个拿离皮肤，看受热的地方：微微发红是正常的；超过微微发红、颜色变深或发白、起疱，或有任何刺痛，就到此为止。低温烫伤开始时不太痛，看比感觉可靠。",
        "Take the box fully off the skin and look at the heated area. Lightly pink is expected; anything past lightly pink — a patch turning darker or pale, a blister, any stinging — is the end of the sitting. A low-temperature burn barely hurts at first, so looking beats feeling.") }
    static var choiceClear: String { AppLocale.pick("看过了——不超过微微发红，继续", "I looked — lightly pink or less. Continue") }
    static var choiceStop: String { AppLocale.pick("颜色不对／有刺痛——现在停", "The colour is off, or it stings — stop now") }
    static var choiceCompare: String { AppLocale.pick("拿不准——拍照对比一下", "Not sure — compare with a photo") }
    static var choiceSkip: String { AppLocale.pick("没有任何不适，这次先不看", "Feels completely fine — skip this look") }

    static var endByCapTitle: String { AppLocale.pick("这一次到时间了", "That's the window for this sitting") }
    static var endTitle: String { AppLocale.pick("这一次结束了", "Sitting ended") }
    static var endBody: String { AppLocale.pick(
        "把盒子拿离身体，最后看一眼皮肤。艾条内部还在阴燃：装进密封灭火管，或把燃烧端深埋进干沙——泡过水也可能复燃。",
        "Take the box off and give the skin one last look. The moxa is still smouldering inside: seal it in an airtight snuffer tube or bury the lit end deep in dry sand — it can reignite even after water.") }
    static var endRecheck: String { AppLocale.pick(
        "过一两个小时再看一眼这块皮肤——低温烫伤有时要过一阵才显出来。",
        "Look at the patch again in an hour or two — a low-temperature burn can take a while to show itself.") }
    static var endNoMore: String { AppLocale.pick(
        "想再来一次？换一天再说——上限保护的就是同一块皮肤。",
        "Another sitting? Not on the same skin today — the cap exists for exactly that patch.") }
    static var doneButton: String { AppLocale.pick("完成", "Done") }

    static var stopTitle: String { AppLocale.pick("停下是对的", "Stopping was right") }
    static var compareTitle: String { AppLocale.pick("对比着问自己", "Ask, comparing") }
    static var compareBefore: String { AppLocale.pick("开始前", "Before") }
    static var compareNow: String { AppLocale.pick("现在", "Now") }
    static var compareNoPhoto: String { AppLocale.pick(
        "没有拍到照片——直接看皮肤本身也一样。",
        "No photo — looking at the skin itself works just as well.") }
    static var compareFooter: String { AppLocale.pick(
        "拿不准就当作「是」。本应用不能识别烫伤——判断永远在你。照片只在这里对照用，不保存、不上传。",
        "If you can't tell, count it as a yes. This app cannot detect burns — the judgement is always yours. Photos are for this screen only — never saved, never uploaded.") }
    static var compareStop: String { AppLocale.pick("有任何一条——停", "Any yes — stop") }
    static var compareContinue: String { AppLocale.pick("都没有——继续", "None of these — continue") }

    /// The look-harder checklist. The colour question is deliberately NOT redness-only: on deeper
    /// skin tones early heat injury reads darker, purplish or grey, and a red-only prompt would
    /// systematically miss it (the equity failure the research flagged in every consumer skin-CV
    /// system). Pinned by test.
    static var checklist: [String] {
        [AppLocale.pick("和周围皮肤比，颜色变了吗——不只是更红：偏深、偏紫、偏灰、发白都算？",
                        "Against the surrounding skin, has the colour changed — not just redder: darker, purplish, greyish or pale all count?"),
         AppLocale.pick("红或深色的范围比刚才更大吗？", "Is the changed area wider than before?"),
         AppLocale.pick("皮肤表面有隆起、发亮或水疱吗？", "Anything raised, shiny, or a blister?"),
         AppLocale.pick("拿开盒子几分钟后还在加深吗?", "Still deepening minutes after the box came off?")]
    }

    /// The stop path's first-aid lines. Scanned like every other moxa surface.
    static var stopLines: [String] {
        [AppLocale.pick("马上把热源从身上拿开，包括余温高的盒体。",
                        "Get the heat source off the body now, including the still-hot box itself."),
         AppLocale.pick("用流动的凉水冲这块皮肤 10–20 分钟。不要冰敷，不要涂牙膏、油或酱油。",
                        "Run cool water over the area for 10–20 minutes. No ice, and no toothpaste, oils or soy sauce on it."),
         AppLocale.pick("起了水疱不要挑破。", "If a blister has formed, leave it unbroken."),
         AppLocale.pick("出现发白或蜡样的皮肤、比硬币大的水疱，或这块皮肤本来感觉就减退（糖尿病、神经受损、高龄），请当天就医。",
                        "Pale or waxy-looking skin, a blister bigger than a coin, or reduced feeling in that area to begin with (diabetes, nerve damage, older age) — see a professional today."),
         AppLocale.pick("今天不要再对这块皮肤加热。", "No more heat on this patch of skin today.")]
    }

    /// Everything above, for the claims scans.
    static var allCopy: [String] {
        [title, tabCaption, setupIntro, requiredNote, drowsyNote, durationLabel, capNote, baselineOffer,
         baselineTaken, photoPrivacy, notifDenied, startButton, hotAnyTime, endEarly,
         notificationBody, checkTitle, checkBody, choiceClear, choiceStop, choiceCompare,
         choiceSkip, endByCapTitle, endTitle, endBody, endRecheck, endNoMore, doneButton,
         stopTitle, compareTitle, compareBefore, compareNow, compareNoPhoto, compareFooter,
         compareStop, compareContinue]
        + checklist + stopLines
    }
}

// ————————————————————————————————————————————————————————————————————————————————————————————————
// The clock UI: setup → running → check card → end cards. One sheet, one NavigationStack.

struct MoxaClockView: View {
    let checksRequired: Bool
    var onClose: () -> Void

    @StateObject private var clock: MoxaClock
    @State private var minutes = MoxaClockPlan.defaultMinutes
    @State private var notifDenied = false
    @State private var showCompare = false
    @State private var takingBaseline = false
    @State private var takingCheckPhoto = false
    @State private var leftAt: Date?
    @Environment(\.scenePhase) private var scenePhase

    init(checksRequired: Bool, onClose: @escaping () -> Void) {
        self.checksRequired = checksRequired
        self.onClose = onClose
        _clock = StateObject(wrappedValue: MoxaClock(checksRequired: checksRequired))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch clock.phase {
                case .ready:        setup
                case .running:      running
                case .checking:     MoxaCheckCard(clock: clock, onCompare: { startCheckPhoto() })
                case .endedByCap,
                     .endedByUser:  MoxaEndCard(byCap: clock.phase == .endedByCap, onDone: onClose)
                case .stoppedForSkin: MoxaStopCard(onDone: onClose)
                }
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocale.pick("关闭", "Close")) {
                        clock.endNow(); MoxaCheckNotification.cancel(); onClose()
                    }.tint(Ink.gold)
                }
            }
        }
        .keepScreenAwake(while: clock.phase == .running)
        .interactiveDismissDisabled(clock.phase == .running || clock.phase == .checking)
        .onChange(of: scenePhase) { sp in
            switch sp {
            case .background, .inactive:
                if clock.phase == .running {
                    clock.scenePaused()
                    if let next = clock.nextEventIn { MoxaCheckNotification.schedule(in: next) }
                    leftAt = Date()
                }
            case .active:
                MoxaCheckNotification.cancel()
                if let t = leftAt {
                    clock.sceneResumed(after: Date().timeIntervalSince(t))
                    leftAt = nil
                }
            @unknown default: break
            }
        }
        .onDisappear { MoxaCheckNotification.cancel() }
        .sheet(isPresented: $takingBaseline) {
            MoxaSkinCamera { clock.baselinePhoto = $0 }
        }
        .sheet(isPresented: $takingCheckPhoto, onDismiss: {
            if clock.checkPhoto != nil { showCompare = true }
        }) {
            MoxaSkinCamera { clock.checkPhoto = $0 }
        }
        .sheet(isPresented: $showCompare) {
            MoxaSkinCompare(clock: clock)
        }
    }

    private func startCheckPhoto() {
        if MoxaSkinCamera.available { takingCheckPhoto = true } else { showCompare = true }
    }

    // MARK: setup

    private var setup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(MoxaClockCopy.title).font(.title2).foregroundStyle(Ink.gold)
                    Text(MoxaClockCopy.setupIntro)
                        .font(.subheadline).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if checksRequired {
                        Label { Text(MoxaClockCopy.requiredNote) } icon: { Image(systemName: "exclamationmark.shield") }
                            .font(.footnote).foregroundStyle(Ink.warn)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).panel()
                    }

                    Text(MoxaClockCopy.drowsyNote)
                        .font(.footnote).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(MoxaClockCopy.durationLabel)
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                        HStack(spacing: 10) {
                            ForEach(MoxaClockPlan.choicesMinutes, id: \.self) { m in
                                Button {
                                    minutes = m
                                } label: {
                                    Text(AppLocale.pick("\(m) 分钟", "\(m) min"))
                                        .font(.subheadline.weight(minutes == m ? .semibold : .regular))
                                        .foregroundStyle(minutes == m ? .black : Ink.text)
                                        .padding(.horizontal, 18).frame(height: 44)
                                        .background(Capsule().fill(minutes == m ? Ink.gold : .clear))
                                        .overlay(Capsule().stroke(minutes == m ? Ink.gold : Ink.line, lineWidth: 1))
                                        .contentShape(Capsule())
                                }
                                .accessibilityAddTraits(minutes == m ? [.isSelected] : [])
                            }
                        }
                        Text(MoxaClockCopy.capNote)
                            .font(.caption2).foregroundStyle(Ink.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if MoxaSkinCamera.available {
                        Button {
                            takingBaseline = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: clock.baselinePhoto == nil ? "camera" : "checkmark.circle.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(clock.baselinePhoto == nil ? MoxaClockCopy.baselineOffer
                                                                    : MoxaClockCopy.baselineTaken)
                                        .font(.subheadline.weight(.semibold))
                                    Text(MoxaClockCopy.photoPrivacy)
                                        .font(.caption2).foregroundStyle(Ink.textDim)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                            }
                            .foregroundStyle(Ink.gold)
                            .padding(14).panel()
                        }
                        .buttonStyle(.plain)
                    }

                    if notifDenied {
                        Text(MoxaClockCopy.notifDenied)
                            .font(.footnote).foregroundStyle(Ink.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Button(MoxaClockCopy.startButton) {
                MoxaCheckNotification.requestAuthorization { granted in
                    notifDenied = !granted
                }
                clock.plan(minutes: minutes)
                clock.start()
            }
            .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    // MARK: running

    private var running: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(timeString(clock.remaining))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Ink.text)
                .accessibilityLabel(AppLocale.pick("剩余 \(Int(clock.remaining / 60)) 分钟",
                                                   "\(Int(clock.remaining / 60)) minutes left"))
            Text(AppLocale.pick("下次看皮肤：\(timeString(clock.secondsToNextCheck)) 后",
                                "Next look at the skin in \(timeString(clock.secondsToNextCheck))"))
                .font(.subheadline).foregroundStyle(Ink.textDim)
            Text(MoxaClockCopy.hotAnyTime)
                .font(.footnote).foregroundStyle(Ink.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(MoxaClockCopy.endEarly) { clock.endNow() }
                .buttonStyle(GoldButtonStyle())
                .padding(.bottom, 24)
        }
    }

    private func timeString(_ s: Double) -> String {
        let t = Int(s.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: — the check card

struct MoxaCheckCard: View {
    @ObservedObject var clock: MoxaClock
    var onCompare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label { Text(MoxaClockCopy.checkTitle) } icon: { Image(systemName: "eye") }
                        .font(.title3.weight(.semibold)).foregroundStyle(Ink.gold)
                    Text(MoxaClockCopy.checkBody)
                        .font(.subheadline).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            VStack(spacing: 10) {
                ForEach(Array(clock.checkChoices.enumerated()), id: \.offset) { _, choice in
                    checkButton(choice)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private func checkButton(_ choice: MoxaCheckChoice) -> some View {
        switch choice {
        case .lookedClear:
            Button(MoxaClockCopy.choiceClear) { clock.answer(.lookedClear) }
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
        case .stop:
            Button(MoxaClockCopy.choiceStop) { clock.answer(.stop) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.terracotta)
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(Capsule().stroke(Ink.terracotta, lineWidth: 1))
                .contentShape(Capsule())
        case .notSure:
            Button(MoxaClockCopy.choiceCompare) { onCompare() }
                .font(.subheadline).foregroundStyle(Ink.gold)
                .frame(maxWidth: .infinity).frame(height: 44)
        case .skip:
            Button(MoxaClockCopy.choiceSkip) { clock.answer(.skip) }
                .font(.footnote).foregroundStyle(Ink.textDim)
                .frame(maxWidth: .infinity).frame(height: 44)
        }
    }
}

// MARK: — end cards

/// The ordinary end: cap reached or ended by hand. Two things must survive the wind-down: what to
/// do with the smouldering moxa, and that the skin gets looked at again later.
struct MoxaEndCard: View {
    let byCap: Bool
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(byCap ? MoxaClockCopy.endByCapTitle : MoxaClockCopy.endTitle)
                .font(.title2).foregroundStyle(Ink.gold)
            Text(MoxaClockCopy.endBody)
                .font(.subheadline).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(MoxaClockCopy.endRecheck)
                .font(.footnote).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            if byCap {
                Text(MoxaClockCopy.endNoMore)
                    .font(.footnote).foregroundStyle(Ink.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(MoxaClockCopy.doneButton) { onDone() }
                .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                .padding(.bottom, 24)
        }
        .padding(24)
    }
}

/// The stop path — the skin said no. First-aid basics, and when to see someone today.
struct MoxaStopCard: View {
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label { Text(MoxaClockCopy.stopTitle) } icon: { Image(systemName: "hand.raised") }
                    .font(.title3.weight(.semibold)).foregroundStyle(Ink.terracotta)
                ForEach(MoxaClockCopy.stopLines, id: \.self) { line in
                    Text("• " + line).font(.subheadline).foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(MoxaClockCopy.doneButton) { onDone() }
                    .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

// MARK: — the photo compare

/// Side-by-side: the before-photo (if one was taken) and the fresh one. NO VERDICT IS COMPUTED —
/// deliberate and load-bearing. Redness estimation from uncalibrated phone photos is unreliable
/// across lighting and, worse, systematically under-reads early heat injury on deeper skin tones
/// (research: dermatology CV drops 29–40% ROC-AUC on diverse-skin data, and no FDA-cleared
/// photo-only burn assessment exists). A wrong "looks fine" would green-light the exact injury
/// this feature exists to prevent. So the screen only helps the user LOOK HARDER: the photos, a
/// checklist whose colour question covers dark-skin presentations, and two buttons — continue
/// (their eyes, their call) or stop — with every doubt tilted toward stop.
struct MoxaSkinCompare: View {
    @ObservedObject var clock: MoxaClock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let now = clock.checkPhoto {
                        HStack(alignment: .top, spacing: 12) {
                            if let before = clock.baselinePhoto {
                                photo(before, label: MoxaClockCopy.compareBefore)
                            }
                            photo(now, label: MoxaClockCopy.compareNow)
                        }
                    } else {
                        Text(MoxaClockCopy.compareNoPhoto)
                            .font(.subheadline).foregroundStyle(Ink.textDim)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(MoxaClockCopy.compareTitle)
                            .font(.caption.weight(.semibold)).foregroundStyle(Ink.gold)
                        ForEach(MoxaClockCopy.checklist, id: \.self) { line in
                            Text("• " + line).font(.footnote).foregroundStyle(Ink.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12).panel()
                    Text(MoxaClockCopy.compareFooter)
                        .font(.caption2).foregroundStyle(Ink.textDim)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(MoxaClockCopy.compareStop) {
                        dismiss(); clock.answer(.stop)
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.terracotta)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .overlay(Capsule().stroke(Ink.terracotta, lineWidth: 1))
                    .contentShape(Capsule())

                    Button(MoxaClockCopy.compareContinue) {
                        dismiss(); clock.answer(.lookedClear)
                    }
                    .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(ShanshuiBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func photo(_ image: UIImage, label: String) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(label).font(.caption2).foregroundStyle(Ink.textDim)
        }
    }
}

/// The thinnest possible camera wrapper: system capture UI, image handed back in memory, nothing
/// written anywhere. `.camera` availability gates the feature out on devices (and the Simulator)
/// without one.
struct MoxaSkinCamera: UIViewControllerRepresentable {
    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MoxaSkinCamera
        init(_ parent: MoxaSkinCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPhoto(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
