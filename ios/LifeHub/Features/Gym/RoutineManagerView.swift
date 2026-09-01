import SwiftUI

/// Gestión de rutinas de gym — espejo de GymRoutines.tsx.
/// Plan activo (Normal/Verano), listado por grupo, crear/editar/borrar.
struct RoutineManagerView: View {
    @State private var routines: [GymRoutine] = []
    @State private var mode = "normal"
    @State private var error: String?
    @State private var loaded = false
    @State private var editing: GymRoutine?
    @State private var creating = false

    var body: some View {
        Screen(title: "Rutinas de gym", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if !loaded {
                SkeletonList()
            } else {
                // Plan activo (recalcula qué toca hoy)
                SectionHeader(title: "Plan activo")
                Picker("", selection: $mode) {
                    Text("Normal").tag("normal")
                    Text("Verano").tag("summer")
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, m in
                    Haptics.selection()
                    Task {
                        _ = try? await API.shared.gymSetRoutineMode(m)
                        await load()
                    }
                }
                Text(mode == "summer"
                     ? "Verano: Front Day (martes) y Back Day (viernes), 1 serie de todo."
                     : "Tu split normal de 5 días.")
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)

                HButton(haptic: Haptics.medium) {
                    creating = true
                } label: {
                    Label("Nueva rutina", systemImage: "plus")
                        .font(Theme.dHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .actionGlass()
                .padding(.top, 4)

                ForEach(["normal", "verano"], id: \.self) { group in
                    let list = routines.filter { ($0.group ?? "normal") == group }
                    if !list.isEmpty {
                        SectionHeader(title: group == "normal" ? "Normal" : "Verano")
                        ForEach(list) { r in
                            RoutineManagerCard(
                                routine: r,
                                onEdit: { Haptics.light(); editing = r },
                                onDelete: {
                                    Task {
                                        _ = try? await API.shared.gymDeleteRoutine(r.id)
                                        Haptics.warning()
                                        await load()
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $creating) {
            RoutineFormSheet(routine: nil) { await load() }
        }
        .sheet(item: $editing) { r in
            RoutineFormSheet(routine: r) { await load() }
        }
    }

    func load() async {
        do {
            async let r = API.shared.gymRoutines()
            async let m = try? API.shared.gymRoutineMode()
            routines = try await r
            if let mm = await m?.mode { mode = mm }
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RoutineManagerCard: View {
    let routine: GymRoutine
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(routine.name)
                    .font(.display(20))
                    .foregroundStyle(Theme.ink)
                Spacer()
                HButton { onEdit() } label: {
                    Image(systemName: "pencil")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                }
                HButton(haptic: Haptics.rigid) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 32)
                }
            }
            ForEach(routine.exercises, id: \.exercise_id) { e in
                Text("\(e.name) — \(e.sets)×\(e.reps_min)-\(e.reps_max)")
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .card()
        .confirmationDialog("¿Borrar \(routine.name)?", isPresented: $confirmDelete) {
            Button("Borrar", role: .destructive) { onDelete() }
        }
    }
}

// ── Alta / edición de rutina ─────────────────────────────────────────────────

/// Ejercicio en edición dentro del formulario (series y rango de repes).
struct RoutineItem: Identifiable, Hashable {
    let exercise_id: Int
    let name: String
    let muscle: String
    let equipment: String
    var sets: Int
    var reps_min: Int
    var reps_max: Int
    var id: Int { exercise_id }
}

struct RoutineFormSheet: View {
    let routine: GymRoutine?
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var items: [RoutineItem] = []
    @State private var exercises: [GymExercise] = []
    @State private var picking = false
    @State private var saving = false

    var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !items.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Nombre (Push, Pull, Pierna…)", text: $name)
                        .padding(14)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)

                    Text("Ejercicios · series × repes mín–máx")
                        .font(Theme.dCaption.weight(.semibold))
                        .foregroundStyle(Theme.muted)

                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(Theme.dSubheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(item.muscle.capitalized)
                                        .font(Theme.dCaption2)
                                        .textCase(.uppercase)
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                HButton(haptic: Haptics.rigid) {
                                    items.removeAll { $0.exercise_id == item.exercise_id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(Theme.dCaption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            HStack(spacing: 12) {
                                Stepper("\(item.sets) series", value: $item.sets, in: 1...12)
                                    .font(Theme.dCaption)
                            }
                            HStack(spacing: 12) {
                                Stepper("\(item.reps_min) mín", value: $item.reps_min, in: 1...50)
                                    .font(Theme.dCaption)
                                Stepper("\(item.reps_max) máx", value: $item.reps_max, in: 1...50)
                                    .font(Theme.dCaption)
                            }
                        }
                        .card(padding: 13)
                    }

                    HButton(haptic: Haptics.medium) {
                        picking = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus")
                            .font(Theme.dSubheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .secondaryGlass(Theme.accent)

                    HButton(haptic: Haptics.success) {
                        Task { await save() }
                    } label: {
                        Text(saving ? "Guardando…" : "Guardar")
                            .font(Theme.dHeadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .actionGlass()
                    .disabled(!valid || saving)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle(routine == nil ? "Nueva rutina" : "Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(isPresented: $picking) {
                ExercisePickerSheet(exercises: exercises) { ex in
                    addExercise(ex)
                } onCreated: { ex in
                    exercises.append(ex)
                }
            }
            .task {
                exercises = (try? await API.shared.gymExercises()) ?? []
                fill()
            }
        }
        .preferredColorScheme(.dark)
    }

    func fill() {
        guard let routine else { return }
        name = routine.name
        items = routine.exercises.map {
            RoutineItem(exercise_id: $0.exercise_id, name: $0.name, muscle: $0.muscle,
                        equipment: $0.equipment, sets: $0.sets, reps_min: $0.reps_min, reps_max: $0.reps_max)
        }
    }

    func addExercise(_ ex: GymExercise) {
        picking = false
        guard !items.contains(where: { $0.exercise_id == ex.id }) else { return }
        items.append(RoutineItem(exercise_id: ex.id, name: ex.name, muscle: ex.muscle,
                                 equipment: ex.equipment, sets: 2, reps_min: 6, reps_max: 8))
    }

    func save() async {
        guard valid, !saving else { return }
        saving = true
        defer { saving = false }
        let payload: [JSONValue] = items.map {
            .object([
                "exercise_id": .int($0.exercise_id),
                "sets": .int($0.sets),
                "reps_min": .int($0.reps_min),
                "reps_max": .int($0.reps_max),
            ])
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        do {
            if let routine {
                _ = try await API.shared.gymUpdateRoutine(routine.id, name: trimmed, exercises: payload)
            } else {
                _ = try await API.shared.gymCreateRoutine(name: trimmed, exercises: payload)
            }
            await onDone()
            dismiss()
        } catch {
            Haptics.warning()
        }
    }
}

// ── Selector de ejercicios (buscar, filtrar por músculo, crear) ──────────────

struct ExercisePickerSheet: View {
    let exercises: [GymExercise]
    let onSelect: (GymExercise) -> Void
    let onCreated: (GymExercise) -> Void
    @Environment(\.dismiss) private var dismiss

    static let muscles = ["Pecho", "Espalda", "Hombros", "Biceps", "Triceps", "Pierna", "Core", "Cardio"]
    static let equipment = ["barra", "mancuernas", "maquina", "polea", "peso corporal"]
    static let equipmentLabels = [
        "barra": "Barra", "mancuernas": "Mancuernas", "maquina": "Máquina",
        "polea": "Polea", "peso corporal": "Peso corporal",
    ]

    @State private var query = ""
    @State private var muscle: String?
    @State private var creating = false
    @State private var newMuscle = "Pecho"
    @State private var newEquipment = "barra"
    @State private var saving = false

    var filtered: [GymExercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter {
            (muscle == nil || $0.muscle == muscle) &&
            (q.isEmpty || $0.name.lowercased().contains(q))
        }
    }

    /// Agrupados por material (orden fijo), primeros 80.
    var groups: [(equipment: String, items: [GymExercise])] {
        let visible = Array(filtered.prefix(80))
        var byEquip: [String: [GymExercise]] = [:]
        for e in visible { byEquip[e.equipment, default: []].append(e) }
        return Self.equipment.compactMap { eq in
            byEquip[eq].map { (eq, $0) }
        } + byEquip.keys.filter { !Self.equipment.contains($0) }.sorted().compactMap { eq in
            byEquip[eq].map { (eq, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField("Buscar…", text: $query)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip(nil, "Todos")
                            ForEach(Self.muscles, id: \.self) { m in chip(m, m) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(groups, id: \.equipment) { group in
                            Text(Self.equipmentLabels[group.equipment] ?? group.equipment)
                                .font(Theme.dCaption.weight(.semibold))
                                .textCase(.uppercase)
                                .tracking(1.5)
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 12)
                            ForEach(group.items) { e in
                                HButton {
                                    onSelect(e)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.name)
                                                .font(Theme.dSubheadline.weight(.medium))
                                                .foregroundStyle(Theme.ink)
                                            Text(e.muscle.capitalized)
                                                .font(Theme.dCaption2)
                                                .textCase(.uppercase)
                                                .foregroundStyle(Theme.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                }
                            }
                        }

                        if filtered.isEmpty {
                            Text("Nada encontrado. Créalo abajo.")
                                .font(Theme.dSubheadline)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }

                        createBlock
                            .padding(.top, 12)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Ejercicios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    func chip(_ value: String?, _ label: String) -> some View {
        let active = muscle == value
        HButton(haptic: Haptics.selection) {
            muscle = value
        } label: {
            Text(label)
                .font(Theme.dCaption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? Theme.accent.opacity(0.15) : Theme.surface2, in: Capsule())
                .foregroundStyle(active ? Theme.accent : Theme.muted)
        }
    }

    @ViewBuilder
    var createBlock: some View {
        if !creating {
            HButton(haptic: Haptics.medium) {
                creating = true
            } label: {
                Label(query.trimmingCharacters(in: .whitespaces).isEmpty
                      ? "Crear ejercicio nuevo"
                      : "Crear \"\(query.trimmingCharacters(in: .whitespaces))\"",
                      systemImage: "plus")
                    .font(Theme.dSubheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    .foregroundStyle(Theme.muted)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nuevo: \(query.trimmingCharacters(in: .whitespaces).isEmpty ? "(escribe el nombre arriba)" : query)")
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Picker("Músculo", selection: $newMuscle) {
                        ForEach(Self.muscles, id: \.self) { Text($0) }
                    }
                    Picker("Material", selection: $newEquipment) {
                        ForEach(Self.equipment, id: \.self) { Text(Self.equipmentLabels[$0] ?? $0) }
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)

                HButton(haptic: Haptics.success) {
                    Task { await create() }
                } label: {
                    Text("Crear y elegir")
                        .font(Theme.dSubheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(14)
            .background(Theme.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    func create() async {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }
        if let ex = try? await API.shared.gymCreateExercise(name: name, muscle: newMuscle, equipment: newEquipment) {
            onCreated(ex)
            onSelect(ex)
            dismiss()
        }
    }
}
