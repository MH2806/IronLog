import SwiftUI
import SwiftData

// MARK: - Hub

struct ToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Strength") {
                    tool("Strength level checker", "trophy", StrengthLevelTool())
                    tool("1RM calculator", "scalemass", OneRMTool())
                    tool("RPE calculator", "gauge.with.dots.needle.67percent", RPETool())
                    tool("Percentage chart", "percent", PercentageTool())
                    tool("Warm-up calculator", "flame", WarmupTool())
                    tool("Barbell plate calculator", "circle.circle", PlateTool())
                    tool("Training volume", "chart.bar.xaxis", VolumeTool())
                    tool("DOTS calculator", "d.circle", DotsTool())
                    tool("Wilks calculator", "w.circle", WilksTool())
                }
                Section("Body & nutrition") {
                    tool("Body fat", "percent", BodyFatTool())
                    tool("Lean body mass", "figure.stand", LBMTool())
                    tool("FFMI", "figure.arms.open", FFMITool())
                    tool("Ideal body weight", "ruler", IBWTool())
                    tool("BMR", "bed.double", BMRTool())
                    tool("TDEE", "bolt", TDEETool())
                    tool("Protein intake", "fork.knife", ProteinTool())
                    tool("Macros", "chart.pie", MacroTool())
                    tool("Bulking calories", "arrow.up.right", BulkTool())
                    tool("Body recomposition", "arrow.triangle.2.circlepath", RecompTool())
                }
            }
            .navigationTitle("Tools")
        }
    }

    private func tool<V: View>(_ title: String, _ icon: String, _ view: V) -> some View {
        NavigationLink { view.navigationTitle(title).navigationBarTitleDisplayMode(.inline) } label: {
            Label(title, systemImage: icon)
        }
    }
}

// MARK: - Shared inputs

struct NumberRow: View {
    let label: String
    @Binding var value: Double
    var unit: String = ""
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading) }
        }
    }
}

struct ResultRow: View {
    let label: String
    let value: String
    var bold = false
    var body: some View {
        LabeledContent(label) { Text(value).monospacedDigit().fontWeight(bold ? .bold : .regular) }
    }
}

/// Body stats shared by most tools, prefilled from the profile.
struct BodyInputs: View {
    @AppStorage(Keys.sex) var sex = "M"
    @AppStorage(Keys.bodyweight) var bodyweight = 80.0
    @AppStorage(Keys.heightCm) var height = 178.0
    @AppStorage(Keys.birthYear) var birthYear = 2000
    var showAge = true
    var body: some View {
        Section("You") {
            Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) } }
                .pickerStyle(.segmented)
            NumberRow(label: "Bodyweight", value: $bodyweight, unit: "kg")
            NumberRow(label: "Height", value: $height, unit: "cm")
            if showAge { Stepper("Born \(String(birthYear))", value: $birthYear, in: 1930...2015) }
        }
    }
}

struct BodyStats {
    let male: Bool, weight: Double, height: Double, age: Double
    static var current: BodyStats {
        let d = UserDefaults.standard
        let w = d.double(forKey: Keys.bodyweight), h = d.double(forKey: Keys.heightCm), y = d.integer(forKey: Keys.birthYear)
        return BodyStats(male: (d.string(forKey: Keys.sex) ?? "M") == "M", weight: w > 0 ? w : 80, height: h > 0 ? h : 178,
                    age: Double(Calendar.current.component(.year, from: .now) - (y > 1900 ? y : 2000)))
    }
    var bmi: Double { weight / pow(height / 100, 2) }
}

enum Formulas {
    // One-rep max
    static let oneRM: [(String, (Double, Double) -> Double)] = [
        ("Epley", { w, r in r <= 1 ? w : w * (1 + r / 30) }),
        ("Brzycki", { w, r in w * 36 / (37 - r) }),
        ("Lombardi", { w, r in w * pow(r, 0.10) }),
        ("Mayhew", { w, r in 100 * w / (52.2 + 41.9 * exp(-0.055 * r)) }),
        ("O'Conner", { w, r in w * (1 + 0.025 * r) }),
        ("Wathan", { w, r in 100 * w / (48.8 + 53.8 * exp(-0.075 * r)) }),
        ("Lander", { w, r in 100 * w / (101.3 - 2.67123 * r) }),
    ]

    /// RTS-style %1RM by "reps + reps in reserve" (effective reps), in half steps from 1 to 16.5.
    static let rpeTable: [Double] = [100, 97.8, 95.5, 93.9, 92.2, 90.7, 89.2, 87.8, 86.3, 85.0, 83.7, 82.4, 81.1, 79.9,
                                     78.6, 77.4, 76.2, 75.1, 73.9, 72.3, 70.7, 69.4, 68.0, 66.7, 65.3, 64.0, 62.6, 61.3,
                                     59.9, 58.6, 57.4, 56.1]
    static func rpePercent(reps: Int, rpe: Double) -> Double? {
        let eff = Double(reps) + (10 - rpe)
        let idx = Int(((eff - 1) * 2).rounded())
        return idx >= 0 && idx < rpeTable.count ? rpeTable[idx] : nil
    }

