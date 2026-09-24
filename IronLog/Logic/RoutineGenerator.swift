import Foundation
import SwiftData

enum Goal: String, CaseIterable, Identifiable {
    case strength = "Strength", hypertrophy = "Muscle size", general = "General fitness"
    var id: String { rawValue }
}

enum Equipment: String, CaseIterable, Identifiable {
    case gym = "Full gym", dumbbells = "Dumbbells only", bodyweight = "Bodyweight"
    var id: String { rawValue }
    /// Equipment this setup has; an exercise fits if everything it needs is in the set.
    var available: Set<String>? {
        switch self {
        case .gym: return nil
        case .dumbbells: return ["dumbbell", "kettlebell", "bench", "bodyweight", "plate", "pull-up bar", "incline bench"]
        case .bodyweight: return ["bodyweight", "pull-up bar", "bench", "dip bars"]
        }
    }
    func allows(_ e: Exercise) -> Bool {
        guard let set = available else { return true }
        return e.allEquipment.allSatisfy { set.contains($0) }
    }
}

enum Experience: String, CaseIterable, Identifiable {
    case beginner = "Beginner", intermediate = "Intermediate", advanced = "Advanced"
    var id: String { rawValue }
}

struct GeneratedExercise: Codable {
    var id: String
    var sets: Int
    var repMin: Int
    var repMax: Int
}

struct GeneratedDay: Codable {
    var name: String
    var exercises: [GeneratedExercise]
}

struct GeneratedPlan: Codable {
    var name: String
    var summary: String
    var days: [GeneratedDay]

    @discardableResult
    func insert(into context: ModelContext, library: ExerciseLibrary, activate: Bool) -> Routine {
        let r = Routine(name: name, summary: summary)
        context.insert(r)
        for (i, d) in days.enumerated() {
            let day = RoutineDay(name: d.name, order: i)
            r.days.append(day)
            for (j, e) in d.exercises.enumerated() where library.exercise(e.id) != nil {
                let info = library.exercise(e.id)
                let isLower = info?.primaryMuscles.contains { ["quadriceps", "hamstrings", "glutes"].contains($0) } ?? false
                let heavy = info?.isCompound == true && info?.isBarbell == true
                let inc = heavy ? (isLower ? 5.0 : 2.5) : 2.0
                day.exercises.append(RoutineExercise(exerciseID: e.id, order: j, targetSets: e.sets,
                                                     repMin: e.repMin, repMax: e.repMax,
                                                     incrementKg: inc, restSeconds: heavy ? 180 : 90))
            }
        }
        if activate {
            let all = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
            for other in all { other.isActive = false }
            r.isActive = true
        }
        return r
    }
}

enum RoutineGenerator {
    enum Slot {
        case squat, hinge, hingeAccessory, singleLeg, horizontalPush, inclinePush, verticalPush,
             horizontalPull, verticalPull, hamstringCurl, quadIsolation, lateralRaise, rearDelt,
             biceps, triceps, calves, core
        var isMainLift: Bool { [.squat, .hinge, .horizontalPush, .verticalPush, .horizontalPull, .verticalPull].contains(self) }
    }

    static func exercise(_ slot: Slot, _ eq: Equipment) -> String? {
        let t: (String, String, String?)
        switch slot {
        case .squat: t = ("barbell-back-squat", "goblet-squat", "lunge")
        case .hinge: t = ("deadlift", "dumbbell-rdl", "single-leg-bodyweight-hip-thrust")
        case .hingeAccessory: t = ("barbell-rdl", "dumbbell-rdl", "single-leg-bodyweight-glute-bridge")
        case .singleLeg: t = ("leg-press", "bulgarian-split-squat", "lunge")
        case .horizontalPush: t = ("barbell-bench-press", "dumbbell-press", "push-up")
        case .inclinePush: t = ("incline-dumbbell-press", "incline-dumbbell-press", "decline-push-up")
        case .verticalPush: t = ("military-press", "dumbbell-shoulder-press", "pike-push-up")
        case .horizontalPull: t = ("barbell-row", "dumbbell-row", "barbell-inverted-row")
        case .verticalPull: t = ("pulldown", "chest-supported-dumbbell-row", "pull-up")
        case .hamstringCurl: t = ("lying-leg-curl", "dumbbell-rdl", "nordic-curl")
        case .quadIsolation: t = ("leg-extension", "dumbbell-split-squat", "sissy-squat")
        case .lateralRaise: t = ("dumbbell-lateral-raise", "dumbbell-lateral-raise", nil)
        case .rearDelt: t = ("face-pull", "dumbbell-rear-delt-fly", nil)
        case .biceps: t = ("barbell-bicep-curl", "dumbbell-bicep-curl", "chin-up")
        case .triceps: t = ("rope-pushdown", "dumbbell-tricep-extension", "diamond-push-up")
        case .calves: t = ("standing-machine-calf-raise", "standing-dumbbell-calf-raise", "bodyweight-elevated-calf-raise")
        case .core: t = ("cable-crunch", "plank", "plank")
        }
        switch eq {
        case .gym: return t.0
        case .dumbbells: return t.1
        case .bodyweight: return t.2
        }
    }

