import SwiftUI
import SwiftData

// MARK: - Community

struct CommunityTab: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.name) private var name = ""
    @State private var friends = FriendCard.load()
    @State private var pasted = ""
    @State private var error: String?
    @State private var showAdd = false

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "Community", subtitle: "Compete with friends on Strength Score") {
                        SquareIconButton(icon: "person.badge.plus") { showAdd = true }
                    }

                    if board.count >= 2 { podium(Array(board.prefix(3)), mine: mine) }

                    SectionTitle(title: "Leaderboard")
                    ForEach(Array(board.enumerated()), id: \.element.id) { item in
                        row(item.offset + 1, item.element, isMe: item.element.id == mine.id)
                            .contextMenu {
                                if item.element.id != mine.id {
                                    Button(role: .destructive) {
                                        friends.removeAll { $0.id == item.element.id }
                                        FriendCard.save(friends)
                                    } label: { Label("Remove", systemImage: "trash") }
                                }
                            }
                    }
                    if friends.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Invite your gym mates").font(.headline)
                            Text("No accounts or servers: share your code, paste theirs. Re-share after a good session to update the board.")
                                .font(.subheadline).foregroundStyle(Palette.text2)
                        }
                        .card()
                    }

                    ShareLink(item: mine.code, preview: SharePreview("My IronLog strength card")) {
                        Label("Share my code", systemImage: "square.and.arrow.up").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Palette.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    NavigationLink { CompetitionComparisonView() } label: {
                        HStack(spacing: 14) {
                            IconTile(icon: "globe.europe.africa.fill", color: Palette.purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Compare with competitors").font(.headline)
                                Text("Where your squat, bench and deadlift sit among real meet results").font(.subheadline)
                                    .foregroundStyle(Palette.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 90)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { addSheet }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste the code your friend shared with you.").foregroundStyle(Palette.text2)
                TextField("Friend's code", text: $pasted, axis: .vertical).font(.caption.monospaced())
                    .padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let error { Text(error).foregroundStyle(Palette.red).font(.caption) }
                Button {
                    guard let card = FriendCard.decode(pasted) else { error = "That isn't a valid IronLog code."; return }
                    friends.removeAll { $0.id == card.id }
                    friends.append(card)
                    FriendCard.save(friends)
                    pasted = ""
                    error = nil
                    showAdd = false
                } label: {
                    Text("Add friend").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Palette.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(pasted.isEmpty)
                Spacer()
            }
            .padding(16)
            .screenBackground()
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Close") { showAdd = false } }
        }
        .presentationDetents([.medium])
    }

    private func level(_ f: FriendCard) -> StrengthLevel? { f.score.map { Rank.from(points: ScoreScale.points(Double($0))).level } }

    private func podium(_ top: [FriendCard], mine: FriendCard) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach([1, 0, 2].filter { $0 < top.count }, id: \.self) { i in
                let f = top[i]
                let lvl = level(f) ?? .beginner
                VStack(spacing: 8) {
                    RankBadge(level: lvl, tier: f.score.map { Rank.from(points: ScoreScale.points(Double($0))).tier } ?? 1,
                              size: i == 0 ? 54 : 42, glow: i == 0)
                    Text(f.id == mine.id ? "You" : f.name).font(.subheadline.bold()).lineLimit(1)
                    Text(f.score.map { "\($0)" } ?? "–").font(.title2.bold()).foregroundStyle(lvl.color)
                    Text(["1st", "2nd", "3rd"][i]).font(.caption.weight(.bold)).foregroundStyle(Palette.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, i == 0 ? 26 : 14)
                        .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card()
    }

    private func row(_ place: Int, _ f: FriendCard, isMe: Bool) -> some View {
        let lvl = level(f)
        return HStack(spacing: 12) {
            Text("\(place)").font(.headline).foregroundStyle(Palette.text2).frame(width: 24)
            ZStack {
                Circle().fill(isMe ? Palette.blueSoft : Palette.cardHi)
                Text(initials(f.name)).font(.subheadline.bold())
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(isMe ? "\(f.name) (you)" : f.name).font(.headline)
                Text("S \(f.squat?.clean ?? "–") · B \(f.bench?.clean ?? "–") · D \(f.deadlift?.clean ?? "–") · \(f.bodyweight.clean) kg")
                    .font(.caption).foregroundStyle(Palette.text2).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(f.score.map { "\($0)" } ?? "–").font(.title3.bold()).monospacedDigit().foregroundStyle(lvl?.color ?? Palette.text2)
                Text(lvl?.name ?? "Unranked").font(.caption).foregroundStyle(Palette.text2)
            }
        }
        .card(padding: 14, radius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isMe ? Palette.blue.opacity(0.6) : .clear, lineWidth: 1))
    }
}

func initials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2)
    let s = parts.compactMap { $0.first }.map(String.init).joined()
    return s.isEmpty ? "?" : s.uppercased()
}

// MARK: - Profile

struct ProfileTab: View {
    enum Pane: Hashable { case stats, badges, tools }
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @Query private var measurements: [BodyMeasurement]
    @AppStorage(Keys.name) private var name = ""
    @State private var pane: Pane = .stats
    @State private var showSettings = false

