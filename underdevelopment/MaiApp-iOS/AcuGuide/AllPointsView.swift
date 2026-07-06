import SwiftUI

// Plain, VoiceOver-friendly catalog of every atlas point, grouped by region — the accessible path
// to the whole atlas (the 3D body is inherently visual). Every point offers practice: the 8
// camera-coached points launch the AR coach, everything else the guided timer session. The launch
// closure carries the chosen rounds and whether the user asked for the no-camera timer session.
struct AllPointsView: View {
    var onPractice: (_ point: Acupoint, _ rounds: Int, _ timerOnly: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favorites = Favorites.shared
    @State private var search = ""

    static let regionOrder: [(id: String, zh: String, en: String)] = [
        ("hand", "手部", "Hand"), ("arm", "手臂", "Arm"), ("head", "头面", "Head & face"),
        ("chest", "胸部", "Chest"), ("abdomen", "腹部", "Abdomen"), ("leg", "腿部", "Leg"), ("foot", "足部", "Foot"),
    ]

    // The catalog is static — group it once, not on every render.
    static let pointsByRegion: [String: [Acupoint]] = Dictionary(grouping: Acupoint.all, by: \.region)

    private func matches(_ pt: Acupoint) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let lq = q.lowercased()
        return pt.id.lowercased().contains(lq) || pt.zh.contains(q)
            || pt.en.lowercased().contains(lq) || pt.pinyin.lowercased().contains(lq)
            || pt.englishName.lowercased().contains(lq)
            || pt.indicationsZh.contains(q) || pt.indicationsEn.lowercased().contains(lq)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                List {
                    let starred = favorites.points.filter(matches)
                    if !starred.isEmpty {
                        Section(AppLocale.pick("收藏", "Favorites")) {
                            ForEach(starred) { pt in pointLink(pt) }
                        }
                    }
                    ForEach(Self.regionOrder, id: \.id) { region in
                        let pts = (Self.pointsByRegion[region.id] ?? []).filter(matches)
                        if !pts.isEmpty {
                            Section(AppLocale.pick(region.zh, region.en)) {
                                ForEach(pts) { pt in pointLink(pt) }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $search,
                        prompt: AppLocale.pick("穴名、编号或用途", "Name, code or traditional use"))
            .navigationTitle(AppLocale.pick("全部穴位", "All points"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { dismiss() }.tint(Ink.gold)
            } }
        }
    }

    private func pointLink(_ pt: Acupoint) -> some View {
        NavigationLink {
            PointInfoView(point: pt, onPractice: onPractice)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(MeridianColors.color(pt.meridian))
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pt.id) · \(pt.zh)")
                        .font(.subheadline).foregroundStyle(Ink.text)
                    Text(pt.en).font(.caption).foregroundStyle(Ink.textDim)
                }
                Spacer()
                if favorites.contains(pt.id) {
                    Image(systemName: "star.fill")
                        .font(.caption).foregroundStyle(Ink.gold)
                        .accessibilityHidden(true)
                }
                Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                    .font(.caption).foregroundStyle(Ink.textDim)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(pt.id), \(AppLocale.pick(pt.zh, pt.en)), \(pt.meridianEn)"
                                + (favorites.contains(pt.id) ? ", \(AppLocale.pick("已收藏", "favorite"))" : ""))
        }
    }
}

// One point, plainly: role, location, traditional uses, caution, evidence pointer — and practice,
// with the round count adjustable and (for coached points) a no-camera timer alternative.
struct PointInfoView: View {
    let point: Acupoint
    var onPractice: (_ point: Acupoint, _ rounds: Int, _ timerOnly: Bool) -> Void
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favorites = Favorites.shared
    @State private var rounds = CoachConst.sessionRounds

    var body: some View {
        ZStack {
            ShanshuiBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Circle().fill(MeridianColors.color(point.meridian)).frame(width: 10, height: 10)
                        Text("\(point.id) · \(point.zh)").font(Typo.serif(22, weight: .semibold)).foregroundStyle(Ink.gold)
                        Text(point.en).font(Typo.code(15)).foregroundStyle(Ink.textDim)
                    }
                    Text(point.meridianEn + (point.englishName.isEmpty ? "" : " · “\(point.englishName)”"))
                        .font(.caption).foregroundStyle(Ink.textDim)
                    if !point.role.isEmpty {
                        Text(point.role).font(.caption).foregroundStyle(Ink.gold.opacity(0.9))
                    }
                    labeled(AppLocale.pick("定位", "Location"), point.location)
                    labeled(AppLocale.pick("传统用途", "Traditional uses"), point.indications)
                    if !point.caution.isEmpty {
                        labeled(AppLocale.pick("注意", "Caution"), point.caution, tint: Ink.terracotta)
                    }

                    // Session length is the user's choice — 1 round ≈ half a minute.
                    Stepper(AppLocale.pick("\(rounds) 轮 · 约 \(sessionMinutes) 分钟",
                                           "\(rounds) rounds · ~\(sessionMinutes) min"),
                            value: $rounds, in: 1...4)
                        .font(.subheadline).foregroundStyle(Ink.text)
                        .padding(12).panel()

                    Button(point.mediapipeTarget != nil
                           ? AppLocale.pick("用相机练习", "Practice with camera")
                           : AppLocale.pick("计时引导练习", "Guided practice (timer)")) {
                        onPractice(point, rounds, false)
                    }
                    .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity).padding(.top, 6)
                    if point.mediapipeTarget != nil {
                        // The camera is optional, never required — low light, privacy, or simply
                        // lying down are all fine reasons to take the guided timer instead.
                        Button(AppLocale.pick("不用相机 · 计时引导", "Timer-guided (no camera)")) {
                            onPractice(point, rounds, true)
                        }
                        .font(.subheadline).foregroundStyle(Ink.gold)
                        .frame(maxWidth: .infinity)
                    }
                    Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                        .font(.caption2).foregroundStyle(Ink.textDim).frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .navigationTitle(point.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    favorites.toggle(point.id)
                } label: {
                    Image(systemName: favorites.contains(point.id) ? "star.fill" : "star")
                }
                .tint(Ink.gold)
                .accessibilityLabel(favorites.contains(point.id)
                                    ? AppLocale.pick("取消收藏", "Remove favorite")
                                    : AppLocale.pick("收藏", "Add favorite"))
            }
        }
    }

    private var sessionMinutes: Int {
        let seconds = Double(rounds) * CoachConst.holdTargetS + Double(max(0, rounds - 1)) * CoachConst.restS
        return max(1, Int((seconds / 60).rounded()))
    }

    private func labeled(_ title: String, _ text: String, tint: Color = Ink.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
            Text(text).font(.subheadline).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
