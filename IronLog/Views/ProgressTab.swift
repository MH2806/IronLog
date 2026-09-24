import SwiftUI
import SwiftData
import Charts

struct ProgressTab: View {
    enum Pane: Hashable { case analytics, exercises, bodyweight }
    enum Lens: Hashable { case overview, week, trends }
    @State private var pane: Pane = .analytics
    @State private var lens: Lens = .overview
    @State private var showAddCustom = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Progress", subtitle: subtitle) {
                        if pane == .exercises { SquareIconButton(icon: "plus") { showAddCustom = true } }
                    }
                    PillTabs(options: [(Pane.analytics, "Analytics"), (Pane.exercises, "Exercises"), (Pane.bodyweight, "Bodyweight")],
                             selection: $pane)
                    switch pane {
                    case .analytics:
                        HStack(spacing: 6) {
                            Text("VIEW").font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2).padding(.trailing, 6)
                            lensButton(.overview, "Overview")
                            lensButton(.week, "This week")
                            lensButton(.trends, "Trends")
                        }
                        switch lens {
                        case .overview: OverviewPane(openExercises: { pane = .exercises })
                        case .week: ThisWeekPane()
                        case .trends: TrendsPane()
                        }
                    case .exercises: ExercisesPane()
                    case .bodyweight: BodyweightPane()
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 90)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAddCustom) { AddCustomExerciseView() }
        }
    }

    private var subtitle: String {
        switch pane {
        case .analytics: return "Strength, recovery, and training trends"
        case .exercises: return "Explore your lifts and exercise history"
        case .bodyweight: return "Bodyweight and measurements"
        }
    }

    private func lensButton(_ l: Lens, _ title: String) -> some View {
        Button { withAnimation { lens = l } } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(lens == l ? Palette.blue : Palette.text2)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(lens == l ? Palette.blueSoft : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Overview

struct OverviewPane: View {
    var openExercises: () -> Void
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]

    var body: some View {
        let profile = ProfileSnapshot.current(measurements)
        let done = workouts.filter { $0.endedAt != nil }
        let report = StrengthScoreEngine.report(workouts: done, library: library, profile: profile)
        let comp = StrengthEngine.report(workouts: done, profile: profile)
        let lifts = Insights.liftSummaries(done, library: library, bodyweight: profile.bodyweight)
        let recovery = Insights.recovery(done, library: library, sleep: nil, restingHR: nil)
        let badges = Insights.badges(done, library: library, report: report)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Your strength profile")
                Tag(text: "RECENT", color: Palette.green).padding(.top, 10)
            }
            NavigationLink { StrengthProfileView() } label: {
                StrengthProfileCard(report: report, competitionPercentile: comp.dotsPercentile)
            }
            .buttonStyle(.plain)

            if !lifts.isEmpty {
                SectionTitle(title: "Your lifts", action: "All lifts", onTap: openExercises)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(lifts.prefix(10)) { l in
                            NavigationLink {
                                if let e = library.exercise(l.exerciseID) { ExerciseDetailView(exercise: e) }
                            } label: { LiftCard(lift: l) }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            SectionTitle(title: "Muscle readiness")
            NavigationLink { RecoveryView() } label: { ReadinessCard(summary: recovery) }.buttonStyle(.plain)

            TotalLiftedCard(total: done.reduce(0) { $0 + $1.volume })

            SectionTitle(title: "Badge case")
            NavigationLink { BadgesView() } label: { BadgeCaseCard(badges: badges) }.buttonStyle(.plain)

            SectionTitle(title: "Your journey")
            JourneyGrid(workouts: done)

            let split = Insights.split(done, library: library)
            if !split.isEmpty {
                SectionTitle(title: "Your training split")
                SplitCard(rows: Array(split.prefix(7)), tip: Insights.splitTip(split))
            }
        }
    }
}

struct StrengthProfileCard: View {
    let report: StrengthScoreReport
    let competitionPercentile: Double?
    @State private var showMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rank = report.rank, let points = report.points, let score = report.score {
                let color = rank.level.color
                HStack(spacing: 16) {
                    RingGauge(progress: Double(score) / 100, color: color, lineWidth: 8) {
                        Text("\(score)").font(.system(size: 30, weight: .bold)).foregroundStyle(color)
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rank.name).font(.title2.bold())
                        if let next = rank.next, let nextPts = rank.nextFloorPoints {
                            let gap = ScoreScale.display(nextPts) - ScoreScale.display(points)
                            Text("\(max(1, Int(gap.rounded(.up)))) pts to \(next.name)").font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
                            HStack {
                                ProgressLine(fraction: (points - rank.floorPoints) / (nextPts - rank.floorPoints), color: color)
                                Text("\(score) / \(ScoreScale.display(nextPts).formatted(.number.precision(.fractionLength(1))))")
                                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.text2)
                            }
                        } else {
                            Text("Top rank").font(.subheadline).foregroundStyle(Palette.text2)
                        }
                    }
                    Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
                }
            } else {
                HStack(spacing: 16) {
                    RingGauge(progress: Double(report.muscles.count) / 3, color: Palette.blue) {
                        Text("\(report.muscles.count)/3").font(.headline)
                    }
                    .frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unlock your rank").font(.title3.bold())
                        Text("Log lifts for 3 muscle groups to get your Strength Score.").font(.subheadline).foregroundStyle(Palette.text2)
                    }
                }
            }
            if let p = competitionPercentile {
                Divider().overlay(Palette.stroke)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top \(max(1, Int((100 - p).rounded())))%").font(.system(size: 34, weight: .bold)).foregroundStyle(Palette.blue)
                    Text("of raw powerlifting competitors by DOTS").font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
                }
            }
            Button { withAnimation(.snappy) { showMap.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("Body map")
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showMap ? 180 : 0))
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text2).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            if showMap {
                BodyDiagram { report.muscle($0)?.level.color }.frame(height: 260)
                LevelLegend()
            }
        }
        .card()
    }
}

