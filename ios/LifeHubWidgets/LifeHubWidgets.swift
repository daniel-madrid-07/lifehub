import WidgetKit
import SwiftUI
import AppIntents

// ── Intent interactivo: marcar/desmarcar un hábito ───────────────────────────
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar hábito"
    @Parameter(title: "id") var id: Int
    @Parameter(title: "hecho") var done: Bool
    @Parameter(title: "plato") var dish: String   // vacío si no es comida
    init() {}
    init(id: Int, done: Bool, dish: String = "") { self.id = id; self.done = done; self.dish = dish }

    // Marca y (si es comida) registra el plato EN PARALELO, para que el check
    // se pinte enseguida en vez de esperar varias llamadas en serie.
    func perform() async throws -> some IntentResult {
        if done {
            _ = try? await API.shared.undoDone(id)
            if !dish.isEmpty, let food = try? await API.shared.foodDay(),
               let item = food.items.last(where: { $0.name == dish }) {
                _ = try? await API.shared.removeFood(item.id)
            }
        } else {
            async let mark: Habit? = try? await API.shared.markDone(id)
            async let log: FoodItem? = dish.isEmpty ? nil : (try? await API.shared.dietLogMeal(dish))
            _ = await (mark, log)
        }
        return .result()
    }
}

struct HabitCheckRow: View {
    let habit: Habit
    var dish: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleHabitIntent(id: habit.id, done: habit.done_today, dish: dish)) {
                Image(systemName: habit.done_today ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(habit.done_today ? Theme.good : Theme.muted)
            }
            .buttonStyle(.plain)
            Text(habit.name)
                .font(.system(size: 15, weight: .medium))
                .strikethrough(habit.done_today)
                .foregroundStyle(habit.done_today ? Theme.muted : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

// ── Barra de macro ───────────────────────────────────────────────────────────
struct MacroBar: View {
    let label: String, value: Double, target: Double, unit: String, tint: Color
    var pct: Double { target > 0 ? min(value / target, 1) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(tint).frame(width: g.size.width * pct)
                }
            }
            .frame(height: 7)
            Text("\(Int(value)) / \(Int(target)) \(unit)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── COMIDA (mediano, rectangular): macros a la izquierda, ticks a la derecha ─
struct MealsEntry: TimelineEntry {
    let date: Date
    let meals: [Habit]
    let dishes: [Int: String]
    let kcal: Double, kcalTarget: Double
    let protein: Double, proteinTarget: Double
}

struct MealsProvider: TimelineProvider {
    func placeholder(in c: Context) -> MealsEntry { MealsEntry(date: .now, meals: [], dishes: [:], kcal: 0, kcalTarget: 2500, protein: 0, proteinTarget: 150) }
    func getSnapshot(in c: Context, completion: @escaping (MealsEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<MealsEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> MealsEntry {
        async let h = try? API.shared.today()
        async let f = try? API.shared.foodDay()
        async let bw = try? API.shared.gymBodyweight()
        async let dp = try? API.shared.dietPlan()
        let order = ["desayuno", "comida", "almuerzo", "merienda", "cena"]
        let meals = ((await h) ?? []).filter { $0.category == .diet }
            .sorted { a, b in
                (order.firstIndex { a.name.lowercased().contains($0) } ?? 9)
                    < (order.firstIndex { b.name.lowercased().contains($0) } ?? 9)
            }
        // Plato de hoy por comida, para poder registrar calorías sin buscarlo al tocar.
        var dishes: [Int: String] = [:]
        if let day = (await dp)?.days.first(where: { $0.is_today }) {
            for m in meals {
                let n = m.name.lowercased()
                dishes[m.id] = n.contains("desayuno") ? day.breakfast
                             : n.contains("merienda") ? day.snack
                             : n.contains("cena") ? day.dinner : day.lunch
            }
        }
        let food = await f
        let weight = (await bw)?.first?.weight ?? Me.fallbackWeight
        return MealsEntry(date: .now, meals: meals, dishes: dishes,
                          kcal: food?.total_kcal ?? 0, kcalTarget: Double(Me.kcalTarget(weight: weight)),
                          protein: food?.total_protein ?? 0, proteinTarget: Me.proteinTarget(weight: weight))
    }
}

struct MealsView: View {
    let entry: MealsEntry
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Comida").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                MacroBar(label: "Calorías", value: entry.kcal, target: entry.kcalTarget, unit: "kcal", tint: Theme.accent)
                MacroBar(label: "Proteína", value: entry.protein, target: entry.proteinTarget, unit: "g", tint: Theme.accent2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(entry.meals.prefix(4)) { HabitCheckRow(habit: $0, dish: entry.dishes[$0.id] ?? "") }
                Spacer(minLength: 0)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

struct MealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsWidgetV2", provider: MealsProvider()) { entry in
            MealsView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=nutrition"))
        }
        .configurationDisplayName("Comida")
        .description("Macros del día y tus comidas con un toque.")
        .supportedFamilies([.systemMedium])
    }
}

// ── Provider de hábitos de hoy (rutinas) ─────────────────────────────────────
struct HabitsEntry: TimelineEntry { let date: Date; let habits: [Habit] }
struct HabitsProvider: TimelineProvider {
    func placeholder(in c: Context) -> HabitsEntry { HabitsEntry(date: .now, habits: []) }
    func getSnapshot(in c: Context, completion: @escaping (HabitsEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> HabitsEntry { HabitsEntry(date: .now, habits: (try? await API.shared.today()) ?? []) }
}

// ── RUTINAS (pequeño) ────────────────────────────────────────────────────────
struct RoutinesView: View {
    let entry: HabitsEntry
    var all: [Habit] { entry.habits.filter { Category.routine.contains($0.category) } }
    var pending: [Habit] { all.filter { $0.due_today && !$0.done_today } }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Rutinas").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(all.filter(\.done_today).count)/\(all.count)")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
            }
            if pending.isEmpty {
                Spacer()
                Text("Todo hecho\npor hoy ✓").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.good)
                Spacer()
            } else {
                ForEach(pending.prefix(4)) { HabitCheckRow(habit: $0) }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutinesWidget", provider: HabitsProvider()) { entry in
            RoutinesView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=routines"))
        }
        .configurationDisplayName("Rutinas")
        .description("Marca tus rutinas del día.")
        .supportedFamilies([.systemSmall])
    }
}

// ── ENTRENO (pequeño): rutina de hoy + progreso vs último ────────────────────
struct WorkoutEntry: TimelineEntry {
    let date: Date
    let name: String?
    let count: Int
    let deltaKg: Double?
}

struct WorkoutProvider: TimelineProvider {
    func placeholder(in c: Context) -> WorkoutEntry { WorkoutEntry(date: .now, name: nil, count: 0, deltaKg: nil) }
    func getSnapshot(in c: Context, completion: @escaping (WorkoutEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> WorkoutEntry {
        async let r = try? API.shared.gymRoutines()
        async let w = try? API.shared.gymWorkouts()
        let routines = (await r) ?? []
        let name = Season.isSummer ? Season.todaySummerRoutine : routines.first { $0.today == true }?.name
        let count = routines.first { $0.name == name }?.exercises.count ?? 0
        let workouts = ((await w) ?? []).sorted { $0.started_at > $1.started_at }
        var delta: Double?
        if workouts.count >= 2, workouts[1].volume > 0 {
            delta = (workouts[0].volume - workouts[1].volume) / workouts[1].volume * 100
        }
        return WorkoutEntry(date: .now, name: name, count: count, deltaKg: delta)
    }
}

struct WorkoutWidgetView: View {
    let entry: WorkoutEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Gym").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            if let name = entry.name {
                Text("HOY TOCA").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text("\(entry.count) ejercicios").font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                Text("Descanso").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Hoy no toca").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if let d = entry.deltaKg {
                Text(d >= 0 ? "▲ +\(Int(d.rounded()))% vs anterior" : "▼ \(Int(d.rounded()))% vs anterior")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Theme.good : Theme.bad)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutWidget", provider: WorkoutProvider()) { entry in
            WorkoutWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=gym"))
        }
        .configurationDisplayName("Entreno de hoy")
        .description("Qué toca hoy y tu progreso respecto al último entreno.")
        .supportedFamilies([.systemSmall])
    }
}

// ── CLAUDE (pequeño): % sesión y semanal ─────────────────────────────────────
struct ClaudeEntry: TimelineEntry { let date: Date; let usage: ClaudeUsage? }
struct ClaudeProvider: TimelineProvider {
    func placeholder(in c: Context) -> ClaudeEntry { ClaudeEntry(date: .now, usage: nil) }
    func getSnapshot(in c: Context, completion: @escaping (ClaudeEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<ClaudeEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> ClaudeEntry { ClaudeEntry(date: .now, usage: try? await API.shared.claudeUsage()) }
}

struct ClaudeWidgetView: View {
    let entry: ClaudeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            if let u = entry.usage {
                pct("Sesión", u.session)
                pct("Semanal", u.weekly)
            } else {
                Spacer(); Text("Sin datos").font(.system(size: 15)).foregroundStyle(Theme.muted); Spacer()
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder func pct(_ label: String, _ w: ClaudeUsage.Window?) -> some View {
        if let w {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(w.pct)%").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(w.pct >= 90 ? Theme.bad : Theme.ink)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(w.pct >= 90 ? Theme.bad : Theme.accent)
                            .frame(width: g.size.width * CGFloat(min(w.pct, 100)) / 100)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeWidget", provider: ClaudeProvider()) { entry in
            ClaudeWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=studies"))
        }
        .configurationDisplayName("Uso de Claude")
        .description("Uso de sesión y semanal.")
        .supportedFamilies([.systemSmall])
    }
}

// ── ESTUDIOS (mediano): mismo texto que la pestaña (studies summary) ─────────
struct StudyEntry: TimelineEntry { let date: Date; let text: String }
struct StudyProvider: TimelineProvider {
    func placeholder(in c: Context) -> StudyEntry { StudyEntry(date: .now, text: "…") }
    func getSnapshot(in c: Context, completion: @escaping (StudyEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> StudyEntry {
        // Mismo texto que muestra la pestaña Estudios (summary de /api/studies).
        let s = try? await API.shared.studies()
        var text = s?.summary
        if (text ?? "").isEmpty { text = (try? await API.shared.aiStudies())?.text }
        return StudyEntry(date: .now, text: (text ?? "").isEmpty ? "Sin novedades de estudios." : text!)
    }
}

struct StudyWidgetView: View {
    let entry: StudyEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Estudios", systemImage: "graduationcap")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
            Text(entry.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudyWidget", provider: StudyProvider()) { entry in
            StudyWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=studies"))
        }
        .configurationDisplayName("Estudios · IA")
        .description("El resumen de estudios que genera la IA.")
        .supportedFamilies([.systemMedium])
    }
}

// ── AGENDA (pequeño): ¿algo hoy? ─────────────────────────────────────────────
struct AgendaEntry: TimelineEntry { let date: Date; let events: [CalendarEvent] }
struct AgendaProvider: TimelineProvider {
    func placeholder(in c: Context) -> AgendaEntry { AgendaEntry(date: .now, events: []) }
    func getSnapshot(in c: Context, completion: @escaping (AgendaEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(1800)))) }
    }
    func fetch() async -> AgendaEntry {
        let cal = Calendar.current
        let all = (try? await API.shared.calendar())?.events ?? []
        let today = all.filter { e in
            guard let d = Fmt.date(e.start) else { return false }
            return cal.isDateInToday(d)
        }.sorted { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
        return AgendaEntry(date: .now, events: today)
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agenda").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            if entry.events.isEmpty {
                Spacer()
                Text("Nada hoy").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("día libre").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
            } else {
                Text("\(entry.events.count) \(entry.events.count == 1 ? "evento" : "eventos") hoy")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                ForEach(entry.events.prefix(3), id: \.self) { e in
                    HStack(spacing: 6) {
                        Text(time(e.start)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                            .frame(width: 44, alignment: .leading)
                        Text(e.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    func time(_ iso: String?) -> String {
        guard let iso, iso.contains("T"), let d = Fmt.date(iso) else { return "todo" }
        return d.formatted(.dateTime.hour().minute())
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgendaWidget", provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=calendar"))
        }
        .configurationDisplayName("Agenda")
        .description("Si tienes algo hoy.")
        .supportedFamilies([.systemSmall])
    }
}

// ── PANTALLA DE BLOQUEO ──────────────────────────────────────────────────────
struct CreatineLockView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family
    var c: Habit? { entry.habits.first { $0.name.lowercased().contains("creatina") } }
    var body: some View {
        switch family {
        case .accessoryCircular:
            if let c {
                Button(intent: ToggleHabitIntent(id: c.id, done: c.done_today)) {
                    Image(systemName: c.done_today ? "checkmark" : "pills.fill")
                        .font(.title2)
                }.buttonStyle(.plain)
            } else {
                Image(systemName: "pills.fill").font(.title2)
            }
        case .accessoryInline:
            if let c {
                Label(c.done_today ? "Creatina \u{2713}" : "Creatina", systemImage: "pills.fill")
            } else {
                Label("Creatina", systemImage: "pills.fill")
            }
        default:
            if let c {
                HStack {
                    Button(intent: ToggleHabitIntent(id: c.id, done: c.done_today)) {
                        Image(systemName: c.done_today ? "checkmark.circle.fill" : "circle").font(.title3)
                    }.buttonStyle(.plain)
                    Text(c.done_today ? "Creatina hecha" : "Creatina").font(.headline)
                    Spacer()
                }
            } else {
                HStack {
                    Image(systemName: "pills.fill").font(.title3)
                    Text("Creatina").font(.headline)
                    Spacer()
                }
            }
        }
    }
}

struct CreatineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CreatineLock", provider: HabitsProvider()) { entry in
            CreatineLockView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Creatina")
        .description("Marca la creatina desde la pantalla de bloqueo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MealsLockView: View {
    let entry: MealsEntry
    @Environment(\.widgetFamily) private var family
    var next: Habit? { entry.meals.first { !$0.done_today } }
    var done: Int { entry.meals.filter(\.done_today).count }
    var total: Int { max(entry.meals.count, 1) }
    var toggleNext: ToggleHabitIntent {
        ToggleHabitIntent(id: next?.id ?? 0, done: false, dish: next.flatMap { entry.dishes[$0.id] } ?? "")
    }
    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(done), in: 0...Double(total)) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text("\(done)").font(.system(.caption2, design: .rounded).bold())
            }
            .gaugeStyle(.accessoryCircular)
        default:
            if let n = next {
                HStack(spacing: 8) {
                    Button(intent: toggleNext) {
                        Image(systemName: "circle").font(.title3)
                    }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Marcar comida (\(done)/\(entry.meals.count))").font(.caption2)
                        Text(n.name).font(.headline).lineLimit(1)
                    }
                    Spacer()
                }
            } else {
                Label("Comidas al día ✓", systemImage: "fork.knife")
            }
        }
    }
}