    /// Rep scheme per slot. `heavyDay` alternates for daily undulating periodisation.
    static func scheme(_ slot: Slot, goal: Goal, exp: Experience, heavyDay: Bool, eq: Equipment) -> (Int, Int, Int) {
        let main = slot.isMainLift
        let extra = exp == .advanced ? 1 : 0
        if eq == .bodyweight { return (3 + extra, 8, 20) }
        switch (goal, main) {
        case (.strength, true):
            if exp == .beginner { return (3, 5, 5) }
            return heavyDay ? (4 + extra, 3, 5) : (3 + extra, 6, 8)
        case (.strength, false): return (3, 8, 12)
        case (.hypertrophy, true):
            return heavyDay ? (3 + extra, 6, 8) : (3 + extra, 8, 12)
        case (.hypertrophy, false): return (3 + extra, 10, 15)
        case (.general, true): return (3, 6, 10)
        case (.general, false): return (2 + extra, 10, 15)
        }
    }

    static func generate(goal: Goal, days: Int, equipment: Equipment, experience: Experience) -> GeneratedPlan {
        let fullA: [Slot] = [.squat, .horizontalPush, .horizontalPull, .hingeAccessory, .lateralRaise, .core]
        let fullB: [Slot] = [.hinge, .verticalPush, .verticalPull, .singleLeg, .biceps, .triceps]
        let fullC: [Slot] = [.squat, .inclinePush, .horizontalPull, .hamstringCurl, .rearDelt, .calves]
        let upper: [Slot] = [.horizontalPush, .horizontalPull, .verticalPush, .verticalPull, .biceps, .triceps]
        let lower: [Slot] = [.squat, .hingeAccessory, .singleLeg, .hamstringCurl, .calves, .core]
        let lowerB: [Slot] = [.hinge, .squat, .quadIsolation, .hamstringCurl, .calves, .core]
        let push: [Slot] = [.horizontalPush, .verticalPush, .inclinePush, .lateralRaise, .triceps]
        let pull: [Slot] = [.hinge, .verticalPull, .horizontalPull, .rearDelt, .biceps]
        let legs: [Slot] = [.squat, .hingeAccessory, .singleLeg, .hamstringCurl, .calves]

        let layout: [(String, [Slot], Bool)]
        let name: String
        switch days {
        case ...2:
            name = "Full body 2×"; layout = [("Full body A", fullA, true), ("Full body B", fullB, false)]
        case 3 where experience == .beginner:
            name = "Full body 3×"; layout = [("Full body A", fullA, true), ("Full body B", fullB, true), ("Full body C", fullC, false)]
        case 3:
            name = "Upper / lower / full"; layout = [("Upper", upper, true), ("Lower", lower, true), ("Full body", fullC, false)]
        case 4:
            name = "Upper / lower 4×"
            layout = [("Upper (heavy)", upper, true), ("Lower (heavy)", lower, true),
                      ("Upper (volume)", upper, false), ("Lower (volume)", lowerB, false)]
        case 5:
            name = "Upper / lower + PPL"
            layout = [("Upper", upper, true), ("Lower", lower, true), ("Push", push, false), ("Pull", pull, false), ("Legs", legs, false)]
        default:
            name = "Push / pull / legs 6×"
            layout = [("Push (heavy)", push, true), ("Pull (heavy)", pull, true), ("Legs (heavy)", legs, true),
                      ("Push (volume)", push, false), ("Pull (volume)", pull, false), ("Legs (volume)", lowerB, false)]
        }

        let plan = layout.map { (entry: (String, [Slot], Bool)) -> GeneratedDay in
            let (dayName, slots, heavy) = entry
            var seen = Set<String>()
            let ex = slots.compactMap { slot -> GeneratedExercise? in
                guard let id = exercise(slot, equipment), seen.insert(id).inserted else { return nil }
                let s = scheme(slot, goal: goal, exp: experience, heavyDay: heavy, eq: equipment)
                return GeneratedExercise(id: id, sets: s.0, repMin: s.1, repMax: s.2)
            }
            return GeneratedDay(name: dayName, exercises: ex)
        }
        let summary = "\(goal.rawValue), \(experience.rawValue.lowercased()), \(equipment.rawValue.lowercased()). " +
            "Double progression: add weight once every set reaches the top of the rep range. " +
            (layout.contains { !$0.2 } && experience != .beginner ? "Heavy and volume days alternate." : "")
        return GeneratedPlan(name: name, summary: summary, days: plan)
    }
}

