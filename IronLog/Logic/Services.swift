import Foundation
import HealthKit
import Security
import UIKit
import UserNotifications

// MARK: - Rest timer

final class RestTimer: ObservableObject {
    @Published var endDate: Date?
    @Published var total: TimeInterval = 0
    @Published var label: String = ""

    var isRunning: Bool { (endDate ?? .distantPast) > .now }

    func start(seconds: Int, label: String) {
        guard seconds > 0 else { return }
        total = TimeInterval(seconds)
        endDate = Date().addingTimeInterval(total)
        self.label = label
        schedule()
    }

    func add(_ seconds: Int) {
        guard let e = endDate else { return }
        endDate = e.addingTimeInterval(TimeInterval(seconds))
        total += TimeInterval(seconds)
        schedule()
    }

    func stop() {
        endDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    }

    private func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let e = endDate else { return }
        let interval = e.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = label.isEmpty ? "Next set." : "Next set: \(label)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

// MARK: - Apple Health

enum HealthSync {
    static let store = HKHealthStore()

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAccess() async throws {
        guard available else { return }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()],
                                             read: [HKQuantityType(.bodyMass)])
    }

    static func save(workout: Workout) async {
        guard available, UserDefaults.standard.bool(forKey: Keys.healthSync), let end = workout.endedAt else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: workout.startedAt)
            try await builder.endCollection(at: end)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "IronLog"])
            _ = try await builder.finishWorkout()
        } catch {
            print("Health save failed: \(error)")
        }
    }

    static func latestBodyweight() async -> (Double, Date)? {
        guard available else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else { return cont.resume(returning: nil) }
                cont.resume(returning: (s.quantity.doubleValue(for: .gramUnit(with: .kilo)), s.endDate))
            }
            store.execute(q)
        }
    }
}

// MARK: - Keychain (API key)

enum Keychain {
    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// MARK: - Friend comparison (no server: share a code, paste theirs)

struct FriendCard: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var sex: String
    var bodyweight: Double
    var dots: Double?
    var squat: Double?
    var bench: Double?
    var deadlift: Double?
    var weeklyVolume: Double
    var updated: Date
    var score: Int? = nil

    private static let prefix = "IRONLOG1:"

    var code: String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return Self.prefix + ((try? enc.encode(self))?.base64EncodedString() ?? "")
    }

    static func decode(_ text: String) -> FriendCard? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(prefix), let data = Data(base64Encoded: String(t.dropFirst(prefix.count))) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(FriendCard.self, from: data)
    }

    static func load() -> [FriendCard] {
        guard let d = UserDefaults.standard.data(forKey: Keys.friends),
              let list = try? JSONDecoder().decode([FriendCard].self, from: d) else { return [] }
        return list
    }

    static func save(_ list: [FriendCard]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: Keys.friends)
    }

    static var myID: UUID {
        if let s = UserDefaults.standard.string(forKey: "social.myID"), let u = UUID(uuidString: s) { return u }
        let u = UUID()
        UserDefaults.standard.set(u.uuidString, forKey: "social.myID")
        return u
    }
}

// MARK: - Export

struct ExportSet: Codable { let weightKg: Double; let reps: Int; let warmup: Bool; let rpe: Double? }
struct ExportExercise: Codable { let id: String; let name: String; let sets: [ExportSet] }
struct ExportWorkout: Codable { let name: String; let start: Date; let end: Date?; let exercises: [ExportExercise] }

enum Exporter {
    static func json(_ workouts: [Workout], library: ExerciseLibrary) -> URL? {
        let items = workouts.filter { $0.endedAt != nil }.map { w in
            ExportWorkout(name: w.name, start: w.startedAt, end: w.endedAt, exercises: w.orderedExercises.map { e in
                ExportExercise(id: e.exerciseID, name: library.name(e.exerciseID), sets: e.orderedSets.filter(\.completed).map {
                    ExportSet(weightKg: $0.weightKg, reps: $0.reps, warmup: $0.isWarmup, rpe: $0.rpe)
                })
            })
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(items) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ironlog-export.json")
        try? data.write(to: url)
        return url
    }
}
