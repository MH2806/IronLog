import SwiftUI
import SwiftData

// MARK: - Ready-made workouts

struct TemplateItem {
    let id: String
    let sets: Int
    let reps: Int
}

struct WorkoutTemplate: Identifiable {
    var id: String { name }
    let name: String
    let categories: [String]
    let muscles: String
    let level: String
    let items: [TemplateItem]
    var minutes: Int { Int((Double(items.reduce(0) { $0 + $1.sets }) * 2.4 + 5).rounded() / 5) * 5 }
}

private func t(_ id: String, _ sets: Int, _ reps: Int) -> TemplateItem { TemplateItem(id: id, sets: sets, reps: reps) }

enum WorkoutLibrary {
    static let categories = ["All", "Push", "Pull", "Legs", "Upper", "Lower", "Full body", "Arms", "Shoulders", "Core"]

    static let all: [WorkoutTemplate] = [
        WorkoutTemplate(name: "Push Basics", categories: ["Push", "Upper"], muscles: "chest · shoulders · triceps", level: "Beginner",
                        items: [t("barbell-bench-press", 3, 8), t("dumbbell-shoulder-press", 3, 10), t("incline-dumbbell-press", 3, 10),
                                t("dumbbell-lateral-raise", 3, 12), t("rope-pushdown", 3, 12)]),
        WorkoutTemplate(name: "Push Day", categories: ["Push", "Upper"], muscles: "chest · shoulders · triceps", level: "Intermediate",
                        items: [t("barbell-bench-press", 4, 6), t("military-press", 3, 8), t("incline-dumbbell-press", 3, 10),
                                t("cable-lateral-raise", 3, 15), t("dips", 3, 10), t("rope-overhead-tricep-extension", 3, 12)]),
        WorkoutTemplate(name: "Chest-Focused Push", categories: ["Push"], muscles: "chest", level: "Intermediate",
                        items: [t("barbell-bench-press", 4, 6), t("incline-bench-press", 3, 8), t("dumbbell-fly", 3, 12),
                                t("cable-crossover", 3, 15), t("dips", 3, 10), t("bar-pushdown", 3, 12)]),
        WorkoutTemplate(name: "Pull Basics", categories: ["Pull", "Upper"], muscles: "back · lats · biceps", level: "Beginner",
                        items: [t("pulldown", 3, 10), t("cable-row", 3, 10), t("dumbbell-row", 3, 10), t("face-pull", 3, 15),
                                t("dumbbell-bicep-curl", 3, 12)]),
        WorkoutTemplate(name: "Pull Day", categories: ["Pull", "Upper"], muscles: "back · lats · biceps", level: "Intermediate",
                        items: [t("deadlift", 3, 5), t("pull-up", 3, 8), t("barbell-row", 3, 8), t("face-pull", 3, 15),
                                t("barbell-bicep-curl", 3, 10), t("hammer-curl", 3, 12)]),
        WorkoutTemplate(name: "Back Width", categories: ["Pull"], muscles: "lats · upper back · traps", level: "Intermediate",
                        items: [t("wide-grip-pull-up", 4, 8), t("neutral-grip-pulldown", 3, 10), t("single-arm-lat-pulldown", 3, 12),
                                t("rope-pullover", 3, 12), t("seated-row-machine", 3, 10), t("dumbbell-shrug", 3, 12)]),
        WorkoutTemplate(name: "Leg Basics", categories: ["Legs", "Lower"], muscles: "quads · hamstrings · calves", level: "Beginner",
                        items: [t("goblet-squat", 3, 10), t("dumbbell-rdl", 3, 10), t("leg-press", 3, 12), t("lying-leg-curl", 3, 12),
                                t("standing-machine-calf-raise", 3, 15)]),
        WorkoutTemplate(name: "Leg Day", categories: ["Legs", "Lower"], muscles: "quads · hamstrings · glutes · calves", level: "Intermediate",
                        items: [t("barbell-back-squat", 4, 6), t("barbell-rdl", 3, 8), t("leg-press", 3, 10), t("leg-extension", 3, 12),
                                t("lying-leg-curl", 3, 12), t("standing-machine-calf-raise", 4, 12)]),
        WorkoutTemplate(name: "Glutes & Hamstrings", categories: ["Legs", "Lower"], muscles: "glutes · hamstrings", level: "Intermediate",
                        items: [t("hip-thrust", 4, 8), t("barbell-rdl", 3, 8), t("bulgarian-split-squat", 3, 10), t("lying-leg-curl", 3, 12),
                                t("cable-glute-kickback", 3, 15), t("hip-abductor", 3, 15)]),
        WorkoutTemplate(name: "Upper Body", categories: ["Upper"], muscles: "chest · back · shoulders · arms", level: "Intermediate",
                        items: [t("barbell-bench-press", 4, 6), t("barbell-row", 4, 8), t("dumbbell-shoulder-press", 3, 10),
                                t("pulldown", 3, 10), t("ez-bar-curl", 3, 12), t("rope-pushdown", 3, 12)]),
        WorkoutTemplate(name: "Lower Body", categories: ["Lower", "Legs"], muscles: "quads · hamstrings · calves · core", level: "Intermediate",
                        items: [t("barbell-back-squat", 4, 6), t("barbell-rdl", 3, 8), t("dumbbell-walking-lunge", 3, 10),
                                t("leg-curl", 3, 12), t("calf-raises", 4, 12), t("cable-crunch", 3, 15)]),
        WorkoutTemplate(name: "Full Body Starter", categories: ["Full body"], muscles: "whole body", level: "Beginner",
                        items: [t("goblet-squat", 3, 10), t("dumbbell-press", 3, 10), t("dumbbell-row", 3, 10), t("dumbbell-rdl", 3, 10),
                                t("plank", 3, 0)]),
        WorkoutTemplate(name: "Full Body Strength", categories: ["Full body"], muscles: "whole body", level: "Advanced",
                        items: [t("barbell-back-squat", 5, 5), t("barbell-bench-press", 5, 5), t("barbell-row", 5, 5),
                                t("military-press", 3, 5), t("deadlift", 1, 5)]),
        WorkoutTemplate(name: "Bodyweight Anywhere", categories: ["Full body"], muscles: "whole body", level: "Beginner",
                        items: [t("push-up", 3, 15), t("lunge", 3, 12), t("pull-up", 3, 6), t("bodyweight-glute-bridge", 3, 15),
                                t("pike-push-up", 3, 8), t("plank", 3, 0)]),
        WorkoutTemplate(name: "Arm Day", categories: ["Arms", "Upper"], muscles: "biceps · triceps · forearms", level: "Intermediate",
                        items: [t("close-grip-bench-press", 3, 8), t("barbell-bicep-curl", 3, 10), t("rope-pushdown", 3, 12),
                                t("incline-dumbbell-curl", 3, 12), t("rope-overhead-tricep-extension", 3, 12), t("hammer-curl", 3, 12),
                                t("barbell-wrist-curl", 2, 15)]),
        WorkoutTemplate(name: "Shoulder Sculpt", categories: ["Shoulders", "Upper"], muscles: "shoulders · traps", level: "Intermediate",
                        items: [t("military-press", 4, 6), t("dumbbell-lateral-raise", 4, 15), t("face-pull", 3, 15),
                                t("arnold-press", 3, 10), t("dumbbell-rear-delt-fly", 3, 15), t("barbell-shrug", 3, 12)]),
        WorkoutTemplate(name: "Core Crusher", categories: ["Core"], muscles: "abs", level: "Beginner",
                        items: [t("cable-crunch", 3, 15), t("hanging-knee-raise", 3, 12), t("plank", 3, 0), t("russian-twist", 3, 20),
                                t("wheel-rollout", 3, 10)]),
    ]

