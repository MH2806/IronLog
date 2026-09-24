import SwiftUI
import SwiftData
import Charts

struct ExerciseDetailView: View {
    let exercise: Exercise
    enum Pane: Hashable { case overview, charts, history }
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @State private var pane: Pane = .overview

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let sessions = Insights.sessions(for: exercise.id, in: workouts, library: library, bodyweight: profile.bodyweight)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                UnderlineTabs(options: [(Pane.overview, "Overview"), (Pane.charts, "Charts"), (Pane.history, "History")], selection: $pane)
                switch pane {
                case .overview: ExerciseOverview(exercise: exercise, sessions: sessions, profile: profile, workouts: workouts)
                case .charts: ExerciseCharts(exercise: exercise, sessions: sessions)
                case .history: ExerciseHistory(exercise: exercise, sessions: sessions)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UnderlineTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].0 == selection
                Button { withAnimation(.snappy) { selection = options[i].0 } } label: {
                    VStack(spacing: 10) {
                        Text(options[i].1).font(.headline).foregroundStyle(on ? .white : Palette.text2)
                        Rectangle().fill(on ? Palette.blue : .clear).frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Overview

struct ExerciseOverview: View {
    let exercise: Exercise
    let sessions: [SessionPoint]
    let profile: ProfileSnapshot
    let workouts: [Workout]
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !exercise.imageURLs.isEmpty {
                TabView {
                    ForEach(exercise.imageURLs, id: \.self) { url in
                        AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(maxWidth: .infinity).background(Color.white)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            if exercise.standard != nil { StandardsCard(exercise: exercise, workouts: workouts, profile: profile) }

            HStack(spacing: 16) {
                BodyDiagram(spacing: 6, lineWidth: 0.6) { m in
                    exercise.primaryMuscles.contains(m) ? Palette.blue : (exercise.secondaryMuscles.contains(m) ? Palette.blue.opacity(0.4) : nil)
                }
                .frame(height: 170)
                VStack(alignment: .leading, spacing: 10) {
                    detail("Primary", exercise.primaryMuscles.map(MuscleName.display).joined(separator: ", "))
                    if !exercise.secondaryMuscles.isEmpty {
                        detail("Secondary", exercise.secondaryMuscles.map(MuscleName.display).joined(separator: ", "))
                    }
                    detail("Equipment", exercise.allEquipment.joined(separator: ", ").capitalized)
                    HStack(spacing: 6) {
                        if let l = exercise.level { Tag(text: l.uppercased()) }
                        if let m = exercise.mechanic { Tag(text: m.uppercased(), color: Palette.purple) }
                    }
                }
                Spacer(minLength: 0)
            }
            .card()

            if !sessions.isEmpty { RecordsCard(exercise: exercise, sessions: sessions) }

            if !exercise.instructions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to").font(.headline)
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(item.offset + 1)").font(.subheadline.bold()).foregroundStyle(Palette.blue)
                                .frame(width: 26, height: 26).background(Palette.blueSoft, in: Circle())
                            Text(item.element).font(.subheadline)
                        }
                    }
                    if let from = exercise.instructionsFrom {
                        Text("Steps and photos are from the closely related \(from); adjust for this variation.")
                            .font(.caption).foregroundStyle(Palette.text2)
                    }
                }
                .card()
            }

            if exercise.isCustom {
                Button("Delete custom exercise", role: .destructive) { library.deleteCustom(exercise.id) }
                    .frame(maxWidth: .infinity).card()
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(Palette.text3)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }
}

struct RecordsCard: View {
    let exercise: Exercise
    let sessions: [SessionPoint]
    var body: some View {
        let sets = sessions.flatMap(\.sets)
        let best = sessions.max { $0.e1rm < $1.e1rm }
        let heaviest = sets.map(\.weightKg).max() ?? 0
        let repRecords: [(Int, Double)] = (1...12).compactMap { r in
            sets.filter { $0.reps >= r }.map(\.weightKg).max().map { (r, $0) }
        }
        VStack(alignment: .leading, spacing: 14) {
            Text("Personal records").font(.headline)
            HStack(spacing: 10) {
                if exercise.trackingType.isRepBased, let best {
                    tile("Best e1RM", best.e1rm.kg)
                    tile("Heaviest", heaviest.kg)
                }
                tile("Sessions", "\(sessions.count)")
            }
            if exercise.trackingType == .weightReps && !repRecords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(repRecords.indices, id: \.self) { i in
                            let r = repRecords[i]
                            VStack(spacing: 2) {
                                Text("\(r.0)RM").font(.caption.weight(.bold)).foregroundStyle(Palette.text2)
                                Text(r.1.clean).font(.subheadline.bold()).monospacedDigit()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
        .card()
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Level floors at the user's bodyweight, with their current rank.
struct StandardsCard: View {
    let exercise: Exercise
    let workouts: [Workout]
    let profile: ProfileSnapshot
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        let bw = profile.bodyweight
        let floors = exercise.standard.flatMap { StrengthStandards.shared?.floors(for: $0, sex: profile.sex, bodyweight: bw) } ?? []
        let mine = StrengthScoreEngine.report(workouts: workouts, library: library, profile: profile)
            .exercises.first { $0.exerciseID == exercise.id }
        VStack(alignment: .leading, spacing: 14) {
            if let mine {
                HStack(spacing: 14) {
                    RankBadge(level: mine.rank.level, tier: mine.rank.tier, size: 56, glow: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mine.rank.name).font(.title3.bold()).foregroundStyle(mine.level.color)
                        Text("\(mine.e1rm.kg) estimated 1RM").font(.subheadline).foregroundStyle(Palette.text2)
                        if let next = mine.rank.next, let np = mine.rank.nextFloorPoints {
                            ProgressLine(fraction: (mine.points - mine.rank.floorPoints) / (np - mine.rank.floorPoints),
                                         color: mine.level.color, height: 6)
                            Text("Next: \(next.name)").font(.caption).foregroundStyle(Palette.text2)
                        }
                    }
                }
                Divider().overlay(Palette.stroke)
            }
            Text("STANDARDS FOR YOU · \(profile.sex.label.uppercased()), \(bw.clean) KG").font(.caption.weight(.bold)).tracking(1.5)
                .foregroundStyle(Palette.text2)
            if floors.count == 5 {
                let top = floors[4] * 1.15
                ForEach(StrengthLevel.allCases, id: \.self) { level in
                    let floor = level == .beginner ? 0 : floors[level.rawValue - 1]
                    HStack(spacing: 10) {
                        RankBadge(level: level, size: 22, dimmed: mine.map { $0.level != level } ?? false)
                        Text(level.name).font(.subheadline.weight(mine?.level == level ? .bold : .medium)).frame(width: 96, alignment: .leading)
                        ProgressLine(fraction: floor / top, color: level.color.opacity(0.8), height: 6)
                        Text(level == .beginner ? "0" : displayed(floor, bw: bw)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .frame(width: 82, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            Text(footer).font(.caption).foregroundStyle(Palette.text2)
        }
        .card()
    }

    private var isTotal: Bool { exercise.trackingType != .weightReps }

    private func displayed(_ total: Double, bw: Double) -> String {
        guard isTotal, let share = exercise.bodyweightShare else { return "\(Progression.roundTo(total, step: 0.5).clean) kg" }
        let own = bw * share
        if exercise.trackingType == .assistedReps {
            return total <= own ? "−\(Progression.roundTo(own - total, step: 0.5).clean) kg" : "no assist"
        }
        if total <= own { return "1 rep" }
        let reps = Int(((total / own) - 1) * 30)
        return total - own < 5 && reps <= 25 ? "\(max(reps, 1)) reps" : "+\(Progression.roundTo(total - own, step: 0.5).clean) kg"
    }

    private var footer: String {
        var t = "Estimated one-rep max needed for each level at your bodyweight."
        if exercise.allEquipment.contains("dumbbell") || exercise.allEquipment.contains("kettlebell") { t += " Dumbbells are per hand." }
        if isTotal { t += " Bodyweight counts toward the load." }
        return t
    }
}

// MARK: - Charts

struct ExerciseCharts: View {
    let exercise: Exercise
    let sessions: [SessionPoint]

    var body: some View {
        if sessions.isEmpty {
            Text("Log this exercise to see charts.").foregroundStyle(Palette.text2).frame(maxWidth: .infinity).card()
        } else {
            VStack(spacing: 16) {
                switch exercise.trackingType {
                case .weightReps, .bodyweightReps, .assistedReps:
                    MetricChart(title: "Max weight progress", unit: "kg", sessions: sessions) { $0.maxWeight }
                    MetricChart(title: "Estimated 1RM progress", unit: "kg", sessions: sessions) { $0.e1rm }
                    MetricChart(title: "Set volume progress", unit: "kg", sessions: sessions) { $0.setVolume }
                    MetricChart(title: "Reps progress", unit: "reps", sessions: sessions) { Double($0.reps) }
                case .duration:
                    MetricChart(title: "Longest hold", unit: "s", sessions: sessions) { Double($0.sets.map(\.durationSec).max() ?? 0) }
                case .cardio:
                    MetricChart(title: "Distance", unit: "km", sessions: sessions) { $0.sets.reduce(0) { $0 + $1.distanceM } / 1000 }
                    MetricChart(title: "Time", unit: "min", sessions: sessions) { Double($0.sets.reduce(0) { $0 + $1.durationSec }) / 60 }
                case .weightDistance:
                    MetricChart(title: "Heaviest carry", unit: "kg", sessions: sessions) { $0.maxWeight }
                }
            }
        }
    }
}

struct MetricChart: View {
    enum Range: Hashable { case m1, m3, m6, all }
    let title: String
    let unit: String
    let sessions: [SessionPoint]
    let value: (SessionPoint) -> Double
    @State private var range: Range = .all

    private struct Pt: Identifiable { let id: Int; let date: Date; let v: Double }

    var body: some View {
        let cutoff: Date? = {
            switch range {
            case .m1: return Calendar.current.date(byAdding: .month, value: -1, to: .now)
            case .m3: return Calendar.current.date(byAdding: .month, value: -3, to: .now)
            case .m6: return Calendar.current.date(byAdding: .month, value: -6, to: .now)
            case .all: return nil
            }
        }()
        let all = sessions.enumerated().map { Pt(id: $0.offset, date: $0.element.date, v: value($0.element)) }
        let pts = all.filter { cutoff == nil || $0.date >= cutoff! }
        let pb = all.max { $0.v < $1.v }
        let current = all.last?.v ?? 0
        let first = all.first?.v ?? 0
        let change = first > 0 ? (current - first) / first * 100 : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased()).font(.footnote.weight(.semibold)).tracking(2.5).foregroundStyle(Palette.text2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(current.clean).font(.system(size: 38, weight: .bold)).monospacedDigit()
                        Text(unit).font(.headline).foregroundStyle(Palette.text2)
                    }
                }
                Spacer()
                if let pb {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Personal best").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text2)
                        Text(pb.v.clean).font(.title.bold()).foregroundStyle(Palette.green)
                    }
                }
            }
            if all.count > 1 && abs(change) >= 0.5 {
                Label("\(Int(abs(change).rounded()))%  vs first record", systemImage: change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(change >= 0 ? Palette.green : Palette.red)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background((change >= 0 ? Palette.green : Palette.red).opacity(0.14), in: Capsule())
            }
            HStack(spacing: 6) {
                rangeButton(.m1, "1M")
                rangeButton(.m3, "3M")
                rangeButton(.m6, "6M")
                rangeButton(.all, "All")
            }
            if pts.count > 1 {
                Chart {
                    ForEach(pts) { p in
                        AreaMark(x: .value("Date", p.date), y: .value(unit, p.v))
                            .foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.35), Palette.blue.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", p.date), y: .value(unit, p.v))
                            .foregroundStyle(Palette.blue).interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    if let pb, pts.contains(where: { $0.id == pb.id }) {
                        PointMark(x: .value("Date", pb.date), y: .value(unit, pb.v))
                            .foregroundStyle(Palette.green).symbolSize(110)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
            } else {
                Text("Not enough sessions in this range.").font(.subheadline).foregroundStyle(Palette.text2)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .card()
    }

    private func rangeButton(_ r: Range, _ label: String) -> some View {
        Button { withAnimation { range = r } } label: {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(range == r ? .white : Palette.text2)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(range == r ? Palette.cardHi : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History

struct ExerciseHistory: View {
    let exercise: Exercise
    let sessions: [SessionPoint]
    var body: some View {
        if sessions.isEmpty {
            Text("No history yet.").foregroundStyle(Palette.text2).frame(maxWidth: .infinity).card()
        } else {
            VStack(spacing: 12) {
                ForEach(sessions.reversed()) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())).font(.headline)
                                Text(s.workoutName).font(.caption).foregroundStyle(Palette.text2)
                            }
                            Spacer()
                            if exercise.trackingType.isRepBased {
                                Text("e1RM \(s.e1rm.clean)").font(.subheadline.bold()).foregroundStyle(Palette.blue)
                            }
                        }
                        ForEach(s.sets) { set in
                            HStack {
                                Text("\(set.order + 1)").font(.subheadline.bold()).foregroundStyle(Palette.text2).frame(width: 24)
                                Text(SetRow.summary(set, exercise.trackingType)).monospacedDigit()
                                Spacer()
                                if set.isPR { Image(systemName: "trophy.fill").foregroundStyle(Palette.yellow) }
                            }
                            .font(.subheadline)
                        }
                    }
                    .card(padding: 14, radius: 20)
                }
            }
        }
    }
}
