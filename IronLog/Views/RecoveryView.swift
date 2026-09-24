import SwiftUI
import SwiftData

struct RecoveryView: View {
    @EnvironmentObject var library: ExerciseLibrary
    @Query(sort: \Workout.startedAt) private var workouts: [Workout]
    @AppStorage(Keys.healthSync) private var healthSync = false
    @State private var sleep: Double?
    @State private var restingHR: Double?

    var body: some View {
        let done = workouts.filter { $0.endedAt != nil }
        let s = Insights.recovery(done, library: library, sleep: sleep, restingHR: restingHR)
        let color = scoreColor(s.score)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Tag(text: "TODAY", color: Palette.green)
                        Spacer()
                        Label(s.score >= 80 ? "Ready to train" : (s.score >= 60 ? "Train smart" : "Take it easy"), systemImage: "bolt.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(color)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .overlay(Capsule().stroke(color.opacity(0.6)))
                    }
                    HStack(spacing: 18) {
                        RingGauge(progress: Double(s.score) / 100, color: color, lineWidth: 12) {
                            VStack(spacing: 0) {
                                Text("\(s.score)").font(.system(size: 44, weight: .bold))
                                Text("/100").font(.subheadline).foregroundStyle(Palette.text2)
                            }
                        }
                        .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.headline).font(.title3.bold())
                            Text(s.detail).font(.subheadline).foregroundStyle(Palette.text2)
                        }
                    }
                    Divider().overlay(Palette.stroke)
                    HStack {
                        stat("heart", "Resting HR", s.restingHR.map { "\(Int($0))" } ?? "—")
                        Divider().frame(height: 40).overlay(Palette.stroke)
                        stat("moon", "Sleep", s.sleepHours.map { "\($0.clean)h" } ?? "—")
                        Divider().frame(height: 40).overlay(Palette.stroke)
                        stat("bolt.fill", "Load", s.loadLabel)
                    }
                }
                .card()

                SectionTitle(title: "Recovery inputs")
                VStack(spacing: 0) {
                    input("moon", Palette.text2, "Sleep", s.sleepHours.map { "Last 24 h: \($0.clean) hours" } ?? "No sleep data available",
                          s.sleepHours == nil ? "Not connected" : "\(s.sleepHours!.clean)h", nil)
                    Divider().overlay(Palette.stroke)
                    input("heart", Palette.text2, "Resting heart rate", s.restingHR == nil ? "Connect Apple Health to add this signal" : "From Apple Health",
                          s.restingHR.map { "\(Int($0)) bpm" } ?? "Not connected", nil)
                    Divider().overlay(Palette.stroke)
                    input("figure.strengthtraining.traditional", Palette.green, "Muscle recovery", "Average across recently trained muscles",
                          "\(Int(s.muscleRecovery * 100))%", s.muscleRecovery)
                    Divider().overlay(Palette.stroke)
                    input("bolt.fill", Palette.orange, "Training load",
                          s.loadRatio.map { "\(Int($0 * 100))% of your four-week average" } ?? "Not enough history yet", s.loadLabel, nil)
                }
                .card(padding: 16)

                SectionTitle(title: "Muscle by muscle")
                VStack(spacing: 14) {
                    BodyDiagram { m in
                        guard let r = s.muscles.first(where: { $0.muscle == m }), r.hoursSince != nil else { return nil }
                        return r.recovery >= 0.85 ? Palette.green : (r.recovery >= 0.5 ? Palette.yellow : Palette.red)
                    }
                    .frame(height: 250)
                    FlowLayout(spacing: 14) {
                        legend(Palette.green, "Ready")
                        legend(Palette.yellow, "Recovering")
                        legend(Palette.red, "Fatigued")
                        legend(Palette.muscleBase, "Not trained this week")
                    }
                    .font(.caption)
                    ForEach(s.muscles.filter { $0.hoursSince != nil }.sorted { $0.recovery < $1.recovery }) { m in
                        HStack(spacing: 10) {
                            Text(MuscleName.display(m.muscle)).font(.subheadline.weight(.semibold)).frame(width: 96, alignment: .leading)
                            ProgressLine(fraction: m.recovery, color: m.recovery >= 0.85 ? Palette.green : (m.recovery >= 0.5 ? Palette.yellow : Palette.red))
                            Text("\(Int(m.recovery * 100))%").font(.subheadline.bold()).monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .card()

                if !healthSync {
                    Text("Turn on Apple Health in Profile → Edit profile to add sleep and resting heart rate. Needs the HealthKit build.")
                        .font(.caption).foregroundStyle(Palette.text2)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard healthSync else { return }
            sleep = await HealthSync.lastNightSleepHours()
            restingHR = await HealthSync.restingHeartRate()
        }
    }

    private func scoreColor(_ s: Int) -> Color { s >= 80 ? Palette.green : (s >= 60 ? Palette.yellow : Palette.orange) }

    private func stat(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Label(label, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(Palette.text2)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
    }

    private func input(_ icon: String, _ color: Color, _ title: String, _ detail: String, _ value: String, _ bar: Double?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(icon: icon, color: color, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(value).font(.headline).foregroundStyle(value == "Heavy" ? Palette.orange : (bar != nil ? Palette.green : Palette.text2))
                }
                Text(detail).font(.subheadline).foregroundStyle(Palette.text2)
                if let bar { ProgressLine(fraction: bar, color: Palette.green, height: 6).padding(.top, 4) }
            }
        }
        .padding(.vertical, 12)
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).foregroundStyle(Palette.text2) }
    }
}
