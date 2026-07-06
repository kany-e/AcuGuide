import SwiftUI

// User-authored routines — the bundled six cover common concerns, but people settle into their own
// sequences. A custom routine is just an ordered list of (point, rounds) that reuses the exact same
// runner as the bundled ones; the coached set stays the documented 8 (the runner branches per point,
// nothing here can add a camera point). Local-only JSON in UserDefaults, like the practice history.
struct CustomRoutine: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var steps: [Step]

    struct Step: Codable, Equatable, Identifiable {
        var id: String = UUID().uuidString
        var pointId: String
        var rounds: Int
        var point: Acupoint? { Acupoint.byId[pointId] }
    }

    // Bridge into the value type the routine runner/cards already understand.
    var asRoutine: Routine {
        Routine(id: "custom-\(id)", zh: name, en: name, icon: "star",
                descZh: "自定义套组。", descEn: "Your own sequence.",
                steps: steps.map { RoutineStep(pointId: $0.pointId, rounds: $0.rounds) })
    }

    var minutes: Int { asRoutine.minutes }
}

final class CustomRoutineStore: ObservableObject {
    static let shared = CustomRoutineStore()

    @Published private(set) var routines: [CustomRoutine] = []

    private let defaults: UserDefaults
    private static let key = "customRoutines"
    private static let cap = 20
    private static let schemaVersion = 1

    private struct Envelope: Codable { let v: Int; let routines: [CustomRoutine] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            routines = env.routines
        }
    }

    // Insert-or-replace by id; new routines append (stable card order).
    func save(_ routine: CustomRoutine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[i] = routine
        } else {
            routines.append(routine)
            if routines.count > Self.cap { routines.removeFirst(routines.count - Self.cap) }
        }
        persist()
    }

    func delete(id: String) {
        routines.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Envelope(v: Self.schemaVersion, routines: routines)) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

// Build or edit one custom routine: name it, pick points from the full atlas, set rounds per point,
// reorder or remove. Steps referencing a coached point run the camera; everything else the timer —
// exactly like the bundled routines.
struct RoutineBuilderView: View {
    var editing: CustomRoutine?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared
    @State private var name: String
    @State private var steps: [CustomRoutine.Step]
    @State private var showPicker = false

    private static let maxSteps = 8

    init(editing: CustomRoutine? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _steps = State(initialValue: editing?.steps ?? [])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !steps.isEmpty
    }

    private var minutes: Int {
        let rounds = steps.reduce(0) { $0 + $1.rounds }
        let seconds = Double(rounds) * CoachConst.holdTargetS + Double(max(0, rounds - 1)) * CoachConst.restS
        return max(1, Int((seconds / 60).rounded()))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                Form {
                    Section(AppLocale.pick("名称", "Name")) {
                        TextField(AppLocale.pick("给套组起个名字", "Name your routine"), text: $name)
                    }
                    Section(AppLocale.pick("穴位顺序", "Points, in order")) {
                        ForEach($steps) { $step in
                            if let pt = step.point {
                                HStack(spacing: 10) {
                                    Circle().fill(MeridianColors.color(pt.meridian)).frame(width: 8, height: 8)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(pt.id) · \(AppLocale.pick(pt.zh, pt.en))")
                                            .font(.subheadline).foregroundStyle(Ink.text)
                                        Text(AppLocale.pick(pt.mediapipeTarget != nil ? "相机引导" : "计时引导",
                                                            pt.mediapipeTarget != nil ? "camera-coached" : "timer-guided"))
                                            .font(.caption2).foregroundStyle(Ink.textDim)
                                    }
                                    Spacer()
                                    Stepper(AppLocale.pick("\(step.rounds) 轮", "\(step.rounds) rounds"),
                                            value: $step.rounds, in: 1...4)
                                        .font(.caption).foregroundStyle(Ink.textDim)
                                        .fixedSize()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .onDelete { steps.remove(atOffsets: $0) }
                        .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                        if steps.count < Self.maxSteps {
                            Button {
                                showPicker = true
                            } label: {
                                Label(AppLocale.pick("添加穴位", "Add a point"), systemImage: "plus.circle")
                                    .foregroundStyle(Ink.gold)
                            }
                        }
                    }
                    if !steps.isEmpty {
                        Section {
                            Text(AppLocale.pick("约 \(minutes) 分钟 · 长按拖动可调整顺序。",
                                                "~\(minutes) min · touch and hold a row to reorder."))
                                .font(.footnote).foregroundStyle(Ink.textDim)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(editing == nil ? AppLocale.pick("新建套组", "New routine")
                                            : AppLocale.pick("编辑套组", "Edit routine"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocale.pick("取消", "Cancel")) { dismiss() }.tint(Ink.gold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocale.pick("保存", "Save")) {
                        var r = editing ?? CustomRoutine(name: "", steps: [])
                        r.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        r.steps = steps
                        CustomRoutineStore.shared.save(r)
                        dismiss()
                    }
                    .tint(Ink.gold)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPicker) {
                RoutinePointPicker { pt in
                    steps.append(CustomRoutine.Step(pointId: pt.id, rounds: 2))
                    showPicker = false
                }
            }
        }
    }
}

// Compact region-grouped picker for the builder — same catalog as AllPointsView, tap-to-add.
private struct RoutinePointPicker: View {
    var onPick: (Acupoint) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ZStack {
                ShanshuiBackground()
                List {
                    ForEach(AllPointsView.regionOrder, id: \.id) { region in
                        let pts = AllPointsView.pointsByRegion[region.id] ?? []
                        if !pts.isEmpty {
                            Section(AppLocale.pick(region.zh, region.en)) {
                                ForEach(pts) { pt in
                                    Button {
                                        onPick(pt)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Circle().fill(MeridianColors.color(pt.meridian))
                                                .frame(width: 9, height: 9).accessibilityHidden(true)
                                            Text("\(pt.id) · \(AppLocale.pick(pt.zh, pt.en))")
                                                .font(.subheadline).foregroundStyle(Ink.text)
                                            Spacer()
                                            Image(systemName: pt.mediapipeTarget != nil ? "camera.viewfinder" : "timer")
                                                .font(.caption).foregroundStyle(Ink.textDim)
                                                .accessibilityHidden(true)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(AppLocale.pick("添加穴位", "Add a point"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(AppLocale.pick("取消", "Cancel")) { dismiss() }.tint(Ink.gold)
            } }
        }
    }
}
