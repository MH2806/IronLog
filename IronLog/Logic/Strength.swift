import Foundation

enum StrengthMath {
    /// Epley, used for charts at any rep count.
    static func epley(_ weight: Double, _ reps: Int) -> Double {
        reps <= 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// e1RM used for scoring. Only sets of 1–10 reps count (estimates beyond 10
    /// reps are unreliable). Average of Epley and Brzycki.
    static func scoringE1RM(_ weight: Double, _ reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= 10 else { return nil }
        if reps == 1 { return weight }
        let r = Double(reps)
        return (weight * (1 + r / 30) + weight * 36 / (37 - r)) / 2
    }

    static func dots(total: Double, bodyweight: Double, sex: Sex, ref: ReferenceData) -> Double? {
        let c = sex == .male ? ref.formulas.dots.M : ref.formulas.dots.F
        guard c.count == 5, let range = ref.formulas.dots.bw[sex.rawValue], range.count == 2 else { return nil }
        let x = min(max(bodyweight, range[0]), range[1])
        let denom = c[0] * pow(x, 4) + c[1] * pow(x, 3) + c[2] * x * x + c[3] * x + c[4]
        return denom > 0 ? total * 500 / denom : nil
    }

    static func goodlift(total: Double, bodyweight: Double, sex: Sex, kind: String, ref: ReferenceData) -> Double? {
        guard let g = ref.formulas.goodlift?[sex.rawValue]?[kind], g.count == 3 else { return nil }
        let denom = g[0] - g[1] * exp(-g[2] * bodyweight)
        return denom > 0 ? total * 100 / denom : nil
    }

    /// Linear interpolation through a 1st..99th percentile curve.
    static func percentile(of v: Double, curve p: [Double]) -> Double {
        guard let first = p.first, let last = p.last else { return 0 }
        if v <= first { return first > 0 ? max(0, v / first) : 0 }
        if v >= last { return 99.5 }
        for i in 0..<(p.count - 1) where v >= p[i] && v < p[i + 1] {
            let span = p[i + 1] - p[i]
            return Double(i + 1) + (span > 0 ? (v - p[i]) / span : 0)
        }
        return 99.5
    }

    /// Value needed to reach a given percentile (for "next tier" targets).
    static func value(atPercentile target: Int, curve p: [Double]) -> Double? {
        guard target >= 1, target <= p.count else { return nil }
        return p[target - 1]
    }

    static func bin(for bodyweight: Double, in bins: [ReferenceData.Bin]) -> ReferenceData.Bin? {
        guard let last = bins.last else { return nil }
        if last.hi == nil && bodyweight >= last.bw - 2.5 { return last }
        return bins.min { abs($0.bw - bodyweight) < abs($1.bw - bodyweight) }
    }
}

enum KeyLift: String, CaseIterable, Identifiable {
    case squat, bench, deadlift
    var id: String { rawValue }
    var title: String {
        switch self {
        case .squat: return "Squat"
        case .bench: return "Bench press"
        case .deadlift: return "Deadlift"
        }
    }
    /// Only competition-style variants are compared against meet data.
    var exerciseIDs: [String] {
        switch self {
        case .squat: return ["barbell-back-squat"]
        case .bench: return ["barbell-bench-press"]
        case .deadlift: return ["deadlift", "sumo-deadlift"]
        }
    }
    var muscles: [String] {
        switch self {
        case .squat: return ["quadriceps", "glutes"]
        case .bench: return ["chest", "triceps", "shoulders"]
        case .deadlift: return ["hamstrings", "back", "glutes"]
        }
    }
}

struct LiftStanding: Identifiable {
    var id: String { lift.rawValue }
    let lift: KeyLift
    let e1rm: Double?
    let date: Date?
    let percentile: Double?
    let cohort: String?
    let nextTierTarget: Double?
}

struct StrengthReport {
    let standings: [LiftStanding]
    let total: Double?
    let totalPercentile: Double?
    let dots: Double?
    let goodlift: Double?
    let dotsPercentile: Double?
    let dotsAgePercentile: Double?
    let ageBandLabel: String?
    let cohortSize: Int?
    let bodyweight: Double
    let sex: Sex
    let population: String
    let hasReference: Bool

    var score: Int? { dots.map { Int($0.rounded()) } }

    func percentile(forMuscle m: String) -> Double? {
        standings.filter { $0.lift.muscles.contains(m) }.compactMap(\.percentile).max()
    }
}

enum StrengthEngine {
    static let windowDays = 180

