import SwiftUI
import WatchKit

@main
struct RepCounterApp: App {
    @StateObject private var store = Store()

    init() {
        // Escucha la configuración que manda el iPhone.
        WatchConfigReceiver.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .background(Theme.bg)
        }
    }
}

// Carrusel de pestañas (desliza en horizontal). Gym es la principal (primera).
struct MainTabView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView().environmentObject(store).tag(0)
            HabitListView(title: "Rutinas", kind: .routine).tag(1)
            HabitListView(title: "Comida", kind: .food).tag(2)
            SleepAlarmView().tag(3)
            WatchSettingsView().tag(4)
        }
        .tabViewStyle(.verticalPage)
    }
}

// ── Pestaña de hábitos marcables (Rutinas / Comida) ─────────────────────────
struct HabitListView: View {
    enum Kind { case routine, food }
    let title: String
    let kind: Kind

    @State private var habits: [WatchHabit] = []
    @State private var loading = true
    @State private var error = false

    private func belongs(_ h: WatchHabit) -> Bool {
        kind == .food ? h.category == "diet" : h.category != "diet"
    }
    private var mine: [WatchHabit] {
        habits.filter(belongs).sorted { ($0.done_today ? 1 : 0) < ($1.done_today ? 1 : 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else if error {
                    Text("Sin conexión")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.muted)
                } else if mine.isEmpty {
                    Text("Nada por hoy")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.muted)
                } else {
                    List {
                        ForEach(mine) { habit in
                            HabitToggleRow(habit: habit) { updated in
                                if let i = habits.firstIndex(where: { $0.id == updated.id }) {
                                    habits[i] = updated
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .containerBackground(Theme.bg, for: .navigation)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            habits = try await API.habitsToday()
            error = false
        } catch {
            self.error = true
        }
        loading = false
    }
}

struct HabitToggleRow: View {
    let habit: WatchHabit
    let onUpdate: (WatchHabit) -> Void
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                do {
                    let updated = habit.done_today ? try await API.undoDone(habit.id)
                                                    : try await API.markDone(habit.id)
                    if !habit.done_today {
                        WKInterfaceDevice.current().play(.success)
                    } else {
                        WKInterfaceDevice.current().play(.click)
                    }
                    onUpdate(updated)
                } catch {
                    WKInterfaceDevice.current().play(.failure)
                }
                busy = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: habit.done_today ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(habit.done_today ? Theme.gain : Theme.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(habit.name)
                        .font(.system(.body))
                        .foregroundStyle(habit.done_today ? Theme.muted : Theme.ink)
                        .strikethrough(habit.done_today)
                        .lineLimit(1)
                    if let t = habit.next_time, habit.due_today, !habit.done_today {
                        Text(t)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// ── Inicio: rutina de hoy + Empezar (estilo Life Hub) ───────────────────────
struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if store.loading {
                    ProgressView().tint(Theme.accent)
                } else if let error = store.error {
                    Text(error)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                } else if store.exercises.isEmpty {
                    Text("Hoy toca descanso")
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    NavigationLink(destination: RoutinePickerView().environmentObject(store)) {
                        Text("Entreno libre")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.muted)
                    .padding(.top, 2)
                } else {
                    Text(store.routine ?? "Entreno")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("\(store.exercises.count) ejercicios")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)

                    Button {
                        WKInterfaceDevice.current().play(.start)
                        started = true
                    } label: {
                        Text("Empezar")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(.black)
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 4)
            .containerBackground(Theme.bg, for: .navigation)
            .navigationDestination(isPresented: $started) {
                WorkoutView().environmentObject(store)
            }
        }
        .task { await store.loadToday() }
    }
}

// ── Selector de rutina para entreno libre (días de descanso) ─────────────────
struct RoutinePickerView: View {
    @EnvironmentObject var store: Store
    @State private var routines: [DeviceRoutine] = []
    @State private var loading = true
    @State private var fetchError: String?
    @State private var selected = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.accent)
            } else if let e = fetchError {
                Text(e)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    ForEach(routines) { r in routineButton(r) }
                }
            }
        }
        .navigationTitle("Rutinas")
        .containerBackground(Theme.bg, for: .navigation)
        .navigationDestination(isPresented: $selected) {
            WorkoutView().environmentObject(store)
        }
        .task {
            do {
                routines = try await API.routines()
            } catch {
                fetchError = "No se pudieron cargar las rutinas."
            }
            loading = false
        }
    }

    @ViewBuilder
    private func routineButton(_ r: DeviceRoutine) -> some View {
        Button {
            Task {
                await store.loadRoutine(id: r.id)
                selected = true
            }
        } label: {
            Text(r.name)
                .foregroundStyle(Theme.ink)
        }
    }
}

// ── Entreno guiado: serie → feedback → siguiente ────────────────────────────
struct WorkoutView: View {
    @EnvironmentObject var store: Store
    @StateObject private var detector = RepDetector()
    @State private var index = 0
    @State private var setsDone = 0
    @State private var weight: Double = 20
    @State private var feedback: String?
    @State private var feedbackGood = false
    @State private var sending = false
    @State private var finishedAll = false
    @State private var totalSets = 0
    @State private var finalized = false
    @FocusState private var weightFocused: Bool

    var body: some View {
        Group {
            if finishedAll || store.exercises.isEmpty {
                doneView
            } else {
                exerciseView
            }
        }
        .containerBackground(Theme.bg, for: .navigation)
        .onAppear {
            syncToExercise()
            detector.startMonitoring()   // escucha sacudidas aunque no cuente
            // Da el foco a la corona para que ajuste el peso sin avisos raros.
            DispatchQueue.main.async { weightFocused = true }
        }
        .onDisappear {
            detector.stopMonitoring()
            store.workout.end()
        }
        .onChange(of: detector.shakeCount) { _, _ in handleShake() }
    }

