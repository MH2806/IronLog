import SwiftUI
import SwiftData
import Charts

struct StrengthProfileView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let report = StrengthScoreEngine.report(workouts: workouts, library: library, profile: profile)
        let comp = StrengthEngine.report(workouts: workouts, profile: profile)
        let history = StrengthScoreEngine.history(workouts: workouts, library: library, profile: profile)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(report)
                if let p = comp.dotsPercentile {
                    PercentileCard(percentile: p, sex: profile.sex)
                }
                muscleMap(report)
                climb(report)
                if !report.muscles.isEmpty { muscles(report) }
                if !report.exercises.isEmpty { lifts(report) }
                if history.count > 1 { historyCard(history) }
                trainingAge(report)
                NavigationLink { CompetitionComparisonView() } label: {
                    HStack(spacing: 14) {
                        IconTile(icon: "chart.bar.xaxis", color: Palette.purple)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Compare with competitors").font(.headline)
                            Text("Squat, bench, deadlift and DOTS vs OpenPowerlifting results").font(.subheadline).foregroundStyle(Palette.text2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
                    }
                    .card()
                }
                .buttonStyle(.plain)
                Text("Each lift's best estimated 1RM from the last year is placed on six bodyweight- and sex-adjusted levels, each split into I–III. Each muscle group takes its best lift, and your score is the average across scored groups. Lifts not trained for 3+ weeks slowly count for less.")
                    .font(.caption).foregroundStyle(Palette.text2)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Strength Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func hero(_ report: StrengthScoreReport) -> some View {
        VStack(spacing: 14) {
            Text("STRENGTH SCORE").font(.subheadline.weight(.bold)).tracking(4)
            if let rank = report.rank, let points = report.points, let score = report.score {
                RankBadge(level: rank.level, tier: rank.tier, size: 130, glow: true).padding(.vertical, 12)
                Text(rank.name).font(.title3.bold()).foregroundStyle(rank.level.color)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(rank.level.color.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(rank.level.color.opacity(0.5)))
                Text("Strength score \(score) / 100").font(.headline).foregroundStyle(Palette.text2)
                if let next = rank.next, let np = rank.nextFloorPoints {
                    VStack(spacing: 6) {
                        ProgressLine(fraction: (points - rank.floorPoints) / (np - rank.floorPoints), color: rank.level.color, height: 10)
                        Text("\(max(1, Int((ScoreScale.display(np) - ScoreScale.display(points)).rounded(.up)))) pts to \(next.name)")
                            .font(.subheadline).foregroundStyle(Palette.text2)
                    }
                    .padding(.horizontal, 30)
                }
                Text("\(report.muscles.count) of \(Muscles.all.count) muscle groups scored · more groups = more accurate")
                    .font(.caption).foregroundStyle(Palette.text3).multilineTextAlignment(.center)
            } else {
                RankBadge(level: .beginner, tier: 1, size: 110, dimmed: true).padding(.vertical, 10)
                Text("No rank yet").font(.title3.bold())
                Text("Log lifts for at least 3 muscle groups. \(report.muscles.count) scored so far.")
                    .font(.subheadline).foregroundStyle(Palette.text2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func muscleMap(_ report: StrengthScoreReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MUSCLE MAP").font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2)
            BodyDiagram { report.muscle($0)?.level.color }.frame(height: 300)
            if let best = report.muscles.max(by: { $0.points < $1.points }) {
                Text("Strongest: \(MuscleName.display(best.muscle)) (\(best.rank.name))").font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            LevelLegend()
        }
        .card()
    }

    private func climb(_ report: StrengthScoreReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CLIMB THE RANKS").font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2)
            HStack(spacing: 0) {
                ForEach(StrengthLevel.allCases, id: \.self) { l in
                    let current = report.level == l
                    VStack(spacing: 6) {
                        RankBadge(level: l, tier: current ? (report.rank?.tier ?? 1) : 1, size: 38, dimmed: !current, glow: current)
                        Text(l.shortName).font(.caption2.weight(current ? .bold : .medium))
                            .foregroundStyle(current ? .white : Palette.text2).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Eighteen ranks from Beginner I to World Class III, scored per lift and per muscle.")
                .font(.subheadline).foregroundStyle(Palette.text2)
        }
        .card()
    }

    private func muscles(_ report: StrengthScoreReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Muscle groups")
            VStack(spacing: 12) {
                ForEach(report.muscles.sorted { $0.points > $1.points }) { m in
                    HStack(spacing: 12) {
                        RankBadge(level: m.rank.level, tier: m.rank.tier, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MuscleName.display(m.muscle)).font(.headline)
                            Text("\(m.rank.name) · from \(m.best.name)").font(.caption).foregroundStyle(Palette.text2).lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(ScoreScale.display(m.points).rounded()))").font(.title3.bold()).monospacedDigit()
                            .foregroundStyle(m.level.color)
                    }
                }
                let missing = Muscles.all.filter { report.muscle($0) == nil }
                if !missing.isEmpty {
                    Text("Not scored yet: \(missing.map(MuscleName.display).joined(separator: ", "))")
                        .font(.caption).foregroundStyle(Palette.text2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card()
        }
    }

    private func lifts(_ report: StrengthScoreReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Per-lift ranks")
            ForEach(report.exercises) { e in
                NavigationLink { if let ex = library.exercise(e.exerciseID) { ExerciseDetailView(exercise: ex) } } label: {
                    LiftRankRow(score: e)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func historyCard(_ history: [StrengthScoreEngine.HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Score history").font(.headline)
            Chart(history) { p in
                AreaMark(x: .value("Week", p.date), y: .value("Score", p.score))
                    .foregroundStyle(LinearGradient(colors: [Palette.green.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Week", p.date), y: .value("Score", p.score)).foregroundStyle(Palette.green)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
        }
        .card()
    }

    @ViewBuilder
    private func trainingAge(_ report: StrengthScoreReport) -> some View {
        if let expected = report.expectedForTrainingAge, let points = report.points, let y = report.trainingYears {
            let diff = ScoreScale.display(points) - ScoreScale.display(expected)
            HStack(spacing: 14) {
                IconTile(icon: "hourglass", color: diff >= 0 ? Palette.green : Palette.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(diff >= 0 ? "\(Int(diff.rounded())) pts ahead for your training age" : "\(Int((-diff).rounded())) pts behind for your training age")
                        .font(.headline)
                    Text("Typical after \(y < 1 ? "\(Int(y * 12)) months" : "\(y.clean) years"): \(Int(ScoreScale.display(expected).rounded())) (\(Rank.from(points: expected).name))")
                        .font(.subheadline).foregroundStyle(Palette.text2)
                }
            }
            .card()
        } else {
            Text("Set when you started training in Profile → Edit profile to compare against your training age.")
                .font(.caption).foregroundStyle(Palette.text2)
        }
    }
}

struct LiftRankRow: View {
    let score: ExerciseScore
    var body: some View {
        let rank = score.rank
        let nextPts = rank.nextFloorPoints
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RankBadge(level: rank.level, tier: rank.tier, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.name).font(.headline).lineLimit(1)
                    Text(rank.name).font(.subheadline.weight(.semibold)).foregroundStyle(rank.level.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(score.e1rm.kg).font(.headline).monospacedDigit()
                    Text("e1RM").font(.caption).foregroundStyle(Palette.text2)
                }
            }
            if let nextPts {
                ProgressLine(fraction: (score.points - rank.floorPoints) / (nextPts - rank.floorPoints), color: rank.level.color, height: 6)
            }
            if score.decayed {
                Text("Not trained since \(score.date.formatted(date: .abbreviated, time: .omitted)); counted at \(score.e1rm.kg) (best \(score.rawE1RM.kg))")
                    .font(.caption2).foregroundStyle(Palette.orange)
            }
        }
        .card(padding: 14, radius: 20)
    }
}

/// Bell-curve style diagram with the user's position.
struct PercentileCard: View {
    let percentile: Double
    let sex: Sex
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Top \(max(1, Int((100 - percentile).rounded())))%").font(.system(size: 38, weight: .bold)).foregroundStyle(Palette.blue)
                Text("DOTS vs raw \(sex == .male ? "male" : "female") powerlifting competitors").font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text2)
            }
            Spacer()
            BellCurve(position: percentile / 100).frame(width: 120, height: 64)
        }
        .card()
    }
}

struct BellCurve: View {
    let position: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pts: [CGPoint] = (0...40).map { i in
                let x = Double(i) / 40
                let y = exp(-pow((x - 0.5) / 0.16, 2) / 2)
                return CGPoint(x: w * x, y: h - 6 - (h - 16) * y)
            }
            let px = w * min(max(position, 0.02), 0.98)
            let py = h - 6 - (h - 16) * exp(-pow((position - 0.5) / 0.16, 2) / 2)
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: h)); pts.forEach { p.addLine(to: $0) }; p.addLine(to: CGPoint(x: w, y: h)) }
                    .fill(LinearGradient(colors: [Palette.blue.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                    .stroke(Palette.blue, lineWidth: 2)
                Path { p in p.move(to: CGPoint(x: px, y: py)); p.addLine(to: CGPoint(x: px, y: h)) }
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Circle().fill(.white).frame(width: 10, height: 10).position(x: px, y: py)
                Text("You").font(.caption2.bold()).position(x: px, y: max(6, py - 12))
            }
        }
    }
}

// MARK: - Competition data (OpenPowerlifting)

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
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
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
