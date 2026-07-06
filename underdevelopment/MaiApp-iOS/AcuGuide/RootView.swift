import SwiftUI

// What a tap launches: a single point session (camera for the 8 coached points, guided timer for
// every other atlas point) or a multi-step routine run.
enum PracticeLaunch: Identifiable {
    case point(Acupoint, rounds: Int)
    case routine(Routine)
    var id: String {
        switch self {
        case .point(let p, let r): return "p:\(p.id):\(r)"
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
                set: { if let p = $0 { launch = .point(p, rounds: CoachConst.sessionRounds) } })
    }

    var body: some View {
        // No separate "Hand" tab — the hand is a drill-down from the 3D body (web parity).
        TabView {
            AtlasTab(startCoach: startCoach)
                .tabItem { Label(AppLocale.pick("图谱", "Atlas"), systemImage: "figure.stand") }

            CoachHome(launch: $launch)
                .tabItem { Label(AppLocale.pick("练习", "Practice"), systemImage: "camera.viewfinder") }

            ChatView(startCoach: startCoach)
                .tabItem { Label(AppLocale.pick("AI 教练", "Coach AI"), systemImage: "bubble.left.and.bubble.right") }
        }
        .tint(Ink.gold)
        // One launcher for every practice shape: camera coach / timer session / routine run.
        .fullScreenCover(item: $launch) { l in
            NavigationStack {
                Group {
                    switch l {
                    case .point(let pt, let rounds):
                        if pt.mediapipeTarget != nil {
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
                    launch = .point(te3, rounds: 1)
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

// The Practice tab: concern-driven routines up front, then the 8 camera-coached points, the
// full catalog, practice insights, and recent history.
struct CoachHome: View {
    @Binding var launch: PracticeLaunch?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var practice = PracticeStore.shared
    @State private var routineSheet: Routine? = nil
    @State private var showAllPoints = false
    private var coachable: [Acupoint] { Acupoint.all.filter { $0.mediapipeTarget != nil } }

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
                            if let te3 = Acupoint.byId["TE3"] { launch = .point(te3, rounds: 1) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(Ink.gold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(AppLocale.pick("第一次？先试一轮", "First time? Try one round"))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.text)
                                    Text(AppLocale.pick("30 秒，相机带你按中渚 TE3。", "30 seconds — the camera guides you on TE3."))
                                        .font(.caption).foregroundStyle(Ink.textDim)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.textDim)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain).panel()
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
                        }
                    }

                    Text(AppLocale.pick("相机引导 · 单穴", "Camera coach · single points"))
                        .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                        .padding(.top, 6)
                    ForEach(coachable) { pt in
                        Button { launch = .point(pt, rounds: CoachConst.sessionRounds) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 10, height: 10)
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
                                Image(systemName: "camera.viewfinder")
                                    .font(.callout).foregroundStyle(Ink.gold.opacity(0.8))
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                        .panel()
                    }

                    Button {
                        showAllPoints = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet").foregroundStyle(Ink.gold)
                            Text(AppLocale.pick("浏览全部穴位（计时引导）", "Browse all points (timer-guided)"))
                                .font(.subheadline).foregroundStyle(Ink.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.textDim)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain).panel()

                    if !practice.records.isEmpty {
                        Text(AppLocale.pick("最近练习", "Recent practice"))
                            .font(Typo.serif(17, weight: .semibold)).foregroundStyle(Ink.gold)
                            .padding(.top, 6)
                        ForEach(practice.records.suffix(3).reversed()) { r in
                            HStack(spacing: 10) {
                                Circle().fill(MeridianColors.color(Acupoint.byId[r.pointId]?.meridian ?? "extra"))
                                    .frame(width: 8, height: 8)
                                Text("\(r.pointId) · \(Acupoint.byId[r.pointId].map { AppLocale.pick($0.zh, $0.en) } ?? "")")
                                    .font(.subheadline).foregroundStyle(Ink.text)
                                Spacer()
                                Text(AppLocale.pick("\(r.rounds)/\(r.roundsTarget) 轮", "\(r.rounds)/\(r.roundsTarget) rounds"))
                                    .font(.caption).foregroundStyle(Ink.textDim)
                                Text(r.date.formatted(.relative(presentation: .named)))
                                    .font(.caption2).foregroundStyle(Ink.textDim)
                            }
                            .padding(12).panel()
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
        .sheet(isPresented: $showAllPoints) {
            AllPointsView { pt in
                showAllPoints = false
                launch = .point(pt, rounds: CoachConst.sessionRounds)
            }
        }
    }

    // This week's sessions, the day streak, and how sessions have felt (last 30 days) — the
    // feelings people report become the app's own honest evidence.
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
            if tally.relief + tally.nochange + tally.worse > 0 {
                Text(AppLocale.pick(
                    "近 30 天的自我反馈：缓解 \(tally.relief) · 无变化 \(tally.nochange) · 更糟 \(tally.worse)",
                    "Your last 30 days: relief \(tally.relief) · no change \(tally.nochange) · worse \(tally.worse)"))
                    .font(.caption).foregroundStyle(Ink.textDim)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}

// Acupoint is already Identifiable via `id`; needed for .fullScreenCover(item:).