    /// Primary muscles a template trains.
    static func muscles(_ tpl: WorkoutTemplate, library: ExerciseLibrary) -> Set<String> {
        Set(tpl.items.flatMap { library.exercise($0.id)?.primaryMuscles ?? [] })
    }

    static func start(_ tpl: WorkoutTemplate, context: ModelContext, history: [Workout], library: ExerciseLibrary) {
        let w = Workout(name: tpl.name)
        context.insert(w)
        for (i, item) in tpl.items.enumerated() {
            guard let info = library.exercise(item.id) else { continue }
            let we = WorkoutExercise(exerciseID: item.id, order: i, restSeconds: info.defaultRest)
            w.exercises.append(we)
            let last = Stats.lastSets(for: item.id, in: history).first { !$0.isWarmup }
            for n in 0..<item.sets {
                let set = SetEntry(order: n, weightKg: last?.weightKg ?? 0, reps: info.trackingType.isRepBased ? item.reps : 0)
                switch info.trackingType {
                case .duration: set.durationSec = last?.durationSec ?? 45
                case .cardio: set.durationSec = last?.durationSec ?? 1200
                case .weightDistance: set.distanceM = last?.distanceM ?? 40
                default: break
                }
                we.sets.append(set)
            }
        }
        try? context.save()
    }
}