    // DOTS (uses the CI-validated coefficients when bundled)
    static func dots(total: Double, bw: Double, male: Bool) -> Double {
        if let ref = ReferenceData.shared, let d = StrengthMath.dots(total: total, bodyweight: bw, sex: male ? .male : .female, ref: ref) {
            return d
        }
        let c = male ? [-0.0000010930, 0.0007391293, -0.1918759221, 24.0900756, -307.75076]
                     : [-0.0000010706, 0.0005158568, -0.1126655495, 13.6175032, -57.96288]
        let x = min(max(bw, 40), male ? 210 : 150)
        return total * 500 / (c[0] * pow(x, 4) + c[1] * pow(x, 3) + c[2] * x * x + c[3] * x + c[4])
    }

    static func wilks(total: Double, bw: Double, male: Bool, v2020: Bool) -> Double {
        let c: [Double]
        let x: Double
        if v2020 {
            c = male ? [47.46178854, 8.472061379, 0.07369410346, -0.001395833811, 7.07665973070743e-06, -1.20804336482315e-08]
                     : [-125.4255398, 13.71219419, -0.03307250631, -0.001050400051, 9.38773881462799e-06, -2.3334613884954e-08]
            x = min(max(bw, 40), male ? 200.95 : 150.95)
        } else {
            c = male ? [-216.0475144, 16.2606339, -0.002388645, -0.00113732, 7.01863e-06, -1.291e-08]
                     : [594.31747775582, -27.23842536447, 0.82112226871, -0.00930733913, 4.731582e-05, -9.054e-08]
            x = min(max(bw, male ? 40 : 26.51), male ? 201.9 : 154.53)
        }
        var poly = 0.0
        for (i, k) in c.enumerated() { poly += k * pow(x, Double(i)) }
        return total * (v2020 ? 600 : 500) / poly
    }

    // Energy
    static func mifflin(_ b: BodyStats) -> Double { 10 * b.weight + 6.25 * b.height - 5 * b.age + (b.male ? 5 : -161) }
    static func harrisBenedict(_ b: BodyStats) -> Double {
        b.male ? 88.362 + 13.397 * b.weight + 4.799 * b.height - 5.677 * b.age
               : 447.593 + 9.247 * b.weight + 3.098 * b.height - 4.330 * b.age
    }
    static func katch(lbm: Double) -> Double { 370 + 21.6 * lbm }
    static func cunningham(lbm: Double) -> Double { 500 + 22 * lbm }

    // Lean mass
    static func boer(_ b: BodyStats) -> Double { b.male ? 0.407 * b.weight + 0.267 * b.height - 19.2 : 0.252 * b.weight + 0.473 * b.height - 48.3 }
    static func james(_ b: BodyStats) -> Double {
        let r = b.weight / b.height
        return b.male ? 1.1 * b.weight - 128 * r * r : 1.07 * b.weight - 148 * r * r
    }
    static func hume(_ b: BodyStats) -> Double {
        b.male ? 0.32810 * b.weight + 0.33929 * b.height - 29.5336 : 0.29569 * b.weight + 0.41813 * b.height - 43.2933
    }
    static func janmahasatian(_ b: BodyStats) -> Double {
        b.male ? 9270 * b.weight / (6680 + 216 * b.bmi) : 9270 * b.weight / (8780 + 244 * b.bmi)
    }

    // Body fat
    static func navy(_ b: BodyStats, waist: Double, neck: Double, hip: Double) -> Double? {
        if b.male {
            guard waist > neck else { return nil }
            return 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(b.height)) - 450
        }
        guard waist + hip > neck else { return nil }
        return 495 / (1.29579 - 0.35004 * log10(waist + hip - neck) + 0.22100 * log10(b.height)) - 450
    }
    /// Jackson-Pollock 3-site (men: chest, abdomen, thigh; women: triceps, suprailiac, thigh), Siri equation.
    static func jp3(_ b: BodyStats, sum: Double) -> Double {
        let d = b.male ? 1.10938 - 0.0008267 * sum + 0.0000016 * sum * sum - 0.0002574 * b.age
                       : 1.0994921 - 0.0009929 * sum + 0.0000023 * sum * sum - 0.0001392 * b.age
        return 495 / d - 450
    }
    static func bmiBodyFat(_ b: BodyStats) -> Double { 1.20 * b.bmi + 0.23 * b.age - 10.8 * (b.male ? 1 : 0) - 5.4 }

    static let activity: [(String, Double)] = [
        ("Desk job, little exercise", 1.2), ("Train 1–3×/week", 1.375), ("Train 3–5×/week", 1.55),
        ("Train 6–7×/week or active job", 1.725), ("Twice a day / manual labour", 1.9),
    ]
}

