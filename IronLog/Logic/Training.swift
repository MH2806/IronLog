import Foundation
import SwiftData

// MARK: - Analytics

struct ExercisePoint: Identifiable {
    let id = UUID()
    let date: Date
    let e1rm: Double
    let bestWeight: Double
    let bestReps: Int
    let volume: Double
}

struct WeekValue: Identifiable {
    var id: Date { week }
    let week: Date
    let value: Double
}

struct MuscleRecovery: Identifiable {
    var id: String { muscle }
    let muscle: String
    let state: RecoveryState
    let hours: Double?
}

enum RecoveryState: String {
    case fatigued = "Fatigued", recovering = "Recovering", ready = "Ready", untrained = "Not trained recently"
}

enum Stats {
    /// Per-session progress. Primary metric depends on how the exercise is tracked:
    /// estimated 1RM (kg) for rep-based work, longest hold (s) for timed work, distance (km) for cardio.
    static func history(for exerciseID: String, in workouts: [Workout], library: ExerciseLibrary,
                        bodyweight: Double) -> [ExercisePoint] {
        let info = library.exercise(exerciseID)
        let tracking = info?.trackingType ?? .weightReps
        return workouts.filter { $0.endedAt != nil }.compactMap { (w: Workout) -> ExercisePoint? in
            let sets = w.exercises.filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets).filter { $0.completed && !$0.isWarmup }
            guard !sets.isEmpty else { return nil }
            let volume = sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
            let heaviest = sets.map(\.weightKg).max() ?? 0
            switch tracking {
            case .duration:
                return ExercisePoint(date: w.startedAt, e1rm: Double(sets.map(\.durationSec).max() ?? 0),
                                     bestWeight: heaviest, bestReps: 0, volume: volume)
            case .cardio:
                return ExercisePoint(date: w.startedAt, e1rm: sets.reduce(0) { $0 + $1.distanceM } / 1000,
                                     bestWeight: 0, bestReps: 0, volume: Double(sets.reduce(0) { $0 + $1.durationSec }) / 60)
            case .weightDistance:
                return ExercisePoint(date: w.startedAt, e1rm: heaviest, bestWeight: heaviest, bestReps: 0,
                                     volume: sets.reduce(0) { $0 + $1.weightKg * $1.distanceM })
            default:
                func load(_ s: SetEntry) -> Double {
                    let l = info?.effectiveLoad(weight: s.weightKg, bodyweight: bodyweight) ?? s.weightKg
                    return StrengthMath.epley(l, s.reps)
                }
                let top = sets.max { load($0) < load($1) }!
                return ExercisePoint(date: w.startedAt, e1rm: load(top), bestWeight: heaviest,
                                     bestReps: top.reps, volume: volume)
            }
        }.sorted { $0.date < $1.date }
    }

    /// Last completed working sets for an exercise, used for "previous" column and smart defaults.
    static func lastSets(for exerciseID: String, in workouts: [Workout], excluding: Workout? = nil) -> [SetEntry] {
        let done = workouts.filter { $0.endedAt != nil && $0.id != excluding?.id }
            .sorted { $0.startedAt > $1.startedAt }
        for w in done {
            let sets = w.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.orderedSets).filter(\.completed)
            if !sets.isEmpty { return sets }
        }
        return []
    }

    static func weekStart(_ d: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: d)?.start ?? d
    }

    static func weekly(_ workouts: [Workout], weeks: Int, value: ([Workout]) -> Double) -> [WeekValue] {
        let cal = Calendar.current
        let thisWeek = weekStart(.now)
        return (0..<weeks).reversed().compactMap { (i: Int) -> WeekValue? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -i, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let ws = workouts.filter { $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end }
            return WeekValue(week: start, value: value(ws))
        }
    }

    /// Hard sets per muscle: primary muscle = 1 set, secondary = 0.5.
    static func setsPerMuscle(_ workouts: [Workout], library: ExerciseLibrary, since: Date) -> [String: Double] {
        var out: [String: Double] = [:]
        for w in workouts where w.endedAt != nil && w.startedAt >= since {
            for ex in w.exercises {
                guard let info = library.exercise(ex.exerciseID) else { continue }
                let n = Double(ex.sets.filter { $0.completed && !$0.isWarmup }.count)
                guard n > 0 else { continue }
                for m in info.primaryMuscles { out[m, default: 0] += n }
                for m in info.secondaryMuscles { out[m, default: 0] += n * 0.5 }
            }
        }
        return out
    }

    /// Heuristic: a muscle hit with >= 3 hard (primary) sets needs ~48h.
    static func recovery(_ workouts: [Workout], library: ExerciseLibrary) -> [MuscleRecovery] {
        var last: [String: Date] = [:]
        let since = Date().addingTimeInterval(-7 * 86400)
        for w in workouts where w.endedAt != nil && w.startedAt >= since {
            var counts: [String: Int] = [:]
            for ex in w.exercises {
                guard let info = library.exercise(ex.exerciseID) else { continue }
                let n = ex.sets.filter { $0.completed && !$0.isWarmup }.count
                for m in info.primaryMuscles { counts[m, default: 0] += n }
            }
            let t = w.endedAt ?? w.startedAt
            for (m, c) in counts where c >= 3 {
                if t > (last[m] ?? .distantPast) { last[m] = t }
            }
        }
        return Muscles.all.map { (m: String) -> MuscleRecovery in
            guard let t = last[m] else { return MuscleRecovery(muscle: m, state: .untrained, hours: nil) }
            let h = Date().timeIntervalSince(t) / 3600
            let s: RecoveryState = h < 24 ? .fatigued : (h < 48 ? .recovering : .ready)
            return MuscleRecovery(muscle: m, state: s, hours: h)
        }
    }

    static func activityDays(_ workouts: [Workout]) -> Set<Date> {
        Set(workouts.filter { $0.endedAt != nil }.map { Calendar.current.startOfDay(for: $0.startedAt) })
    }

    static func streakWeeks(_ workouts: [Workout]) -> Int {
        let weeks = Set(workouts.filter { $0.endedAt != nil }.map { weekStart($0.startedAt) })
        var n = 0
        var cursor = weekStart(.now)
        if !weeks.contains(cursor) { cursor = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor }
        while weeks.contains(cursor) {
            n += 1
            cursor = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return n
    }
}

