import SwiftUI

// What a tap launches: a single point session (camera for the 8 coached points, guided timer for
// every other atlas point — or by explicit choice: the camera is optional even for the coached 8)
// or a multi-step routine run.
enum PracticeLaunch: Identifiable {
    case point(Acupoint, rounds: Int, timerOnly: Bool)
    case routine(Routine)
    var id: String {
        switch self {
        case .point(let p, let r, let t): return "p:\(p.id):\(r):\(t)"
        case .routine(let r): return "r:\(r.id)"
        }
    }
}

struct RootView: View {
    @State private var launch: PracticeLaunch? = nil
    @ObservedObject private var settings = AppSettings.shared   // re-render tab labels on toggle
    @State private var showOnboarding = !AppSettings.shared.seenOnboarding

    // Bridge for children that just hand back a point (atlas markers, chat suggestions).
    private var startCoach: Binding<Acupoint?> {
        Binding(get: { nil },
                set: { if let p = $0 { launch = .point(p, rounds: CoachConst.sessionRounds, timerOnly: false) } })
    }

    var body: some View {
        // No separate "Hand" tab — the hand is a drill-down from the 3D body (web parity).
        TabView {
            AtlasTab(startCoach: startCoach)
                .tabItem { Label(AppLocale.pick("图谱", "Atlas"), systemImage: "figure.stand") }

            CoachHome(launch: $launch)
                .tabItem { Label(AppLocale.pick("练习", "Practice"), systemImage: "camera.viewfinder") }

            ChatView(startCoach: startCoach)
                .tabItem { Label(CoachPersona.name, systemImage: "bubble.left.and.bubble.right") }
        }
        .tint(Ink.gold)
        // One launcher for every practice shape: camera coach / timer session / routine run.
        .fullScreenCover(item: $launch) { l in
            NavigationStack {
                Group {
                    switch l {
                    case .point(let pt, let rounds, let timerOnly):
                        if pt.mediapipeTarget != nil && !timerOnly {
                            ARCoachView(acupoint: pt, roundsTarget: rounds)
                        } else {
                            TimerSessionView(acupoint: pt, roundsTarget: rounds)
                        }
                    case .routine(let r):
                        RoutineRunView(routine: r) { launch = nil }
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocale.pick("关闭", "Close")) { launch = nil }.tint(Ink.gold)
                } }
            }
        }
        // First run: what the app is (and isn't), how the coach works, the privacy story —
        // with an optional 30-second quick try as the very first action.
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { quickTry in
                settings.seenOnboarding = true
                showOnboarding = false
                if quickTry, let te3 = Acupoint.byId["TE3"] {
                    launch = .point(te3, rounds: 1, timerOnly: false)
                }
            }
        }
    }
}

// Atlas tab: the 3D body IS the whole atlas (no 2D drill-down). Tap a region label to zoom the
// camera in-scene, tap a 3D acupoint marker for its details, and the practice button launches the
// right session for the point (camera for the coached 8, guided timer otherwise).
struct AtlasTab: View {
    @Binding var startCoach: Acupoint?
    var body: some View {
        // No .ignoresSafeArea here: the SceneKit view + projected-label overlay ignore the safe
        // area internally (so projectPoint coords line up), while the back button + point panel
        // stay inside the safe area and clear the status bar / tab bar.
        Body3DView(onPractice: { startCoach = $0 })
    }
}

// The Practice tab: concern-driven routines (bundled + the user's own) up front, then favorites,
// the 8 camera-coached points, the full catalog, practice insights, and recent history.
struct CoachHome: View {
    @Binding var launch: PracticeLaunch?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var practice = PracticeStore.shared
    @ObservedObject private var favorites = Favorites.shared
    @ObservedObject private var custom = CustomRoutineStore.shared
    @State private var routineSheet: Routine? = nil
    @State private var builderSheet: BuilderTarget? = nil
    @State private var showAllPoints = false
    @State private var showHistory = false
    private var coachable: [Acupoint] { Acupoint.all.filter { $0.mediapipeTarget != nil } }

