import SwiftUI
import SwiftData

// MARK: - Routines

struct RoutinesView: View {
    @Binding var showActive: Bool
    @Environment(\.modelContext) private var context
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var showGenerator = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showGenerator = true } label: { Label("Build a plan for me", systemImage: "wand.and.stars") }
                    Button { createBlank() } label: { Label("Create empty routine", systemImage: "plus") }
                }
                Section("Proven templates") {
                    template("Beginner full body 3×", .strength, 3, .gym, .beginner)
                    template("Upper / lower 4×", .strength, 4, .gym, .intermediate)
                    template("Push / pull / legs 6×", .hypertrophy, 6, .gym, .intermediate)
                    template("Dumbbell full body 3×", .general, 3, .dumbbells, .beginner)
                }
                if !routines.isEmpty {
                    Section("Your routines") {
                        ForEach(routines) { r in
                            NavigationLink { RoutineDetailView(routine: r, showActive: $showActive) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(r.name).font(.headline)
                                        if r.isActive { Text("Active").font(.caption.bold()).foregroundStyle(Theme.plateGreen) }
                                    }
                                    Text("\(r.days.count) days · next: \(r.nextDay?.name ?? "–")").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            for i in idx { context.delete(routines[i]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Routines")
            .sheet(isPresented: $showGenerator) { RoutineGeneratorView() }
        }
    }

    private func template(_ title: String, _ goal: Goal, _ days: Int, _ eq: Equipment, _ exp: Experience) -> some View {
        Button {
            var plan = RoutineGenerator.generate(goal: goal, days: days, equipment: eq, experience: exp)
            plan.name = title
            plan.insert(into: context, library: library, activate: routines.allSatisfy { !$0.isActive })
            try? context.save()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
            }
        }
    }

    private func createBlank() {
        let r = Routine(name: "My routine")
        context.insert(r)
        r.days.append(RoutineDay(name: "Day 1", order: 0))
        try? context.save()
    }
}

struct RoutineDetailView: View {
    @Bindable var routine: Routine
    @Binding var showActive: Bool
    @Environment(\.modelContext) private var context
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var allRoutines: [Routine]
    @State private var pickerDay: RoutineDay?

    var body: some View {
        List {
            Section {
                TextField("Name", text: $routine.name)
                Toggle("Active routine", isOn: Binding(get: { routine.isActive }, set: { on in
                    for r in allRoutines { r.isActive = false }
                    routine.isActive = on
                    try? context.save()
                }))
                if !routine.summary.isEmpty { Text(routine.summary).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(routine.orderedDays) { day in
                Section {
                    ForEach(day.orderedExercises) { e in RoutineExerciseRow(target: e) }
                        .onDelete { idx in
                            let list = day.orderedExercises
                            for i in idx { day.exercises.removeAll { $0.id == list[i].id }; context.delete(list[i]) }
                        }
                    Button { pickerDay = day } label: { Label("Add exercise", systemImage: "plus") }
                    Button {
                        _ = WorkoutFactory.start(from: day, context: context, history: workouts.filter { $0.endedAt != nil }, library: library)
                        if let idx = routine.orderedDays.firstIndex(where: { $0.id == day.id }) { routine.nextDayIndex = idx }
                        try? context.save()
                        showActive = true
                    } label: { Label("Start this day", systemImage: "play.fill") }
                        .disabled(workouts.contains { $0.endedAt == nil })
                } header: {
                    HStack {
                        TextField("Day name", text: Binding(get: { day.name }, set: { day.name = $0 }))
                            .font(.headline).textCase(nil)
                        if routine.nextDay?.id == day.id { Text("Next").font(.caption.bold()).foregroundStyle(Theme.plateGreen) }
                        Button(role: .destructive) {
                            routine.days.removeAll { $0.id == day.id }
                            context.delete(day)
                        } label: { Image(systemName: "trash") }
                    }
                }
            }
            Section {
                Button {
                    routine.days.append(RoutineDay(name: "Day \(routine.days.count + 1)", order: (routine.days.map(\.order).max() ?? -1) + 1))
                } label: { Label("Add day", systemImage: "calendar.badge.plus") }
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickerDay) { day in
            ExercisePicker { picked in
                let start = (day.exercises.map(\.order).max() ?? -1) + 1
                for (i, e) in picked.enumerated() {
                    let heavy = e.isCompound && e.isBarbell
                    day.exercises.append(RoutineExercise(exerciseID: e.id, order: start + i, targetSets: 3,
                                                         repMin: heavy ? 5 : 8, repMax: heavy ? 8 : 12,
                                                         incrementKg: heavy ? 2.5 : 2, restSeconds: e.defaultRest))
                }
                try? context.save()
            }
        }
    }
}

struct RoutineExerciseRow: View {
    @Bindable var target: RoutineExercise
    @EnvironmentObject var library: ExerciseLibrary
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { expanded.toggle() } } label: {
                HStack {
                    Text(library.name(target.exerciseID)).foregroundStyle(.primary)
                    Spacer()
                    Text(target.weightKg > 0 ? "\(target.repText) @ \(target.weightKg.kg)" : target.repText)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if !target.lastNote.isEmpty { Text(target.lastNote).font(.caption).foregroundStyle(.secondary) }
            if target.pendingDeload {
                HStack {
                    Text("Deload to \(Progression.roundTo(target.weightKg * 0.9, step: max(target.incrementKg / 2, 0.5)).kg)?")
                        .font(.caption.bold())
                    Spacer()
                    Button("Accept") { Progression.acceptDeload(target) }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Ignore") { target.pendingDeload = false; target.failStreak = 0 }.controlSize(.small)
                }
                .tint(Theme.plateRed)
            }
            if expanded {
                Stepper("Sets: \(target.targetSets)", value: $target.targetSets, in: 1...10)
                Stepper("Min reps: \(target.repMin)", value: $target.repMin, in: 1...30)
                Stepper("Max reps: \(target.repMax)", value: $target.repMax, in: target.repMin...40)
                HStack {
                    Text("Working weight")
                    Spacer()
                    TextField("kg", value: $target.weightKg, format: .number).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).frame(width: 80)
                }
                Stepper("Increment: \(target.incrementKg.kg)", value: $target.incrementKg, in: 0.5...10, step: 0.5)
                Stepper("Rest: \(target.restSeconds)s", value: $target.restSeconds, in: 0...600, step: 15)
            }
        }
    }
}

// MARK: - Plan builder

struct RoutineGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ExerciseLibrary
    @State private var goal: Goal = .hypertrophy
    @State private var days = 4
    @State private var equipment: Equipment = .gym
    @State private var experience: Experience = .intermediate
    @State private var notes = ""
    @State private var plan: GeneratedPlan?
    @State private var loading = false
    @State private var error: String?

    private var hasKey: Bool { !(Keychain.get("anthropicKey") ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Goal", selection: $goal) { ForEach(Goal.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Days per week: \(days)", value: $days, in: 2...6)
                Picker("Equipment", selection: $equipment) { ForEach(Equipment.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Experience", selection: $experience) { ForEach(Experience.allCases) { Text($0.rawValue).tag($0) } }
                Section {
                    TextField("Anything else? Injuries, weak points, time limits…", text: $notes, axis: .vertical)
                    Button("Generate") {
                        plan = RoutineGenerator.generate(goal: goal, days: days, equipment: equipment, experience: experience)
                    }
                    Button(loading ? "Asking Claude…" : "Generate with Claude") { generateAI() }
                        .disabled(!hasKey || loading)
                } footer: {
                    Text(hasKey ? "Claude uses your notes and picks from the exercise library."
                                : "Add an Anthropic API key in Profile to enable Claude-generated plans. The standard generator works offline.")
                }
                if let error { Text(error).foregroundStyle(Theme.plateRed).font(.caption) }
                if let plan {
                    Section(plan.name) {
                        Text(plan.summary).font(.caption).foregroundStyle(.secondary)
                        ForEach(plan.days.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.days[i].name).font(.headline)
                                ForEach(plan.days[i].exercises.indices, id: \.self) { j in
                                    let e = plan.days[i].exercises[j]
                                    LibraryName(id: e.id, suffix: "\(e.sets)×\(e.repMin == e.repMax ? "\(e.repMin)" : "\(e.repMin)–\(e.repMax)")")
                                        .font(.caption)
                                }
                            }
                        }
                        Button("Save and make active") {
                            plan.insert(into: context, library: library, activate: true)
                            try? context.save()
                            dismiss()
                        }
                        .bold()
                    }
                }
            }
            .navigationTitle("Build a plan")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func generateAI() {
        loading = true
        error = nil
        Task {
            do {
                plan = try await AIRoutineService.generate(goal: goal, days: days, equipment: equipment,
                                                          experience: experience, notes: notes, library: library)
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

// MARK: - Profile & settings

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.name) private var name = ""
    @AppStorage(Keys.sex) private var sex = "M"
    @AppStorage(Keys.bodyweight) private var bodyweight = 80.0
    @AppStorage(Keys.birthYear) private var birthYear = 2000
    @AppStorage(Keys.defaultRest) private var defaultRest = 0
    @AppStorage(Keys.healthSync) private var healthSync = false
    @AppStorage(Keys.aiModel) private var aiModel = "claude-sonnet-5"
    @AppStorage(Keys.trainingSince) private var trainingSince = 0.0
    @AppStorage(Keys.heightCm) private var height = 178.0
    @State private var apiKey = Keychain.get("anthropicKey") ?? ""
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Name", text: $name)
                    Picker("Sex (for strength comparisons)", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper("Born \(String(birthYear))", value: $birthYear, in: 1930...2015)
                    HStack {
                        Text("Bodyweight")
                        Spacer()
                        TextField("kg", value: $bodyweight, format: .number).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    NumberRow(label: "Height", value: $height, unit: "cm")
                    Toggle("I know when I started training", isOn: Binding(
                        get: { trainingSince > 0 },
                        set: { on in
                            trainingSince = on ? (Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now).timeIntervalSince1970 : 0
                        }))
                    if trainingSince > 0 {
                        DatePicker("Started consistent training", selection: Binding(
                            get: { Date(timeIntervalSince1970: trainingSince) },
                            set: { trainingSince = $0.timeIntervalSince1970 }), in: ...Date.now, displayedComponents: .date)
                    }
                    if measurements.contains(where: { $0.kind == .bodyweight }) {
                        Text("Your latest logged bodyweight is used instead of this when available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Compare") {
                    NavigationLink { StrengthScoreView() } label: { Label("Strength Score", systemImage: "figure.strengthtraining.traditional") }
                    NavigationLink { FriendsView() } label: { Label("Friends & leaderboard", systemImage: "person.3") }
                    NavigationLink { HistoryView() } label: { Label("Workout history", systemImage: "clock.arrow.circlepath") }
                }

                Section("Training") {
                    Picker("Default rest", selection: $defaultRest) {
                        Text("Per exercise").tag(0)
                        ForEach([60, 90, 120, 180, 240], id: \.self) { Text("\($0)s").tag($0) }
                    }
                }

                Section {
                    Toggle("Save workouts to Apple Health", isOn: $healthSync)
                        .disabled(!HealthSync.available)
                        .onChange(of: healthSync) { _, on in
                            if on { Task { try? await HealthSync.requestAccess() } }
                        }
                } footer: {
                    Text("If Health access fails after sideloading, your signing tool stripped the HealthKit entitlement. Everything else still works.")
                }

                Section {
                    SecureField("Anthropic API key (optional)", text: $apiKey)
                        .onSubmit { Keychain.set("anthropicKey", apiKey) }
                        .onChange(of: apiKey) { _, v in Keychain.set("anthropicKey", v) }
                    TextField("Model", text: $aiModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                } header: { Text("AI plans") } footer: {
                    Text("Stored in the iOS Keychain. Only used when you tap Generate with Claude.")
                }

                Section("Data") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Share export", systemImage: "square.and.arrow.up") }
                    } else {
                        Button("Export all workouts (JSON)") { exportURL = Exporter.json(workouts, library: library) }
                    }
                    LabeledContent("Workouts", value: "\(workouts.filter { $0.endedAt != nil }.count)")
                    LabeledContent("Exercises in library", value: "\(library.all.count)")
                    if let ref = ReferenceData.shared {
                        LabeledContent("Strength data", value: ref.dataDate)
                    }
                }

                Section("Credits") {
                    Text("Exercise photos and steps: free-exercise-db (public domain). Competition comparisons: OpenPowerlifting project, openpowerlifting.org.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct FriendsView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.name) private var name = ""
    @State private var friends = FriendCard.load()
    @State private var pasted = ""
    @State private var error: String?

    private var me: FriendCard {
        let profile = ProfileSnapshot.current(measurements)
        let r = StrengthEngine.report(workouts: workouts, profile: profile)
        let week = workouts.filter { $0.startedAt >= Stats.weekStart(.now) }.reduce(0) { $0 + $1.volume }
        func lift(_ l: KeyLift) -> Double? { r.standings.first { $0.lift == l }?.e1rm }
        let score = StrengthScoreEngine.report(workouts: workouts, library: library, profile: profile).score
        return FriendCard(id: FriendCard.myID, name: name.isEmpty ? "Me" : name, sex: profile.sex.rawValue,
                          bodyweight: profile.bodyweight, dots: r.dots, squat: lift(.squat), bench: lift(.bench),
                          deadlift: lift(.deadlift), weeklyVolume: week, updated: .now, score: score)
    }

    var body: some View {
        let mine = me
        let board = ([mine] + friends).sorted { ($0.score ?? 0, $0.dots ?? 0) > ($1.score ?? 0, $1.dots ?? 0) }
        List {
            Section {
                ForEach(Array(board.enumerated()), id: \.element.id) { item in
                    let f = item.element
                    HStack {
                        Text("\(item.offset + 1)").font(.headline).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(f.name + (f.id == mine.id ? " (you)" : "")).bold()
                            Text("S \(f.squat?.clean ?? "–") · B \(f.bench?.clean ?? "–") · D \(f.deadlift?.clean ?? "–") @ \(f.bodyweight.clean) kg")
                                .font(.caption).foregroundStyle(.secondary)
                            if f.id != mine.id {
                                Text("Updated \(f.updated.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(f.score.map { "\($0)" } ?? "–").font(.title3.bold()).monospacedDigit()
                                .foregroundStyle(Theme.color(f.score.map { StrengthLevel.from(points: Double($0)) }))
                            Text("DOTS \(f.dots.map { "\(Int($0))" } ?? "–") · \(Int(f.weeklyVolume / 1000))t/wk")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { board[$0].id }.filter { $0 != mine.id }
                    friends.removeAll { ids.contains($0.id) }
                    FriendCard.save(friends)
                }
            } header: { Text("Leaderboard (Strength Score)") } footer: {
                Text("Strength Score and DOTS both adjust for bodyweight and sex, so different-sized lifters compare fairly.")
            }

            Section {
                ShareLink(item: mine.code, preview: SharePreview("My IronLog strength card")) {
                    Label("Share my code", systemImage: "square.and.arrow.up")
                }
                TextField("Paste a friend's code", text: $pasted, axis: .vertical).font(.caption.monospaced())
                Button("Add friend") {
                    guard let card = FriendCard.decode(pasted) else { error = "That isn't a valid IronLog code."; return }
                    friends.removeAll { $0.id == card.id }
                    friends.append(card)
                    FriendCard.save(friends)
                    pasted = ""
                    error = nil
                }
                .disabled(pasted.isEmpty)
                if let error { Text(error).foregroundStyle(Theme.plateRed).font(.caption) }
            } header: { Text("Add or update friends") } footer: {
                Text("No account or server: send your code, paste theirs. Re-share after a good session to update the board.")
            }
        }
        .navigationTitle("Friends")
    }
}