struct LevelLegend: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], spacing: 8) {
            ForEach(StrengthLevel.allCases, id: \.self) { l in
                HStack(spacing: 6) {
                    Circle().fill(l.color).frame(width: 10, height: 10)
                    Text(l.name).font(.caption.weight(.medium)).foregroundStyle(Palette.text2)
                }
            }
        }
    }
}

struct LiftCard: View {
    let lift: LiftSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(lift.name).font(.headline).lineLimit(1)
                if lift.prThisWeek { Image(systemName: "flame.fill").foregroundStyle(Palette.orange).font(.subheadline) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(lift.usesReps ? "\(Int(lift.current))" : "\(Int(lift.current.rounded()))").font(.title.bold())
                Text(lift.usesReps ? "reps" : "kg").font(.headline).foregroundStyle(Palette.text2)
                Spacer()
                if abs(lift.delta) >= 0.05 {
                    Label(lift.delta.clean + (lift.usesReps ? "" : " kg"), systemImage: lift.delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(lift.delta >= 0 ? Palette.green : Palette.red)
                }
            }
            Text(lift.usesReps ? "best set" : "e1RM").font(.subheadline.weight(.medium)).foregroundStyle(Palette.text2)
            Sparkline(values: lift.values).frame(height: 44).padding(.top, 6)
        }
        .frame(width: 200)
        .card(padding: 16, radius: 22)
    }
}