// MARK: - Strength tools

struct StrengthLevelTool: View {
    @EnvironmentObject var library: ExerciseLibrary
    @AppStorage(Keys.sex) private var sex = "M"
    @AppStorage(Keys.bodyweight) private var bodyweight = 80.0
    @State private var exerciseID = "barbell-bench-press"
    @State private var weight = 60.0
    @State private var reps = 5.0

    var body: some View {
        let scored = library.builtIn.filter { $0.standard != nil }
        let ex = library.exercise(exerciseID)
        let result = ex.flatMap { StrengthScoreEngine.check(exercise: $0, weight: weight, reps: Int(reps), bodyweight: bodyweight,
                                                            sex: Sex(rawValue: sex) ?? .male) }
        Form {
            Section {
                Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
                NumberRow(label: "Bodyweight", value: $bodyweight, unit: "kg")
                Picker("Exercise", selection: $exerciseID) {
                    ForEach(scored) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.navigationLink)
                NumberRow(label: ex?.trackingType == .assistedReps ? "Assistance" : (ex?.trackingType == .bodyweightReps ? "Added weight" : "Weight"),
                          value: $weight, unit: "kg")
                NumberRow(label: "Reps", value: $reps)
            }
            if let r = result {
                let level = StrengthLevel.from(points: r.points)
                Section {
                    HStack {
                        Text(level.name).font(.title2.bold()).foregroundStyle(Theme.color(level))
                        Spacer()
                        Text("\(Int(r.points)) pts").monospacedDigit()
                    }
                    ResultRow(label: "Estimated 1RM (load)", value: r.e1rm.kg)
                    ForEach(1..<6, id: \.self) { i in
                        ResultRow(label: StrengthLevel(rawValue: i)!.name, value: "from \(r.floors[i - 1].kg)")
                    }
                } footer: {
                    Text("Floors are estimated one-rep maxes for your bodyweight. Dumbbell numbers are per hand; bodyweight moves include your bodyweight.")
                }
            } else {
                Text("Enter a set of 1–10 reps (up to 25 for bodyweight moves).").foregroundStyle(.secondary)
            }
        }
    }
}