// MARK: - Optional: Claude-generated plans (bring your own API key)

enum AIRoutineService {
    enum AIError: LocalizedError {
        case noKey, badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add an Anthropic API key in Profile to use AI plans."
            case .badResponse(let s): return "Couldn't read the plan: \(s)"
            }
        }
    }

    static func generate(goal: Goal, days: Int, equipment: Equipment, experience: Experience,
                         notes: String, library: ExerciseLibrary) async throws -> GeneratedPlan {
        guard let key = Keychain.get("anthropicKey"), !key.isEmpty else { throw AIError.noKey }
        let model = UserDefaults.standard.string(forKey: Keys.aiModel) ?? "claude-sonnet-5"

        let candidates = library.builtIn.filter { $0.category != "cardio" && equipment.allows($0) }
        let catalogue = candidates.map { "\($0.id)|\($0.primaryMuscles.joined(separator: ","))|\($0.mechanic ?? "")" }
            .joined(separator: "\n")

        let prompt = """
        Design a \(days)-day-per-week resistance training programme.
        Goal: \(goal.rawValue). Experience: \(experience.rawValue). Equipment: \(equipment.rawValue).
        Extra notes from the lifter: \(notes.isEmpty ? "none" : notes)

        Use proper periodisation (e.g. heavy/volume day alternation for intermediates and above),
        balanced weekly volume across muscle groups (roughly 10-20 hard sets per major muscle per week),
        and 4-7 exercises per day. Only use exercise ids from this catalogue (id|primary muscles|mechanic):
        \(catalogue)

        Respond with ONLY a JSON object, no markdown, in this shape:
        {"name": string, "summary": string (2 sentences explaining the structure and progression),
         "days": [{"name": string, "exercises": [{"id": string, "sets": int, "repMin": int, "repMax": int}]}]}
        """

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = ["model": model, "max_tokens": 4000,
                                   "messages": [["role": "user", "content": prompt]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.badResponse(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw AIError.badResponse("unexpected API response")
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw AIError.badResponse("no JSON in reply")
        }
        var plan = try JSONDecoder().decode(GeneratedPlan.self, from: Data(text[start...end].utf8))
        // Drop anything hallucinated outside the catalogue and clamp nonsense values.
        let valid = Set(candidates.map(\.id))
        plan.days = plan.days.map { (day: GeneratedDay) -> GeneratedDay in
            var d = day
            d.exercises = d.exercises.filter { valid.contains($0.id) }.map { (ex: GeneratedExercise) -> GeneratedExercise in
                var e = ex
                e.sets = min(max(e.sets, 1), 8)
                e.repMin = min(max(e.repMin, 1), 30)
                e.repMax = min(max(e.repMax, e.repMin), 30)
                return e
            }
            return d
        }.filter { !$0.exercises.isEmpty }
        guard !plan.days.isEmpty else { throw AIError.badResponse("no usable exercises") }
        return plan
    }
}
