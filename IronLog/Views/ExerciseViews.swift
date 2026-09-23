import SwiftUI
import SwiftData
import Charts

struct ExerciseFilterBar: View {
    @Binding var muscle: String?
    @Binding var equipment: String?
    @Binding var level: String?
    let equipmentOptions: [String]

    var body: some View {
        HStack {
            Menu {
                Button("Any muscle") { muscle = nil }
                ForEach(Muscles.all, id: \.self) { m in Button(m.capitalized) { muscle = m } }
            } label: { Label(muscle?.capitalized ?? "Muscle", systemImage: "figure.arms.open") }
            Menu {
                Button("Any equipment") { equipment = nil }
                ForEach(equipmentOptions, id: \.self) { e in Button(e.capitalized) { equipment = e } }
            } label: { Label(equipment?.capitalized ?? "Equipment", systemImage: "dumbbell") }
            Menu {
                Button("Any level") { level = nil }
                ForEach(["beginner", "intermediate", "advanced"], id: \.self) { l in Button(l.capitalized) { level = l } }
            } label: { Label(level?.capitalized ?? "Level", systemImage: "chart.bar") }
            Spacer()
        }
        .font(.subheadline)
    }
}

private func filtered(_ list: [Exercise], search: String, muscle: String?, equipment: String?, level: String?) -> [Exercise] {
    list.filter { e in
        (search.isEmpty || e.name.localizedCaseInsensitiveContains(search)) &&
        (muscle == nil || e.primaryMuscles.contains(muscle!) || e.secondaryMuscles.contains(muscle!)) &&
        (equipment == nil || e.allEquipment.contains(equipment!)) &&
        (level == nil || e.level == level)
    }
}

private func equipmentOptions(_ list: [Exercise]) -> [String] {
    Array(Set(list.flatMap(\.allEquipment))).sorted()
}

