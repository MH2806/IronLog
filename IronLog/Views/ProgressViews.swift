import SwiftUI
import SwiftData
import Charts

struct ProgressTab: View {
    @State private var page = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $page) {
                    Text("Strength").tag(0)
                    Text("Training").tag(1)
                    Text("Muscles").tag(2)
                    Text("Body").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.bottom, 6)
                switch page {
                case 0: StrengthScoreView()
                case 1: TrainingAnalyticsView()
                case 2: MuscleAnalyticsView()
                default: BodyView()
                }
            }
            .navigationTitle("Progress")
        }
    }
}

// MARK: - Strength Score

struct StrengthScoreView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let report = StrengthScoreEngine.report(workouts: workouts, library: library, profile: profile)
        let history = StrengthScoreEngine.history(workouts: workouts, library: library, profile: profile)

        List {
            if StrengthStandards.shared == nil {
                Label("standards.json is missing from the build.", systemImage: "exclamationmark.triangle")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(report.score.map { "\($0)" } ?? "—")
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.color(report.level))
                        Text(report.level?.name ?? "Not enough data").font(.title3.bold())
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: report.coverage).tint(Theme.accent)
                        Text("\(report.muscles.count) of \(Muscles.all.count) muscle groups scored. More groups make the score more accurate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let expected = report.expectedForTrainingAge, let s = report.score, let y = report.trainingYears {
                        let diff = Double(s) - expected
                        Text("Typical after \(y < 1 ? "\(Int(y * 12)) months" : "\(y.clean) years") of training: about \(Int(expected)) (\(StrengthLevel.from(points: expected).name)). You're \(abs(Int(diff))) points \(diff >= 0 ? "ahead" : "behind").")
                            .font(.callout)
                    } else if report.trainingYears == nil {
                        Text("Set when you started training in Profile to see how you compare for your training age.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(report.sex.label), \(report.bodyweight.kg) bodyweight").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                BodyMap(report: report, compact: false).frame(height: 260)
                LevelLegend()
            }

            if history.count > 1 {
                Section("Score over time") {
                    Chart(history) { p in
                        LineMark(x: .value("Week", p.date), y: .value("Score", p.score)).interpolationMethod(.monotone)
                        PointMark(x: .value("Week", p.date), y: .value("Score", p.score)).symbolSize(16)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .foregroundStyle(Theme.accent)
                    .frame(height: 180)
                }
            }

            if !report.muscles.isEmpty {
                Section("Muscle groups") {
                    ForEach(report.muscles.sorted { $0.points > $1.points }) { m in
                        HStack {
                            Circle().fill(Theme.color(m.level)).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(m.muscle.capitalized)
                                Text("from \(m.best.name)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(Int(m.points))").bold().monospacedDigit()
                                Text(m.level.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    let missing = Muscles.all.filter { report.muscle($0) == nil }
                    if !missing.isEmpty {
                        Text("Not scored yet: \(missing.map(\.capitalized).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !report.exercises.isEmpty {
                Section("Your lifts") {
                    ForEach(report.exercises) { e in ExerciseScoreRow(score: e) }
                }
            }

            Section {
                NavigationLink("Compare with competition powerlifters") { CompetitionComparisonView() }
            } footer: {
                Text("Each lift's best estimated 1RM from the last year is placed on six bodyweight-adjusted levels (Beginner → World Class, 100 points each). Each muscle group takes its best lift, and your score is the average of your scored groups. Lifts not trained for 3+ weeks slowly lose weight in the score.")
            }
        }
        .navigationTitle("Strength Score")
    }
}

struct ExerciseScoreRow: View {
    let score: ExerciseScore
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(score.name).font(.subheadline.bold())
                Spacer()
                Text(score.e1rm.kg).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(Theme.color(score.level)).frame(width: geo.size.width * min(score.points, 600) / 600)
                }
            }
            .frame(height: 7)
            HStack {
                Text("\(score.level.name) · \(Int(score.points)) pts").font(.caption.bold())
                Spacer()
                if let next = score.nextFloor {
                    Text("\(StrengthLevel(rawValue: score.level.rawValue + 1)?.name ?? "") at \(next.kg)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if score.decayed {
                Text("Last trained \(score.date.formatted(.relative(presentation: .named))), counted at \(score.e1rm.kg) (best \(score.rawE1RM.kg))")
                    .font(.caption2).foregroundStyle(Theme.plateRed)
            }
        }
        .padding(.vertical, 3)
    }
}

struct LevelLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], spacing: 6) {
            ForEach(StrengthLevel.allCases, id: \.self) { l in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.color(l)).frame(width: 12, height: 12)
                    Text(l.name).font(.caption)
                }
            }
        }
    }
}