    static func bestE1RM(ids: [String], workouts: [Workout], from: Date, to: Date) -> (Double, Date)? {
        var best: (Double, Date)?
        for w in workouts where w.endedAt != nil && w.startedAt >= from && w.startedAt <= to {
            for ex in w.exercises where ids.contains(ex.exerciseID) {
                for s in ex.sets where s.completed && !s.isWarmup {
                    if let e = StrengthMath.scoringE1RM(s.weightKg, s.reps), e > (best?.0 ?? 0) {
                        best = (e, w.startedAt)
                    }
                }
            }
        }
        return best
    }

    static func report(workouts: [Workout], profile: ProfileSnapshot, asOf: Date = .now) -> StrengthReport {
        let ref = ReferenceData.shared
        let bw = profile.bodyweight(at: asOf)
        let sexData = ref?.sexData(profile.sex, population: profile.population)
        let from = Calendar.current.date(byAdding: .day, value: -windowDays, to: asOf) ?? asOf

        var standings: [LiftStanding] = []
        for lift in KeyLift.allCases {
            let best = bestE1RM(ids: lift.exerciseIDs, workouts: workouts, from: from, to: asOf)
            var pct: Double?
            var cohort: String?
            var target: Double?
            if let best, let bins = sexData?.lifts[lift.rawValue]?.bins,
               let bin = StrengthMath.bin(for: bw, in: bins) {
                let p = StrengthMath.percentile(of: best.0, curve: bin.p)
                pct = p
                cohort = cohortText(bin)
                let next = [25, 50, 75, 90].first { Double($0) > p }
                target = next.flatMap { StrengthMath.value(atPercentile: $0, curve: bin.p) }
            }
            standings.append(LiftStanding(lift: lift, e1rm: best?.0, date: best?.1,
                                          percentile: pct, cohort: cohort, nextTierTarget: target))
        }

        let lifts = standings.compactMap(\.e1rm)
        let total: Double? = lifts.count == 3 ? lifts.reduce(0, +) : nil
        var dots: Double?, gl: Double?, totalPct: Double?, dotsPct: Double?, agePct: Double?
        var ageLabel: String?
        if let total, let ref {
            dots = StrengthMath.dots(total: total, bodyweight: bw, sex: profile.sex, ref: ref)
            gl = StrengthMath.goodlift(total: total, bodyweight: bw, sex: profile.sex, kind: "sbd", ref: ref)
            if let bins = sexData?.lifts["total"]?.bins, let bin = StrengthMath.bin(for: bw, in: bins) {
                totalPct = StrengthMath.percentile(of: total, curve: bin.p)
            }
            if let dots, let d = sexData?.dots {
                dotsPct = StrengthMath.percentile(of: dots, curve: d.all.p)
                if let age = profile.age, let band = d.ageBands.first(where: { age >= $0.lo && age <= $0.hi }) {
                    agePct = StrengthMath.percentile(of: dots, curve: band.p)
                    ageLabel = band.hi >= 99 ? "\(band.lo)+" : "\(band.lo)–\(band.hi)"
                }
            }
        }
        return StrengthReport(standings: standings, total: total, totalPercentile: totalPct,
                              dots: dots, goodlift: gl, dotsPercentile: dotsPct,
                              dotsAgePercentile: agePct, ageBandLabel: ageLabel,
                              cohortSize: sexData?.dots.all.n, bodyweight: bw, sex: profile.sex,
                              population: profile.population, hasReference: ref != nil)
    }

    static func cohortText(_ bin: ReferenceData.Bin) -> String {
        let range = bin.hi.map { "\(bin.lo.clean)–\($0.clean) kg" } ?? "\(bin.lo.clean)+ kg"
        return "\(range), \(bin.n.formatted()) lifters"
    }

    struct ScorePoint: Identifiable {
        var id: Date { date }
        let date: Date
        let dots: Double
    }

    /// Weekly DOTS history using bodyweight at the time.
    static func scoreHistory(workouts: [Workout], profile: ProfileSnapshot, weeks: Int = 26) -> [ScorePoint] {
        guard let ref = ReferenceData.shared else { return [] }
        let cal = Calendar.current
        var out: [ScorePoint] = []
        for w in stride(from: weeks - 1, through: 0, by: -1) {
            guard let end = cal.date(byAdding: .weekOfYear, value: -w, to: .now),
                  let start = cal.date(byAdding: .day, value: -windowDays, to: end) else { continue }
            let bests = KeyLift.allCases.compactMap { bestE1RM(ids: $0.exerciseIDs, workouts: workouts, from: start, to: end)?.0 }
            guard bests.count == 3,
                  let d = StrengthMath.dots(total: bests.reduce(0, +), bodyweight: profile.bodyweight(at: end),
                                            sex: profile.sex, ref: ref) else { continue }
            out.append(ScorePoint(date: end, dots: d))
        }
        return out
    }
}
