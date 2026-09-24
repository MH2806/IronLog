import SwiftUI
import SwiftData
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }

    // Show the rest-timer notification even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct IronLogApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var library = ExerciseLibrary()
    @StateObject private var restTimer = RestTimer()
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(restTimer)
                .environmentObject(app)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Workout.self, WorkoutExercise.self, SetEntry.self,
                              BodyMeasurement.self, Routine.self, RoutineDay.self, RoutineExercise.self])
    }
}

// MARK: - App state

final class AppState: ObservableObject {
    @Published var showActive = false
    @Published var tab: AppTab = .log
}

enum AppTab: Hashable { case log, train, progress, community, profile }

// MARK: - Theme

enum Theme {
    static let accent = Palette.blue
    static let plateRed = Palette.red
    static let plateYellow = Palette.yellow
    static let plateGreen = Palette.green
    static let noData = Palette.muscleBase

    /// Colour per Strength Score level.
    static func color(_ level: StrengthLevel?) -> Color {
        guard let level else { return noData }
        switch level {
        case .beginner: return Color(red: 0.78, green: 0.36, blue: 0.33)
        case .novice: return Color(red: 0.85, green: 0.56, blue: 0.30)
        case .intermediate: return Color(red: 0.22, green: 0.80, blue: 0.50)
        case .advanced: return Color(red: 0.32, green: 0.52, blue: 0.95)
        case .elite: return Color(red: 0.60, green: 0.40, blue: 0.95)
        case .worldClass: return Color(red: 0.90, green: 0.33, blue: 0.56)
        }
    }

    static func tier(_ percentile: Double?) -> (name: String, color: Color) {
        guard let p = percentile else { return ("No data", noData) }
        switch p {
        case ..<25: return ("Developing", color(.novice))
        case ..<50: return ("Intermediate", color(.intermediate))
        case ..<75: return ("Advanced", color(.advanced))
        case ..<90: return ("Elite", color(.elite))
        default: return ("Top 10%", color(.worldClass))
        }
    }
}

// MARK: - Settings keys + profile snapshot

enum Keys {
    static let name = "profile.name"
    static let sex = "profile.sex"
    static let bodyweight = "profile.bodyweightKg"
    static let heightCm = "profile.heightCm"
    static let birthYear = "profile.birthYear"
    static let population = "profile.population"   // "all" | "tested"
    static let defaultRest = "settings.defaultRest"
    static let healthSync = "settings.healthSync"
    static let aiModel = "settings.aiModel"
    static let friends = "social.friends"
    static let trainingSince = "profile.trainingSince"   // timeIntervalSince1970, 0 = not set
}

enum Sex: String, CaseIterable, Identifiable, Codable {
    case male = "M", female = "F"
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

struct ProfileSnapshot {
    var name: String
    var sex: Sex
    var profileBodyweight: Double
    var birthYear: Int
    var population: String
    var trainingSince: Date?
    var measurements: [BodyMeasurement]

    static func current(_ measurements: [BodyMeasurement]) -> ProfileSnapshot {
        let d = UserDefaults.standard
        let bw = d.double(forKey: Keys.bodyweight)
        return ProfileSnapshot(
            name: d.string(forKey: Keys.name) ?? "",
            sex: Sex(rawValue: d.string(forKey: Keys.sex) ?? "M") ?? .male,
            profileBodyweight: bw > 0 ? bw : 80,
            birthYear: d.integer(forKey: Keys.birthYear),
            population: d.string(forKey: Keys.population) ?? "all",
            trainingSince: d.double(forKey: Keys.trainingSince) > 0 ? Date(timeIntervalSince1970: d.double(forKey: Keys.trainingSince)) : nil,
            measurements: measurements.filter { $0.kind == .bodyweight }.sorted { $0.date < $1.date })
    }

    var age: Int? {
        guard birthYear > 1900 else { return nil }
        return Calendar.current.component(.year, from: .now) - birthYear
    }

    var bodyweight: Double { measurements.last?.value ?? profileBodyweight }

    var trainingYears: Double? { trainingSince.map { max(0, Date().timeIntervalSince($0) / (365.25 * 86400)) } }

    func bodyweight(at date: Date) -> Double {
        if let m = measurements.last(where: { $0.date <= date }) { return m.value }
        return measurements.first?.value ?? profileBodyweight
    }
}

// MARK: - Formatting

extension Double {
    var clean: String { formatted(.number.precision(.fractionLength(0...1))) }
    var kg: String { clean + " kg" }
}

func percentileText(_ p: Double) -> String {
    if p >= 99.5 { return "top 1%" }
    if p < 1 { return "bottom 1%" }
    let n = Int(p.rounded(.down))
    let suffix: String
    switch (n % 100, n % 10) {
    case (11...13, _): suffix = "th"
    case (_, 1): suffix = "st"
    case (_, 2): suffix = "nd"
    case (_, 3): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix) percentile"
}

func durationText(_ t: TimeInterval) -> String {
    let m = Int(t) / 60
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}