struct OneRMTool: View {
    @State private var weight = 100.0
    @State private var reps = 5.0
    @State private var rir = 0.0
    var body: some View {
        let r = reps + rir
        let results = Formulas.oneRM.map { ($0.0, $0.1(weight, r)) }
        let avg = results.map(\.1).reduce(0, +) / Double(results.count)
        Form {
            Section {
                NumberRow(label: "Weight", value: $weight, unit: "kg")
                NumberRow(label: "Reps", value: $reps)
                Stepper("Reps in reserve: \(Int(rir))", value: $rir, in: 0...5)
            }
            Section("Estimated 1RM") {
                ResultRow(label: "Average", value: avg.kg, bold: true)
                ForEach(results.indices, id: \.self) { i in ResultRow(label: results[i].0, value: results[i].1.kg) }
            }
            Section("Load for each rep target (Epley)") {
                ForEach(1...12, id: \.self) { n in
                    let load = n == 1 ? avg : avg / (1 + Double(n) / 30)
                    ResultRow(label: "\(n) rep\(n == 1 ? "" : "s")", value: "\(Progression.roundTo(load, step: 2.5).clean) kg")
                }
            }
            if r > 10 { Text("Estimates get less accurate beyond 10 reps.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct RPETool: View {
    @State private var weight = 100.0
    @State private var reps = 5
    @State private var rpe = 8.0
    @State private var targetReps = 3
    @State private var targetRPE = 8.5
    @State private var backoff = 10.0
    var body: some View {
        let pct = Formulas.rpePercent(reps: reps, rpe: rpe)
        let e1rm = pct.map { weight / ($0 / 100) }
        let tPct = Formulas.rpePercent(reps: targetReps, rpe: targetRPE)
        Form {
            Section("A set you did") {
                NumberRow(label: "Weight", value: $weight, unit: "kg")
                Stepper("Reps: \(reps)", value: $reps, in: 1...12)
                Stepper("RPE: \(rpe.clean)", value: $rpe, in: 6...10, step: 0.5)
                if let e1rm { ResultRow(label: "Estimated 1RM", value: e1rm.kg, bold: true) }
            }
            Section("Plan the next set") {
                Stepper("Reps: \(targetReps)", value: $targetReps, in: 1...12)
                Stepper("RPE: \(targetRPE.clean)", value: $targetRPE, in: 6...10, step: 0.5)
                if let e1rm, let tPct {
                    let top = e1rm * tPct / 100
                    ResultRow(label: "Target load", value: "\(Progression.roundTo(top, step: 2.5).clean) kg", bold: true)
                    Stepper("Back-off: −\(Int(backoff))%", value: $backoff, in: 0...30, step: 2.5)
                    ResultRow(label: "Back-off sets", value: "\(Progression.roundTo(top * (1 - backoff / 100), step: 2.5).clean) kg")
                }
            }
            Section("RPE chart (% of 1RM)") {
                ScrollView(.horizontal) {
                    Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("RPE").bold()
                            ForEach(1...12, id: \.self) { Text("\($0)").bold() }
                        }
                        ForEach([10.0, 9.5, 9, 8.5, 8, 7.5, 7, 6.5], id: \.self) { r in
                            GridRow {
                                Text(r.clean).bold()
                                ForEach(1...12, id: \.self) { n in
                                    Text(Formulas.rpePercent(reps: n, rpe: r).map { String(format: "%.1f", $0) } ?? "–")
                                }
                            }
                        }
                    }
                    .font(.caption.monospacedDigit())
                }
            }
        }
    }
}

struct PercentageTool: View {
    @State private var oneRM = 140.0
    var body: some View {
        Form {
            NumberRow(label: "1RM", value: $oneRM, unit: "kg")
            Section("Training loads") {
                ForEach(Array(stride(from: 100, through: 30, by: -5)), id: \.self) { p in
                    let reps = p == 100 ? 1 : Int((30 * (100 / Double(p) - 1)).rounded())
                    HStack {
                        Text("\(p)%").frame(width: 50, alignment: .leading)
                        Text("\(Progression.roundTo(oneRM * Double(p) / 100, step: 2.5).clean) kg").monospacedDigit()
                        Spacer()
                        Text("~\(reps) reps · \(zone(p))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ResultRow(label: "55–65%", value: "3–6 reps/set, 18–30 total")
                ResultRow(label: "70–80%", value: "3–6 reps/set, 12–24 total")
                ResultRow(label: "80–90%", value: "2–4 reps/set, 10–20 total")
                ResultRow(label: "90%+", value: "1–2 reps/set, 4–10 total")
            } header: { Text("Prilepin's chart") }
        }
    }
    private func zone(_ p: Int) -> String {
        switch p {
        case 90...: return "max strength"
        case 80..<90: return "strength"
        case 65..<80: return "hypertrophy"
        case 50..<65: return "technique / speed"
        default: return "warm-up"
        }
    }
}

struct WarmupTool: View {
    @State private var working = 100.0
    @State private var bar = 20.0
    @State private var template = 0
    private let templates: [(String, [(Double, Int)])] = [
        ("Standard", [(0, 10), (0.4, 5), (0.6, 3), (0.8, 2), (0.9, 1)]),
        ("Quick", [(0, 8), (0.5, 5), (0.75, 2)]),
        ("Heavy singles", [(0, 10), (0.4, 5), (0.55, 3), (0.7, 2), (0.8, 1), (0.88, 1), (0.94, 1)]),
    ]
    var body: some View {
        Form {
            Section {
                NumberRow(label: "Working weight", value: $working, unit: "kg")
                NumberRow(label: "Bar", value: $bar, unit: "kg")
                Picker("Template", selection: $template) {
                    ForEach(templates.indices, id: \.self) { Text(templates[$0].0).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Warm-up") {
                ForEach(templates[template].1.indices, id: \.self) { i in
                    let step = templates[template].1[i]
                    let w = max(bar, Progression.roundTo(working * step.0, step: 2.5))
                    ResultRow(label: step.0 == 0 ? "Empty bar" : "\(Int(step.0 * 100))%", value: "\(w.clean) kg × \(step.1)")
                }
                ResultRow(label: "Working sets", value: "\(working.clean) kg", bold: true)
            }
        }
    }
}

struct PlateTool: View {
    @State private var target = 100.0
    @State private var lb = false
    @State private var bar = 20.0
    @State private var counts: [Double: Int] = [:]
    private var plates: [Double] { lb ? [45, 35, 25, 10, 5, 2.5] : [25, 20, 15, 10, 5, 2.5, 1.25] }
    private var unit: String { lb ? "lb" : "kg" }

    var body: some View {
        let perSide = max(0, (target - bar) / 2)
        let loadout = split(perSide)
        let remainder = perSide - loadout.reduce(0, +)
        let counted = bar + 2 * plates.reduce(0) { $0 + $1 * Double(counts[$1] ?? 0) }
        Form {
            Section {
                Picker("Units", selection: $lb) { Text("kg").tag(false)
                Text("lb").tag(true) }
                    .pickerStyle(.segmented)
                    .onChange(of: lb) { _, isLb in bar = isLb ? 45 : 20; target = isLb ? 225 : 100; counts = [:] }
                NumberRow(label: "Target", value: $target, unit: unit)
                NumberRow(label: "Bar", value: $bar, unit: unit)
            }
            Section("Per side") {
                if loadout.isEmpty { Text("Just the bar").foregroundStyle(.secondary) }
                ForEach(plates.filter { p in loadout.contains(p) }, id: \.self) { p in
                    ResultRow(label: "\(p.clean) \(unit)", value: "× \(loadout.filter { $0 == p }.count)")
                }
                if remainder > 0.01 { Text("Can't make exactly; \(remainder.clean) \(unit) short per side.").font(.caption).foregroundStyle(Theme.plateRed) }
            }
            Section("Count what's on the bar (per side)") {
                ForEach(plates, id: \.self) { p in
                    Stepper("\(p.clean) \(unit): \(counts[p] ?? 0)", value: Binding(get: { counts[p] ?? 0 }, set: { counts[p] = $0 }), in: 0...10)
                }
                ResultRow(label: "Total", value: "\(counted.clean) \(unit)", bold: true)
            }
        }
    }

    private func split(_ side: Double) -> [Double] {
        var left = side, out: [Double] = []
        for p in plates { while left >= p - 0.001 { out.append(p); left -= p } }
        return out
    }
}

struct VolumeTool: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }) private var workouts: [Workout]
    // (muscle, MEV, MAV low, MAV high, MRV) — approximate landmarks popularised by Renaissance Periodization.
    private let landmarks: [(String, Double, Double, Double, Double)] = [
        ("chest", 8, 12, 20, 22), ("back", 10, 14, 22, 25), ("lats", 10, 14, 22, 25), ("shoulders", 8, 16, 22, 26),
        ("biceps", 8, 14, 20, 26), ("triceps", 6, 10, 14, 18), ("quadriceps", 8, 12, 18, 20), ("hamstrings", 4, 10, 16, 20),
        ("glutes", 0, 4, 12, 16), ("calves", 8, 12, 16, 20), ("abs", 0, 16, 20, 25), ("traps", 0, 12, 20, 26), ("forearms", 2, 10, 18, 25),
    ]
    @State private var sets: [String: Double] = [:]

    var body: some View {
        Form {
            Section {
                Button("Fill from the last 7 days") {
                    let logged = Stats.setsPerMuscle(workouts, library: library, since: Date().addingTimeInterval(-7 * 86400))
                    for m in landmarks.map(\.0) { sets[m] = (logged[m] ?? 0).rounded() }
                }
            } footer: { Text("Hard sets per muscle per week. Secondary muscles count as half a set.") }
            Section {
                ForEach(landmarks.indices, id: \.self) { i in
                    let l = landmarks[i]
                    let v = sets[l.0] ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper("\(l.0.capitalized): \(Int(v))", value: Binding(get: { v }, set: { sets[l.0] = $0 }), in: 0...40)
                        Text(verdict(v, l)).font(.caption).foregroundStyle(color(v, l))
                    }
                }
            } footer: {
                Text("MEV = least that grows muscle, MRV = most you can recover from. Landmarks are approximate and individual.")
            }
        }
    }
    private func verdict(_ v: Double, _ l: (String, Double, Double, Double, Double)) -> String {
        if v < l.1 { return "Below growth floor (MEV \(Int(l.1)))" }
        if v <= l.3 { return v >= l.2 ? "Productive range (\(Int(l.2))–\(Int(l.3)))" : "Maintaining / low productive" }
        if v <= l.4 { return "Near recovery ceiling (MRV \(Int(l.4)))" }
        return "Past recovery ceiling"
    }
    private func color(_ v: Double, _ l: (String, Double, Double, Double, Double)) -> Color {
        if v < l.1 { return .secondary }
        if v <= l.3 { return Theme.plateGreen }
        return v <= l.4 ? Theme.plateYellow : Theme.plateRed
    }
}

struct DotsTool: View {
    @State private var total = 500.0
    @AppStorage(Keys.bodyweight) private var bw = 80.0
    @AppStorage(Keys.sex) private var sex = "M"
    var body: some View {
        Form {
            Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
            NumberRow(label: "Total (S+B+D)", value: $total, unit: "kg")
            NumberRow(label: "Bodyweight", value: $bw, unit: "kg")
            ResultRow(label: "DOTS", value: Formulas.dots(total: total, bw: bw, male: sex == "M").clean, bold: true)
            ResultRow(label: "IPF GL", value: ReferenceData.shared.flatMap {
                StrengthMath.goodlift(total: total, bodyweight: bw, sex: Sex(rawValue: sex) ?? .male, kind: "sbd", ref: $0)
            }.map { $0.clean } ?? "—")
        }
    }
}

struct WilksTool: View {
    @State private var total = 500.0
    @AppStorage(Keys.bodyweight) private var bw = 80.0
    @AppStorage(Keys.sex) private var sex = "M"
    var body: some View {
        Form {
            Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) } }.pickerStyle(.segmented)
            NumberRow(label: "Total (S+B+D)", value: $total, unit: "kg")
            NumberRow(label: "Bodyweight", value: $bw, unit: "kg")
            ResultRow(label: "Wilks (original)", value: Formulas.wilks(total: total, bw: bw, male: sex == "M", v2020: false).clean, bold: true)
            ResultRow(label: "Wilks 2020", value: Formulas.wilks(total: total, bw: bw, male: sex == "M", v2020: true).clean)
        }
    }
}