struct ReadinessCard: View {
    let summary: RecoverySummary
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                IconTile(icon: "battery.75percent", color: Palette.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.ready.count) ready · \(summary.recovering.count) recovering").font(.headline)
                    Text("Plan today around what is ready now").font(.subheadline).foregroundStyle(Palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
            }
            if !summary.recovering.isEmpty {
                chipGroup("Recovering", summary.recovering.map(\.muscle), Palette.orange)
            }
            chipGroup("Ready to train", summary.ready.map(\.muscle), Palette.green)
        }
        .card()
    }

    private func chipGroup(_ title: String, _ muscles: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(2).foregroundStyle(Palette.text2)
                Spacer()
                Text("\(muscles.count)").font(.subheadline.bold()).foregroundStyle(color)
            }
            FlowLayout(spacing: 8) {
                ForEach(muscles, id: \.self) { m in
                    Text(MuscleName.display(m)).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(color.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(color.opacity(0.4)))
                }
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: min(maxX, width), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct MilestoneIcon: View {
    let milestone: Milestone
    var size: CGFloat = 60
    var locked = false
    var body: some View {
        ZStack {
            Hexagon().fill(LinearGradient(colors: [Palette.blue.opacity(0.9), Palette.purple.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            Hexagon().stroke(Color.white.opacity(0.4), lineWidth: 1.5).padding(3)
            Image(systemName: milestone.icon).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .blur(radius: locked ? 6 : 0)
        .opacity(locked ? 0.5 : 1)
    }
}

struct TotalLiftedCard: View {
    let total: Double
    var body: some View {
        let m = Insights.milestoneProgress(total: total)
        let earned = Insights.milestones.filter { $0.kg <= total }
        let upcoming = Insights.milestones.filter { $0.kg > total }.prefix(2)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total Lifted").font(.headline).foregroundStyle(Palette.text2)
                    Text(total.compact + " kg").font(.system(size: 44, weight: .bold)).foregroundStyle(Palette.blue)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let l = m.latest {
                        (Text("Latest unlock: ").foregroundColor(Palette.text2) + Text(l.name).bold()).font(.subheadline)
                    }
                }
                Spacer()
                if let l = m.latest {
                    VStack(spacing: 6) {
                        MilestoneIcon(milestone: l, size: 84)
                        Text("LATEST").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Palette.text2)
                    }
                }
            }
            if let next = m.next {
                HStack {
                    Text("Next: \(next.name)").font(.headline)
                    Spacer()
                    Text("\(Int(m.fraction * 100))% there").font(.headline).foregroundStyle(Palette.blue)
                }
                ProgressLine(fraction: m.fraction, color: Palette.blue, height: 10)
            }
            Divider().overlay(Palette.stroke)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(earned.suffix(4)) { MilestoneIcon(milestone: $0, size: 44) }
                    ForEach(Array(upcoming)) { MilestoneIcon(milestone: $0, size: 44, locked: true) }
                }
            }
            NavigationLink { JourneyView(total: total) } label: {
                HStack(spacing: 2) { Text("View journey"); Image(systemName: "chevron.right") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .card()
    }
}

struct JourneyView: View {
    let total: Double
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Insights.milestones) { m in
                    let done = total >= m.kg
                    HStack(spacing: 14) {
                        MilestoneIcon(milestone: m, size: 52, locked: !done)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.name).font(.headline)
                            Text("\(Int(m.kg).formatted()) kg").font(.subheadline).foregroundStyle(Palette.text2)
                            if !done { ProgressLine(fraction: total / m.kg, color: Palette.blue, height: 6) }
                        }
                        Spacer()
                        if done { Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.green).font(.title2) }
                    }
                    .card(padding: 14)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Your journey")
    }
}

struct BadgeCaseCard: View {
    let badges: [Badge]
    var body: some View {
        let earned = badges.filter(\.earned)
        let rank = badges.last { $0.category == .rank && $0.earned }
        let journey = badges.last { $0.category == .journey && $0.earned }
        let session = badges.last { $0.category == .session && $0.earned }
        HStack(spacing: 18) {
            BadgeMedal(badge: rank, fallbackIcon: "shield.fill", label: "Rank")
            BadgeMedal(badge: journey, fallbackIcon: "airplane", label: "Journey")
            BadgeMedal(badge: session, fallbackIcon: "figure.strengthtraining.traditional", label: "Session")
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text("\(earned.count) / \(badges.count)").font(.subheadline.bold()).foregroundStyle(Palette.blue)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Palette.blueSoft, in: Capsule())
                HStack(spacing: 2) { Text("View all"); Image(systemName: "chevron.right") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.blue)
            }
        }
        .card()
    }
}