// MARK: - PR detection

enum PRDetector {
    /// Returns a description if this set beats every earlier set of the exercise.
    static func check(_ set: SetEntry, exercise info: Exercise?, exerciseID: String, workouts: [Workout],
                      bodyweight: Double) -> String? {
        guard !set.isWarmup else { return nil }
        let tracking = info?.trackingType ?? .weightReps
        let prior = workouts.flatMap { $0.exercises.filter { $0.exerciseID == exerciseID } }
            .flatMap(\.sets).filter { $0.completed && !$0.isWarmup && $0.id != set.id }
        guard !prior.isEmpty else { return nil } // first time doing it; not a meaningful PR

        switch tracking {
        case .duration:
            let best = prior.map(\.durationSec).max() ?? 0
            return set.durationSec > best ? "Longest hold: \(set.durationSec)s" : nil
        case .cardio:
            let best = prior.map(\.distanceM).max() ?? 0
            return set.distanceM > best ? "Longest distance: \((set.distanceM / 1000).clean) km" : nil
        case .weightDistance:
            let best = prior.map(\.weightKg).max() ?? 0
            return set.weightKg > best ? "Heaviest carry: \(set.weightKg.kg)" : nil
        default:
            guard set.reps > 0 else { return nil }
            func e(_ s: SetEntry) -> Double {
                StrengthMath.epley(info?.effectiveLoad(weight: s.weightKg, bodyweight: bodyweight) ?? s.weightKg, s.reps)
            }
            let bestE = prior.map(e).max() ?? 0
            let bestWeight = prior.map(\.weightKg).max() ?? 0
            let repsAtBest = prior.filter { $0.weightKg == bestWeight }.map(\.reps).max() ?? 0
            if tracking == .weightReps && set.weightKg > bestWeight { return "Heaviest weight: \(set.weightKg.kg)" }
            if e(set) > bestE + 0.01 { return "Best estimated 1RM: \(e(set).kg)" }
            if tracking != .assistedReps && set.weightKg == bestWeight && set.reps > repsAtBest {
                return tracking == .bodyweightReps && bestWeight == 0 ? "Most reps: \(set.reps)" : "Most reps at \(set.weightKg.kg)"
            }
            return nil
        }
    }
}

// MARK: - Adaptive progression (double progression + deload detection)

enum Progression {
    static func roundTo(_ v: Double, step: Double) -> Double {
        guard step > 0 else { return v }
        return (v / step).rounded() * step
    }