// MARK: - Body & nutrition tools

struct BodyFatTool: View {
    @State private var waist = 85.0
    @State private var neck = 38.0
    @State private var hip = 95.0
    @State private var s1 = 12.0
    @State private var s2 = 18.0
    @State private var s3 = 15.0
    @AppStorage(Keys.sex) private var sex = "M"
    var body: some View {
        let b = BodyStats.current
        Form {
            BodyInputs()
            Section("Navy tape method") {
                NumberRow(label: "Waist (at navel)", value: $waist, unit: "cm")
                NumberRow(label: "Neck", value: $neck, unit: "cm")
                if sex == "F" { NumberRow(label: "Hips", value: $hip, unit: "cm") }
                ResultRow(label: "Body fat", value: Formulas.navy(b, waist: waist, neck: neck, hip: hip).map { "\($0.clean)%" } ?? "—", bold: true)
            }
            Section(sex == "M" ? "Skinfolds: chest, abdomen, thigh (mm)" : "Skinfolds: triceps, suprailiac, thigh (mm)") {
                NumberRow(label: "Site 1", value: $s1, unit: "mm")
                NumberRow(label: "Site 2", value: $s2, unit: "mm")
                NumberRow(label: "Site 3", value: $s3, unit: "mm")
                ResultRow(label: "Body fat (Jackson-Pollock 3)", value: "\(Formulas.jp3(b, sum: s1 + s2 + s3).clean)%", bold: true)
            }
            Section {
                ResultRow(label: "From BMI (\(b.bmi.clean))", value: "\(Formulas.bmiBodyFat(b).clean)%")
            } footer: { Text("The BMI estimate over-reads for muscular lifters; prefer tape or calipers.") }
            if let bf = Formulas.navy(b, waist: waist, neck: neck, hip: hip) {
                Section("From the Navy estimate") {
                    ResultRow(label: "Lean mass", value: (b.weight * (1 - bf / 100)).kg)
                    ResultRow(label: "Fat mass", value: (b.weight * bf / 100).kg)
                    ResultRow(label: "FFMI", value: (b.weight * (1 - bf / 100) / pow(b.height / 100, 2)).clean)
                }
            }
        }
    }
}