struct BadgeMedal: View {
    let badge: Badge?
    var fallbackIcon = "lock.fill"
    var label: String? = nil
    var size: CGFloat = 58
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let b = badge, b.earned {
                    Hexagon().fill(LinearGradient(colors: [color(b.category), color(b.category).opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    Hexagon().stroke(Color.white.opacity(0.4), lineWidth: 1.5).padding(3)
                    Image(systemName: b.icon).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(Palette.cardHi)
                    Image(systemName: "lock.fill").font(.system(size: size * 0.3)).foregroundStyle(Palette.text2)
                }
            }
            .frame(width: size, height: size)
            if let label { Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.text2) }
        }
    }

    private func color(_ c: BadgeCategory) -> Color {
        switch c {
        case .rank: return Theme.color(.intermediate)
        case .journey: return Palette.blue
        case .session: return Color(red: 0.72, green: 0.55, blue: 0.3)
        case .streak: return Palette.orange
        case .records: return Palette.yellow
        case .plates: return Palette.purple
        }
    }
}

struct BadgesView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    var body: some View {
        let done = workouts.filter { $0.endedAt != nil }
        let report = StrengthScoreEngine.report(workouts: done, library: library, profile: .current(measurements))
        let badges = Insights.badges(done, library: library, report: report)
        ScrollView { BadgeGrid(badges: badges).padding(16) }
            .screenBackground()
            .navigationTitle("Badges")
    }
}

struct BadgeGrid: View {
    let badges: [Badge]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(BadgeCategory.allCases, id: \.self) { cat in
                let list = badges.filter { $0.category == cat }
                SectionTitle(title: "\(cat.rawValue) · \(list.filter(\.earned).count)/\(list.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                    ForEach(list) { b in
                        VStack(spacing: 6) {
                            BadgeMedal(badge: b, size: 56)
                            Text(b.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                            if !b.earned { ProgressLine(fraction: b.progress, color: Palette.blue, height: 4).frame(width: 56) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
    }
}

struct JourneyGrid: View {
    let workouts: [Workout]
    var body: some View {
        let weekStart = Stats.weekStart(.now)
        let week = workouts.filter { $0.startedAt >= weekStart }
        let totalTime = workouts.reduce(0) { $0 + $1.duration }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(icon: "figure.strengthtraining.traditional", color: Palette.blue, value: "\(workouts.count)", label: "Total Workouts",
                     delta: week.isEmpty ? nil : "\(week.count) this week")
            StatCard(icon: "scalemass.fill", color: Palette.green, value: workouts.reduce(0) { $0 + $1.volume }.compact,
                     label: "Total Volume", delta: week.isEmpty ? nil : "\(week.reduce(0) { $0 + $1.volume }.compact) this week")
            StatCard(icon: "trophy.fill", color: Palette.yellow, value: "\(workouts.reduce(0) { $0 + $1.prCount })", label: "Total PRs",
                     delta: week.isEmpty ? nil : "\(week.reduce(0) { $0 + $1.prCount }) this week")
            StatCard(icon: "timer", color: Palette.purple, value: "\(Int(totalTime / 3600))h", label: "Time Training")
        }
    }
}

struct SplitCard: View {
    let rows: [SplitRow]
    let tip: String?
    var body: some View {
        let maxShare = max(rows.map { max($0.share, $0.usual) }.max() ?? 0.25, 0.01)
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { r in
                HStack(spacing: 12) {
                    Text(MuscleName.display(r.muscle)).font(.headline).frame(width: 104, alignment: .leading).lineLimit(1)
                    ProgressLine(fraction: r.share / maxShare, color: Palette.blue, height: 10, marker: r.usual / maxShare)
                    Text("\(Int((r.share * 100).rounded()))%").font(.headline).monospacedDigit().frame(width: 46, alignment: .trailing)
                }
            }
            Divider().overlay(Palette.stroke)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.7)).frame(width: 3, height: 14)
                Text("= your usual split (6 months) · bars = last 30 days").font(.caption).foregroundStyle(Palette.text2)
            }
            if let tip {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Palette.blue)
                    Text(tip).font(.subheadline).foregroundStyle(Palette.text2)
                }
            }
        }
        .card()
    }
}

// MARK: - This week