struct MealsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsLock", provider: MealsProvider()) { entry in
            MealsLockView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
        .configurationDisplayName("Comida (bloqueo)")
        .description("Marca comidas desde la pantalla de bloqueo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// ── SUEÑO (pequeño): hora de dormir y alarma basada en agenda ────────────────
struct SleepPlanEntry: TimelineEntry {
    let date: Date
    let bedtime: Date
    let alarm: Date
    let byAgenda: Bool   // true → alarm calculada desde evento de mañana
}

struct SleepPlanProvider: TimelineProvider {
    func placeholder(in c: Context) -> SleepPlanEntry { fallback() }
    func getSnapshot(in c: Context, completion: @escaping (SleepPlanEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<SleepPlanEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(1800)))) }
    }

    func fallback() -> SleepPlanEntry {
        let cal = Calendar.current; let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let alarm   = cal.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        let bedtime = alarm.addingTimeInterval(-(8 * 3600 + 15 * 60))
        return SleepPlanEntry(date: now, bedtime: bedtime, alarm: alarm, byAgenda: false)
    }

    func fetch() async -> SleepPlanEntry {
        let cal = Calendar.current; let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let ud = UserDefaults(suiteName: appGroupID) ?? .standard
        let latency: TimeInterval = 15 * 60

        // Personal sleep need from SleepManager (falls back to 8 h)
        let rawNeed = ud.double(forKey: "sleep_need_secs")
        let needSecs: TimeInterval = rawNeed > 0 ? rawNeed : 8 * 3600

        // Habitual wake hour → base alarm (falls back to 7:30)
        let wakeH = ud.double(forKey: "sleep_habitual_wake_h")
        var alarm: Date
        if wakeH > 0 {
            let h = Int(wakeH), m = Int((wakeH - Double(h)) * 60)
            alarm = cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrow) ?? tomorrow
        } else {
            alarm = cal.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? tomorrow
        }
        var byAgenda = false

        // Override with first calendar event of tomorrow if it means waking earlier
        if let events = try? await API.shared.calendar() {
            let first = (events.events ?? []).filter { e in
                guard let d = Fmt.date(e.start), e.start?.contains("T") == true else { return false }
                return cal.isDateInTomorrow(d)
            }.min { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
            if let ev = first, let start = Fmt.date(ev.start) {
                let deadline = start.addingTimeInterval(-45 * 60)
                if deadline < alarm { alarm = deadline; byAgenda = true }
            }
        }

        let bedtime = alarm.addingTimeInterval(-(needSecs + latency))
        return SleepPlanEntry(date: now, bedtime: bedtime, alarm: alarm, byAgenda: byAgenda)
    }
}

