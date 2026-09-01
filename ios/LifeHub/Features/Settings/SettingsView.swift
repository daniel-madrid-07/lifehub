import SwiftUI

/// Ajustes: gestión de hábitos, estado de conexiones y sesión.
struct SettingsView: View {
    var body: some View {
        Screen(title: "Ajustes") {
            Text("Todo lo que se edita vive aquí. La app del día a día queda limpia: solo marcar, apuntar y consultar.")
                .font(Theme.dSubheadline)
                .foregroundStyle(Theme.muted)

            SettingsLink(icon: "square.grid.2x2", title: "Barra de navegación",
                         hint: "Elige qué apps van en la barra inferior") { NavbarSettingsView() }
            SettingsLink(icon: "dumbbell", title: "Rutinas de gym",
                         hint: "Crear y editar rutinas y ejercicios") { RoutineManagerView() }
            SettingsLink(icon: "checklist.unchecked", title: "Hábitos y comidas",
                         hint: "Crear, editar o pausar tus rutinas diarias") { HabitManagerView() }
            SettingsLink(icon: "cart", title: "Lista de la compra",
                         hint: "Añadir o quitar productos") { ShoppingScreen() }
            SettingsLink(icon: "envelope", title: "Conexiones",
                         hint: "Token de Google y sesión de Epitech") { ConnectionsView() }
        }
    }
}

struct SettingsLink<Destination: View>: View {
    let icon: String
    let title: String
    let hint: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.dHeadline)
                        .foregroundStyle(Theme.ink)
                    Text(hint)
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.dFootnote)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }
}

/// Lista de la compra como pantalla completa (reutiliza ShoppingView).
struct ShoppingScreen: View {
    var body: some View {
        Screen(title: "Compra") { ShoppingView() }
    }
}

// ── Barra de navegación configurable ─────────────────────────────────────────

struct NavbarSettingsView: View {
    @AppStorage("nav_slots") private var slotsRaw = "gym,nutrition,finance,more"

    var slots: [NavModule] {
        let m = slotsRaw.split(separator: ",").compactMap { NavModule(rawValue: String($0)) }
        return m.count == 4 ? m : RootView.defaultSlots
    }

    var body: some View {
        Screen(title: "Barra de navegación") {
            Text("Elige qué apps van en la barra inferior. \"Hoy\" queda fija en el centro y la app abre siempre ahí.")
                .font(Theme.dSubheadline)
                .foregroundStyle(Theme.muted)

            slotRow(0, "Izquierda ·1")
            slotRow(1, "Izquierda ·2")
            HStack(spacing: 12) {
                Image(systemName: "house")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Hoy")
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("centro · fija")
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
            }
            .card()
            slotRow(2, "Derecha ·1")
            slotRow(3, "Derecha ·2")
        }
    }

    @ViewBuilder
    func slotRow(_ i: Int, _ label: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.dCaption)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
            Spacer()
            Menu {
                ForEach(NavModule.selectable) { m in
                    Button { setSlot(i, m) } label: { Label(m.label, systemImage: m.icon) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: slots[i].icon).font(.system(size: 16, weight: .light))
                    Text(slots[i].label).font(Theme.dHeadline)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
            }
        }
        .card()
    }

    /// Asigna el módulo al hueco i; si ya estaba en otro hueco, los intercambia
    /// (así los 4 siempre son distintos).
    func setSlot(_ i: Int, _ m: NavModule) {
        var s = slots
        if let j = s.firstIndex(of: m), j != i { s[j] = s[i] }
        s[i] = m
        slotsRaw = s.map(\.rawValue).joined(separator: ",")
        Haptics.selection()
    }
}

// ── Conexiones (estado + renovar token de Google) ────────────────────────────

struct ConnectionsView: View {
    @State private var status: AuthStatus?
    @State private var opening = false