    // One sheet, two shapes: a fresh builder or editing an existing custom routine.
    private enum BuilderTarget: Identifiable {
        case new
        case edit(CustomRoutine)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let r): return r.id
            }
        }
    }

    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppLocale.pick("练习", "Practice"))
                        .font(Typo.serif(22, weight: .semibold)).foregroundStyle(Ink.gold)
                        .frame(maxWidth: .infinity)

                    // First-run quick win: one 30-second camera-coached round.
                    if practice.records.isEmpty {
                        Button {
                            if let te3 = Acupoint.byId["TE3"] { launch = .point(te3, rounds: 1, timerOnly: false) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(Ink.gold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocale.pick("第一次？先试一轮", "First time? Try one round"))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                    Text(AppLocale.pick("30 秒，\(CoachPersona.name) 带你按中渚 TE3。",
                                                        "30 seconds — \(CoachPersona.name) walks you through TE3."))
                                        .font(.caption).foregroundStyle(Ink.textDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.textDim)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain).panel()
                        .accessibilityElement(children: .combine)
                    }

                    // Practice insights — the history means something.
                    if !practice.records.isEmpty {
                        insightsCard
                    }

                    Text(AppLocale.pick("调理套组", "Routines"))
                        .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Routine.all) { r in
                            Button { routineSheet = r } label: { RoutineCard(routine: r) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(routineAccessibilityLabel(r))
                        }
                        ForEach(custom.routines) { cr in
                            Button { routineSheet = cr.asRoutine } label: { RoutineCard(routine: cr.asRoutine) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(routineAccessibilityLabel(cr.asRoutine)
                                                    + ", " + AppLocale.pick("自定义", "custom"))
                                .contextMenu {
                                    Button {
                                        builderSheet = .edit(cr)
                                    } label: {
                                        Label(AppLocale.pick("编辑", "Edit"), systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        custom.delete(id: cr.id)
                                    } label: {
                                        Label(AppLocale.pick("删除", "Delete"), systemImage: "trash")
                                    }
                                }
                        }
                        // Build-your-own — same runner, the user's own sequence.
                        Button { builderSheet = .new } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: "plus.circle").font(.title3).foregroundStyle(Ink.gold)
                                Text(AppLocale.pick("新建套组", "New routine"))
                                    .font(Typo.serif(16, weight: .semibold)).foregroundStyle(Ink.text)
                                Text(AppLocale.pick("自选穴位与顺序", "Your points, your order"))
                                    .font(.caption2).foregroundStyle(Ink.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).panel()
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }

                    if !favorites.points.isEmpty {
                        Text(AppLocale.pick("收藏", "Favorites"))
                            .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                            .padding(.top, 6)
                        ForEach(favorites.points) { pt in
                            pointRow(pt)
                        }
                    }

                    Text(AppLocale.pick("相机引导 · 单穴", "Camera coach · single points"))
                        .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                        .padding(.top, 6)
                    ForEach(coachable) { pt in
                        pointRow(pt)
                    }

                    Button {
                        showAllPoints = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet").foregroundStyle(Ink.gold)
                            Text(AppLocale.pick("浏览全部穴位", "Browse all points"))
                                .font(.subheadline).foregroundStyle(Ink.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.textDim)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain).panel()
                    .accessibilityElement(children: .combine)

                    if !practice.records.isEmpty {
                        HStack {
                            Text(AppLocale.pick("最近练习", "Recent practice"))
                                .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                            Spacer()
                            Button(AppLocale.pick("全部记录", "See all")) { showHistory = true }
                                .font(.caption).tint(Ink.gold)
                        }
                        .padding(.top, 6)
                        ForEach(practice.records.suffix(3).reversed()) { r in
                            HStack(spacing: 10) {
                                Circle().fill(MeridianColors.color(Acupoint.byId[r.pointId]?.meridian ?? "extra"))
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text("\(r.pointId) · \(Acupoint.byId[r.pointId].map { AppLocale.pick($0.zh, $0.en) } ?? "")")
                                    .font(.subheadline).foregroundStyle(Ink.text)
                                Spacer()
                                Text(AppLocale.pick("\(r.rounds)/\(r.roundsTarget) 轮", "\(r.rounds)/\(r.roundsTarget) rounds"))
                                    .font(.caption).foregroundStyle(Ink.textDim)
                                Text(r.date.formatted(.relative(presentation: .named)))
                                    .font(.caption2).foregroundStyle(Ink.textDim)
                            }
                            .padding(12).panel()
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                        .font(.caption2).foregroundStyle(Ink.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding()
            }
        }
        .sheet(item: $routineSheet) { r in
            RoutineDetailSheet(routine: r) {
                routineSheet = nil
                launch = .routine(r)
            }
        }
        .sheet(item: $builderSheet) { target in
            switch target {
            case .new: RoutineBuilderView()
            case .edit(let cr): RoutineBuilderView(editing: cr)
            }
        }
        .sheet(isPresented: $showAllPoints) {
            AllPointsView { pt, rounds, timerOnly in
                showAllPoints = false
                launch = .point(pt, rounds: rounds, timerOnly: timerOnly)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView()
        }
    }

    // Shared row for favorites + the coached list: tap launches the right session for the point.
    private func pointRow(_ pt: Acupoint) -> some View {
        Button { launch = .point(pt, rounds: CoachConst.sessionRounds, timerOnly: false) } label: {
            HStack(spacing: 12) {
                Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(pt.id) · \(pt.zh)")
                            .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                        Text(pt.en).font(Typo.code(14)).foregroundStyle(Ink.textDim)
                        if pt.id == "TE3" {
                            Text(AppLocale.pick("推荐", "suggested"))
                                .font(.caption2).foregroundStyle(Ink.paperLight)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Ink.gold.opacity(0.9)))
                        }
                    }
                    Text(pt.location)
                        .font(.caption).foregroundStyle(Ink.text)
                        .multilineTextAlignment(.leading).lineLimit(2)
                }
                Spacer()
                Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                    .font(.callout).foregroundStyle(Ink.gold.opacity(0.8))
                    .accessibilityHidden(true)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .panel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pt.id), \(AppLocale.pick(pt.zh, pt.en)), "
                            + AppLocale.pick(pt.mediapipeTarget != nil ? "相机引导" : "计时引导",
                                             pt.mediapipeTarget != nil ? "camera-coached" : "timer-guided"))
    }

    private func routineAccessibilityLabel(_ r: Routine) -> String {
        r.name + ", " + AppLocale.pick("\(r.steps.count) 个穴位，约 \(r.minutes) 分钟",
                                       "\(r.steps.count) points, about \(r.minutes) minutes")
    }

    // This week's sessions, the day streak, and how sessions have felt (last 30 days) — the
    // feelings people report become the app's own honest evidence. One VoiceOver element: the
    // separate number/caption pairs fragment into meaningless pieces otherwise.
    private var insightsCard: some View {
        let tally = practice.feelingTally()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(practice.weekCount)").font(Typo.serif(24, weight: .semibold)).foregroundStyle(Ink.gold)
                    Text(AppLocale.pick("本周练习", "this week")).font(.caption2).foregroundStyle(Ink.textDim)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(practice.streakDays)").font(Typo.serif(24, weight: .semibold)).foregroundStyle(Ink.jade)
                    Text(AppLocale.pick("连续天数", "day streak")).font(.caption2).foregroundStyle(Ink.textDim)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(practice.sessionCount)").font(Typo.serif(24, weight: .semibold)).foregroundStyle(Ink.text)
                    Text(AppLocale.pick("累计", "total")).font(.caption2).foregroundStyle(Ink.textDim)
                }
            }
            if tally.relaxing + tally.neutral + tally.uncomfortable > 0 {
                Text(AppLocale.pick(
                    "近 30 天的体验：放松 \(tally.relaxing) · 一般 \(tally.neutral) · 不舒服 \(tally.uncomfortable)",
                    "How sessions felt (30 days): relaxing \(tally.relaxing) · neutral \(tally.neutral) · uncomfortable \(tally.uncomfortable)"))
                    .font(.caption).foregroundStyle(Ink.textDim)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocale.pick(
            "本周练习 \(practice.weekCount) 次，连续 \(practice.streakDays) 天，累计 \(practice.sessionCount) 次。"
            + "近 30 天体验：放松 \(tally.relaxing)，一般 \(tally.neutral)，不舒服 \(tally.uncomfortable)。",
            "\(practice.weekCount) sessions this week, \(practice.streakDays) day streak, \(practice.sessionCount) total. "
            + "Last 30 days: relaxing \(tally.relaxing), neutral \(tally.neutral), uncomfortable \(tally.uncomfortable)."))
    }
}

// Acupoint is already Identifiable via `id`; needed for .fullScreenCover(item:).