// MARK: - Train tab

struct TrainTab: View {
    enum Pane: Hashable { case workouts, routines, coach }
    @State private var section: Pane = .workouts
    @State private var showGenerator = false
    @State private var showNewMenu = false
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Train", subtitle: "Saved sessions and ready-made workouts") {
                        SquareIconButton(icon: "plus") { showNewMenu = true }
                    }
                    PillTabs(options: [(Pane.workouts, "Workouts"), (Pane.routines, "Routines"), (Pane.coach, "Coach")], selection: $section)
                    switch section {
                    case .workouts: WorkoutsSection()
                    case .routines: RoutinesSection()
                    case .coach: CoachSection(showGenerator: $showGenerator)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 90)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showGenerator) { RoutineGeneratorView() }
            .confirmationDialog("Create", isPresented: $showNewMenu) {
                Button("Build a plan for me") { showGenerator = true }
                Button("Empty routine") {
                    let r = Routine(name: "My routine")
                    context.insert(r)
                    r.days.append(RoutineDay(name: "Day 1", order: 0))
                    try? context.save()
                    section = .routines
                }
            }
        }
    }
}

struct WorkoutsSection: View {
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var category = "All"
    @State private var showAllSaved = false

    private var hasActive: Bool { workouts.contains { $0.endedAt == nil } }

