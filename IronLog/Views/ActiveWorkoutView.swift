import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Bindable var workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var restTimer: RestTimer
    @Query(sort: \Workout.startedAt, order: .reverse) private var allWorkouts: [Workout]
    @Query private var routines: [Routine]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.defaultRest) private var defaultRest = 0

    @State private var showPicker = false
    @State private var prMessage: String?
    @State private var confirmDiscard = false
    @State private var confirmFinish = false

    private var history: [Workout] { allWorkouts.filter { $0.endedAt != nil && $0.id != workout.id } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: $workout.name).font(.title3.bold())
                    HStack {
                        Label { Text(workout.startedAt, style: .timer).monospacedDigit() } icon: { Image(systemName: "clock") }
                        Spacer()
                        Text("\(Int(workout.volume).formatted()) kg").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                ForEach(workout.orderedExercises) { ex in
                    ExerciseCard(exercise: ex, history: history, onComplete: completed(_:in:), onRemove: { remove(ex) })
                }
                Section {
                    Button { showPicker = true } label: { Label("Add exercise", systemImage: "plus") }
                    TextField("Notes", text: $workout.notes, axis: .vertical)
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { if restTimer.isRunning { RestTimerBar() } }
            .overlay(alignment: .top) {
                if let msg = prMessage {
                    Label(msg, systemImage: "trophy.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.plateYellow, in: Capsule())
                        .foregroundStyle(.black)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 4)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Finish workout") { confirmFinish = true }
                        Button("Discard workout", role: .destructive) { confirmDiscard = true }
                    } label: { Text("Finish").bold() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePicker { picked in
                    for e in picked { WorkoutFactory.addExercise(e, to: workout, history: history, defaultRest: defaultRest) }
                    try? context.save()
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    restTimer.stop()
                    context.delete(workout)
                    try? context.save()
                    dismiss()
                }
            }
            .confirmationDialog("Finish workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Finish and save") { finish() }
            } message: {
                Text("Sets you haven't ticked will be removed.")
            }
        }
    }

    private func completed(_ set: SetEntry, in ex: WorkoutExercise) {
        if set.completed {
            set.completedAt = .now
            if let msg = PRDetector.check(set, exercise: library.exercise(ex.exerciseID), exerciseID: ex.exerciseID,
                                          workouts: history, bodyweight: ProfileSnapshot.current(measurements).bodyweight) {
                set.isPR = true
                Haptics.success()
                withAnimation { prMessage = msg }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { prMessage = nil } }
            } else {
                Haptics.tap()
            }
            restTimer.start(seconds: ex.restSeconds, label: library.name(ex.exerciseID))
        } else {
            set.isPR = false
            set.completedAt = nil
        }
        try? context.save()
    }

    private func remove(_ ex: WorkoutExercise) {
        workout.exercises.removeAll { $0.id == ex.id }
        context.delete(ex)
        try? context.save()
    }

    private func finish() {
        for ex in workout.exercises {
            for s in ex.sets where !s.completed { context.delete(s) }
            ex.sets.removeAll { !$0.completed }
            if ex.sets.isEmpty { context.delete(ex) }
        }
        workout.exercises.removeAll { $0.sets.isEmpty }
        workout.endedAt = .now
        if let dayID = workout.routineDayID,
           let routine = routines.first(where: { $0.days.contains { $0.id == dayID } }) {
            Progression.apply(workout: workout, routine: routine)
        }
        try? context.save()
        restTimer.stop()
        let w = workout
        Task { await HealthSync.save(workout: w) }
        dismiss()
    }
}

struct ExerciseCard: View {
    @Bindable var exercise: WorkoutExercise
    let history: [Workout]
    let onComplete: (SetEntry, WorkoutExercise) -> Void
    let onRemove: () -> Void
    @EnvironmentObject var library: ExerciseLibrary
    @Environment(\.modelContext) private var context

