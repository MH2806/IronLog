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