    /// Call after a workout started from a routine is finished.
    static func apply(workout: Workout, routine: Routine) {
        let targets = routine.days.flatMap(\.exercises)
        for ex in workout.exercises {
            guard let rid = ex.routineExerciseID, let t = targets.first(where: { $0.id == rid }) else { continue }
            let working = ex.orderedSets.filter { !$0.isWarmup }
            let done = working.filter(\.completed)
            guard !done.isEmpty else { continue }
            let topWeight = done.map(\.weightKg).max() ?? t.weightKg

            if t.weightKg == 0 {
                t.weightKg = topWeight
                t.lastNote = "Starting weight set to \(topWeight.kg)"
                continue
            }
            let allHitTop = done.count >= t.targetSets && done.allSatisfy { $0.reps >= t.repMax && $0.weightKg >= t.weightKg }
            let missed = done.count < t.targetSets || done.contains { $0.reps < t.repMin }

            if allHitTop {
                t.weightKg = roundTo(t.weightKg + t.incrementKg, step: t.incrementKg / 2)
                t.failStreak = 0
                t.pendingDeload = false
                t.lastNote = "Hit \(t.repMax) on every set, increased to \(t.weightKg.kg)"
            } else if missed {
                t.failStreak += 1
                if t.failStreak >= 2 {
                    t.pendingDeload = true
                    t.lastNote = "Missed the rep target \(t.failStreak) sessions in a row. A 10% deload is suggested."
                } else {
                    t.lastNote = "Below \(t.repMin) reps, keeping \(t.weightKg.kg)"
                }
            } else {
                t.failStreak = 0
                t.lastNote = "In range, keeping \(t.weightKg.kg) and adding reps"
            }
        }
        let count = max(routine.days.count, 1)
        routine.nextDayIndex = (routine.nextDayIndex + 1) % count
    }

    static func acceptDeload(_ t: RoutineExercise) {
        t.weightKg = roundTo(t.weightKg * 0.9, step: max(t.incrementKg / 2, 0.5))
        t.pendingDeload = false
        t.failStreak = 0
        t.lastNote = "Deloaded to \(t.weightKg.kg)"
    }
}

// MARK: - Starting workouts

enum WorkoutFactory {
    static func start(from day: RoutineDay, context: ModelContext, history: [Workout], library: ExerciseLibrary) -> Workout {
        let w = Workout(name: day.name, routineDayID: day.id)
        context.insert(w)
        for (i, t) in day.orderedExercises.enumerated() {
            let we = WorkoutExercise(exerciseID: t.exerciseID, order: i, restSeconds: t.restSeconds, routineExerciseID: t.id)
            w.exercises.append(we)
            let fallback = Stats.lastSets(for: t.exerciseID, in: history).first(where: { !$0.isWarmup })?.weightKg ?? 0
            let weight = t.weightKg > 0 ? t.weightKg : fallback
            let tracking = library.exercise(t.exerciseID)?.trackingType ?? .weightReps
            let last = Stats.lastSets(for: t.exerciseID, in: history).first(where: { !$0.isWarmup })
            for s in 0..<t.targetSets {
                let set = SetEntry(order: s, weightKg: weight, reps: tracking.isRepBased ? t.repMax : 0)
                if tracking == .duration { set.durationSec = last?.durationSec ?? 45 }
                if tracking == .cardio { set.durationSec = last?.durationSec ?? 1200 }
                if tracking == .weightDistance { set.distanceM = last?.distanceM ?? 40 }
                we.sets.append(set)
            }
        }
        return w
    }

    static func addExercise(_ exercise: Exercise, to w: Workout, history: [Workout], defaultRest: Int) {
        let we = WorkoutExercise(exerciseID: exercise.id, order: (w.exercises.map(\.order).max() ?? -1) + 1,
                                 restSeconds: defaultRest > 0 ? defaultRest : exercise.defaultRest)
        w.exercises.append(we)
        let last = Stats.lastSets(for: exercise.id, in: history, excluding: w).filter { !$0.isWarmup }
        if last.isEmpty {
            for s in 0..<(exercise.trackingType == .cardio ? 1 : 3) {
                let set = SetEntry(order: s, weightKg: 0, reps: exercise.trackingType.isRepBased ? 8 : 0)
                switch exercise.trackingType {
                case .duration: set.durationSec = 45
                case .cardio: set.durationSec = 20 * 60
                case .weightDistance: set.distanceM = 40
                default: break
                }
                we.sets.append(set)
            }
        } else {
            for (i, s) in last.enumerated() {
                let set = SetEntry(order: i, weightKg: s.weightKg, reps: s.reps)
                set.durationSec = s.durationSec
                set.distanceM = s.distanceM
                we.sets.append(set)
            }
        }
    }
}
