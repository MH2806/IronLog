import Foundation
import SwiftUI

enum Tracking: String, Codable, CaseIterable, Identifiable {
    case weightReps, bodyweightReps, assistedReps, duration, cardio, weightDistance
    var id: String { rawValue }
    var label: String {
        switch self {
        case .weightReps: return "Weight × reps"
        case .bodyweightReps: return "Bodyweight (+ added kg) × reps"
        case .assistedReps: return "Assisted (− kg) × reps"
        case .duration: return "Time"
        case .cardio: return "Cardio (time + distance)"
        case .weightDistance: return "Weight × distance"
        }
    }
    var isRepBased: Bool { self == .weightReps || self == .bodyweightReps || self == .assistedReps }
}

struct ExerciseStandard: Codable, Hashable {
    let anchor: String
    let factor: Double
    let confidence: Double
}

struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String?
    let images: [String]
    var equipmentList: [String]? = nil
    var tracking: Tracking? = nil
    var bodyweightShare: Double? = nil
    var instructionsFrom: String? = nil
    var standard: ExerciseStandard? = nil

    var isCustom: Bool { id.hasPrefix("custom:") }
    var isCompound: Bool { mechanic == "compound" }
    var trackingType: Tracking { tracking ?? .weightReps }
    var allEquipment: [String] { equipmentList ?? [equipment].compactMap { $0 } }
    var imageURLs: [URL] {
        images.compactMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }
    var isBarbell: Bool { allEquipment.contains("barbell") || allEquipment.contains("trap bar") }
    /// Sensible default rest: longer for heavy compounds.
    var defaultRest: Int { isCompound && isBarbell ? 180 : 90 }

    /// Load used for strength estimates (kg), given the logged weight field.
    func effectiveLoad(weight: Double, bodyweight: Double) -> Double? {
        switch trackingType {
        case .weightReps: return weight
        case .bodyweightReps: return bodyweight * (bodyweightShare ?? 1) + weight
        case .assistedReps: return max(bodyweight * (bodyweightShare ?? 1) - weight, 0)
        case .duration, .cardio, .weightDistance: return nil
        }
    }
}

enum Muscles {
    static let all = ["chest", "shoulders", "triceps", "biceps", "forearms", "lats", "back", "traps",
                      "abs", "quadriceps", "hamstrings", "glutes", "calves"]
    /// Groups used for radar/balance charts.
    static let groups: [(name: String, muscles: [String])] = [
        ("Chest", ["chest"]),
        ("Shoulders", ["shoulders"]),
        ("Arms", ["triceps", "biceps", "forearms"]),
        ("Back", ["lats", "back", "traps"]),
        ("Core", ["abs"]),
        ("Quads", ["quadriceps"]),
        ("Posterior", ["hamstrings", "glutes"]),
        ("Calves", ["calves"]),
    ]
}

final class ExerciseLibrary: ObservableObject {
    @Published private(set) var builtIn: [Exercise] = []
    @Published private(set) var custom: [Exercise] = []
    private var index: [String: Exercise] = [:]

    private var customURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom_exercises.json")
    }

    init() {
        if let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Exercise].self, from: data) {
            builtIn = list
        }
        if let data = try? Data(contentsOf: customURL),
           let list = try? JSONDecoder().decode([Exercise].self, from: data) {
            custom = list
        }
        rebuild()
    }

    var all: [Exercise] { (custom + builtIn) }

    func exercise(_ id: String) -> Exercise? { index[id] }
    func name(_ id: String) -> String { index[id]?.name ?? id.replacingOccurrences(of: "_", with: " ") }

    func addCustom(name: String, primary: [String], secondary: [String], equipment: String, compound: Bool,
                   tracking: Tracking = .weightReps) {
        let ex = Exercise(id: "custom:\(UUID().uuidString)", name: name, force: nil, level: nil,
                          mechanic: compound ? "compound" : "isolation", equipment: equipment,
                          primaryMuscles: primary, secondaryMuscles: secondary,
                          instructions: [], category: tracking == .cardio ? "cardio" : "strength", images: [],
                          equipmentList: [equipment], tracking: tracking,
                          bodyweightShare: tracking == .bodyweightReps || tracking == .assistedReps ? 1.0 : nil)
        custom.append(ex)
        save()
    }

    func deleteCustom(_ id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    private func save() {
        rebuild()
        if let data = try? JSONEncoder().encode(custom) { try? data.write(to: customURL) }
    }

    private func rebuild() {
        index = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

// MARK: - OpenPowerlifting reference data (generated in CI)

struct ReferenceData: Decodable {
    let generatedAt: String
    let dataDate: String
    let source: String
    let formulas: Formulas
    let validation: Validation?
    let populations: [String: [String: SexData]]

    struct Formulas: Decodable {
        let dots: DotsFormula
        let goodlift: [String: [String: [Double]]]?
    }
    struct DotsFormula: Decodable {
        let M: [Double]
        let F: [Double]
        let bw: [String: [Double]]
    }
    struct Validation: Decodable {
        let dots: DotsCheck?
    }
    struct DotsCheck: Decodable {
        let n: Int
        let medianAbsErr: Double
        let p99AbsErr: Double
    }
    struct SexData: Decodable {
        let lifts: [String: LiftData]
        let dots: DotsData
    }
    struct LiftData: Decodable {
        let n: Int
        let bins: [Bin]
    }
    struct Bin: Decodable {
        let bw: Double
        let lo: Double
        let hi: Double?
        let n: Int
        let p: [Double]
    }
    struct DotsData: Decodable {
        let all: Curve
        let ageBands: [AgeBand]
    }
    struct Curve: Decodable {
        let n: Int
        let p: [Double]
    }
    struct AgeBand: Decodable {
        let lo: Int
        let hi: Int
        let n: Int
        let p: [Double]
    }

    static let shared: ReferenceData? = {
        guard let url = Bundle.main.url(forResource: "reference", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReferenceData.self, from: data)
    }()

    func sexData(_ sex: Sex, population: String) -> SexData? {
        (populations[population] ?? populations["all"])?[sex.rawValue]
    }
}
