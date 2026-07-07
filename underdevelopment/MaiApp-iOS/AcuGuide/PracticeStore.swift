import Foundation
import CoreTransferable
import UniformTypeIdentifiers

// On-device practice history — the recap used to vanish the moment it was dismissed. Each coached
// session (completed OR ended early — both first-class) saves one record; the self-reported feeling
// is attached when chosen. Stored as a small JSON payload in UserDefaults, capped, never synced or
// uploaded (matches the app's nothing-leaves-the-device posture).
struct PracticeRecord: Codable, Identifiable, Equatable {
    let id: String            // uuid
    let date: Date
    let pointId: String
    let rounds: Int
    let roundsTarget: Int
    let heldS: Double
    var feeling: String?      // "relaxing" | "neutral" | "uncomfortable" (legacy: relief/nochange/worse)
    var roundsHeldS: [Double]? = nil   // per-round held seconds (absent on records saved before v2)
}

final class PracticeStore: ObservableObject {
    static let shared = PracticeStore()

    @Published private(set) var records: [PracticeRecord] = []   // newest LAST

    private let defaults: UserDefaults
    private static let key = "practiceHistory"
    private static let unreadableKey = "practiceHistory.unreadable"
    private static let cap = 300                                  // plenty of history, bounded storage
    private static let schemaVersion = 2

    // v2 on-disk shape. v1 was a bare [PracticeRecord] array — still readable below, and any
    // FUTURE shape change must keep a fallback chain here rather than silently dropping history.
    private struct Envelope: Codable {
        let v: Int
        let records: [PracticeRecord]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else { return }
        let dec = JSONDecoder()
        if let env = try? dec.decode(Envelope.self, from: data) {
            records = env.records
        } else if let recs = try? dec.decode([PracticeRecord].self, from: data) {
            records = recs                                        // v1 → migrated on next persist
        } else {
            // Never silently erase the user's history: park the bytes so a future build (or the
            // user's own export) can still recover them, then start fresh.
            defaults.set(data, forKey: Self.unreadableKey)
        }
    }

    func add(_ record: PracticeRecord) {
        records.append(record)
        if records.count > Self.cap { records.removeFirst(records.count - Self.cap) }
        invalidateInsights()
        persist()
    }

    func setFeeling(id: String, feeling: String) {
        guard let i = records.lastIndex(where: { $0.id == id }) else { return }
        records[i].feeling = feeling
        invalidateInsights()
        persist()
    }

    var sessionCount: Int { records.count }

    // ── Cached insights ─────────────────────────────────────────────────────────
    // The Practice tab re-renders on every store change; these derived values are O(records)
    // apiece, so they're computed once per (records change, calendar day) instead of per render.
    // The day stamp matters: weekCount/streak depend on "today", not just on the data.
    private var insightsCache: (day: Date, week: Int, streak: Int, tally30: (Int, Int, Int))?

    private func invalidateInsights() { insightsCache = nil }

    private func insights() -> (week: Int, streak: Int, tally30: (Int, Int, Int)) {
        let today = Calendar.current.startOfDay(for: Date())
        if let c = insightsCache, c.day == today { return (c.week, c.streak, c.tally30) }
        let fresh = (day: today, week: computeWeekCount(), streak: computeStreakDays(),
                     tally30: computeFeelingTally(days: 30))
        insightsCache = fresh
        return (fresh.week, fresh.streak, fresh.tally30)
    }

    // Sessions in the trailing 7 days — the "this week" insight.
    var weekCount: Int { insights().week }

    // Consecutive calendar days with at least one session, counting back from today (0 = none today).
    var streakDays: Int { insights().streak }

    // Self-reported EXPERIENCE over the trailing 30 days — how sessions felt (relaxing / neutral /
    // uncomfortable), deliberately NOT an efficacy score: one session of acupressure can't honestly
    // be judged "relief vs worse", but comfort is real signal for which points suit the user.
    // Legacy keys from the earlier outcome-framed prompt map onto the experience scale.
    func feelingTally(days: Int = 30) -> (relaxing: Int, neutral: Int, uncomfortable: Int) {
        if days == 30 { return insights().tally30 }
        return computeFeelingTally(days: days)
    }

    private func computeWeekCount() -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return records.filter { $0.date > cutoff }.count
    }

    private func computeFeelingTally(days: Int) -> (relaxing: Int, neutral: Int, uncomfortable: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return (0, 0, 0) }
        var relaxing = 0, neutral = 0, uncomfortable = 0
        for r in records where r.date > cutoff {
            // FeelingScale (SessionUI.swift) owns the canonical + legacy key mapping.
            switch FeelingScale(anyKey: r.feeling) {
            case .relaxing: relaxing += 1
            case .neutral: neutral += 1
            case .uncomfortable: uncomfortable += 1
            case nil: break
            }
        }
        return (relaxing, neutral, uncomfortable)
    }

    private func computeStreakDays() -> Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // Per-point practice counts, most-practiced first — the history screen's "your points" stats.
    func pointCounts() -> [(pointId: String, count: Int)] {
        var tally: [String: Int] = [:]
        for r in records { tally[r.pointId, default: 0] += 1 }
        return tally.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map { (pointId: $0.key, count: $0.value) }
    }

    // Pretty-printed JSON of the whole history — for the user's own export (local-only data means
    // a lost phone would otherwise erase it).
    func exportJSON() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(records) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Envelope(v: Self.schemaVersion, records: records)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// Lazy export payload for ShareLink: `ShareLink(item:)` builds its item on every body evaluation,
// and eagerly pretty-printing the whole history there re-encoded up to 300 records per render
// (review-caught). DataRepresentation's closure runs only when the user actually shares.
struct PracticeExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { _ in
            Data(PracticeStore.shared.exportJSON().utf8)
        }
        .suggestedFileName("acuguide-practice.json")
    }
}

// Starred acupoints — quick access to the points someone actually returns to. A plain string-set
// in UserDefaults; local-only like everything else.
final class Favorites: ObservableObject {
    static let shared = Favorites()

    @Published private(set) var ids: Set<String> = []

    private let defaults: UserDefaults
    private static let key = "favoritePoints"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let arr = defaults.stringArray(forKey: Self.key) { ids = Set(arr) }
    }

    func contains(_ pointId: String) -> Bool { ids.contains(pointId) }

    func toggle(_ pointId: String) {
        if ids.contains(pointId) { ids.remove(pointId) } else { ids.insert(pointId) }
        defaults.set(ids.sorted(), forKey: Self.key)
    }

    // Favorites in atlas order (Acupoint.all order), so the row reads like the catalog.
    var points: [Acupoint] { Acupoint.all.filter { ids.contains($0.id) } }
}
