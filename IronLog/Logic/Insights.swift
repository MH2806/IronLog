import Foundation

// MARK: - Body parts (for workout tags and split)

enum BodyPart: String, CaseIterable {
    case chest, back, shoulders, arms, legs, core

    var label: String { rawValue.uppercased() }

    static func of(_ muscle: String) -> BodyPart {
        switch muscle {
        case "chest": return .chest
        case "lats", "back", "traps": return .back
        case "shoulders": return .shoulders
        case "biceps", "triceps", "forearms": return .arms
        case "abs": return .core
        default: return .legs
        }
    }
}

enum MuscleName {
    static func display(_ m: String) -> String {
        switch m {
        case "quadriceps": return "Quads"
        case "back": return "Upper Back"
        default: return m.capitalized
        }
    }
    /// Which side of the body diagram shows this muscle best.
    static func isBack(_ m: String) -> Bool {
        ["lats", "back", "traps", "triceps", "glutes", "hamstrings", "calves"].contains(m)
    }
}

// MARK: - Per-session series

struct SessionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let workoutName: String
    let maxWeight: Double
    let e1rm: Double
    let setVolume: Double
    let reps: Int
    let best: SetEntry
    let sets: [SetEntry]
}

struct LiftSummary: Identifiable {
    var id: String { exerciseID }
    let exerciseID: String
    let name: String
    let sessions: [SessionPoint]
    let usesReps: Bool
    let prThisWeek: Bool

    var latest: SessionPoint { sessions.last! }
    var values: [Double] { sessions.suffix(14).map { usesReps ? Double($0.reps) : $0.e1rm } }
    var current: Double { usesReps ? Double(latest.reps) : latest.e1rm }
    /// Change against the first session in the last 90 days.
    var delta: Double {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        guard let base = sessions.first(where: { $0.date >= cutoff }) ?? sessions.first else { return 0 }
        return current - (usesReps ? Double(base.reps) : base.e1rm)
    }
}

// MARK: - Training split

struct SplitRow: Identifiable {
    var id: String { muscle }
    let muscle: String
    let share: Double
    let usual: Double
}

// MARK: - Milestones and badges

struct Milestone: Identifiable {
    var id: String { name }
    let name: String
    let kg: Double
    let icon: String
}

enum BadgeCategory: String, CaseIterable {
    case rank = "Rank", journey = "Journey", session = "Sessions", streak = "Streaks", records = "Records", plates = "Plate club"
}

struct Badge: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let category: BadgeCategory
    let icon: String
    let earned: Bool
    let progress: Double
}

// MARK: - Recovery

struct MuscleReadiness: Identifiable {
    var id: String { muscle }
    let muscle: String
    let recovery: Double      // 0–1
    let hoursSince: Double?
    let sets: Int
    var isReady: Bool { recovery >= 0.85 }
}

struct RecoverySummary {
    let score: Int
    let muscleRecovery: Double
    let loadRatio: Double?
    let muscles: [MuscleReadiness]
    let sleepHours: Double?
    let restingHR: Double?

    var loadLabel: String {
        guard let r = loadRatio else { return "—" }
        return r < 0.8 ? "Light" : (r <= 1.1 ? "Normal" : "Heavy")
    }
    var ready: [MuscleReadiness] { muscles.filter(\.isReady) }
    var recovering: [MuscleReadiness] { muscles.filter { !$0.isReady } }
    var headline: String {
        switch score {
        case 80...: return "You have capacity today"
        case 60..<80: return "Train, but go easy on sore muscles"
        default: return "A lighter day would help"
        }
    }
    var detail: String {
        switch score {
        case 80...: return "Your recent training and recovery signals support a normal session."
        case 60..<80: return "Some muscles are still recovering. Pick a session that trains the ready ones."
        default: return "Recent load is high and several muscles are fatigued. Consider rest or light technique work."
        }
    }
}