struct LBMTool: View {
    @State private var bodyFat = 0.0
    var body: some View {
        let b = BodyStats.current
        Form {
            BodyInputs(showAge: false)
            Section {
                NumberRow(label: "Body fat (optional)", value: $bodyFat, unit: "%")
                if bodyFat > 0 { ResultRow(label: "From body fat", value: (b.weight * (1 - bodyFat / 100)).kg, bold: true) }
            }
            Section("Estimates from height and weight") {
                ResultRow(label: "Boer", value: Formulas.boer(b).kg)
                ResultRow(label: "James", value: Formulas.james(b).kg)
                ResultRow(label: "Hume", value: Formulas.hume(b).kg)
                ResultRow(label: "Janmahasatian", value: Formulas.janmahasatian(b).kg)
            }
        }
    }
}

struct FFMITool: View {
    @State private var bodyFat = 15.0
    var body: some View {
        let b = BodyStats.current
        let h = b.height / 100
        let lbm = b.weight * (1 - bodyFat / 100)
        let ffmi = lbm / (h * h)
        let normalised = ffmi + 6.1 * (1.8 - h)
        Form {
            BodyInputs(showAge: false)
            NumberRow(label: "Body fat", value: $bodyFat, unit: "%")
            Section {
                ResultRow(label: "FFMI", value: ffmi.clean)
                ResultRow(label: "Height-normalised FFMI", value: normalised.clean, bold: true)
                ResultRow(label: "Lean mass", value: lbm.kg)
            } footer: {
                Text("Around 18–20 is typical for untrained men (roughly 14–17 for women). About 25 is the commonly cited ceiling for drug-free men (Kouri et al., 1995); body-fat measurement error moves FFMI by ±1.")
            }
        }
    }
}

