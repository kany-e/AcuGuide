import Foundation

// On-device practice history — the recap used to vanish the moment it was dismissed. Each coached
// session (completed OR ended early — both first-class) saves one record; the self-reported feeling
// is attached when chosen. Stored as a small JSON array in UserDefaults, capped, never synced or
// uploaded (matches the app's nothing-leaves-the-device posture).
struct PracticeRecord: Codable, Identifiable, Equatable {
    let id: String            // uuid
    let date: Date
    let pointId: String
    let rounds: Int
    let roundsTarget: Int
    let heldS: Double
    var feeling: String?      // "relief" | "nochange" | "worse" — set from the recap
}

final class PracticeStore: ObservableObject {
    static let shared = PracticeStore()

    @Published private(set) var records: [PracticeRecord] = []   // newest LAST

    private let defaults: UserDefaults
    private static let key = "practiceHistory"
    private static let cap = 300                                  // plenty of history, bounded storage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let recs = try? JSONDecoder().decode([PracticeRecord].self, from: data) {
            records = recs
        }
    }

    func add(_ record: PracticeRecord) {
        records.append(record)
        if records.count > Self.cap { records.removeFirst(records.count - Self.cap) }
        persist()
    }

    func setFeeling(id: String, feeling: String) {
        guard let i = records.lastIndex(where: { $0.id == id }) else { return }
        records[i].feeling = feeling
        persist()
    }

    var sessionCount: Int { records.count }

    // Sessions in the trailing 7 days — the "this week" insight.
    var weekCount: Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return records.filter { $0.date > cutoff }.count
    }

    // Self-reported feelings over the trailing `days` — the user's own honest evidence.
    func feelingTally(days: Int = 30) -> (relief: Int, nochange: Int, worse: Int) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return (0, 0, 0) }
        var relief = 0, nochange = 0, worse = 0
        for r in records where r.date > cutoff {
            switch r.feeling {
            case "relief": relief += 1
            case "nochange": nochange += 1
            case "worse": worse += 1
            default: break
            }
        }
        return (relief, nochange, worse)
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

    // Consecutive calendar days with at least one session, counting back from today (0 = none today).
    var streakDays: Int {
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

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.key) }
    }
}
