import SwiftUI

// Plain, VoiceOver-friendly catalog of every atlas point, grouped by region — the accessible path
// to the whole atlas (the 3D body is inherently visual). Every point offers practice: the 8
// camera-coached points launch the AR coach, everything else the guided timer session. The launch
// closure carries the chosen rounds and whether the user asked for the no-camera timer session.
struct AllPointsView: View {
    var onPractice: (_ point: Acupoint, _ rounds: Int, _ timerOnly: Bool) -> Void
    var onLocate: ((Acupoint) -> Void)? = nil     // forwarded to the point card's "Find my spot"
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
            PointInfoView(point: pt, onPractice: onPractice, onLocate: onLocate)
        } label: {
            AcupointListRow(pt: pt, showsStar: true)
                .accessibilityLabel("\(pt.id), \(AppLocale.pick(pt.zh, pt.en)), \(pt.meridianEn)"
                                    + (favorites.contains(pt.id) ? ", \(AppLocale.pick("已收藏", "favorite"))" : ""))
        }
    }
}

// THE atlas list row (this catalog + the routine builder's picker share it): meridian dot,
// "ID · name", camera/timer trailing icon, one combined VoiceOver element. The catalog variant
// (showsStar) adds the English subtitle and the favorites star; the picker stays single-line.
struct AcupointListRow: View {
    let pt: Acupoint
    var showsStar: Bool = false
    @ObservedObject private var favorites = Favorites.shared   // star updates live on toggle

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(MeridianColors.color(pt.meridian))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            if showsStar {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pt.id) · \(pt.zh)")
                        .font(.subheadline).foregroundStyle(Ink.text)
                    Text(pt.en).font(.caption).foregroundStyle(Ink.textDim)
                }
            } else {
                Text("\(pt.id) · \(AppLocale.pick(pt.zh, pt.en))")
                    .font(.subheadline).foregroundStyle(Ink.text)
            }
            Spacer()
            if showsStar && favorites.contains(pt.id) {
                Image(systemName: "star.fill")
                    .font(.caption).foregroundStyle(Ink.gold)
                    .accessibilityHidden(true)
            }
            Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                .font(.caption).foregroundStyle(Ink.textDim)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// One point, plainly: role, location, traditional uses, caution, evidence pointer — and practice,
// with the round count adjustable and (for coached points) a no-camera timer alternative.
struct PointInfoView: View {
    let point: Acupoint
    var onPractice: (_ point: Acupoint, _ rounds: Int, _ timerOnly: Bool) -> Void
    // Optional so existing call sites are untouched; when provided, the point card offers
    // "Find my spot" — the entry to per-user calibration, which used to be reachable only by
    // starting a full session and tapping an unlabeled glyph in the camera overlay bar.
    var onLocate: ((Acupoint) -> Void)? = nil
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var favorites = Favorites.shared
    @ObservedObject private var speaker = AtlasSpeaker.shared
    @ObservedObject private var calibration = PointCalibration.shared
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
                    // Plain-language "how to find it" (the same guide the on-camera locate step uses) —
                    // easier to act on than the formal location.
                    if point.hasFindGuide {
                        labeled(AppLocale.pick("这样找", "How to find it"), point.findHow, tint: Ink.gold)
                    }
                    // Read the name + where-to-find aloud, for anyone who'd rather listen than read.
                    Button { speaker.toggle(point.spokenInfo) } label: {
                        Label(speaker.speaking ? AppLocale.pick("停止朗读", "Stop reading")
                                                : AppLocale.pick("朗读位置与找法", "Read the location aloud"),
                              systemImage: speaker.speaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Ink.gold)
                    }
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
                    // FIND MY SPOT — the app's one genuinely uncopyable capability. Everyone's hand
                    // is slightly different, so the computed ring is a starting point; confirming
                    // where YOU feel the point stores a correction that re-applies at any hand pose.
                    // Only offered for camera-coached points with a find-by-feel guide (the locate
                    // step needs both a live ring and written guidance).
                    if let onLocate, point.mediapipeTarget != nil, point.hasFindGuide {
                        let saved = calibration.hasCalibration(point.id)
                        Button(saved ? AppLocale.pick("重新找我的位置", "Re-find my spot")
                                     : AppLocale.pick("找到我的位置", "Find my spot")) { onLocate(point) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Ink.gold)
                            .frame(maxWidth: .infinity).padding(.top, 2)
                        Text(saved
                             ? AppLocale.pick("这个穴位已按你的手校准过 — 每次练习都会用你保存的位置。",
                                              "Tuned to your hand — every session uses the spot you saved.")
                             : AppLocale.pick("用相机按感觉微调位置，之后每次练习都会记住它。",
                                              "Fine-tune it by feel on camera once, and every session after remembers it."))
                            .font(.caption2).foregroundStyle(saved ? Ink.jade : Ink.textDim)
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                    WellnessFooter()
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
        .onDisappear { speaker.stop() }
    }

    private var sessionMinutes: Int { Routine.minutes(forRounds: rounds) }

    private func labeled(_ title: String, _ text: String, tint: Color = Ink.text) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Ink.textDim)
            Text(text).font(.subheadline).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}