struct ThisWeekPane: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]

    var body: some View {
        let start = Stats.weekStart(.now)
        let lastStart = start.addingTimeInterval(-7 * 86400)
        let done = workouts.filter { $0.endedAt != nil }
        let week = done.filter { $0.startedAt >= start }
        let last = done.filter { $0.startedAt >= lastStart && $0.startedAt < start }
        let sets = Stats.setsPerMuscle(done, library: library, since: start)
        let maxSets = max(sets.values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                compare("figure.strengthtraining.traditional", Palette.blue, "\(week.count)", "Workouts", Double(week.count), Double(last.count))
                compare("scalemass.fill", Palette.green, week.reduce(0) { $0 + $1.volume }.compact + " kg", "Volume",
                        week.reduce(0) { $0 + $1.volume }, last.reduce(0) { $0 + $1.volume })
                compare("list.number", Palette.purple, "\(week.reduce(0) { $0 + $1.workingSets.count })", "Sets",
                        Double(week.reduce(0) { $0 + $1.workingSets.count }), Double(last.reduce(0) { $0 + $1.workingSets.count }))
                compare("trophy.fill", Palette.yellow, "\(week.reduce(0) { $0 + $1.prCount })", "PRs",
                        Double(week.reduce(0) { $0 + $1.prCount }), Double(last.reduce(0) { $0 + $1.prCount }))
            }

            SectionTitle(title: "Muscles hit this week")
            VStack(spacing: 14) {
                BodyDiagram { m in
                    guard let n = sets[m], n > 0 else { return nil }
                    return Palette.blue.opacity(0.35 + 0.65 * min(1, n / maxSets))
                }
                .frame(height: 240)
                ForEach(Muscles.all.filter { (sets[$0] ?? 0) > 0 }.sorted { (sets[$0] ?? 0) > (sets[$1] ?? 0) }, id: \.self) { m in
                    let n = sets[m] ?? 0
                    HStack(spacing: 10) {
                        Text(MuscleName.display(m)).font(.subheadline.weight(.semibold)).frame(width: 96, alignment: .leading)
                        ProgressLine(fraction: n / 20, color: n >= 10 ? Palette.green : Palette.blue, height: 8)
                        Text(n.clean).font(.subheadline.bold()).monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                }
                Text("Hard sets per muscle (secondary muscles count half). 10–20 a week is the usual growth range.")
                    .font(.caption).foregroundStyle(Palette.text2)
            }
            .card()

            let prs: [(String, SetEntry)] = week.flatMap { (w: Workout) -> [(String, SetEntry)] in
                w.exercises.flatMap { (ex: WorkoutExercise) -> [(String, SetEntry)] in ex.sets.filter(\.isPR).map { (ex.exerciseID, $0) } }
            }
            if !prs.isEmpty {
                SectionTitle(title: "PRs this week")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(prs.indices, id: \.self) { i in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(Palette.yellow)
                            Text(library.name(prs[i].0)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(prs[i].1.weightKg.clean) × \(prs[i].1.reps)").monospacedDigit().foregroundStyle(Palette.text2)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func compare(_ icon: String, _ color: Color, _ value: String, _ label: String, _ now: Double, _ before: Double) -> some View {
        let diff = now - before
        return StatCard(icon: icon, color: color, value: value, label: label,
                        delta: diff > 0 ? "\(diff.compact) vs last week" : nil)
    }
}

// MARK: - Trends

struct LiftSeries: Identifiable {
    let id: String
    let name: String
    let points: [SessionPoint]
}

struct TrendsPane: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]

    var body: some View {
        let done = workouts.filter { $0.endedAt != nil }
        let profile = ProfileSnapshot.current(measurements)
        let history = StrengthScoreEngine.history(workouts: done, library: library, profile: profile)
        let volume = Stats.weekly(done, weeks: 12) { ws in ws.reduce(0) { $0 + $1.volume } }
        let freq = Stats.weekly(done, weeks: 12) { Double($0.count) }
        let keyLifts = ["barbell-bench-press", "barbell-back-squat", "deadlift", "military-press"]
        let series: [LiftSeries] = keyLifts.map {
            LiftSeries(id: $0, name: library.name($0),
                       points: Insights.sessions(for: $0, in: done, library: library, bodyweight: profile.bodyweight))
        }
        .filter { !$0.points.isEmpty }
        VStack(alignment: .leading, spacing: 14) {
            if history.count > 1 {
                chartCard("Strength score", subtitle: "Weekly, 0–100") {
                    Chart(history) { p in
                        AreaMark(x: .value("Week", p.date), y: .value("Score", p.score))
                            .foregroundStyle(LinearGradient(colors: [Palette.green.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Week", p.date), y: .value("Score", p.score)).foregroundStyle(Palette.green)
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                }
            }
            chartCard("Weekly volume", subtitle: "kg lifted, last 12 weeks") {
                Chart(volume) {
                    BarMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("kg", $0.value))
                        .foregroundStyle(Palette.blue.gradient).cornerRadius(5)
                }
            }
            chartCard("Workouts per week", subtitle: "Last 12 weeks") {
                Chart(freq) {
                    BarMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Workouts", $0.value))
                        .foregroundStyle(Palette.purple.gradient).cornerRadius(5)
                }
            }
            if !series.isEmpty {
                chartCard("Key lifts", subtitle: "Estimated 1RM") {
                    Chart {
                        ForEach(series) { item in
                            ForEach(item.points) { p in
                                LineMark(x: .value("Date", p.date), y: .value("kg", p.e1rm), series: .value("Lift", item.name))
                                    .foregroundStyle(by: .value("Lift", item.name))
                                    .interpolationMethod(.monotone)
                            }
                        }
                    }
                    .chartLegend(position: .bottom)
                }
            }
        }
    }

    private func chartCard<C: View>(_ title: String, subtitle: String, @ViewBuilder _ chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(Palette.text2)
            chart().frame(height: 180)
        }
        .card()
    }
}

// MARK: - Exercises

struct ExercisesPane: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @State private var search = ""
    @State private var muscle: String?
    @State private var mine = true
    @State private var limit = 40

    var body: some View {
        let done = workouts.filter { $0.endedAt != nil }
        let lifts = Insights.liftSummaries(done, library: library, bodyweight: ProfileSnapshot.current(measurements).bodyweight)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.text2)
                TextField("Search exercises…", text: $search).textInputAutocapitalization(.never)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.text2) } }
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Muscles.all, id: \.self) { m in
                        Button { muscle = muscle == m ? nil : m } label: { MuscleTile(muscle: m, selected: muscle == m) }
                            .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Chip(text: "My lifts  \(lifts.count)", selected: mine) { mine = true }
                Chip(text: "All exercises", selected: !mine) { mine = false }
            }

            if mine {
                let list = lifts.filter { l in
                    (search.isEmpty || l.name.localizedCaseInsensitiveContains(search)) &&
                    (muscle == nil || (library.exercise(l.exerciseID)?.primaryMuscles.contains(muscle!) ?? false))
                }
                if list.isEmpty {
                    Text(lifts.isEmpty ? "Exercises you log will appear here with their progress." : "No logged lifts match.")
                        .font(.subheadline).foregroundStyle(Palette.text2).card()
                }
                ForEach(list) { l in
                    NavigationLink { if let e = library.exercise(l.exerciseID) { ExerciseDetailView(exercise: e) } } label: {
                        LiftRow(lift: l, exercise: library.exercise(l.exerciseID))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                let list = library.all.filter { e in
                    (search.isEmpty || e.name.localizedCaseInsensitiveContains(search)) &&
                    (muscle == nil || e.primaryMuscles.contains(muscle!) || e.secondaryMuscles.contains(muscle!))
                }
                ForEach(list.prefix(limit)) { e in
                    NavigationLink { ExerciseDetailView(exercise: e) } label: {
                        HStack(spacing: 14) {
                            ExerciseThumb(exercise: e)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.name).font(.headline).lineLimit(1)
                                Text([e.primaryMuscles.map(MuscleName.display).joined(separator: ", "), e.allEquipment.first ?? ""]
                                        .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(Palette.text2).lineLimit(1)
                            }
                            Spacer()
                            if let l = e.level { Tag(text: l.uppercased(), color: l == "beginner" ? Palette.green : (l == "advanced" ? Palette.orange : Palette.blue)) }
                        }
                        .card(padding: 12, radius: 20)
                    }
                    .buttonStyle(.plain)
                }
                if list.count > limit {
                    Button("Show more (\(list.count - limit))") { limit += 40 }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding()
                }
            }
        }
    }
}