    /// Sacudir la muñeca empieza o termina la serie (sin tocar la pantalla).
    private func handleShake() {
        guard !finishedAll, !sending else { return }
        if detector.running { finishSet() } else { startSet() }
    }

    private var exercise: DeviceExercise { store.exercises[index] }

    private var exerciseView: some View {
        VStack(spacing: 4) {
            // Cabecera estilo Life Hub
            Text("\(index + 1)/\(store.exercises.count) · SERIE \(min(setsDone + 1, exercise.target_sets))/\(exercise.target_sets)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)
            Text(exercise.name)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)

            // Contador grande + correcciones manuales
            HStack(spacing: 10) {
                Button { detector.adjust(-1) } label: {
                    Image(systemName: "minus").font(.caption2)
                }
                .buttonStyle(.bordered).tint(Theme.muted)
                .disabled(!detector.running)

                Text("\(detector.reps)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(detector.running ? Theme.ink : Theme.muted)
                    .contentTransition(.numericText())
                    .frame(minWidth: 60)

                Button { detector.adjust(+1) } label: {
                    Image(systemName: "plus").font(.caption2)
                }
                .buttonStyle(.bordered).tint(Theme.muted)
                .disabled(!detector.running)
            }

            if detector.running && detector.manual {
                Text("Cuenta manual con +/−")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.muted)
            }

            // Peso real de tu app (recomendación), ajustable con la corona
            Text("\(weight, specifier: "%.2f") kg")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .focusable(true)
                .focused($weightFocused)
                .digitalCrownRotation($weight, from: 0, through: 300, by: 0.25,
                                      sensitivity: .low, isContinuous: false)
                .onChange(of: weight) { _, v in
                    weight = (v * 4).rounded() / 4
                }

            if let f = feedback {
                Text(f)
                    .font(.caption2)
                    .foregroundStyle(feedbackGood ? Theme.gain : Theme.muted)
                    .multilineTextAlignment(.center)
            }

            if detector.running {
                Button(action: finishSet) {
                    Text("Terminar serie").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            } else {
                Button(action: startSet) {
                    Text(sending ? "Guardando…" : "Empezar serie").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.gain).foregroundStyle(.black)
                .disabled(sending)
            }
            Text("o sacude la muñeca")
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 2)
    }

    private var doneView: some View {
        VStack(spacing: 8) {
            Text("ENTRENO COMPLETADO")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.accent)
            Text(store.routine ?? "Hecho")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("\(totalSets) series guardadas")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 5) {
                if !finalized { ProgressView().scaleEffect(0.6) }
                Text(finalized ? "Entreno finalizado en Life Hub" : "Finalizando…")
                    .font(.system(size: 10))
                    .foregroundStyle(finalized ? Theme.gain : Theme.muted)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .task {
            // Finaliza el entreno en el backend (mismo que el móvil): aparece en
            // "últimos entrenos" y sus pesos cuentan para la recomendación.
            guard !finalized else { return }
            _ = await API.finishActiveWorkout()
            finalized = true
        }
    }

    // ── Lógica ──────────────────────────────────────────────────────────────
    private func syncToExercise() {
        guard !store.exercises.isEmpty, index < store.exercises.count else { return }
        weight = store.exercises[index].weight ?? weight
    }

    private func startSet() {
        feedback = nil
        Task {
            await store.workout.requestAuth()
            store.workout.start()
        }
        detector.beginSet(for: exercise.name, id: exercise.exercise_id)
    }

    private func finishSet() {
        detector.endSet()
        store.workout.end()
        // Número REAL: recuento offline sobre toda la serie (no el contador vivo).
        let reps = detector.manual ? detector.reps : detector.reconciledCount()
        detector.reps = reps   // reconcilia el contador grande con lo que se guarda
        guard reps > 0 else {
            feedback = "0 reps: serie descartada"
            feedbackGood = false
            return
        }
        sending = true
        Task {
            do {
                let r = try await API.logSet(exerciseId: exercise.exercise_id,
                                             weight: weight, reps: reps)
                totalSets += 1
                var parts = ["\(reps) reps guardadas"]
                if r.pr == "peso" {
                    parts.append("PR de peso")
                    feedbackGood = true
                    WKInterfaceDevice.current().play(.notification)
                } else if r.pr == "1rm" {
                    parts.append("PR de 1RM")
                    feedbackGood = true
                    WKInterfaceDevice.current().play(.notification)
                } else if let pb = r.prev_best, weight > pb {
                    parts.append("+\(String(format: "%.1f", weight - pb)) kg vs anterior")
                    feedbackGood = true
                    WKInterfaceDevice.current().play(.success)
                } else {
                    feedbackGood = false
                    WKInterfaceDevice.current().play(.success)
                }
                setsDone += 1
                if setsDone >= exercise.target_sets {
                    // Ejercicio completado → pasa al siguiente con su peso real
                    if let nw = r.next_weight, let cur = exercise.weight, nw > cur {
                        parts.append("Próxima vez: \(String(format: "%.1f", nw)) kg")
                    }
                    feedback = parts.joined(separator: " · ")
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    advance()
                } else {
                    feedback = parts.joined(separator: " · ")
                }
            } catch {
                feedback = "Sin conexión: no se guardó"
                feedbackGood = false
            }
            sending = false
        }
    }

    private func advance() {
        if index + 1 < store.exercises.count {
            index += 1
            setsDone = 0
            feedback = nil
            syncToExercise()
            WKInterfaceDevice.current().play(.directionUp)
        } else {
            finishedAll = true
            WKInterfaceDevice.current().play(.success)
        }
    }
}