/// Front/back body diagram, each muscle region coloured by its level.
struct BodyMap: View {
    let report: StrengthScoreReport
    let compact: Bool

    struct Region {
        let muscle: String
        let rect: CGRect   // in a 100 x 100 space per figure (figure is 50 wide)
        let round: CGFloat
    }

    let front: [Region] = [
        Region(muscle: "shoulders", rect: CGRect(x: 9, y: 17, width: 8, height: 7), round: 4),
        Region(muscle: "shoulders", rect: CGRect(x: 33, y: 17, width: 8, height: 7), round: 4),
        Region(muscle: "chest", rect: CGRect(x: 17.5, y: 18, width: 15, height: 10), round: 3),
        Region(muscle: "biceps", rect: CGRect(x: 8, y: 25, width: 6, height: 12), round: 3),
        Region(muscle: "biceps", rect: CGRect(x: 36, y: 25, width: 6, height: 12), round: 3),
        Region(muscle: "forearms", rect: CGRect(x: 6, y: 38, width: 6, height: 13), round: 3),
        Region(muscle: "forearms", rect: CGRect(x: 38, y: 38, width: 6, height: 13), round: 3),
        Region(muscle: "abs", rect: CGRect(x: 19.5, y: 29, width: 11, height: 18), round: 3),
        Region(muscle: "quadriceps", rect: CGRect(x: 16.5, y: 52, width: 8, height: 22), round: 4),
        Region(muscle: "quadriceps", rect: CGRect(x: 25.5, y: 52, width: 8, height: 22), round: 4),
    ]
    let back: [Region] = [
        Region(muscle: "traps", rect: CGRect(x: 18, y: 13, width: 14, height: 6), round: 3),
        Region(muscle: "shoulders", rect: CGRect(x: 9, y: 17, width: 8, height: 7), round: 4),
        Region(muscle: "shoulders", rect: CGRect(x: 33, y: 17, width: 8, height: 7), round: 4),
        Region(muscle: "lats", rect: CGRect(x: 16, y: 21, width: 6, height: 16), round: 3),
        Region(muscle: "lats", rect: CGRect(x: 28, y: 21, width: 6, height: 16), round: 3),
        Region(muscle: "back", rect: CGRect(x: 22.5, y: 20, width: 5, height: 25), round: 2),
        Region(muscle: "triceps", rect: CGRect(x: 8, y: 25, width: 6, height: 12), round: 3),
        Region(muscle: "triceps", rect: CGRect(x: 36, y: 25, width: 6, height: 12), round: 3),
        Region(muscle: "glutes", rect: CGRect(x: 16.5, y: 45, width: 17, height: 9), round: 4),
        Region(muscle: "hamstrings", rect: CGRect(x: 16.5, y: 55, width: 8, height: 19), round: 4),
        Region(muscle: "hamstrings", rect: CGRect(x: 25.5, y: 55, width: 8, height: 19), round: 4),
        Region(muscle: "calves", rect: CGRect(x: 17, y: 76, width: 7, height: 15), round: 3),
        Region(muscle: "calves", rect: CGRect(x: 26, y: 76, width: 7, height: 15), round: 3),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 100, geo.size.height / 100)
            let ox = (geo.size.width - 100 * s) / 2
            ZStack(alignment: .topLeading) {
                figure(front, offset: 0, scale: s, ox: ox, label: "Front")
                figure(back, offset: 50, scale: s, ox: ox, label: "Back")
            }
        }
    }

    @ViewBuilder
    private func figure(_ regions: [Region], offset: CGFloat, scale s: CGFloat, ox: CGFloat, label: String) -> some View {
        let base = Color(.tertiarySystemFill)
        Group {
            // silhouette
            Circle().fill(base).frame(width: 9 * s, height: 9 * s).position(x: ox + (offset + 25) * s, y: 8 * s)
            RoundedRectangle(cornerRadius: 4 * s).fill(base)
                .frame(width: 22 * s, height: 36 * s).position(x: ox + (offset + 25) * s, y: 33 * s)
            RoundedRectangle(cornerRadius: 3 * s).fill(base)
                .frame(width: 18 * s, height: 44 * s).position(x: ox + (offset + 25) * s, y: 72 * s)
            ForEach(regions.indices, id: \.self) { i in
                let r = regions[i]
                let level = report.muscle(r.muscle)?.level
                RoundedRectangle(cornerRadius: r.round * s)
                    .fill(level == nil ? Color(.systemGray4) : Theme.color(level))
                    .frame(width: r.rect.width * s, height: r.rect.height * s)
                    .position(x: ox + (offset + r.rect.midX) * s, y: r.rect.midY * s)
            }
            if !compact {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                    .position(x: ox + (offset + 25) * s, y: 97 * s)
            }
        }
    }
}