struct IBWTool: View {
    var body: some View {
        let b = BodyStats.current
        let inchesOver5ft = max(0, b.height / 2.54 - 60)
        let h2 = pow(b.height / 100, 2)
        Form {
            BodyInputs(showAge: false)
            Section("Classic formulas") {
                ResultRow(label: "Devine", value: ((b.male ? 50 : 45.5) + 2.3 * inchesOver5ft).kg)
                ResultRow(label: "Robinson", value: ((b.male ? 52 : 49) + (b.male ? 1.9 : 1.7) * inchesOver5ft).kg)
                ResultRow(label: "Miller", value: ((b.male ? 56.2 : 53.1) + (b.male ? 1.41 : 1.36) * inchesOver5ft).kg)
                ResultRow(label: "Hamwi", value: ((b.male ? 48 : 45.5) + (b.male ? 2.7 : 2.2) * inchesOver5ft).kg)
                ResultRow(label: "Healthy BMI (18.5–24.9)", value: "\((18.5 * h2).clean)–\((24.9 * h2).clean) kg")
            }
            Section {
                let bf = b.male ? 0.15 : 0.25
                let lo = (b.male ? 20 : 16) * h2 / (1 - bf), hi = (b.male ? 23 : 19) * h2 / (1 - bf)
                ResultRow(label: "Muscular range", value: "\(lo.clean)–\(hi.clean) kg", bold: true)
            } footer: {
                Text("These formulas ignore muscle. The muscular range is the weight for an FFMI of \(b.male ? "20–23" : "16–19") at \(b.male ? 15 : 25)% body fat.")
            }
        }
    }
}

struct BMRTool: View {
    @State private var bodyFat = 0.0
    var body: some View {
        let b = BodyStats.current
        let lbm = bodyFat > 0 ? b.weight * (1 - bodyFat / 100) : nil
        Form {
            BodyInputs()
            NumberRow(label: "Body fat (for Katch/Cunningham)", value: $bodyFat, unit: "%")
            Section("Resting calories / day") {
                ResultRow(label: "Mifflin-St Jeor", value: "\(Int(Formulas.mifflin(b))) kcal", bold: true)
                ResultRow(label: "Harris-Benedict (revised)", value: "\(Int(Formulas.harrisBenedict(b))) kcal")
                ResultRow(label: "Katch-McArdle", value: lbm.map { "\(Int(Formulas.katch(lbm: $0))) kcal" } ?? "needs body fat")
                ResultRow(label: "Cunningham", value: lbm.map { "\(Int(Formulas.cunningham(lbm: $0))) kcal" } ?? "needs body fat")
            }
        }
    }
}

struct ActivityPicker: View {
    @Binding var activity: Int
    var body: some View {
        Picker("Activity", selection: $activity) {
            ForEach(Formulas.activity.indices, id: \.self) { Text(Formulas.activity[$0].0).tag($0) }
        }
    }
}

struct TDEETool: View {
    @State private var activity = 2
    var body: some View {
        let b = BodyStats.current
        let tdee = Formulas.mifflin(b) * Formulas.activity[activity].1
        Form {
            BodyInputs()
            ActivityPicker(activity: $activity)
            Section("Daily calories") {
                ResultRow(label: "Maintenance", value: "\(Int(tdee)) kcal", bold: true)
                ResultRow(label: "Cut (−20%)", value: "\(Int(tdee * 0.8)) kcal")
                ResultRow(label: "Slow cut (−10%)", value: "\(Int(tdee * 0.9)) kcal")
                ResultRow(label: "Lean bulk (+10%)", value: "\(Int(tdee * 1.1)) kcal")
            }
        }
    }
}

struct ProteinTool: View {
    @State private var goal = 1
    @State private var bodyFat = 0.0
    var body: some View {
        let b = BodyStats.current
        let lbm = bodyFat > 0 ? b.weight * (1 - bodyFat / 100) : Formulas.boer(b)
        let range: (Double, Double) = goal == 0 ? (2.3 * lbm, 3.1 * lbm) : (1.6 * b.weight, 2.2 * b.weight)
        Form {
            BodyInputs(showAge: false)
            Picker("Goal", selection: $goal) { Text("Cutting").tag(0)
                Text("Maintain / gain").tag(1) }.pickerStyle(.segmented)
            NumberRow(label: "Body fat (optional)", value: $bodyFat, unit: "%")
            Section {
                ResultRow(label: "Daily protein", value: "\(Int(range.0))–\(Int(range.1)) g", bold: true)
                ResultRow(label: "Per meal (4 meals)", value: "\(Int(range.0 / 4))–\(Int(range.1 / 4)) g")
            } footer: {
                Text(goal == 0 ? "2.3–3.1 g per kg of lean mass while dieting (Helms et al., 2014). Lean mass is estimated if you leave body fat blank."
                               : "1.6 g/kg is where the benefit plateaus on average; 2.2 g/kg covers most people (Morton et al., 2018).")
            }
        }
    }
}

