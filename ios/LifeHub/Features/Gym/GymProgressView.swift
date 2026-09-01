import SwiftUI
import Charts

/// Referencia mínima a un ejercicio de tus rutinas.
struct ExRef: Identifiable, Hashable {
    let id: Int
    let name: String
    let muscle: String
}

/// Progreso por ejercicio: 1RM estimado y peso top por sesión, PRs y
/// recomendación actual. Solo lista los ejercicios de TUS rutinas.
struct GymProgressView: View {
    @State private var exercises: [ExRef] = []
    @State private var selected: ExRef?
    @State private var progress: GymProgress?
    @State private var error: String?

    var body: some View {
        Screen(title: "Progreso", refresh: { await loadExercises() }) {
            if let error {
                ErrorCard(detail: error) { await loadExercises() }
            } else if exercises.isEmpty {
                SkeletonList()
            } else {
                Menu {
                    ForEach(groupedMuscles, id: \.self) { muscle in
                        Section(muscle.capitalized) {
                            ForEach(exercises.filter { $0.muscle == muscle }) { ex in
                                Button(ex.name) {
                                    selected = ex
                                    Task { await loadProgress(ex) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selected?.name ?? "Elige ejercicio")
                            .font(Theme.dHeadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(Theme.dCaption)
                            .foregroundStyle(Theme.muted)
                    }
                    .card()
                }

                if let p = progress {
                    HStack(spacing: 10) {
                        StatTile(icon: "trophy.fill", value: "\(p.pr_weight.clean) kg", label: "récord de peso")
                        StatTile(icon: "bolt.fill", value: "\(p.pr_1rm.clean) kg", label: "récord de 1RM estimado")
                    }

                    if let w = p.recommendation.weight {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Próxima sesión: \(w.clean) kg × \(p.recommendation.reps)", systemImage: "target")
                                .font(Theme.dSubheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(p.recommendation.note)
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card()
                    }

                    if p.sessions.count > 1 {
                        SectionHeader(title: "1RM estimado")
                        Chart(p.sessions, id: \.date) { s in
                            LineMark(
                                x: .value("Fecha", Fmt.date(s.date) ?? .now),
                                y: .value("1RM", s.est_1rm)
                            )
                            .foregroundStyle(Theme.accent)
                            .symbol(.circle)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                        .card()
                    }

                    SectionHeader(title: "Sesiones")
                    ForEach(p.sessions.reversed(), id: \.date) { s in
                        HStack {
                            Text(Fmt.short(s.date))
                                .font(Theme.dSubheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(s.top_weight.clean)×\(s.top_reps) · 1RM \(s.est_1rm.clean) · \(Int(s.volume)) kg")
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
                    }
                }
            }
        }
        .task { await loadExercises() }
    }

    var groupedMuscles: [String] {
        Array(Set(exercises.map(\.muscle))).sorted()
    }

    func loadExercises() async {
        do {
            // Solo los ejercicios que aparecen en tus rutinas (sin duplicados).
            let routines = try await API.shared.gymRoutines()
            var seen = Set<Int>()
            var out: [ExRef] = []
            for r in routines {
                for e in r.exercises where !seen.contains(e.exercise_id) {
                    seen.insert(e.exercise_id)
                    out.append(ExRef(id: e.exercise_id, name: e.name, muscle: e.muscle))
                }
            }
            exercises = out.sorted { $0.muscle == $1.muscle ? $0.name < $1.name : $0.muscle < $1.muscle }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadProgress(_ ex: ExRef) async {
        progress = nil
        progress = try? await API.shared.gymProgress(ex.id)
    }
}