struct SleepPlanWidgetView: View {
    let entry: SleepPlanEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sueño").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text("ACUÉSTATE").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted).tracking(1)
            Text(hm(entry.bedtime))
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                Image(systemName: "alarm").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Text(hm(entry.alarm))
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            if entry.byAgenda {
                Text("por agenda").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }
    func hm(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }
}

struct SleepPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepPlanWidget", provider: SleepPlanProvider()) { entry in
            SleepPlanWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=sleep"))
        }
        .configurationDisplayName("Plan de sueño")
        .description("Hora de dormir y alarma según tu agenda de mañana.")
        .supportedFamilies([.systemSmall])
    }
}

// ── iOS 18 Controls (pantalla de bloqueo + Control Center + Action Button) ────

// Kind constants fuera de los structs @available para que los intents puedan usarlos sin guard
private let controlKindCreatina = "com.example.lifehub.CreatinaControl"
private let controlKindMeals    = "com.example.lifehub.MealsControl"

struct ToggleCreatinaControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Creatina"

    func perform() async throws -> some IntentResult {
        let habits = (try? await API.shared.today()) ?? []
        if let c = habits.first(where: { $0.name.lowercased().contains("creatina") }) {
            if c.done_today { _ = try? await API.shared.undoDone(c.id) }
            else            { _ = try? await API.shared.markDone(c.id) }
        }
        if #available(iOS 18, *) {
            ControlCenter.shared.reloadControls(ofKind: controlKindCreatina)
        }
        return .result()
    }
}

