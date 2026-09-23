import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }) private var active: [Workout]
    @State private var showActive = false

    var body: some View {
        TabView {
            TodayView(showActive: $showActive)
                .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            RoutinesView(showActive: $showActive)
                .tabItem { Label("Routines", systemImage: "list.bullet.rectangle") }
            ProgressTab()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            NavigationStack { ExerciseLibraryView() }
                .tabItem { Label("Exercises", systemImage: "books.vertical") }
            ToolsView()
                .tabItem { Label("Tools", systemImage: "function") }
        }
        .fullScreenCover(isPresented: $showActive) {
            if let w = active.first {
                ActiveWorkoutView(workout: w)
            } else {
                Color.clear.onAppear { showActive = false }
            }
        }
    }
}

struct TodayView: View {
    @Binding var showActive: Bool
    @Environment(\.modelContext) private var context
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var routines: [Routine]
    @State private var showProfile = false
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.name) private var name = ""

    private var done: [Workout] { workouts.filter { $0.endedAt != nil } }
    private var activeRoutine: Routine? { routines.first(where: \.isActive) }

    var body: some View {
        NavigationStack {
            List {
                if let w = workouts.first(where: { $0.endedAt == nil }) {
                    Section {
                        Button { showActive = true } label: {
                            HStack {
                                Image(systemName: "timer")
                                Text("Resume \(w.name)").bold()
                                Spacer()
                                Text(w.startedAt, style: .timer).monospacedDigit()
                            }
                            .foregroundStyle(.white)
                        }
                        .listRowBackground(Theme.accent)
                    }
                }
                Section {
                    let report = StrengthScoreEngine.report(workouts: done, library: library, profile: .current(measurements))
                    NavigationLink { StrengthScoreView() } label: { ScoreCard(report: report) }
                }

                Section("Next up") {
                    if let r = activeRoutine, let day = r.nextDay {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(day.name).font(.headline)
                            Text(r.name).font(.subheadline).foregroundStyle(.secondary)
                            ForEach(day.orderedExercises) { e in
                                LibraryName(id: e.exerciseID, suffix: e.weightKg > 0 ? "\(e.repText) @ \(e.weightKg.kg)" : e.repText)
                                    .font(.caption)
                            }
                            if day.exercises.contains(where: \.pendingDeload) {
                                Label("Deload suggested for some lifts. Review in Routines.", systemImage: "arrow.down.circle")
                                    .font(.caption).foregroundStyle(Theme.plateRed)
                            }
                        }
                        Button("Start \(day.name)") { start(day) }
                            .disabled(activeWorkoutExists)
                    } else {
                        Text("No active routine. Pick or generate one in Routines.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Start empty workout") { startEmpty() }
                        .disabled(activeWorkoutExists)
                }

                Section("This week") {
                    let week = done.filter { $0.startedAt >= Stats.weekStart(.now) }
                    HStack {
                        StatTile(title: "Workouts", value: "\(week.count)")
                        StatTile(title: "Volume", value: "\(Int(week.reduce(0) { $0 + $1.volume }).formatted()) kg")
                        StatTile(title: "Streak", value: "\(Stats.streakWeeks(done)) wk")
                    }
                }

                Section {
                    ForEach(done.prefix(5)) { w in
                        NavigationLink { WorkoutDetailView(workout: w) } label: { WorkoutRow(workout: w) }
                    }
                    NavigationLink("All workouts") { HistoryView() }
                } header: { Text("Recent") }
            }
            .navigationTitle(name.isEmpty ? "Today" : "Hi, \(name)")
            .toolbar {
                Button { showProfile = true } label: { Image(systemName: "person.crop.circle") }
            }
            .sheet(isPresented: $showProfile) { ProfileView() }
        }
    }

    private var activeWorkoutExists: Bool { workouts.contains { $0.endedAt == nil } }

    private func start(_ day: RoutineDay) {
        _ = WorkoutFactory.start(from: day, context: context, history: done, library: library)
        try? context.save()
        showActive = true
    }

    private func startEmpty() {
        let w = Workout(name: "Workout")
        context.insert(w)
        try? context.save()
        showActive = true
    }
}

struct ScoreCard: View {
    let report: StrengthScoreReport
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Strength Score").font(.subheadline).foregroundStyle(.secondary)
                if let s = report.score, let level = report.level {
                    Text("\(s)").font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.color(level))
                    Text("\(level.name) · \(report.muscles.count) of \(Muscles.all.count) muscle groups scored")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Log lifts for at least 3 muscle groups to get your score")
                        .font(.callout)
                    Text("\(report.muscles.count) of 3 so far").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            BodyMap(report: report, compact: true).frame(width: 90, height: 110)
        }
        .padding(.vertical, 6)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LibraryName: View {
    @EnvironmentObject var library: ExerciseLibrary
    let id: String
    var suffix: String = ""
    var body: some View {
        HStack {
            Text(library.name(id))
            if !suffix.isEmpty { Spacer(); Text(suffix).foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}

struct WorkoutRow: View {
    let workout: Workout
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(workout.name).font(.headline)
                if workout.prCount > 0 {
                    Label("\(workout.prCount)", systemImage: "trophy.fill").font(.caption).foregroundStyle(Theme.plateYellow)
                }
            }
            Text("\(workout.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(durationText(workout.duration)) · \(Int(workout.volume).formatted()) kg")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HistoryView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(workouts) { w in
                NavigationLink { WorkoutDetailView(workout: w) } label: { WorkoutRow(workout: w) }
            }
            .onDelete { idx in
                for i in idx { context.delete(workouts[i]) }
                try? context.save()
            }
        }
        .overlay { if workouts.isEmpty { ContentUnavailableView("No workouts yet", systemImage: "dumbbell") } }
        .navigationTitle("History")
    }
}

struct WorkoutDetailView: View {
    let workout: Workout
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        List {
            Section {
                HStack {
                    StatTile(title: "Duration", value: durationText(workout.duration))
                    StatTile(title: "Volume", value: "\(Int(workout.volume).formatted()) kg")
                    StatTile(title: "PRs", value: "\(workout.prCount)")
                }
            }
            ForEach(workout.orderedExercises) { ex in
                Section(library.name(ex.exerciseID)) {
                    ForEach(ex.orderedSets.filter(\.completed)) { s in
                        HStack {
                            Text(s.isWarmup ? "W" : "\(s.order + 1)").foregroundStyle(.secondary).frame(width: 24)
                            Text(SetRow.summary(s, library.exercise(ex.exerciseID)?.trackingType ?? .weightReps)).monospacedDigit()
                            if let r = s.rpe { Text("@\(r.clean)").foregroundStyle(.secondary) }
                            Spacer()
                            if s.isPR { Image(systemName: "trophy.fill").foregroundStyle(Theme.plateYellow) }
                            if s.reps > 0 && s.weightKg > 0 {
                                Text("e1RM \(StrengthMath.epley(s.weightKg, s.reps).clean)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !workout.notes.isEmpty { Section("Notes") { Text(workout.notes) } }
        }
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
