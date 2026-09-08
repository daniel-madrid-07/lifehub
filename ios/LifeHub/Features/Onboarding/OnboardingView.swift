import SwiftUI

/// Configuración inicial, la única vez que sale.
///
/// Paso 1: tus datos, para calcular calorías y objetivos.
/// Paso 2: cómo entrenas, para crear tus rutinas de salida.
///
/// No se pide ningún servidor: la app funciona sola desde el primer momento.
/// Conectar un backend es opcional y se hace luego desde Ajustes.
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var step = 0
    @State private var saving = false
    @State private var error: String?

    // Paso 1 — perfil
    @State private var name = ""
    @State private var heightCm = 175.0
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var sex = "m"
    @State private var activityFactor = 1.55
    @State private var goal = "Mantener"

    // Paso 2 — rutina
    @State private var templates: [RoutineTemplate] = []
    @State private var chosenTemplate: String?
    @State private var sets = 3

    private let goals = [
        ("Volumen", "Ganar músculo (+300 kcal)"),
        ("Definicion", "Perder grasa (−400 kcal)"),
        ("Mantener", "Mantener el peso"),
    ]
    private let activities: [(String, Double)] = [
        ("Sedentario", 1.2),
        ("Ligera (1-3 días)", 1.375),
        ("Moderada (3-5 días)", 1.55),
        ("Alta (6-7 días)", 1.725),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { profileStep } else { routineStep }
            }
            .navigationTitle(step == 0 ? "Bienvenido" : "Cómo entrenas")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ── Paso 1: perfil ──────────────────────────────────────────────────

    private var profileStep: some View {
        Form {
            Section {
                Text("Con estos datos se calculan tus calorías y proteína diarias. Todo se guarda en tu iPhone y puedes cambiarlo cuando quieras.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Sobre ti") {
                TextField("Nombre (opcional)", text: $name)
                DatePicker("Fecha de nacimiento", selection: $birthDate,
                           in: ...Date(), displayedComponents: .date)
                Picker("Sexo", selection: $sex) {
                    Text("Hombre").tag("m")
                    Text("Mujer").tag("f")
                }
                Stepper("Altura: \(Int(heightCm)) cm", value: $heightCm, in: 120...230, step: 1)
            }

            Section("Actividad") {
                Picker("Cuánto te mueves", selection: $activityFactor) {
                    ForEach(activities, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.menu)
            }

            Section("Objetivo") {
                ForEach(goals, id: \.0) { value, hint in
                    Button {
                        goal = value
                        Haptics.selection()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(value).foregroundStyle(.primary)
                                Text(hint).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if goal == value {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Continuar") {
                    Task { await saveProfile() }
                }
                .disabled(saving)
            }
        }
    }

    private func saveProfile() async {
        saving = true
        defer { saving = false }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        do {
            try await Me.save([
                "name": name.isEmpty ? .null : .string(name),
                "height_cm": .double(heightCm),
                "birth_date": .string(iso.string(from: birthDate)),
                "sex": .string(sex),
                "activity_factor": .double(activityFactor),
                "goal": .string(goal),
            ])
            templates = (try? await API.shared.routineTemplates()) ?? []
            step = 1
        } catch {
            self.error = "No se pudo guardar el perfil."
        }
    }

    // ── Paso 2: rutina de salida ────────────────────────────────────────

    private var routineStep: some View {
        Form {
            Section {
                Text("Elige un esquema de entrenamiento para empezar. Se crean las rutinas y podrás editarlas, o saltarte esto y crearlas tú.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper("Series por ejercicio: \(sets)", value: $sets, in: 1...6)
            }

            ForEach(templates) { template in
                Section {
                    Button {
                        chosenTemplate = template.id
                        Haptics.selection()
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).foregroundStyle(.primary)
                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if chosenTemplate == template.id {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await finish() }
                } label: {
                    HStack {
                        Text(chosenTemplate == nil ? "Empezar sin rutinas" : "Empezar")
                        Spacer()
                        if saving { ProgressView() }
                    }
                }
                .disabled(saving)
            }
        }
    }

    private func finish() async {
        saving = true
        defer { saving = false }

        if let chosenTemplate {
            _ = try? await API.shared.applyRoutineTemplate(chosenTemplate, sets: sets)
        }
        Haptics.success()
        onDone()
    }
}