/// OpenPowerlifting-based comparison for squat, bench and deadlift.
struct CompetitionComparisonView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.population) private var population = "all"

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let report = StrengthEngine.report(workouts: workouts, profile: profile)
        let ref = ReferenceData.shared
        List {
            if !report.hasReference {
                Label("Competition data wasn't bundled. It's downloaded by the GitHub Action at build time.",
                      systemImage: "exclamationmark.triangle")
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DOTS").font(.subheadline).foregroundStyle(.secondary)
                    Text(report.dots.map { $0.clean } ?? "—").font(.system(size: 40, weight: .heavy, design: .rounded))
                    if let p = report.dotsPercentile {
                        Text("Stronger than \(Int(p))% of \(population == "tested" ? "drug-tested " : "")raw \(report.sex == .male ? "male" : "female") competitors")
                            .font(.callout)
                    }
                    if let p = report.dotsAgePercentile, let band = report.ageBandLabel {
                        Text("\(percentileText(p)) for ages \(band)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let gl = report.goodlift { Text("IPF GL points: \(gl.clean)").font(.caption).foregroundStyle(.secondary) }
                }
                Picker("Compare against", selection: $population) {
                    Text("All raw lifters").tag("all")
                    Text("Drug-tested only").tag("tested")
                }
            }
            Section("By lift, vs competitors your bodyweight") {
                ForEach(report.standings) { s in LiftStandingRow(standing: s) }
            }
            if let ref {
                Section {
                    Text("Source: \(ref.source), snapshot \(ref.dataDate). Each lifter counted once at their best raw result.")
                    if let v = ref.validation?.dots {
                        Text("DOTS formula checked against the dataset: median error \(String(format: "%.3f", v.medianAbsErr)) points over \(v.n.formatted()) results.")
                    }
                    Text("These are people who compete, so percentiles are much tougher than your gym.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Competition data")
    }
}

struct LiftStandingRow: View {
    let standing: LiftStanding
    var body: some View {
        let tier = Theme.tier(standing.percentile)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(standing.lift.title).font(.headline)
                Spacer()
                Text(standing.e1rm?.kg ?? "Not logged").monospacedDigit()
            }
            if let p = standing.percentile {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(tier.color).frame(width: geo.size.width * min(p, 100) / 100)
                    }
                }
                .frame(height: 8)
                Text(percentileText(p)).font(.caption.bold())
                if let c = standing.cohort { Text(c).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Training analytics

struct TrainingAnalyticsView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @EnvironmentObject var library: ExerciseLibrary
    @Query private var measurements: [BodyMeasurement]
    @State private var exerciseID = "barbell-back-squat"

    var body: some View {
        let volume = Stats.weekly(workouts, weeks: 12) { ws in ws.reduce(0) { $0 + $1.volume } }
        let freq = Stats.weekly(workouts, weeks: 12) { Double($0.count) }
        let trained = Array(Set(workouts.flatMap { $0.exercises.map(\.exerciseID) })).sorted { library.name($0) < library.name($1) }
        List {
            Section("Weekly volume (kg)") {
                Chart(volume) { BarMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("kg", $0.value)) }
                    .foregroundStyle(Theme.accent).frame(height: 160)
            }
            Section("Workouts per week") {
                Chart(freq) { BarMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Workouts", $0.value)) }
                    .foregroundStyle(Theme.plateGreen).frame(height: 120)
            }
            Section("Activity") { ActivityHeatmap(days: Stats.activityDays(workouts)) }
            if !trained.isEmpty {
                Section("Strength curve") {
                    Picker("Exercise", selection: $exerciseID) {
                        ForEach(trained, id: \.self) { Text(library.name($0)).tag($0) }
                    }
                    let pts = Stats.history(for: exerciseID, in: workouts, library: library,
                                            bodyweight: ProfileSnapshot.current(measurements).bodyweight)
                    if pts.isEmpty {
                        Text("No sets logged for this exercise.").foregroundStyle(.secondary)
                    } else {
                        Chart(pts) {
                            LineMark(x: .value("Date", $0.date), y: .value("e1RM", $0.e1rm)).interpolationMethod(.monotone)
                            PointMark(x: .value("Date", $0.date), y: .value("e1RM", $0.e1rm)).symbolSize(16)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .foregroundStyle(Theme.plateRed).frame(height: 180)
                        if let first = pts.first, let last = pts.last, first.e1rm > 0 {
                            let change = (last.e1rm - first.e1rm) / first.e1rm * 100
                            Text("\(change >= 0 ? "+" : "")\(change.clean)% est. 1RM since \(first.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onAppear { if !trained.contains(exerciseID), let f = trained.first { exerciseID = f } }
            }
        }
    }
}

struct ActivityHeatmap: View {
    let days: Set<Date>
    private let weeks = 20

    var body: some View {
        let cal = Calendar.current
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: Stats.weekStart(.now)) ?? .now
        HStack(spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                        RoundedRectangle(cornerRadius: 2)
                            .fill(days.contains(cal.startOfDay(for: day)) ? Theme.plateGreen : Color(.tertiarySystemFill))
                            .opacity(day > .now ? 0.3 : 1)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Muscle analytics

struct MuscleAnalyticsView: View {
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @EnvironmentObject var library: ExerciseLibrary

    var body: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let monthAgo = Date().addingTimeInterval(-28 * 86400)
        let weekly = Stats.setsPerMuscle(workouts, library: library, since: weekAgo)
        let month = Stats.setsPerMuscle(workouts, library: library, since: monthAgo)
        let groups = Muscles.groups.map { g in (g.name, g.muscles.reduce(0.0) { $0 + (month[$1] ?? 0) } / 4) }
        let recovery = Stats.recovery(workouts, library: library)

        List {
            Section {
                ForEach(recovery.filter { $0.state != .untrained }) { r in
                    HStack {
                        Circle().fill(color(r.state)).frame(width: 10, height: 10)
                        Text(r.muscle.capitalized)
                        Spacer()
                        Text(r.state.rawValue).foregroundStyle(.secondary)
                        if let h = r.hours { Text("\(Int(h))h").monospacedDigit().foregroundStyle(.secondary) }
                    }
                }
                if recovery.allSatisfy({ $0.state == .untrained }) {
                    Text("Nothing trained in the last week.").foregroundStyle(.secondary)
                }
            } header: { Text("Recovery") } footer: {
                Text("A muscle hit with 3+ hard sets shows as fatigued for 24h and recovering until 48h.")
            }

            Section {
                RadarChart(labels: groups.map { $0.0 }, values: groups.map { $0.1 })
                    .frame(height: 260)
            } header: { Text("Muscle balance") } footer: {
                Text("Average weekly hard sets per group over the last 4 weeks. Secondary muscles count as half a set.")
            }

            Section {
                ForEach(Muscles.all.filter { (weekly[$0] ?? 0) > 0 }.sorted { (weekly[$0] ?? 0) > (weekly[$1] ?? 0) }, id: \.self) { m in
                    let v = weekly[m] ?? 0
                    HStack {
                        Text(m.capitalized).frame(width: 100, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.plateGreen.opacity(0.15))
                                    .frame(width: geo.size.width * 10 / 25).offset(x: geo.size.width * 10 / 25)
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * min(v, 25) / 25)
                            }
                        }
                        .frame(height: 10)
                        Text(v.clean).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                }
            } header: { Text("Sets this week") } footer: {
                Text("Shaded band is 10–20 sets/week, the range most hypertrophy research uses as a productive dose.")
            }
        }
    }

    private func color(_ s: RecoveryState) -> Color {
        switch s {
        case .fatigued: return Theme.plateRed
        case .recovering: return Theme.plateYellow
        case .ready: return Theme.plateGreen
        case .untrained: return Theme.noData
        }
    }
}

struct RadarChart: View {
    let labels: [String]
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let n = max(labels.count, 3)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 28
            let maxV = max(values.max() ?? 1, 1)
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    polygon(Array(repeating: Double(ring) / 4, count: n), c: c, r: r)
                        .stroke(Color(.separator), lineWidth: 0.5)
                }
                polygon(values.map { $0 / maxV }, c: c, r: r).fill(Theme.accent.opacity(0.3))
                polygon(values.map { $0 / maxV }, c: c, r: r).stroke(Theme.accent, lineWidth: 2)
                ForEach(labels.indices, id: \.self) { i in
                    let p = point(i, n: n, frac: 1.18, c: c, r: r)
                    Text("\(labels[i])\n\(values[i].clean)").font(.caption2).multilineTextAlignment(.center)
                        .position(p)
                }
            }
        }
    }

    private func point(_ i: Int, n: Int, frac: Double, c: CGPoint, r: CGFloat) -> CGPoint {
        let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
        return CGPoint(x: c.x + CGFloat(cos(a) * frac) * r, y: c.y + CGFloat(sin(a) * frac) * r)
    }

    private func polygon(_ fracs: [Double], c: CGPoint, r: CGFloat) -> Path {
        Path { path in
            for (i, f) in fracs.enumerated() {
                let p = point(i, n: fracs.count, frac: f, c: c, r: r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Body measurements

struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var kind: MeasurementKind = .bodyweight
    @State private var value: Double?
    @State private var date = Date()
    @State private var syncing = false

    var body: some View {
        let series = measurements.filter { $0.kind == kind }
        List {
            Section {
                Picker("Measurement", selection: $kind) {
                    ForEach(MeasurementKind.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    TextField("Value", value: $value, format: .number).keyboardType(.decimalPad)
                    Text(kind.unit).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Button("Log \(kind.label.lowercased())") {
                    guard let v = value, v > 0 else { return }
                    context.insert(BodyMeasurement(kind: kind, value: v, date: date))
                    try? context.save()
                    value = nil
                }
                .disabled((value ?? 0) <= 0)
                if kind == .bodyweight && HealthSync.available {
                    Button(syncing ? "Importing…" : "Import latest from Apple Health") { importHealth() }.disabled(syncing)
                }
            }

            if series.count > 1 {
                Section(kind.label) {
                    Chart(series) {
                        LineMark(x: .value("Date", $0.date), y: .value(kind.unit, $0.value)).interpolationMethod(.monotone)
                        PointMark(x: .value("Date", $0.date), y: .value(kind.unit, $0.value)).symbolSize(16)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .foregroundStyle(Theme.accent).frame(height: 180)
                    if let f = series.first, let l = series.last {
                        let d = l.value - f.value
                        Text("\(d >= 0 ? "+" : "")\(d.clean) \(kind.unit) since \(f.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("History") {
                ForEach(series.reversed()) { m in
                    LabeledContent(m.date.formatted(date: .abbreviated, time: .omitted), value: "\(m.value.clean) \(kind.unit)")
                }
                .onDelete { idx in
                    let rev = Array(series.reversed())
                    for i in idx { context.delete(rev[i]) }
                    try? context.save()
                }
            }
        }
    }

    private func importHealth() {
        syncing = true
        Task {
            try? await HealthSync.requestAccess()
            if let latest = await HealthSync.latestBodyweight(),
               !measurements.contains(where: { $0.kind == .bodyweight && abs($0.date.timeIntervalSince(latest.1)) < 60 }) {
                context.insert(BodyMeasurement(kind: .bodyweight, value: (latest.0 * 10).rounded() / 10, date: latest.1))
                try? context.save()
            }
            syncing = false
        }
    }
}
