import SwiftUI

// Plain, VoiceOver-friendly catalog of every atlas point, grouped by region — the accessible path
// to the whole atlas (the 3D body is inherently visual). Every point offers practice: the 8
// camera-coached points launch the AR coach, everything else the guided timer session.
struct AllPointsView: View {
    var onPractice: (Acupoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    private static let regionOrder: [(id: String, zh: String, en: String)] = [
        ("hand", "手部", "Hand"), ("arm", "手臂", "Arm"), ("head", "头面", "Head & face"),
        ("chest", "胸部", "Chest"), ("abdomen", "腹部", "Abdomen"), ("leg", "腿部", "Leg"), ("foot", "足部", "Foot"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                List {
                    ForEach(Self.regionOrder, id: \.id) { region in
                        let pts = Acupoint.all.filter { $0.region == region.id }
                        if !pts.isEmpty {
                            Section(AppLocale.pick(region.zh, region.en)) {
                                ForEach(pts) { pt in
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
                                            Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                                                .font(.caption).foregroundStyle(Ink.textDim)
                                                .accessibilityHidden(true)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("\(pt.id), \(AppLocale.pick(pt.zh, pt.en)), \(pt.meridianEn)")
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocale.pick("全部穴位", "All points"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(AppLocale.pick("完成", "Done")) { dismiss() }.tint(Ink.gold)
            } }
        }
    }
}

// One point, plainly: role, location, traditional uses, caution, evidence pointer — and practice.
struct PointInfoView: View {
    let point: Acupoint
    var onPractice: (Acupoint) -> Void

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
                    Button(point.mediapipeTarget != nil
                           ? AppLocale.pick("用相机练习", "Practice with camera")
                           : AppLocale.pick("计时引导练习", "Guided practice (timer)")) {
                        onPractice(point)
                    }
                    .buttonStyle(GoldButtonStyle()).frame(maxWidth: .infinity).padding(.top, 6)
                    Text(AppLocale.pick("仅供养生自我保养，非医疗建议。", "Wellness self-care only — not medical advice."))
                        .font(.caption2).foregroundStyle(Ink.textDim).frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
        .navigationTitle(point.id)
        .navigationBarTitleDisplayMode(.inline)
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