struct ExerciseLibraryView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @State private var search = ""
    @State private var muscle: String?
    @State private var equipment: String?
    @State private var level: String?
    @State private var showAdd = false

    var body: some View {
        let list = filtered(library.all, search: search, muscle: muscle, equipment: equipment, level: level)
        List {
            ExerciseFilterBar(muscle: $muscle, equipment: $equipment, level: $level, equipmentOptions: equipmentOptions(library.all))
            ForEach(list) { e in
                NavigationLink { ExerciseDetailView(exercise: e) } label: { ExerciseRow(exercise: e) }
            }
        }
        .overlay {
            if library.all.isEmpty {
                ContentUnavailableView("Exercise library missing", systemImage: "exclamationmark.triangle",
                                       description: Text("exercises.json wasn't bundled. Rebuild with the GitHub Action."))
            }
        }
        .searchable(text: $search)
        .navigationTitle("Exercises (\(list.count))")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showAdd) { AddCustomExerciseView() }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(exercise.name)
                if exercise.isCustom { Image(systemName: "person.fill").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(([exercise.primaryMuscles.joined(separator: ", "), exercise.mechanic ?? "", exercise.level ?? "",
                   exercise.allEquipment.joined(separator: ", ")]).filter { !$0.isEmpty }.joined(separator: " · ").capitalized)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct ExercisePicker: View {
    let onPick: ([Exercise]) -> Void
    @EnvironmentObject var library: ExerciseLibrary
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @State private var search = ""
    @State private var muscle: String?
    @State private var equipment: String?
    @State private var level: String?
    @State private var selected: [String] = []

    private var recentIDs: [String] {
        var seen = Set<String>(), out: [String] = []
        for w in workouts.prefix(20) {
            for e in w.orderedExercises where seen.insert(e.exerciseID).inserted { out.append(e.exerciseID) }
        }
        return Array(out.prefix(12))
    }

    var body: some View {
        NavigationStack {
            let list = filtered(library.all, search: search, muscle: muscle, equipment: equipment, level: level)
            List {
                ExerciseFilterBar(muscle: $muscle, equipment: $equipment, level: $level,
                                  equipmentOptions: equipmentOptions(library.all))
                if search.isEmpty && muscle == nil && equipment == nil && level == nil && !recentIDs.isEmpty {
                    Section("Recent") {
                        ForEach(recentIDs.compactMap { library.exercise($0) }) { e in row(e) }
                    }
                }
                Section("All") { ForEach(list) { e in row(e) } }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        onPick(selected.compactMap { library.exercise($0) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(_ e: Exercise) -> some View {
        Button {
            if let i = selected.firstIndex(of: e.id) { selected.remove(at: i) } else { selected.append(e.id) }
        } label: {
            HStack {
                ExerciseRow(exercise: e).foregroundStyle(.primary)
                Spacer()
                if let i = selected.firstIndex(of: e.id) {
                    Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Theme.accent, in: Circle())
                }
            }
        }
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt)
    private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @State private var metric = 0

    private var unit: String {
        switch exercise.trackingType {
        case .duration: return "s"
        case .cardio: return "km"
        default: return "kg"
        }
    }

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let points = Stats.history(for: exercise.id, in: workouts, library: library, bodyweight: profile.bodyweight)
        let repBased = exercise.trackingType.isRepBased
        List {
            if !exercise.imageURLs.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(exercise.imageURLs, id: \.self) { url in
                                AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: {
                                    ProgressView().frame(width: 160, height: 120)
                                }
                                .frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent("Primary", value: exercise.primaryMuscles.joined(separator: ", ").capitalized)
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secondary", value: exercise.secondaryMuscles.joined(separator: ", ").capitalized)
                }
                if !exercise.allEquipment.isEmpty {
                    LabeledContent("Equipment", value: exercise.allEquipment.joined(separator: ", ").capitalized)
                }
                if let l = exercise.level { LabeledContent("Level", value: l.capitalized) }
                if let m = exercise.mechanic { LabeledContent("Type", value: m.capitalized) }
                LabeledContent("Logged as", value: exercise.trackingType.label)
            }

            if exercise.standard != nil {
                StandardsSection(exercise: exercise, workouts: workouts, profile: profile)
            }

            if !points.isEmpty {
                Section("Your progress") {
                    if repBased {
                        Picker("Metric", selection: $metric) {
                            Text("Est. 1RM").tag(0)
                            Text("Top weight").tag(1)
                            Text("Volume").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    Chart(points) { p in
                        let y = !repBased || metric == 0 ? p.e1rm : (metric == 1 ? p.bestWeight : p.volume)
                        LineMark(x: .value("Date", p.date), y: .value(unit, y)).interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value(unit, y)).symbolSize(20)
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(height: 200)
                    if let best = points.max(by: { $0.e1rm < $1.e1rm }) {
                        LabeledContent(repBased ? "Best est. 1RM" : "Best",
                                       value: "\(best.e1rm.clean) \(unit) (\(best.date.formatted(date: .abbreviated, time: .omitted)))")
                    }
                    if repBased { LabeledContent("Heaviest", value: (points.map(\.bestWeight).max() ?? 0).kg) }
                    LabeledContent("Sessions", value: "\(points.count)")
                }
                if repBased {
                    Section("Rep records") {
                        ForEach(repRecords(), id: \.reps) { rec in
                            LabeledContent("\(rec.reps) rep\(rec.reps == 1 ? "" : "s")", value: rec.weight.kg)
                        }
                    }
                }
            }

            if !exercise.instructions.isEmpty {
                Section {
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(item.offset + 1).").foregroundStyle(.secondary)
                            Text(item.element)
                        }
                    }
                } header: {
                    Text("How to")
                } footer: {
                    if let from = exercise.instructionsFrom {
                        Text("Steps and photos are from the closely related \(from); adjust for this variation.")
                    } else if !exercise.images.isEmpty {
                        Text("Photos and steps: free-exercise-db (public domain).")
                    }
                }
            }

            if exercise.isCustom {
                Section { Button("Delete custom exercise", role: .destructive) { library.deleteCustom(exercise.id) } }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Heaviest weight lifted for each rep count 1–12.
    private func repRecords() -> [RepRecord] {
        var best: [Int: Double] = [:]
        for w in workouts {
            for ex in w.exercises where ex.exerciseID == exercise.id {
                for s in ex.sets where s.completed && !s.isWarmup && s.reps >= 1 && s.reps <= 12 {
                    best[s.reps] = max(best[s.reps] ?? 0, s.weightKg)
                }
            }
        }
        return best.sorted { $0.key < $1.key }.map { RepRecord(reps: $0.key, weight: $0.value) }
    }
}

struct AddCustomExerciseView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var primary: Set<String> = []
    @State private var secondary: Set<String> = []
    @State private var equipment = "barbell"
    @State private var compound = true
    @State private var tracking: Tracking = .weightReps

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Equipment", selection: $equipment) {
                    ForEach(["barbell", "dumbbell", "cable", "machine", "smith machine", "bodyweight", "kettlebell", "resistance band", "plate", "other"], id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
                Toggle("Compound movement", isOn: $compound)
                Picker("Logged as", selection: $tracking) {
                    ForEach(Tracking.allCases) { Text($0.label).tag($0) }
                }
                Section("Primary muscles") { muscleToggles($primary) }
                Section("Secondary muscles") { muscleToggles($secondary) }
            }
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.addCustom(name: name, primary: Array(primary), secondary: Array(secondary),
                                          equipment: equipment, compound: compound, tracking: tracking)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
        }
    }

    private func muscleToggles(_ set: Binding<Set<String>>) -> some View {
        ForEach(Muscles.all, id: \.self) { m in
            Toggle(m.capitalized, isOn: Binding(
                get: { set.wrappedValue.contains(m) },
                set: { on in if on { set.wrappedValue.insert(m) } else { set.wrappedValue.remove(m) } }))
        }
    }
}

struct RepRecord {
    let reps: Int
    let weight: Double
}

/// Level floors for this exercise at the user's bodyweight, plus where they sit.
struct StandardsSection: View {
    let exercise: Exercise
    let workouts: [Workout]
    let profile: ProfileSnapshot
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        let bw = profile.bodyweight
        let floors = exercise.standard.flatMap { StrengthStandards.shared?.floors(for: $0, sex: profile.sex, bodyweight: bw) } ?? []
        let mine = StrengthScoreEngine.report(workouts: workouts, library: library, profile: profile)
            .exercises.first { $0.exerciseID == exercise.id }
        let isTotal = exercise.trackingType != .weightReps
        Section {
            if let mine {
                HStack {
                    Circle().fill(Theme.color(mine.level)).frame(width: 12, height: 12)
                    Text("You: \(mine.level.name)").bold()
                    Spacer()
                    Text("\(Int(mine.points)) pts · \(mine.e1rm.kg)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ForEach(Array(StrengthLevel.allCases.enumerated()), id: \.offset) { item in
                let level = item.element
                let floor = level == .beginner ? 0 : (floors.count == 5 ? floors[level.rawValue - 1] : 0)
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.color(level)).frame(width: 12, height: 12)
                    Text(level.name)
                    Spacer()
                    Text(level == .beginner ? "from 0" : "from \(displayed(floor, bw: bw, total: isTotal))")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .fontWeight(mine?.level == level ? .bold : .regular)
            }
        } header: {
            Text("Standards for you (\(profile.sex.label.lowercased()), \(bw.kg))")
        } footer: {
            Text(footer(isTotal: isTotal))
        }
    }

    /// For bodyweight moves, convert total load back to "bodyweight + x kg" so it reads like what you'd log.
    private func displayed(_ total: Double, bw: Double, total isTotal: Bool) -> String {
        guard isTotal, let share = exercise.bodyweightShare else { return "\(Progression.roundTo(total, step: 0.5).clean) kg (1RM)" }
        let own = bw * share
        switch exercise.trackingType {
        case .assistedReps:
            return total <= own ? "−\(Progression.roundTo(own - total, step: 0.5).clean) kg assist" : "unassisted"
        default:
            let reps = total <= own ? 0 : Int(((total / own) - 1) * 30)
            return total <= own ? "1 rep" : (total - own < 5 && reps <= 25 ? "\(max(reps, 1)) reps" : "+\(Progression.roundTo(total - own, step: 0.5).clean) kg (1RM)")
        }
    }

    private func footer(isTotal: Bool) -> String {
        var t = "Estimated one-rep max needed for each level, scaled to your bodyweight."
        if exercise.allEquipment.contains("dumbbell") || exercise.allEquipment.contains("kettlebell") {
            t += " Dumbbell and kettlebell numbers are per hand."
        }
        if isTotal { t += " Bodyweight counts toward the load." }
        return t
    }
}
