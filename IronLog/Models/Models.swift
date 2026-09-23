import Foundation
import SwiftData

@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var notes: String = ""
    var routineDayID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise] = []

    init(name: String, startedAt: Date = .now, routineDayID: UUID? = nil) {
        self.name = name
        self.startedAt = startedAt
        self.routineDayID = routineDayID
    }

    var orderedExercises: [WorkoutExercise] { exercises.sorted { $0.order < $1.order } }
    var workingSets: [SetEntry] { exercises.flatMap(\.sets).filter { $0.completed && !$0.isWarmup } }
    /// Logged weight × reps (bodyweight share not included, matching what's on the bar).
    var volume: Double { workingSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }
    var prCount: Int { workingSets.filter(\.isPR).count }
    var duration: TimeInterval { (endedAt ?? .now).timeIntervalSince(startedAt) }
}

@Model
final class WorkoutExercise {
    var id: UUID = UUID()
    var exerciseID: String = ""
    var order: Int = 0
    var restSeconds: Int = 120
    var routineExerciseID: UUID?
    var workout: Workout?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workoutExercise)
    var sets: [SetEntry] = []

    init(exerciseID: String, order: Int, restSeconds: Int = 120, routineExerciseID: UUID? = nil) {
        self.exerciseID = exerciseID
        self.order = order
        self.restSeconds = restSeconds
        self.routineExerciseID = routineExerciseID
    }

    var orderedSets: [SetEntry] { sets.sorted { $0.order < $1.order } }
}

@Model
final class SetEntry {
    var id: UUID = UUID()
    var order: Int = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var rpe: Double?
    var durationSec: Int = 0
    var distanceM: Double = 0
    var isWarmup: Bool = false
    var completed: Bool = false
    var completedAt: Date?
    var isPR: Bool = false
    var workoutExercise: WorkoutExercise?

    init(order: Int, weightKg: Double, reps: Int, isWarmup: Bool = false) {
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
    }
}

enum MeasurementKind: String, CaseIterable, Identifiable, Codable {
    case bodyweight, bodyFat, waist, chest, arm, thigh, hips, neck
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bodyweight: return "Bodyweight"
        case .bodyFat: return "Body fat"
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .arm: return "Arm"
        case .thigh: return "Thigh"
        case .hips: return "Hips"
        case .neck: return "Neck"
        }
    }
    var unit: String {
        switch self {
        case .bodyweight: return "kg"
        case .bodyFat: return "%"
        default: return "cm"
        }
    }
}

@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date()
    var kindRaw: String = MeasurementKind.bodyweight.rawValue
    var value: Double = 0

    init(kind: MeasurementKind, value: Double, date: Date = .now) {
        self.kindRaw = kind.rawValue
        self.value = value
        self.date = date
    }

    var kind: MeasurementKind { MeasurementKind(rawValue: kindRaw) ?? .bodyweight }
}

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false
    var nextDayIndex: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \RoutineDay.routine)
    var days: [RoutineDay] = []

    init(name: String, summary: String = "") {
        self.name = name
        self.summary = summary
    }

    var orderedDays: [RoutineDay] { days.sorted { $0.order < $1.order } }
    var nextDay: RoutineDay? {
        let d = orderedDays
        guard !d.isEmpty else { return nil }
        return d[nextDayIndex % d.count]
    }
}

@Model
final class RoutineDay {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var routine: Routine?
    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.day)
    var exercises: [RoutineExercise] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    var orderedExercises: [RoutineExercise] { exercises.sorted { $0.order < $1.order } }
}

@Model
final class RoutineExercise {
    var id: UUID = UUID()
    var exerciseID: String = ""
    var order: Int = 0
    var targetSets: Int = 3
    var repMin: Int = 8
    var repMax: Int = 12
    var weightKg: Double = 0
    var incrementKg: Double = 2.5
    var restSeconds: Int = 120
    var failStreak: Int = 0
    var pendingDeload: Bool = false
    var lastNote: String = ""
    var day: RoutineDay?

    init(exerciseID: String, order: Int, targetSets: Int, repMin: Int, repMax: Int,
         incrementKg: Double = 2.5, restSeconds: Int = 120) {
        self.exerciseID = exerciseID
        self.order = order
        self.targetSets = targetSets
        self.repMin = repMin
        self.repMax = repMax
        self.incrementKg = incrementKg
        self.restSeconds = restSeconds
    }

    var repText: String { repMin == repMax ? "\(targetSets)×\(repMin)" : "\(targetSets)×\(repMin)–\(repMax)" }
}
