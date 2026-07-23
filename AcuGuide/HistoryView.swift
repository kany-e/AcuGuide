import SwiftUI

// The full practice history — the Practice tab shows the last three sessions; this screen shows
// everything the device has: per-point practice counts, then every session with its rounds,
// held time, per-round breakdown (records saved since v2) and the self-reported experience.
// Local-only data; the share button is the user's own backup path.
struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var practice = PracticeStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                List {
                    let counts = practice.pointCounts()
                    if !counts.isEmpty {
                        Section(AppLocale.pick("常练穴位", "Most practiced")) {
                            ForEach(counts.prefix(5), id: \.pointId) { entry in
                                HStack(spacing: 10) {
                                    Circle().fill(MeridianColors.color(Acupoint.byId[entry.pointId]?.meridian ?? "extra"))
                                        .frame(width: 9, height: 9).accessibilityHidden(true)
                                    Text("\(entry.pointId) · \(Acupoint.byId[entry.pointId].map { AppLocale.pick($0.zh, $0.en) } ?? "")")
                                        .font(.subheadline).foregroundStyle(Ink.text)
                                    Spacer()
                                    Text(AppLocale.pick("\(entry.count) 次", "\(entry.count)×"))
                                        .font(Typo.code(14)).foregroundStyle(Ink.gold)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    Section(AppLocale.pick("全部记录", "All sessions")) {
                        ForEach(practice.records.reversed()) { r in
                            sessionRow(r)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocale.pick("练习记录", "Practice history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: PracticeExport(),
                              preview: SharePreview("AcuGuide practice history")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Ink.gold)
                    .accessibilityLabel(AppLocale.pick("导出练习记录", "Export practice history"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("完成", "Done")) { dismiss() }.tint(Ink.gold)
                }
            }
        }
    }

    private func sessionRow(_ r: PracticeRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Circle().fill(MeridianColors.color(Acupoint.byId[r.pointId]?.meridian ?? "extra"))
                    .frame(width: 9, height: 9).accessibilityHidden(true)
                Text("\(r.pointId) · \(Acupoint.byId[r.pointId].map { AppLocale.pick($0.zh, $0.en) } ?? "")")
                    .font(.subheadline).foregroundStyle(Ink.text)
                Spacer()
                Text(r.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(Ink.textDim)
            }
            HStack(spacing: 8) {
                Text(AppLocale.pick("\(r.rounds)/\(r.roundsTarget) 轮 · 共 \(Int(r.heldS.rounded())) 秒",
                                    "\(r.rounds)/\(r.roundsTarget) rounds · \(Int(r.heldS.rounded()))s held"))
                    .font(.caption).foregroundStyle(Ink.textDim)
                // Same experience scale as the recap; FeelingScale absorbs the legacy keys from
                // the outcome-framed prompt, so old records still read correctly.
                if let f = FeelingScale(anyKey: r.feeling) {
                    Text(f.label).font(.caption).foregroundStyle(f.color)
                }
            }
            if let per = r.roundsHeldS, !per.isEmpty {
                Text(AppLocale.pick("各轮：", "Rounds: ")
                     + per.map { "\(Int($0.rounded()))s" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(Ink.textDim)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