    var body: some View {
        let done = workouts.filter { $0.endedAt != nil }
        let report = StrengthScoreEngine.report(workouts: done, library: library, profile: .current(measurements))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(done, report: report)
                    PillTabs(options: [(Pane.stats, "Stats"), (Pane.badges, "Badges"), (Pane.tools, "Tools")], selection: $pane)
                    switch pane {
                    case .stats: stats(done)
                    case .badges: BadgeGrid(badges: Insights.badges(done, library: library, report: report))
                    case .tools: ToolsGrid()
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 90)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func header(_ done: [Workout], report: StrengthScoreReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().fill(Palette.cardHi)
                    Circle().stroke(report.level?.color ?? Palette.stroke, lineWidth: 3)
                    Text(initials(name.isEmpty ? "Iron Log" : name)).font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.text2)
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name.isEmpty ? "Your name" : name).font(.title.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    if let rank = report.rank {
                        HStack(spacing: 6) {
                            RankBadge(level: rank.level, tier: rank.tier, size: 22)
                            Text(rank.name).font(.subheadline.weight(.semibold)).foregroundStyle(rank.level.color)
                        }
                    } else {
                        Text("Unranked").font(.subheadline).foregroundStyle(Palette.text2)
                    }
                }
            }
            Divider().overlay(Palette.stroke)
            HStack(spacing: 0) {
                headerStat("\(done.count)", "WORKOUTS")
                Divider().frame(height: 40).overlay(Palette.stroke)
                headerStat("\(done.reduce(0) { $0 + $1.prCount })", "PRS")
                Divider().frame(height: 40).overlay(Palette.stroke)
                headerStat(report.score.map { "\($0)" } ?? "–", "SCORE")
            }
            Button { showSettings = true } label: {
                Label("Edit profile", systemImage: "pencil").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Palette.stroke, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            Divider().overlay(Palette.stroke)
            ActivityHeatmap(workouts: done)
        }
        .card()
    }

    private func headerStat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).font(.title2.bold()).monospacedDigit()
            Text(l).font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func stats(_ done: [Workout]) -> some View {
        let streak = Stats.streakWeeks(done)
        let week = done.filter { $0.startedAt >= Stats.weekStart(.now) }
        HStack(spacing: 16) {
            IconTile(icon: "flame.fill", color: streak > 0 ? Palette.orange : Palette.blue, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak) week streak").font(.title3.bold())
                Text(streak > 0 ? "Trained every week since \(Calendar.current.date(byAdding: .weekOfYear, value: -(streak - 1), to: Stats.weekStart(.now))?.formatted(.dateTime.day().month(.abbreviated)) ?? "")" : "Train this week to start one")
                    .font(.subheadline).foregroundStyle(Palette.text2)
            }
        }
        .card()
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK").font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2)
            HStack(spacing: 10) {
                weekTile("\(week.count)", "WORKOUTS")
                weekTile("\(Int(week.reduce(0) { $0 + $1.volume }).formatted()) kg", "VOLUME")
                weekTile("\(week.reduce(0) { $0 + Insights.totalReps($1) })", "REPS")
            }
        }
        .card()
        NavigationLink { StrengthProfileView() } label: {
            HStack(spacing: 14) {
                IconTile(icon: "trophy.fill", color: Palette.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Strength Score").font(.headline)
                    Text("Ranks, muscle map and per-lift standards").font(.subheadline).foregroundStyle(Palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
            }
            .card()
        }
        .buttonStyle(.plain)
        NavigationLink { RecoveryView() } label: {
            HStack(spacing: 14) {
                IconTile(icon: "battery.75percent", color: Palette.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery").font(.headline)
                    Text("Readiness score and muscle-by-muscle recovery").font(.subheadline).foregroundStyle(Palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.text3)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private func weekTile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v).font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.caption.weight(.bold)).tracking(1).foregroundStyle(Palette.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// GitHub-style activity grid for the last 26 weeks.
struct ActivityHeatmap: View {
    let workouts: [Workout]
    private let weeks = 26

    var body: some View {
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for w in workouts { counts[cal.startOfDay(for: w.startedAt), default: 0] += 1 }
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: Stats.weekStart(.now)) ?? .now
        let recent = workouts.filter { $0.startedAt >= start }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY").font(.footnote.weight(.semibold)).tracking(3).foregroundStyle(Palette.text2)
                Spacer()
                Text("\(recent) workouts").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text2)
            }
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        Text(["M", "", "W", "", "F", "", "S"][d]).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.text2)
                            .frame(width: 10, height: 11)
                    }
                }
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            let n = counts[cal.startOfDay(for: day)] ?? 0
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(day > .now ? Color.clear : (n == 0 ? Palette.cardHi : Palette.blue.opacity(n > 1 ? 1 : 0.7)))
                                .frame(height: 11)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(start.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(Palette.text2)
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(Palette.text2)
                RoundedRectangle(cornerRadius: 2).fill(Palette.cardHi).frame(width: 10, height: 10)
                RoundedRectangle(cornerRadius: 2).fill(Palette.blue.opacity(0.7)).frame(width: 10, height: 10)
                RoundedRectangle(cornerRadius: 2).fill(Palette.blue).frame(width: 10, height: 10)
                Text("More").font(.caption2).foregroundStyle(Palette.text2)
            }
        }
    }
}