    var body: some View {
        let previous = Stats.lastSets(for: exercise.exerciseID, in: history)
        let tracking = library.exercise(exercise.exerciseID)?.trackingType ?? .weightReps
        let cols = SetRow.columns(tracking)
        Section {
            HStack(spacing: 8) {
                Text("Set").frame(width: 30)
                Text("Previous").frame(maxWidth: .infinity, alignment: .leading)
                Text(cols.0).frame(width: 64)
                Text(cols.1).frame(width: 48)
                Image(systemName: "checkmark").frame(width: 34)
            }
            .font(.caption).foregroundStyle(.secondary)

            ForEach(exercise.orderedSets) { s in
                let idx = exercise.orderedSets.firstIndex { $0.id == s.id } ?? 0
                SetRow(set: s, tracking: tracking, label: s.isWarmup ? "W" : "\(workingNumber(s))",
                       previous: idx < previous.count ? previous[idx] : nil) { onComplete(s, exercise) }
                    .swipeActions {
                        Button(role: .destructive) {
                            exercise.sets.removeAll { $0.id == s.id }
                            context.delete(s)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button { s.isWarmup.toggle() } label: { Label("Warm-up", systemImage: "flame") }.tint(.orange)
                    }
            }

            Button {
                let last = exercise.orderedSets.last
                let set = SetEntry(order: (last?.order ?? -1) + 1, weightKg: last?.weightKg ?? 0,
                                   reps: last?.reps ?? (tracking.isRepBased ? 8 : 0))
                set.durationSec = last?.durationSec ?? 0
                set.distanceM = last?.distanceM ?? 0
                exercise.sets.append(set)
            } label: { Label("Add set", systemImage: "plus.circle") }
        } header: {
            HStack {
                NavigationLink {
                    if let info = library.exercise(exercise.exerciseID) { ExerciseDetailView(exercise: info) }
                } label: {
                    Text(library.name(exercise.exerciseID)).font(.headline).foregroundStyle(Theme.accent).textCase(nil)
                }
                Spacer()
                Menu {
                    Picker("Rest", selection: $exercise.restSeconds) {
                        ForEach([0, 60, 90, 120, 150, 180, 240, 300], id: \.self) { s in
                            Text(s == 0 ? "Off" : "\(s / 60):\(String(format: "%02d", s % 60))").tag(s)
                        }
                    }
                    Button("Remove exercise", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body)
                }
            }
        }
    }

    private func workingNumber(_ s: SetEntry) -> Int {
        (exercise.orderedSets.filter { !$0.isWarmup }.firstIndex { $0.id == s.id } ?? 0) + 1
    }
}

struct SetRow: View {
    @Bindable var set: SetEntry
    let tracking: Tracking
    let label: String
    let previous: SetEntry?
    let onToggle: () -> Void

    static func columns(_ t: Tracking) -> (String, String) {
        switch t {
        case .weightReps: return ("kg", "Reps")
        case .bodyweightReps: return ("+kg", "Reps")
        case .assistedReps: return ("−kg", "Reps")
        case .duration: return ("+kg", "Sec")
        case .cardio: return ("Min", "Km")
        case .weightDistance: return ("kg", "Metres")
        }
    }

    static func summary(_ s: SetEntry, _ t: Tracking) -> String {
        switch t {
        case .weightReps: return "\(s.weightKg.clean) × \(s.reps)"
        case .bodyweightReps: return s.weightKg > 0 ? "+\(s.weightKg.clean) × \(s.reps)" : "\(s.reps) reps"
        case .assistedReps: return "−\(s.weightKg.clean) × \(s.reps)"
        case .duration: return s.weightKg > 0 ? "+\(s.weightKg.clean) · \(s.durationSec)s" : "\(s.durationSec)s"
        case .cardio: return "\(s.durationSec / 60) min · \((s.distanceM / 1000).clean) km"
        case .weightDistance: return "\(s.weightKg.clean) · \(Int(s.distanceM)) m"
        }
    }

    private var firstField: Binding<Double> {
        switch tracking {
        case .cardio:
            return Binding(get: { Double(set.durationSec) / 60 }, set: { set.durationSec = Int(($0 * 60).rounded()) })
        default:
            return $set.weightKg
        }
    }

    private var secondField: Binding<Double> {
        switch tracking {
        case .duration:
            return Binding(get: { Double(set.durationSec) }, set: { set.durationSec = max(0, Int($0)) })
        case .cardio:
            return Binding(get: { set.distanceM / 1000 }, set: { set.distanceM = max(0, $0 * 1000) })
        case .weightDistance:
            return $set.distanceM
        default:
            return Binding(get: { Double(set.reps) }, set: { set.reps = max(0, Int($0)) })
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 30).foregroundStyle(set.isWarmup ? .orange : .primary)
            Group {
                if let p = previous { Text(Self.summary(p, tracking)) } else { Text("–") }
            }
            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1).minimumScaleFactor(0.7)
            TextField("0", value: firstField, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.center)
                .frame(width: 64).padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            TextField("0", value: secondField, format: .number)
                .keyboardType(tracking == .cardio ? .decimalPad : .numberPad).multilineTextAlignment(.center)
                .frame(width: 48).padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            Button {
                set.completed.toggle()
                onToggle()
            } label: {
                Image(systemName: set.completed ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(set.completed ? Theme.plateGreen : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 34)
            if set.isPR { Image(systemName: "trophy.fill").foregroundStyle(Theme.plateYellow).font(.caption) }
        }
        .listRowBackground(set.completed ? Theme.plateGreen.opacity(0.12) : nil)
    }
}

struct RestTimerBar: View {
    @EnvironmentObject var restTimer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = max(0, (restTimer.endDate ?? ctx.date).timeIntervalSince(ctx.date))
            let frac = restTimer.total > 0 ? remaining / restTimer.total : 0
            HStack(spacing: 14) {
                Button { restTimer.add(-15) } label: { Text("−15") }
                VStack(spacing: 4) {
                    Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                        .font(.title2.bold()).monospacedDigit()
                    ProgressView(value: frac).tint(.white)
                }
                Button { restTimer.add(15) } label: { Text("+15") }
                Button { restTimer.stop() } label: { Image(systemName: "xmark") }
            }
            .buttonStyle(.bordered).tint(.white)
            .padding()
            .foregroundStyle(.white)
            .background(Theme.accent)
        }
    }
}
