import SwiftUI

// Routine cards → detail sheet → sequential runner. The runner chains the existing session
// experiences (AR coach for the 8 camera points, guided timer for everything else) with a
// "next point" hand-off on each recap; the safety gate is confirmed once at the first step
// of a run (it is one continuous session).
struct RoutineCard: View {
    let routine: Routine
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: routine.icon).font(.title3).foregroundStyle(Ink.gold)
            Text(routine.name).font(Typo.serif(16, weight: .semibold)).foregroundStyle(Ink.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(AppLocale.pick("\(routine.steps.count) 穴 · 约 \(routine.minutes) 分钟",
                                "\(routine.steps.count) pts · ~\(routine.minutes) min"))
                .font(.caption2).foregroundStyle(Ink.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).panel()
    }
}

struct RoutineDetailSheet: View {
    let routine: Routine
    var onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: routine.icon).font(.title2).foregroundStyle(Ink.gold)
                        Text(routine.name).font(Typo.serif(22, weight: .semibold)).foregroundStyle(Ink.gold)
                    }
                    Text(routine.desc).font(.subheadline).foregroundStyle(Ink.text)
                    ForEach(Array(routine.steps.enumerated()), id: \.offset) { i, step in
                        if let pt = step.point {
                            HStack(spacing: 10) {
                                Text("\(i + 1)").font(Typo.code(13)).foregroundStyle(Ink.gold)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().stroke(Ink.line, lineWidth: 1))
                                Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 8, height: 8)
                                Text("\(pt.id) · \(AppLocale.pick(pt.zh, pt.en))")
                                    .font(.subheadline).foregroundStyle(Ink.text)
                                Spacer()
                                Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                                    .font(.caption).foregroundStyle(Ink.textDim)
                                Text(AppLocale.pick("\(step.rounds) 轮", "\(step.rounds) rounds"))
                                    .font(.caption).foregroundStyle(Ink.textDim)
                            }
                            .padding(10).panel()
                        }
                    }
                    Text(AppLocale.pick("带相机图标的穴位由相机引导，其余为计时引导（按说明自行定位）。",
                                        "Camera-marked points are camera-coached; the rest are timer-guided (self-located from the instructions)."))
                        .font(.footnote).foregroundStyle(Ink.textDim)
                    Spacer()
                    Button(AppLocale.pick("开始套组", "Start routine")) { onStart() }
                        .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity)
                    WellnessFooter()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("关闭", "Close")) { dismiss() }.tint(Ink.gold)
            } }
        }
    }
}

// Sequential step runner. `id(stepIndex)` gives each step a FRESH session view (state objects and
// all); the safety gate shows on the first step only — one confirmation per continuous run.
struct RoutineRunView: View {
    let routine: Routine
    var onClose: () -> Void
    @State private var stepIndex = 0

    var body: some View {
        Group {
            if stepIndex >= routine.steps.count {
                finished
            } else if let pt = routine.steps[stepIndex].point {
                stepSession(pt, rounds: routine.steps[stepIndex].rounds)
                    .id(stepIndex)
            } else {
                // A step whose pointId no longer resolves must not soft-lock the run — skip it.
                Color.clear.onAppear { stepIndex += 1 }
            }
        }
    }

    // One shared session factory (PracticeSessionView) — it owns the camera-vs-timer dispatch AND
    // the camera-denied timer fallback, so a routine step is never unpassable.
    @ViewBuilder private func stepSession(_ pt: Acupoint, rounds: Int) -> some View {
        PracticeSessionView(point: pt, rounds: rounds, onNext: nextHandOff,
                            acknowledgedInitially: stepIndex > 0)
    }

    private var nextHandOff: (label: String, action: () -> Void) {
        let isLast = stepIndex == routine.steps.count - 1
        let label: String
        if isLast {
            label = AppLocale.pick("完成套组", "Finish routine")
        } else if let nxt = routine.steps[stepIndex + 1].point {
            label = AppLocale.pick("下一穴：\(nxt.zh)", "Next: \(nxt.en)")
        } else {
            label = AppLocale.pick("继续", "Continue")
        }
        return (label, { stepIndex += 1 })
    }

    private var finished: some View {
        ZStack {
            ShanshuiBackground()
            VStack(spacing: 18) {
                Image(systemName: routine.icon).font(.system(size: 44)).foregroundStyle(Ink.gold)
                Text(AppLocale.pick("套组完成", "Routine complete")).font(.title2).foregroundStyle(Ink.gold)
                Text(AppLocale.pick("「\(routine.zh)」的每个穴位都记入了练习记录。",
                                    "Every point of “\(routine.en)” is in your practice history."))
                    .foregroundStyle(Ink.text).multilineTextAlignment(.center)
                Button(AppLocale.pick("完成", "Done")) { onClose() }.buttonStyle(GoldButtonStyle())
                WellnessFooter()
            }
            .padding(28)
        }
    }
}
