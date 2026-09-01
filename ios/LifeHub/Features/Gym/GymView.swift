import SwiftUI

/// Gym: entreno activo, rutina de hoy, historial y accesos a Progreso/Salud.
struct GymView: View {
    @State private var active: GymWorkout?
    @State private var routines: [GymRoutine] = []
    @State private var workouts: [GymWorkoutSummary] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var training: GymWorkout?

    var body: some View {
        Screen(title: "Gym", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if !loaded {
                SkeletonList()
            } else {
                // Navegación: 2×2 para que quepan sin cortarse
                let navFont = Theme.dCaption.weight(.semibold)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                    NavigationLink { GymOverallProgressView() } label: {
                        Label("Progreso", systemImage: "chart.bar.fill")
                            .font(navFont).frame(maxWidth: .infinity)
                    }
                    .secondaryGlass()
                    NavigationLink { GymProgressView() } label: {
                        Label("Ejercicio", systemImage: "chart.line.uptrend.xyaxis")
                            .font(navFont).frame(maxWidth: .infinity)
                    }
                    .secondaryGlass()
                    NavigationLink { PRView() } label: {
                        Label("PR", systemImage: "trophy")
                            .font(navFont).frame(maxWidth: .infinity)
                    }
                    .secondaryGlass()
                    NavigationLink { GymHealthView() } label: {
                        Label("Salud", systemImage: "heart.fill")
                            .font(navFont).frame(maxWidth: .infinity)
                    }
                    .secondaryGlass()
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.light() })

                // Entreno a medias → continuar
                if let active {
                    Button {
                        Haptics.medium()
                        training = active
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Entreno en curso")
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(.black)
                                Text(active.routine_name ?? "Libre")
                                    .font(Theme.dCaption)
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(.black)
                        }
                        .padding(16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                SectionHeader(title: Season.isSummer ? "Rutinas · Verano" : "Rutinas")
                ForEach(Season.filter(routines, name: \.name)) { routine in
                    RoutineCard(routine: routine) {
                        Haptics.medium()
                        Task { await start(routine: routine) }
                    }
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
        .fullScreenCover(item: $training) { workout in
            GymTrainView(workout: workout) {
                training = nil
                Task { await load() }
            }
        }
    }

    func start(routine: GymRoutine?) async {
        do {
            training = try await API.shared.gymStartWorkout(routineId: routine?.id)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func load() async {
        do {
            async let a = API.shared.gymActiveWorkout()
            async let r = API.shared.gymRoutines()
            async let w = API.shared.gymWorkouts()
            active = try await a
            routines = try await r
            workouts = try await w
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RoutineCard: View {
    let routine: GymRoutine
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(routine.name)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                if routine.today == true {
                    Text("HOY")
                        .font(Theme.dCaption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button("Empezar", action: onStart)
                    .font(Theme.dCaption.weight(.bold))
                    .actionGlass()
            }
            Text("\(routine.exercises.count) ejercicios")
                .font(Theme.dCaption)
                .foregroundStyle(Theme.muted)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(routine.today == true ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }
}

