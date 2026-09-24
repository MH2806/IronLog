import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject var app: AppState
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }) private var active: [Workout]

    var body: some View {
        TabView(selection: $app.tab) {
            LogTab().tag(AppTab.log)
                .tabItem { Label("Log", systemImage: "house") }
            TrainTab().tag(AppTab.train)
                .tabItem { Label("Train", systemImage: "dumbbell") }
            ProgressTab().tag(AppTab.progress)
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            CommunityTab().tag(AppTab.community)
                .tabItem { Label("Community", systemImage: "person.3") }
            ProfileTab().tag(AppTab.profile)
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .overlay(alignment: .bottom) {
            if let w = active.first, !app.showActive {
                ActiveWorkoutBanner(workout: w) { app.showActive = true }
                    .padding(.horizontal, 12).padding(.bottom, 56)
            }
        }
        .fullScreenCover(isPresented: $app.showActive) {
            if let w = active.first {
                ActiveWorkoutView(workout: w)
            } else {
                Color.clear.onAppear { app.showActive = false }
            }
        }
        .onAppear {
            let tab = UITabBarAppearance()
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = UIColor(Palette.bg)
            UITabBar.appearance().standardAppearance = tab
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
    }
}

struct ActiveWorkoutBanner: View {
    let workout: Workout
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.name.isEmpty ? "Workout" : workout.name).font(.subheadline.bold())
                    Text("\(workout.workingSets.count) sets done").font(.caption).opacity(0.8)
                }
                Spacer()
                Text(workout.startedAt, style: .timer).font(.headline.monospacedDigit())
                Image(systemName: "chevron.up")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Palette.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout helpers

enum WorkoutActions {
    /// Starts a new workout copying another one's exercises and sets.
    static func repeatWorkout(_ source: Workout, context: ModelContext) {
        let w = Workout(name: source.name)
        context.insert(w)
        for ex in source.orderedExercises {
            let we = WorkoutExercise(exerciseID: ex.exerciseID, order: ex.order, restSeconds: ex.restSeconds)
            w.exercises.append(we)
            for s in ex.orderedSets where s.completed {
                let set = SetEntry(order: s.order, weightKg: s.weightKg, reps: s.reps, isWarmup: s.isWarmup)
                set.durationSec = s.durationSec
                set.distanceM = s.distanceM
                we.sets.append(set)
            }
        }
        try? context.save()
    }

    static func startEmpty(context: ModelContext) {
        context.insert(Workout(name: "Quick Workout"))
        try? context.save()
    }
}

struct LibraryName: View {
    let id: String
    @EnvironmentObject var library: ExerciseLibrary
    var suffix: String = ""
    var body: some View {
        HStack {
            Text(library.name(id))
            if !suffix.isEmpty { Spacer(); Text(suffix).foregroundStyle(Palette.text2).monospacedDigit() }
        }
    }
}

struct ExerciseThumb: View {
    let exercise: Exercise?
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let url = exercise?.imageURLs.first {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.9) }
            } else {
                Image(systemName: "dumbbell.fill").foregroundStyle(Palette.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.blueSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