    var body: some View {
        let days = routines.flatMap(\.orderedDays)
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Your workouts", action: days.count > 3 ? (showAllSaved ? "Less" : "View All") : nil) {
                showAllSaved.toggle()
            }
            if days.isEmpty {
                Text("Workouts you save in a routine show up here. Tap + to build one.")
                    .font(.subheadline).foregroundStyle(Palette.text2).card()
            }
            ForEach(showAllSaved ? days : Array(days.prefix(3))) { day in
                NavigationLink {
                    if let r = day.routine { RoutineDetailView(routine: r, showActive: $app.showActive) }
                } label: {
                    HStack(spacing: 14) {
                        IconTile(icon: "bookmark", size: 50)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.name).font(.headline)
                            Text("\(day.exercises.count) exercises · \(day.routine?.name ?? "")").font(.subheadline).foregroundStyle(Palette.text2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.text2)
                    }
                    .card(padding: 14)
                }
                .buttonStyle(.plain)
            }

            SectionTitle(title: "Workout library")
            ChipBar(options: WorkoutLibrary.categories.map { ($0, $0) }, selection: $category)
            ForEach(WorkoutLibrary.all.filter { category == "All" || $0.categories.contains(category) }) { tpl in
                NavigationLink { TemplateDetailView(template: tpl) } label: {
                    TemplateCard(template: tpl, disabled: hasActive) {
                        WorkoutLibrary.start(tpl, context: context, history: workouts.filter { $0.endedAt != nil }, library: library)
                        app.showActive = true
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TemplateCard: View {
    let template: WorkoutTemplate
    var disabled = false
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(template.name).font(.title3.bold())
                Text(template.muscles).font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
                HStack(spacing: 8) {
                    Tag(text: "\(template.items.count) EXERCISES")
                    Tag(text: "~\(template.minutes) MIN")
                    Tag(text: template.level.uppercased(), color: levelColor)
                }
            }
            Spacer(minLength: 4)
            Button(action: onStart) {
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(Palette.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
        }
        .card()
    }

    private var levelColor: Color {
        switch template.level {
        case "Beginner": return Palette.green
        case "Advanced": return Palette.orange
        default: return Palette.blue
        }
    }
}

struct TemplateDetailView: View {
    let template: WorkoutTemplate
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]

    var body: some View {
        let muscles = WorkoutLibrary.muscles(template, library: library)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    BodyDiagram(spacing: 6, lineWidth: 0.6) { muscles.contains($0) ? Palette.blue : nil }.frame(height: 160)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(template.muscles.capitalized).font(.headline)
                        Text("\(template.items.count) exercises · ~\(template.minutes) min").foregroundStyle(Palette.text2)
                        Tag(text: template.level.uppercased())
                    }
                }
                .card()
                ForEach(template.items.indices, id: \.self) { i in
                    let item = template.items[i]
                    let info = library.exercise(item.id)
                    NavigationLink { if let info { ExerciseDetailView(exercise: info) } } label: {
                        HStack(spacing: 12) {
                            ExerciseThumb(exercise: info, size: 50)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info?.name ?? item.id).font(.headline)
                                Text(info?.trackingType == .duration ? "\(item.sets) sets · timed" : "\(item.sets) × \(item.reps)")
                                    .font(.subheadline).foregroundStyle(Palette.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    WorkoutLibrary.start(template, context: context, history: workouts.filter { $0.endedAt != nil }, library: library)
                    app.showActive = true
                } label: {
                    Label("Start workout", systemImage: "play.fill").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Palette.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(workouts.contains { $0.endedAt == nil })
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RoutinesSection: View {
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.createdAt, order: .reverse) private var routines: [Routine]
    @State private var toDelete: Routine?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Your routines")
            if routines.isEmpty {
                Text("No routines yet. Add a proven template below or build one in Coach.").font(.subheadline)
                    .foregroundStyle(Palette.text2).card()
            }
            ForEach(routines) { r in
                NavigationLink { RoutineDetailView(routine: r, showActive: $app.showActive) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(r.name).font(.title3.bold())
                            Spacer()
                            if r.isActive { Tag(text: "ACTIVE", color: Palette.green) }
                        }
                        Text("\(r.days.count) days · next: \(r.nextDay?.name ?? "–")").font(.subheadline).foregroundStyle(Palette.text2)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(r.orderedDays) { d in
                                    Text(d.name).font(.caption.bold())
                                        .foregroundStyle(r.nextDay?.id == d.id ? Palette.blue : Palette.text2)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(r.nextDay?.id == d.id ? Palette.blueSoft : Palette.cardHi, in: Capsule())
                                }
                            }
                        }
                    }
                    .card()
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { toDelete = r } label: { Label("Delete routine", systemImage: "trash") }
                }
            }

            SectionTitle(title: "Proven templates")
            template("Beginner full body", "3 days a week", .strength, 3, .gym, .beginner)
            template("Upper / lower", "4 days a week", .strength, 4, .gym, .intermediate)
            template("Push / pull / legs", "6 days a week", .hypertrophy, 6, .gym, .intermediate)
            template("Dumbbell full body", "3 days, dumbbells only", .general, 3, .dumbbells, .beginner)
        }
        .confirmationDialog("Delete \(toDelete?.name ?? "routine")?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = toDelete { context.delete(r); try? context.save() }
                toDelete = nil
            }
        }
    }

    private func template(_ title: String, _ sub: String, _ goal: Goal, _ days: Int, _ eq: Equipment, _ exp: Experience) -> some View {
        Button {
            var plan = RoutineGenerator.generate(goal: goal, days: days, equipment: eq, experience: exp)
            plan.name = title
            plan.insert(into: context, library: library, activate: routines.allSatisfy { !$0.isActive })
            try? context.save()
        } label: {
            HStack(spacing: 14) {
                IconTile(icon: "calendar.badge.plus", color: Palette.purple, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(sub).font(.subheadline).foregroundStyle(Palette.text2)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Palette.blue)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }
}

struct CoachSection: View {
    @Binding var showGenerator: Bool
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var routines: [Routine]

    var body: some View {
        let rec = Insights.recovery(workouts, library: library, sleep: nil, restingHR: nil)
        let readiness = Dictionary(uniqueKeysWithValues: rec.muscles.map { ($0.muscle, $0.recovery) })
        let suggestion = WorkoutLibrary.all.max { score($0, readiness) < score($1, readiness) }
        let hasActive = workouts.contains { $0.endedAt == nil }
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink { RecoveryView() } label: {
                HStack(spacing: 16) {
                    RingGauge(progress: Double(rec.score) / 100, color: color(rec.score), lineWidth: 7) {
                        Text("\(rec.score)").font(.title2.bold())
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.headline).font(.headline)
                        Text("\(rec.ready.count) muscle groups ready · \(rec.recovering.count) recovering")
                            .font(.subheadline).foregroundStyle(Palette.text2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
                }
                .card()
            }
            .buttonStyle(.plain)

            if let s = suggestion {
                SectionTitle(title: "Suggested for today")
                NavigationLink { TemplateDetailView(template: s) } label: {
                    TemplateCard(template: s, disabled: hasActive) {
                        WorkoutLibrary.start(s, context: context, history: workouts.filter { $0.endedAt != nil }, library: library)
                        app.showActive = true
                    }
                }
                .buttonStyle(.plain)
                Text("Picked because it trains the muscles that have recovered most.").font(.caption).foregroundStyle(Palette.text2)
            }

            if let r = routines.first(where: \.isActive), let day = r.nextDay {
                SectionTitle(title: "Next in \(r.name)")
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.name).font(.title3.bold())
                    ForEach(day.orderedExercises) { e in
                        LibraryName(id: e.exerciseID, suffix: e.weightKg > 0 ? "\(e.repText) @ \(e.weightKg.kg)" : e.repText)
                            .font(.subheadline)
                    }
                    Button {
                        _ = WorkoutFactory.start(from: day, context: context, history: workouts.filter { $0.endedAt != nil }, library: library)
                        try? context.save()
                        app.showActive = true
                    } label: {
                        Label("Start \(day.name)", systemImage: "play.fill").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Palette.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(hasActive).padding(.top, 4)
                }
                .card()
            }

            SectionTitle(title: "Plan builder")
            Button { showGenerator = true } label: {
                HStack(spacing: 14) {
                    IconTile(icon: "sparkles", color: Palette.purple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build a plan for me").font(.headline)
                        Text("Goal, days, equipment and experience. Optional Claude-generated plans.").font(.subheadline)
                            .foregroundStyle(Palette.text2)
                    }
                    Spacer()
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private func score(_ tpl: WorkoutTemplate, _ readiness: [String: Double]) -> Double {
        let m = WorkoutLibrary.muscles(tpl, library: library)
        guard !m.isEmpty else { return 0 }
        let avg = m.map { readiness[$0] ?? 1 }.reduce(0, +) / Double(m.count)
        let worst = m.map { readiness[$0] ?? 1 }.min() ?? 1
        return avg * 0.6 + worst * 0.4 + (tpl.level == "Intermediate" ? 0.01 : 0)
    }

    private func color(_ s: Int) -> Color { s >= 80 ? Palette.green : (s >= 60 ? Palette.yellow : Palette.orange) }
}
