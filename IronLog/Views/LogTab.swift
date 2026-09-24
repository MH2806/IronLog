import SwiftUI
import SwiftData

private let mondayCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.firstWeekday = 2
    c.locale = .current
    return c
}()

private func weekStart(_ d: Date) -> Date {
    mondayCalendar.dateInterval(of: .weekOfYear, for: d)?.start ?? mondayCalendar.startOfDay(for: d)
}

struct LogTab: View {
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query private var routines: [Routine]
    @State private var weekOffset = 0
    @State private var selectedDay: Date?
    @State private var limit = 25

    private var done: [Workout] { workouts.filter { $0.endedAt != nil } }
    private var hasActive: Bool { workouts.contains { $0.endedAt == nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("TRAINING LOG").font(.headline).tracking(4).foregroundStyle(Palette.text2)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                    WeekStrip(workouts: done, weekOffset: $weekOffset, selectedDay: $selectedDay)
                    startRow
                    feed
                }
                .padding(.horizontal, 16).padding(.bottom, 90)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var startRow: some View {
        HStack(spacing: 10) {
            Button {
                WorkoutActions.startEmpty(context: context)
                app.showActive = true
            } label: {
                Label("Start workout", systemImage: "plus").font(.subheadline.bold())
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Palette.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(hasActive).opacity(hasActive ? 0.5 : 1)
            if let r = routines.first(where: \.isActive), let day = r.nextDay {
                Button {
                    _ = WorkoutFactory.start(from: day, context: context, history: done, library: library)
                    try? context.save()
                    app.showActive = true
                } label: {
                    VStack(spacing: 1) {
                        Text("Next up").font(.caption2).foregroundStyle(Palette.text2)
                        Text(day.name).font(.subheadline.bold()).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.stroke))
                }
                .buttonStyle(.plain).disabled(hasActive)
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if done.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "dumbbell").font(.largeTitle).foregroundStyle(Palette.blue)
                Text("No workouts yet").font(.headline)
                Text("Start one above, or pick a ready-made workout in Train.").font(.subheadline).foregroundStyle(Palette.text2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let day = selectedDay {
            let list = done.filter { mondayCalendar.isDate($0.startedAt, inSameDayAs: day) }
            SectionTitle(title: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            if list.isEmpty {
                Text("Rest day").foregroundStyle(Palette.text2).frame(maxWidth: .infinity).card()
            }
            ForEach(list) { w in card(w) }
        } else {
            ForEach(groups()) { group in
                SectionTitle(title: group.title)
                ForEach(group.items) { w in card(w) }
            }
            if done.count > limit {
                Button("Show more") { limit += 25 }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func card(_ w: Workout) -> some View {
        NavigationLink { WorkoutDetailView(workout: w) } label: {
            WorkoutCard(workout: w, canRepeat: !hasActive) {
                WorkoutActions.repeatWorkout(w, context: context)
                app.showActive = true
            }
        }
        .buttonStyle(.plain)
    }

    private struct LogGroup: Identifiable {
        var id: String { title }
        let title: String
        var items: [Workout]
    }

    private func groups() -> [LogGroup] {
        let thisWeek = weekStart(.now)
        let lastWeek = mondayCalendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        var out: [LogGroup] = []
        func add(_ title: String, _ w: Workout) {
            if let i = out.firstIndex(where: { $0.title == title }) { out[i].items.append(w) } else { out.append(LogGroup(title: title, items: [w])) }
        }
        for w in done.prefix(limit) {
            if mondayCalendar.isDateInToday(w.startedAt) { add("Today", w) }
            else if w.startedAt >= thisWeek { add("This week", w) }
            else if w.startedAt >= lastWeek { add("Last week", w) }
            else { add(w.startedAt.formatted(.dateTime.month(.wide).year()), w) }
        }
        return out
    }
}

struct WeekStrip: View {
    let workouts: [Workout]
    @Binding var weekOffset: Int
    @Binding var selectedDay: Date?

    var body: some View {
        let start = mondayCalendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart(.now)) ?? .now
        let days = (0..<7).compactMap { mondayCalendar.date(byAdding: .day, value: $0, to: start) }
        let trained = Set(workouts.map { mondayCalendar.startOfDay(for: $0.startedAt) })
        VStack(spacing: 14) {
            HStack {
                Button { weekOffset -= 1; selectedDay = nil } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(title(start)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text2)
                Spacer()
                Button { weekOffset += 1; selectedDay = nil } label: { Image(systemName: "chevron.right") }
                    .disabled(weekOffset >= 0).opacity(weekOffset >= 0 ? 0.3 : 1)
            }
            .font(.headline).foregroundStyle(.white).padding(.horizontal, 12)

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let isSel = selectedDay.map { mondayCalendar.isDate($0, inSameDayAs: d) } ?? false
                    let isToday = mondayCalendar.isDateInToday(d)
                    let future = d > .now
                    Button {
                        guard !future else { return }
                        selectedDay = isSel ? nil : d
                    } label: {
                        VStack(spacing: 8) {
                            Text(d.formatted(.dateTime.weekday(.narrow))).font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.text2)
                            Text(d.formatted(.dateTime.day())).font(.title3.bold())
                                .foregroundStyle(isToday || isSel ? Palette.blue : (future ? Palette.text3 : .white))
                                .frame(width: 42, height: 40)
                                .background {
                                    if isSel || isToday {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.blueSoft)
                                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Palette.blue.opacity(isSel ? 1 : 0.5), lineWidth: isSel ? 2 : 1))
                                    }
                                }
                            Circle().fill(trained.contains(mondayCalendar.startOfDay(for: d)) ? Palette.blue : .clear)
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().overlay(Palette.stroke)
            HStack(spacing: 14) {
                IconTile(icon: "calendar", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    let count = workouts.filter { $0.startedAt >= start && $0.startedAt < start.addingTimeInterval(7 * 86400) }.count
                    Text(selectedDay == nil ? "\(count) workout\(count == 1 ? "" : "s") this week" : "Filtered by day").font(.headline)
                    Text(selectedDay == nil ? "Tap a day to filter the workouts below" : "Tap the day again to clear")
                        .font(.subheadline).foregroundStyle(Palette.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card()
    }

    private func title(_ start: Date) -> String {
        switch weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        default:
            let end = start.addingTimeInterval(6 * 86400)
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}

struct WorkoutCard: View {
    let workout: Workout
    var canRepeat = true
    let onRepeat: () -> Void
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(workout.name.isEmpty ? "Workout" : workout.name).font(.title3.bold()).lineLimit(2)
                Spacer()
                if workout.prCount > 0 { PillBadge(icon: "trophy.fill", text: "\(workout.prCount) PB") }
                Button(action: onRepeat) {
                    Image(systemName: "arrow.clockwise").font(.headline).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.stroke))
                }
                .buttonStyle(.plain).disabled(!canRepeat).opacity(canRepeat ? 1 : 0.4)
            }
            Text("\(dateText) · \(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
            HStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    ForEach(Insights.bodyParts(of: workout, library: library), id: \.self) { Tag(text: $0.label) }
                }
                Spacer()
                HStack(spacing: 3) {
                    Text("\(Int(workout.volume).formatted())").bold()
                    Text("kg ·").foregroundStyle(Palette.text2)
                    Text("\(Insights.totalReps(workout))").bold()
                    Text("reps").foregroundStyle(Palette.text2)
                }
                .font(.subheadline).monospacedDigit()
            }
        }
        .card()
    }

    private var dateText: String {
        let d = workout.startedAt
        return Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Workout detail

struct WorkoutDetailView: View {
    let workout: Workout
    @EnvironmentObject var library: ExerciseLibrary
    @EnvironmentObject var app: AppState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }) private var active: [Workout]
    @State private var confirmDelete = false

    var body: some View {
        let muscles = Set(workout.exercises.flatMap { library.exercise($0.exerciseID)?.primaryMuscles ?? [] })
        let secondary = Set(workout.exercises.flatMap { library.exercise($0.exerciseID)?.secondaryMuscles ?? [] })
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(workout.startedAt.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(Palette.text2)
                    HStack(spacing: 10) {
                        mini("clock", durationText(workout.duration), "Duration")
                        mini("scalemass", workout.volume.compact + " kg", "Volume")
                        mini("repeat", "\(Insights.totalReps(workout))", "Reps")
                        mini("trophy", "\(workout.prCount)", "PBs")
                    }
                }
                HStack(alignment: .center, spacing: 16) {
                    BodyDiagram(spacing: 8, lineWidth: 0.6) { m in
                        muscles.contains(m) ? Palette.blue : (secondary.contains(m) ? Palette.blue.opacity(0.4) : nil)
                    }
                    .frame(height: 170)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Muscles worked").font(.headline)
                        ForEach(Array(muscles).sorted(), id: \.self) { m in
                            Text(MuscleName.display(m)).font(.subheadline).foregroundStyle(Palette.text2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .card()

                ForEach(workout.orderedExercises) { ex in
                    let info = library.exercise(ex.exerciseID)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ExerciseThumb(exercise: info, size: 44)
                            Text(library.name(ex.exerciseID)).font(.headline)
                            Spacer()
                        }
                        ForEach(ex.orderedSets.filter(\.completed)) { s in
                            HStack {
                                Text(s.isWarmup ? "W" : "\(s.order + 1)").font(.subheadline.bold())
                                    .foregroundStyle(s.isWarmup ? Palette.orange : Palette.text2).frame(width: 26)
                                Text(SetRow.summary(s, info?.trackingType ?? .weightReps)).monospacedDigit()
                                if let r = s.rpe { Text("@\(r.clean)").foregroundStyle(Palette.text2) }
                                Spacer()
                                if s.isPR { Image(systemName: "trophy.fill").foregroundStyle(Palette.yellow) }
                                if s.reps > 0 && s.weightKg > 0 {
                                    Text("e1RM \(StrengthMath.epley(s.weightKg, s.reps).clean)").font(.caption).foregroundStyle(Palette.text2)
                                }
                            }
                        }
                    }
                    .card()
                }
                if !workout.notes.isEmpty { Text(workout.notes).card() }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { WorkoutActions.repeatWorkout(workout, context: context); app.showActive = true } label: {
                    Label("Repeat workout", systemImage: "arrow.clockwise")
                }
                .disabled(!active.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(workout)
                try? context.save()
                dismiss()
            }
        }
    }

    private func mini(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(Palette.blue)
            Text(value).font(.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