struct LiftRow: View {
    let lift: LiftSummary
    let exercise: Exercise?
    var body: some View {
        HStack(spacing: 14) {
            ExerciseThumb(exercise: exercise, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(lift.name).font(.headline).lineLimit(1)
                    if lift.prThisWeek { Image(systemName: "flame.fill").foregroundStyle(Palette.orange) }
                }
                Text("Last: \(SetRow.summary(lift.latest.best, exercise?.trackingType ?? .weightReps)) · \(lift.latest.date.relativeDay)")
                    .font(.subheadline).foregroundStyle(Palette.text2).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(lift.current.rounded()))").font(.title3.bold())
                    Text(lift.usesReps ? "reps" : "kg e1RM").font(.caption).foregroundStyle(Palette.text2)
                }
                HStack(spacing: 6) {
                    if abs(lift.delta) >= 0.05 {
                        Label(lift.delta.clean, systemImage: lift.delta >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(lift.delta >= 0 ? Palette.green : Palette.red)
                    }
                    Sparkline(values: lift.values).frame(width: 70, height: 26)
                }
            }
        }
        .card(padding: 12, radius: 22)
    }
}

// MARK: - Bodyweight

struct BodyweightPane: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @State private var kind: MeasurementKind = .bodyweight
    @State private var value: Double?
    @State private var date = Date()
    @State private var syncing = false

    var body: some View {
        let series = measurements.filter { $0.kind == kind }
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MeasurementKind.allCases) { k in Chip(text: k.label, selected: kind == k) { kind = k } }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let l = series.last {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(l.value.clean).font(.system(size: 44, weight: .bold))
                        Text(kind.unit).font(.title3).foregroundStyle(Palette.text2)
                    }
                    if let f = series.first, series.count > 1 {
                        let d = l.value - f.value
                        Text("\(d >= 0 ? "+" : "")\(d.clean) \(kind.unit) since \(f.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline).foregroundStyle(Palette.text2)
                    }
                } else {
                    Text("No \(kind.label.lowercased()) logged yet").font(.headline)
                }
                if series.count > 1 {
                    Chart(series) {
                        AreaMark(x: .value("Date", $0.date), y: .value(kind.unit, $0.value))
                            .foregroundStyle(LinearGradient(colors: [Palette.blue.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", $0.date), y: .value(kind.unit, $0.value)).foregroundStyle(Palette.blue)
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("Log \(kind.label.lowercased())").font(.headline)
                HStack {
                    TextField("Value", value: $value, format: .number).keyboardType(.decimalPad).font(.title3.bold())
                    Text(kind.unit).foregroundStyle(Palette.text2)
                    DatePicker("", selection: $date, displayedComponents: .date).labelsHidden()
                }
                HStack {
                    Button {
                        guard let v = value, v > 0 else { return }
                        context.insert(BodyMeasurement(kind: kind, value: v, date: date))
                        try? context.save()
                        value = nil
                    } label: {
                        Text("Save").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Palette.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled((value ?? 0) <= 0)
                    if kind == .bodyweight && HealthSync.available {
                        Button(syncing ? "Importing…" : "From Health") { importHealth() }.disabled(syncing)
                            .font(.subheadline.bold()).padding(.horizontal, 12)
                    }
                }
            }
            .card()

            if !series.isEmpty {
                SectionTitle(title: "History")
                VStack(spacing: 0) {
                    ForEach(series.reversed()) { m in
                        HStack {
                            Text(m.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(Palette.text2)
                            Spacer()
                            Text("\(m.value.clean) \(kind.unit)").bold().monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button(role: .destructive) { context.delete(m); try? context.save() } label: { Label("Delete", systemImage: "trash") }
                        }
                        Divider().overlay(Palette.stroke)
                    }
                }
                .card(padding: 14)
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