    var body: some View {
        Screen(title: "Conexiones", refresh: { status = try? await API.shared.authStatus() }) {
            Text("Estado de tus cuentas. Cuando algo caduque, se renueva desde aquí.")
                .font(Theme.dSubheadline)
                .foregroundStyle(Theme.muted)

            if let status {
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionRow(
                        name: "Google · Gmail y Agenda",
                        connected: status.google.connected,
                        detail: status.google.days_left.map { "\($0) días" }
                    )
                    Text(status.google.connected
                         ? "Correo y agenda funcionando."
                         : "No conecta: renueva el token para volver a leer correo y agenda.")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                    if !status.google.connected {
                        HButton(haptic: Haptics.medium) {
                            Task { await renew() }
                        } label: {
                            Text(opening ? "Abriendo Google…" : "Renovar token")
                                .font(Theme.dSubheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .actionGlass()
                        .disabled(opening)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    ConnectionRow(
                        name: "Epitech · intra",
                        connected: status.epitech.connected,
                        detail: status.epitech.days_left.map { "~\($0) días" }
                    )
                    Text(status.epitech.connected
                         ? "Estudios y el coach funcionan."
                         : "Sesión caída: hay que rehacer el login (Microsoft + 2FA). Dímelo y lo renovamos.")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                }
                .card()
            } else {
                SkeletonList(rows: 2)
            }
        }
        .task { status = try? await API.shared.authStatus() }
    }

    func renew() async {
        opening = true
        defer { opening = false }
        if let r = try? await API.shared.authGoogleURL(), let url = URL(string: r.url) {
            await UIApplication.shared.open(url)
        }
    }
}

struct ConnectionRow: View {
    let name: String
    let connected: Bool
    let detail: String?

    var body: some View {
        HStack {
            Circle()
                .fill(connected ? Theme.good : Theme.bad)
                .frame(width: 9, height: 9)
            Text(name)
                .font(Theme.dSubheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(connected ? (detail ?? "Conectado") : "Sin conexión")
                .font(Theme.dCaption)
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── Gestión de hábitos (CRUD, vive en Ajustes como en la web) ───────────────

struct HabitManagerView: View {
    @State private var habits: [Habit]?
    @State private var error: String?
    @State private var editing: Habit?
    @State private var creating = false

    var body: some View {
        Screen(title: "Hábitos", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let habits {
                HButton(haptic: Haptics.medium) {
                    creating = true
                } label: {
                    Label("Nuevo hábito", systemImage: "plus")
                        .font(Theme.dHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .actionGlass()

                ForEach(habits) { habit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(Theme.dHeadline)
                                .foregroundStyle(habit.active ? Theme.ink : Theme.muted)
                            Text(habit.category.label)
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: .init(
                            get: { habit.active },
                            set: { on in
                                Task {
                                    _ = try? await API.shared.updateHabit(habit.id, ["active": .bool(on)])
                                    await load()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .card(padding: 13)
                    .contextMenu {
                        Button {
                            editing = habit
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                _ = try? await API.shared.deleteHabit(habit.id)
                                await load()
                            }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            } else {
                SkeletonList()
            }
        }
        .task { await load() }
        .sheet(isPresented: $creating) {
            HabitFormSheet(habit: nil) { await load() }
        }
        .sheet(item: $editing) { habit in
            HabitFormSheet(habit: habit) { await load() }
        }
    }

    func load() async {
        do {
            habits = try await API.shared.habits()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Alta/edición de hábito: horas fijas, días de la semana o cada N días.
struct HabitFormSheet: View {
    let habit: Habit?
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Category = .custom
    @State private var scheduleType = "daily_times"
    @State private var times = "09:00"
    @State private var intervalDays = 2
    @State private var weekDays: Set<Int> = []

    private let dayNames = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)

                Picker("Categoría", selection: $category) {
                    ForEach(Category.allCases) { c in
                        Text(c.label).tag(c)
                    }
                }

                Picker("Horario", selection: $scheduleType) {
                    Text("Horas fijas").tag("daily_times")
                    Text("Días de la semana").tag("week_days")
                    Text("Cada N días").tag("interval_days")
                }

                switch scheduleType {
                case "interval_days":
                    Stepper("Cada \(intervalDays) días", value: $intervalDays, in: 1...30)
                case "week_days":
                    HStack {
                        ForEach(0..<7, id: \.self) { d in
                            Button(dayNames[d]) {
                                if weekDays.contains(d) { weekDays.remove(d) } else { weekDays.insert(d) }
                            }
                            .buttonStyle(.borderless)
                            .font(Theme.dCaption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                weekDays.contains(d) ? Theme.accent : Theme.surface2,
                                in: Circle()
                            )
                            .foregroundStyle(weekDays.contains(d) ? .black : Theme.muted)
                        }
                    }
                    TextField("Horas (09:00, 14:00…)", text: $times)
                default:
                    TextField("Horas (09:00, 14:00…)", text: $times)
                }
            }
            .navigationTitle(habit == nil ? "Nuevo hábito" : "Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { fill() }
        }
        .preferredColorScheme(.dark)
    }

    func fill() {
        guard let habit else { return }
        name = habit.name
        category = habit.category
        scheduleType = habit.schedule_type
        switch habit.schedule {
        case .times(let t): times = t.joined(separator: ", ")
        case .interval(let n): intervalDays = n
        case .week(let w):
            weekDays = Set(w.days)
            times = w.times.joined(separator: ", ")
        }
    }

    func save() async {
        let timeList = times.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let schedule: JSONValue
        switch scheduleType {
        case "interval_days":
            schedule = .int(intervalDays)
        case "week_days":
            schedule = .object([
                "days": .array(weekDays.sorted().map { .int($0) }),
                "times": .array(timeList.map { .string($0) }),
            ])
        default:
            schedule = .array(timeList.map { .string($0) })
        }

        let data: [String: JSONValue] = [
            "name": .string(name),
            "category": .string(category.rawValue),
            "schedule_type": .string(scheduleType),
            "schedule": schedule,
        ]
        if let habit {
            _ = try? await API.shared.updateHabit(habit.id, data)
        } else {
            _ = try? await API.shared.createHabit(data)
        }
        await onDone()
        dismiss()
    }
}