enum Insights {
    static func completed(_ w: [Workout]) -> [Workout] { w.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt } }

    static func sessions(for exerciseID: String, in workouts: [Workout], library: ExerciseLibrary,
                         bodyweight: Double) -> [SessionPoint] {
        let info = library.exercise(exerciseID)
        return completed(workouts).compactMap { (w: Workout) -> SessionPoint? in
            let sets = w.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.orderedSets)
                .filter { $0.completed && !$0.isWarmup }
            guard !sets.isEmpty else { return nil }
            func e(_ s: SetEntry) -> Double {
                let load = info?.effectiveLoad(weight: s.weightKg, bodyweight: bodyweight) ?? s.weightKg
                return StrengthMath.epley(load, s.reps)
            }
            let best = sets.max { e($0) < e($1) }!
            return SessionPoint(date: w.startedAt, workoutName: w.name,
                                maxWeight: sets.map(\.weightKg).max() ?? 0, e1rm: e(best),
                                setVolume: sets.map { $0.weightKg * Double($0.reps) }.max() ?? 0,
                                reps: sets.map(\.reps).max() ?? 0, best: best, sets: sets)
        }
    }

    static func liftSummaries(_ workouts: [Workout], library: ExerciseLibrary, bodyweight: Double) -> [LiftSummary] {
        let done = completed(workouts)
        var lastSeen: [String: Date] = [:]
        for w in done { for ex in w.exercises where ex.sets.contains(where: \.completed) { lastSeen[ex.exerciseID] = w.startedAt } }
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        return lastSeen.sorted { $0.value > $1.value }.compactMap { (entry: (key: String, value: Date)) -> LiftSummary? in
            let id = entry.key
            let info = library.exercise(id)
            guard info?.trackingType.isRepBased ?? true else { return nil }
            let s = sessions(for: id, in: done, library: library, bodyweight: bodyweight)
            guard !s.isEmpty else { return nil }
            let usesReps = info?.trackingType == .bodyweightReps && s.allSatisfy { $0.maxWeight == 0 }
            let pr = done.contains { w in
                w.startedAt >= weekAgo && w.exercises.contains { $0.exerciseID == id && $0.sets.contains(where: \.isPR) }
            }
            return LiftSummary(exerciseID: id, name: library.name(id), sessions: s, usesReps: usesReps, prThisWeek: pr)
        }
    }

    static func bodyParts(of w: Workout, library: ExerciseLibrary) -> [BodyPart] {
        var count: [BodyPart: Int] = [:]
        for ex in w.exercises {
            let n = max(1, ex.sets.filter(\.completed).count)
            for m in library.exercise(ex.exerciseID)?.primaryMuscles ?? [] { count[BodyPart.of(m), default: 0] += n }
        }
        let total = max(1, count.values.reduce(0, +))
        return count.filter { Double($0.value) / Double(total) >= 0.2 }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
    }

    static func totalReps(_ w: Workout) -> Int { w.workingSets.reduce(0) { $0 + $1.reps } }

    // Split: share of primary working sets per muscle, last 30 days vs last 180 days.
    static func split(_ workouts: [Workout], library: ExerciseLibrary) -> [SplitRow] {
        func shares(days: Double) -> [String: Double] {
            let since = Date().addingTimeInterval(-days * 86400)
            var c: [String: Double] = [:]
            for w in workouts where w.endedAt != nil && w.startedAt >= since {
                for ex in w.exercises {
                    let n = Double(ex.sets.filter { $0.completed && !$0.isWarmup }.count)
                    for m in library.exercise(ex.exerciseID)?.primaryMuscles ?? [] { c[m, default: 0] += n }
                }
            }
            let t = max(1, c.values.reduce(0, +))
            return c.mapValues { $0 / t }
        }
        let now = shares(days: 30), usual = shares(days: 180)
        return Set(now.keys).union(usual.keys)
            .map { SplitRow(muscle: $0, share: now[$0] ?? 0, usual: usual[$0] ?? 0) }
            .sorted { $0.share > $1.share }
    }

    static func splitTip(_ rows: [SplitRow]) -> String? {
        guard let under = rows.filter({ $0.usual >= 0.04 }).max(by: { ($0.usual - $0.share) < ($1.usual - $1.share) }),
              under.usual - under.share >= 0.01 else { return nil }
        return "Add one \(MuscleName.display(under.muscle).lowercased()) session this month and your split lines up with your usual balance."
    }

    static let milestones: [Milestone] = [
        Milestone(name: "Grand piano", kg: 500, icon: "pianokeys"),
        Milestone(name: "Family car", kg: 1_500, icon: "car.fill"),
        Milestone(name: "Hippo", kg: 3_000, icon: "pawprint.fill"),
        Milestone(name: "African elephant", kg: 6_000, icon: "pawprint.fill"),
        Milestone(name: "T. rex", kg: 8_000, icon: "lizard.fill"),
        Milestone(name: "Double-decker bus", kg: 12_000, icon: "bus.fill"),
        Milestone(name: "Humpback whale", kg: 30_000, icon: "fish.fill"),
        Milestone(name: "Tram", kg: 60_000, icon: "tram.fill"),
        Milestone(name: "Blue whale", kg: 150_000, icon: "fish.fill"),
        Milestone(name: "Statue of Liberty", kg: 225_000, icon: "building.columns.fill"),
        Milestone(name: "Boeing 747", kg: 400_000, icon: "airplane"),
        Milestone(name: "Space station", kg: 420_000, icon: "globe.europe.africa.fill"),
        Milestone(name: "High-speed train", kg: 700_000, icon: "train.side.front.car"),
        Milestone(name: "Saturn V rocket", kg: 2_900_000, icon: "flame.fill"),
        Milestone(name: "Eiffel Tower", kg: 7_300_000, icon: "building.2.fill"),
        Milestone(name: "Titanic", kg: 52_000_000, icon: "ferry.fill"),
    ]

    static func milestoneProgress(total: Double) -> (latest: Milestone?, next: Milestone?, fraction: Double) {
        let latest = milestones.last { $0.kg <= total }
        let next = milestones.first { $0.kg > total }
        guard let next else { return (latest, nil, 1) }
        let base = latest?.kg ?? 0
        return (latest, next, (total - base) / (next.kg - base))
    }

    static func badges(_ workouts: [Workout], library: ExerciseLibrary, report: StrengthScoreReport) -> [Badge] {
        let done = completed(workouts)
        let n = done.count
        let volume = done.reduce(0) { $0 + $1.volume }
        let prs = done.reduce(0) { $0 + $1.prCount }
        let streak = Stats.streakWeeks(done)
        func heaviest(_ ids: [String]) -> Double {
            done.flatMap { $0.exercises.filter { ids.contains($0.exerciseID) } }.flatMap(\.sets)
                .filter { $0.completed && $0.reps >= 1 }.map(\.weightKg).max() ?? 0
        }
        let bench = heaviest(["barbell-bench-press"]), squat = heaviest(["barbell-back-squat"])
        let dead = heaviest(["deadlift", "sumo-deadlift"])
        var out: [Badge] = []
        let level = report.level?.rawValue ?? -1
        for l in StrengthLevel.allCases.dropFirst() {
            out.append(Badge(title: l.name, detail: "Reach \(l.name) overall", category: .rank, icon: "shield.fill",
                             earned: level >= l.rawValue, progress: level >= l.rawValue ? 1 : max(0, Double(level + 1) / Double(l.rawValue + 1))))
        }
        for m in milestones.prefix(12) {
            out.append(Badge(title: m.name, detail: "Lift \(Int(m.kg).formatted()) kg in total", category: .journey, icon: m.icon,
                             earned: volume >= m.kg, progress: min(1, volume / m.kg)))
        }
        for t in [1, 10, 25, 50, 100, 250, 500] {
            out.append(Badge(title: t == 1 ? "First session" : "\(t) sessions", detail: "Finish \(t) workout\(t == 1 ? "" : "s")",
                             category: .session, icon: "figure.strengthtraining.traditional", earned: n >= t, progress: min(1, Double(n) / Double(t))))
        }
        for t in [4, 12, 26, 52] {
            out.append(Badge(title: "\(t)-week streak", detail: "Train every week for \(t) weeks", category: .streak, icon: "flame.fill",
                             earned: streak >= t, progress: min(1, Double(streak) / Double(t))))
        }
        for t in [10, 50, 100, 250, 500] {
            out.append(Badge(title: "\(t) PRs", detail: "Set \(t) personal records", category: .records, icon: "trophy.fill",
                             earned: prs >= t, progress: min(1, Double(prs) / Double(t))))
        }
        let plates: [(String, Double, Double)] = [("Bench", 60, bench), ("Bench", 100, bench), ("Bench", 140, bench),
                                                  ("Squat", 100, squat), ("Squat", 140, squat), ("Squat", 180, squat),
                                                  ("Deadlift", 140, dead), ("Deadlift", 180, dead), ("Deadlift", 220, dead)]
        for (lift, kg, best) in plates {
            let count = Int((kg - 20) / 40)
            out.append(Badge(title: "\(count)-plate \(lift.lowercased())", detail: "\(lift) \(Int(kg)) kg for a rep",
                             category: .plates, icon: "circle.circle.fill", earned: best >= kg, progress: min(1, best / kg)))
        }
        return out
    }

    // MARK: Recovery

    static func readiness(_ workouts: [Workout], library: ExerciseLibrary) -> [MuscleReadiness] {
        let since = Date().addingTimeInterval(-7 * 86400)
        var last: [String: Date] = [:], sets: [String: Int] = [:]
        for w in workouts where w.endedAt != nil && w.startedAt >= since {
            var c: [String: Int] = [:]
            for ex in w.exercises {
                let n = ex.sets.filter { $0.completed && !$0.isWarmup }.count
                for m in library.exercise(ex.exerciseID)?.primaryMuscles ?? [] { c[m, default: 0] += n }
            }
            let t = w.endedAt ?? w.startedAt
            for (m, n) in c where n > 0 && t > (last[m] ?? .distantPast) { last[m] = t; sets[m] = n }
        }
        return Muscles.all.map { (m: String) -> MuscleReadiness in
            guard let t = last[m] else { return MuscleReadiness(muscle: m, recovery: 1, hoursSince: nil, sets: 0) }
            let h = Date().timeIntervalSince(t) / 3600
            let n = sets[m] ?? 0
            let needed: Double = n >= 6 ? 72 : (n >= 3 ? 48 : 24)
            return MuscleReadiness(muscle: m, recovery: min(1, h / needed), hoursSince: h, sets: n)
        }
    }

    static func recovery(_ workouts: [Workout], library: ExerciseLibrary, sleep: Double?, restingHR: Double?) -> RecoverySummary {
        let muscles = readiness(workouts, library: library)
        let trained = muscles.filter { $0.hoursSince != nil }
        let muscle = trained.isEmpty ? 1 : trained.map(\.recovery).reduce(0, +) / Double(trained.count)
        let now = Date()
        let done = workouts.filter { $0.endedAt != nil }
        let last7 = done.filter { $0.startedAt >= now.addingTimeInterval(-7 * 86400) }.reduce(0) { $0 + $1.volume }
        let last28 = done.filter { $0.startedAt >= now.addingTimeInterval(-28 * 86400) }.reduce(0) { $0 + $1.volume }
        let ratio: Double? = last28 > 0 ? last7 / (last28 / 4) : nil
        var score = muscle * 100
        if let r = ratio, r > 1.2 { score -= min(15, (r - 1.2) * 50) }
        if let s = sleep { score = score * 0.8 + min(100, s / 8 * 100) * 0.2 }
        return RecoverySummary(score: Int(max(0, min(100, score)).rounded()), muscleRecovery: muscle, loadRatio: ratio,
                               muscles: muscles, sleepHours: sleep, restingHR: restingHR)
    }
}
