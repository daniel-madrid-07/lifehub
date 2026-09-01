import SwiftUI
import Charts

/// Progreso general del gimnasio: resumen de la semana, volumen por músculo,
/// tendencia de volumen por entreno y peso corporal.
struct GymOverallProgressView: View {
    @State private var weekly: WeeklyStats?
    @State private var workouts: [GymWorkoutSummary] = []
    @State private var bodyweight: [BodyWeightEntry] = []
    @State private var loaded = false

    var body: some View {
        Screen(title: "Progreso", refresh: { await load() }) {
            if !loaded {
                SkeletonList()
            } else {
                // Resumen de la semana
                if let weekly {
                    HStack(spacing: 10) {
                        StatTile(icon: "square.stack.3d.up.fill", value: "\(weekly.total_sets)", label: "series esta semana")
                        StatTile(icon: "figure.strengthtraining.traditional", value: "\(weekly.muscles.count)", label: "grupos trabajados")
                    }

                    if !weekly.muscles.isEmpty {
                        SectionHeader(title: "Volumen por músculo")
                        VStack(spacing: 8) {
                            ForEach(weekly.muscles, id: \.muscle) { m in
                                HStack {
                                    Text(m.muscle.capitalized)
                                        .font(Theme.dSubheadline)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text("\(m.sets) series · \(Int(m.volume)) kg")
                                        .font(Theme.dCaption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .card()
                    }
                }

                // Tendencia de volumen por entreno
                if workouts.count > 1 {
                    SectionHeader(title: "Volumen por entreno")
                    Chart(workouts.reversed()) { w in
                        LineMark(
                            x: .value("Fecha", Fmt.date(w.started_at) ?? .now),
                            y: .value("Volumen", w.volume)
                        )
                        .foregroundStyle(Theme.accent)
                        .symbol(.circle)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .card()
                }

                // Peso corporal
                if bodyweight.count > 1 {
                    SectionHeader(title: "Peso corporal")
                    Chart(bodyweight.reversed(), id: \.id) { e in
                        LineMark(
                            x: .value("Fecha", Fmt.date(e.at) ?? .now),
                            y: .value("Peso", e.weight)
                        )
                        .foregroundStyle(Theme.accent2)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                    .card()
                }

                if !workouts.isEmpty {
                    SectionHeader(title: "Últimos entrenos")
                    ForEach(workouts.prefix(10)) { w in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.routine_name ?? "Libre")
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                Text(Fmt.short(w.started_at))
                                    .font(Theme.dCaption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(w.sets) series · \(Int(w.volume)) kg · \(w.duration_min) min")
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 13)
                    }
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        async let s = try? API.shared.gymWeeklyStats()
        async let w = try? API.shared.gymWorkouts()
        async let b = try? API.shared.gymBodyweight()
        weekly = await s
        workouts = await w ?? []
        bodyweight = await b ?? []
        loaded = true
    }
}
