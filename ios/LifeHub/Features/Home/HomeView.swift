import SwiftUI

/// Inicio — el panel del día: qué comer ahora, qué toca en el gym, qué tienes
/// pendiente (rutinas, tareas, agenda y estudios) y el resumen de macros.
struct HomeView: View {
    @State private var habits: [Habit] = []
    @State private var food: FoodDay?
    @State private var tasks: [TaskItem] = []
    @State private var routines: [GymRoutine] = []
    @State private var diet: DietPlan?
    @State private var events: [CalendarEvent] = []
    @State private var studies: StudyOverview?
    @State private var weight = Me.fallbackWeight
    @State private var mealToast: String?

    var pendingHabits: [Habit] { habits.filter { $0.due_today } }
    var pendingTasks: [TaskItem] { tasks.filter { !$0.done } }
    var todayRoutine: GymRoutine? {
        if Season.isSummer {
            guard let n = Season.todaySummerRoutine else { return nil }
            return routines.first { $0.name == n }
        }
        return routines.first { $0.today == true }
    }
    var todayDiet: DietDay? { diet?.days.first { $0.is_today } }
    var todayEvents: [CalendarEvent] {
        events.filter {
            guard let d = Fmt.date($0.start) else { return false }
            return Calendar.current.isDateInToday(d)
        }
    }

    var body: some View {
        Screen(title: greeting, refresh: { await load() }) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                .font(Theme.dSubheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, -8)

            CoachCard { try await API.shared.aiToday() }

            // ── Qué toca comer ahora ──
            if let dish = currentMeal?.dish, !dish.isEmpty {
                SectionHeader(title: "Ahora toca comer")
                mealCard(slot: currentMeal!.label, dish: dish)
            }

            // ── Gimnasio de hoy ──
            SectionHeader(title: "Gimnasio")
            gymCard

            // ── Pendiente ──
            if !pendingHabits.isEmpty {
                SectionHeader(title: "Pendiente ahora")
                ForEach(pendingHabits.prefix(4)) { habit in
                    HabitRow(habit: habit) { replace($0) }
                }
            }

            // ── Agenda (solo lo de HOY) ──
            if !todayEvents.isEmpty {
                SectionHeader(title: "Agenda de hoy")
                ForEach(todayEvents, id: \.self) { EventRow(event: $0) }
            }

            // ── Estudios (deadline más próxima) ──
            if let deadline = nextStudy {
                SectionHeader(title: "Estudios")
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deadline.title)
                            .font(Theme.dHeadline)
                            .foregroundStyle(Theme.ink)
                        Text(deadline.detail)
                            .font(Theme.dCaption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .card()
            }

            // ── Resumen del día ──
            SectionHeader(title: "Resumen")
            HStack(spacing: 10) {
                StatTile(icon: "flame", value: food.map { "\(Int($0.total_kcal))" } ?? "—",
                         label: "de \(Me.kcalTarget(weight: weight)) kcal")
                StatTile(icon: "bolt.heart", value: food.map { "\(Int($0.total_protein)) g" } ?? "—",
                         label: "de \(Int(Me.proteinTarget(weight: weight))) g de proteína")
            }
            HStack(spacing: 10) {
                StatTile(icon: "checklist", value: "\(pendingTasks.count)",
                         label: pendingTasks.count == 1 ? "tarea pendiente" : "tareas pendientes")
                StatTile(icon: "circle.badge.checkmark",
                         value: "\(habits.filter(\.done_today).count)/\(habits.count)",
                         label: "rutinas hechas")
            }
        }
        .overlay(alignment: .topTrailing) {
            NavigationLink { MoreView() } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.muted)
                    .padding(10)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
        }
        .task { await load() }
    }

    // ── Tarjetas ──────────────────────────────────────────────────────────────

    @ViewBuilder
    func mealCard(slot: String, dish: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot)
                    .font(Theme.dCaption)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                Text(dish)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                if let mealToast {
                    Text(mealToast).font(Theme.dCaption).foregroundStyle(Theme.good)
                }
            }
            Spacer()
            Button("Apuntar") {
                Task {
                    Haptics.success()
                    _ = try? await API.shared.dietLogMeal(dish)
                    mealToast = "Apuntado en macros"
                    await loadFood()
                }
            }
            .font(Theme.dCaption.weight(.bold))
            .actionGlass()
        }
        .card()
    }

    @ViewBuilder
    var gymCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .foregroundStyle(Theme.accent)
            if let r = todayRoutine {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoy toca")
                        .font(Theme.dCaption).textCase(.uppercase).foregroundStyle(Theme.muted)
                    Text(r.name)
                        .font(Theme.dHeadline).foregroundStyle(Theme.ink)
                    Text("\(r.exercises.count) ejercicios")
                        .font(Theme.dCaption).foregroundStyle(Theme.muted)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Descanso")
                        .font(Theme.dHeadline).foregroundStyle(Theme.ink)
                    Text("Hoy no hay entreno programado.")
                        .font(Theme.dCaption).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .card()
    }

    // ── Datos derivados ───────────────────────────────────────────────────────

    struct Meal { let label: String; let dish: String }
    var currentMeal: Meal? {
        guard let d = todayDiet else { return nil }
        switch Calendar.current.component(.hour, from: .now) {
        case ..<11: return Meal(label: "Desayuno", dish: d.breakfast)
        case 11..<16: return Meal(label: "Comida", dish: d.lunch)
        case 16..<20: return Meal(label: "Merienda", dish: d.snack)
        default: return Meal(label: "Cena", dish: d.dinner)
        }
    }

    struct StudyLine { let title: String; let detail: String }
    var nextStudy: StudyLine? {
        if let p = studies?.projects?.first {
            return StudyLine(title: p.title, detail: p.deadline.map { "Entrega: \($0)" } ?? (p.progress ?? "En curso"))
        }
        if let a = studies?.activities?.first {
            return StudyLine(title: a.title, detail: a.start.map { "Empieza: \($0)" } ?? "Próxima actividad")
        }
        return nil
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 6..<13: return "Buenos días"
        case 13..<21: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    func replace(_ updated: Habit) {
        if let i = habits.firstIndex(where: { $0.id == updated.id }) { habits[i] = updated }
    }

    func loadFood() async { food = try? await API.shared.foodDay() }

    func load() async {
        async let h = try? API.shared.today()
        async let f = try? API.shared.foodDay()
        async let t = try? API.shared.tasks()
        async let r = try? API.shared.gymRoutines()
        async let d = try? API.shared.dietPlan()
        async let c = try? API.shared.calendar()
        async let s = try? API.shared.studies()
        async let bw = try? API.shared.gymBodyweight()
        habits = await h ?? []
        food = await f
        tasks = await t ?? []
        routines = await r ?? []
        diet = await d
        events = (await c)?.events ?? []
        studies = await s
        if let last = await bw?.first?.weight { weight = last }
    }
}

struct StatTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.display(26, weight: .regular))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(Theme.dCaption)
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
    }
}

extension String {
    /// Primera letra en mayúscula (para la fecha con weekday en minúscula).
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