struct MarkNextMealControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Comida"

    func perform() async throws -> some IntentResult {
        let habits = (try? await API.shared.today()) ?? []
        if let next = habits.filter({ $0.category == .diet }).first(where: { !$0.done_today }) {
            _ = try? await API.shared.markDone(next.id)
        }
        if #available(iOS 18, *) {
            ControlCenter.shared.reloadControls(ofKind: controlKindMeals)
        }
        return .result()
    }
}

@available(iOS 18, *)
struct CreatinaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: controlKindCreatina, provider: Provider()) { isDone in
            ControlWidgetButton(action: ToggleCreatinaControlIntent()) {
                Label(isDone ? "Hecha" : "Creatina",
                      systemImage: isDone ? "checkmark.circle.fill" : "pills.fill")
            }
        }
        .displayName("Creatina")
        .description("Marca o desmarca la creatina del dia")
    }
}

@available(iOS 18, *)
extension CreatinaControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool {
            let habits = try await API.shared.today()
            return habits.first { $0.name.lowercased().contains("creatina") }?.done_today ?? false
        }
    }
}

@available(iOS 18, *)
struct MealsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: controlKindMeals, provider: Provider()) { s in
            ControlWidgetButton(action: MarkNextMealControlIntent()) {
                Label("\(s.done)/\(s.total)", systemImage: "fork.knife")
            }
        }
        .displayName("Comida")
        .description("Marca la siguiente comida del dia")
    }
}

@available(iOS 18, *)
extension MealsControl {
    struct Summary: Sendable { let done: Int; let total: Int }
    struct Provider: ControlValueProvider {
        var previewValue: Summary { Summary(done: 0, total: 5) }
        func currentValue() async throws -> Summary {
            let habits = try await API.shared.today()
            let meals = habits.filter { $0.category == .diet }
            return Summary(done: meals.filter(\.done_today).count, total: max(meals.count, 1))
        }
    }
}

// ── Bundle ───────────────────────────────────────────────────────────────────
@main
struct LifeHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealsWidget()
        RoutinesWidget()
        WorkoutWidget()
        ClaudeWidget()
        AgendaWidget()
        StudyWidget()
        CreatineWidget()
        MealsLockWidget()
        SleepPlanWidget()
        if #available(iOS 18, *) {
            CreatinaControl()
            MealsControl()
        }
    }
}