struct MacroTool: View {
    @State private var calories = 2500.0
    @State private var proteinPerKg = 1.8
    @State private var fatPerKg = 0.8
    var body: some View {
        let w = BodyStats.current.weight
        let p = proteinPerKg * w, f = fatPerKg * w
        let c = max(0, (calories - p * 4 - f * 9) / 4)
        Form {
            BodyInputs(showAge: false)
            NumberRow(label: "Calories", value: $calories, unit: "kcal")
            Stepper("Protein: \(proteinPerKg.clean) g/kg", value: $proteinPerKg, in: 1.2...3.0, step: 0.1)
            Stepper("Fat: \(fatPerKg.clean) g/kg", value: $fatPerKg, in: 0.5...1.5, step: 0.1)
            Section("Daily targets") {
                ResultRow(label: "Protein", value: "\(Int(p)) g", bold: true)
                ResultRow(label: "Fat", value: "\(Int(f)) g", bold: true)
                ResultRow(label: "Carbs", value: "\(Int(c)) g", bold: true)
            }
            if fatPerKg < 0.6 { Text("Fat below ~0.6 g/kg is hard to sustain.").font(.caption).foregroundStyle(Theme.plateRed) }
        }
    }
}

struct BulkTool: View {
    @State private var activity = 2
    @State private var level = 0
    var body: some View {
        let b = BodyStats.current
        let tdee = Formulas.mifflin(b) * Formulas.activity[activity].1
        let surplus: (Double, Double) = [(0.10, 0.20), (0.05, 0.10), (0.03, 0.05)][level]
        let monthly: (Double, Double) = [(1.0, 1.5), (0.5, 1.0), (0.25, 0.5)][level]
        Form {
            BodyInputs()
            ActivityPicker(activity: $activity)
            Picker("Experience", selection: $level) { Text("Beginner").tag(0)
                Text("Intermediate").tag(1)
                Text("Advanced").tag(2) }
                .pickerStyle(.segmented)
            Section {
                ResultRow(label: "Maintenance", value: "\(Int(tdee)) kcal")
                ResultRow(label: "Bulk calories", value: "\(Int(tdee * (1 + surplus.0)))–\(Int(tdee * (1 + surplus.1))) kcal", bold: true)
                ResultRow(label: "Target gain", value: "\((b.weight * monthly.0 / 100 / 4.33).clean)–\((b.weight * monthly.1 / 100 / 4.33).clean) kg/week")
            } footer: {
                Text("Weigh daily and compare weekly averages. Two weeks under target: add 100–150 kcal. Two weeks over: take 100–150 away.")
            }
        }
    }
}

struct RecompTool: View {
    @State private var activity = 2
    @State private var bodyFat = 20.0
    @State private var trainingDays = 4.0
    @State private var experience = 0
    var body: some View {
        let b = BodyStats.current
        let tdee = Formulas.mifflin(b) * Formulas.activity[activity].1
        let train = tdee * 1.05, rest = tdee * 0.85
        let protein = 2.2 * b.weight
        let highFat = b.male ? bodyFat >= 15 : bodyFat >= 25
        let viability = experience == 0 || highFat ? "Good" : (experience == 1 ? "Moderate" : "Low")
        Form {
            BodyInputs()
            ActivityPicker(activity: $activity)
            NumberRow(label: "Body fat", value: $bodyFat, unit: "%")
            Stepper("Training days: \(Int(trainingDays))", value: $trainingDays, in: 2...6)
            Picker("Training history", selection: $experience) {
                Text("New / returning").tag(0)
                Text("1–3 years").tag(1)
                Text("3+ years").tag(2)
            }.pickerStyle(.segmented)
            Section("Targets") {
                ResultRow(label: "Training days", value: "\(Int(train)) kcal", bold: true)
                ResultRow(label: "Rest days", value: "\(Int(rest)) kcal", bold: true)
                ResultRow(label: "Weekly average", value: "\(Int((train * trainingDays + rest * (7 - trainingDays)) / 7)) kcal")
                ResultRow(label: "Protein", value: "\(Int(protein)) g/day")
                ResultRow(label: "Viability", value: viability)
            }
            Section {
                let fatLoss = experience == 0 ? (1.5, 3.0) : (1.0, 2.0)
                let muscle = [(1.0, 2.5), (0.5, 1.0), (0.2, 0.5)][experience]
                ResultRow(label: "Fat loss (12 wk)", value: "\(fatLoss.0.clean)–\(fatLoss.1.clean) kg")
                ResultRow(label: "Muscle gain (12 wk)", value: "\(muscle.0.clean)–\(muscle.1.clean) kg")
            } header: { Text("Realistic 12-week outcome") } footer: {
                Text("Recomps work best for beginners, people returning from a break, and higher body fat. Lean, experienced lifters usually do better alternating bulks and cuts.")
            }
        }
    }
}
