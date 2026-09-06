import SwiftUI

/// Edición del perfil: datos corporales, objetivo, material del gimnasio y
/// ubicación para el clima. Todo lo que antes estaba fijo en el código.
struct ProfileSettingsView: View {
    @State private var profile = Me.current
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?

    // Campos editables
    @State private var name = ""
    @State private var heightCm = 175.0
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var sex = "m"
    @State private var activityFactor = 1.5
    @State private var goal = "Mantener"
    @State private var bodyFat = ""
    @State private var barWeight = 20.0
    @State private var city = ""

    private let goals = ["Volumen", "Definicion", "Mantener"]
    private let activities: [(String, Double)] = [
        ("Sedentario", 1.2),
        ("Ligera (1-3 días)", 1.375),
        ("Moderada (3-5 días)", 1.55),
        ("Alta (6-7 días)", 1.725),
    ]

    var body: some View {
        Form {
            Section("Sobre ti") {
                TextField("Nombre", text: $name)
                Toggle("Fecha de nacimiento", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Nacimiento", selection: $birthDate, displayedComponents: .date)
                }
                Picker("Sexo", selection: $sex) {
                    Text("Hombre").tag("m")
                    Text("Mujer").tag("f")
                }
                Stepper("Altura: \(Int(heightCm)) cm", value: $heightCm, in: 120...230, step: 1)
                HStack {
                    Text("% graso")
                    Spacer()
                    TextField("opcional", text: $bodyFat)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section {
                Picker("Actividad", selection: $activityFactor) {
                    ForEach(activities, id: \.1) { Text($0.0).tag($0.1) }
                }
                Picker("Objetivo", selection: $goal) {
                    ForEach(goals, id: \.self) { Text($0) }
                }
            } header: {
                Text("Objetivo")
            } footer: {
                if profile.kcal_target > 0 {
                    Text("Ahora mismo: \(profile.kcal_target) kcal y \(Int(profile.protein_target)) g de proteína al día, con \(Int(profile.weight)) kg de peso.")
                }
            }

            Section {
                Stepper("Barra: \(barWeight, specifier: "%g") kg", value: $barWeight, in: 0...50, step: 2.5)
            } header: {
                Text("Gimnasio")
            } footer: {
                Text("El peso de la barra se usa para calcular qué discos poner por lado.")
            }

            Section {
                TextField("Ciudad", text: $city)
            } header: {
                Text("Ubicación")
            } footer: {
                Text("Solo para el clima del resumen diario. Déjalo vacío para no incluirlo.")
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
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Guardar")
                        Spacer()
                        if saving { ProgressView() }
                    }
                }
                .disabled(saving)
            }
        }
        .navigationTitle("Tu perfil")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            profile = await Me.refresh()
            fillFields()
            loaded = true
        }
    }

    private func fillFields() {
        name = profile.name ?? ""
        heightCm = profile.height_cm
        sex = profile.sex
        activityFactor = profile.activity_factor
        goal = profile.goal
        barWeight = profile.bar_weight
        city = profile.city ?? ""
        bodyFat = profile.body_fat_pct.map { String(format: "%g", $0) } ?? ""

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let raw = profile.birth_date {
            birthDate = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) ?? Date()
            hasBirthDate = true
        }
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var patch: [String: JSONValue] = [
            "name": name.isEmpty ? .null : .string(name),
            "height_cm": .double(heightCm),
            "sex": .string(sex),
            "activity_factor": .double(activityFactor),
            "goal": .string(goal),
            "bar_weight": .double(barWeight),
            "city": city.isEmpty ? .null : .string(city),
        ]
        if hasBirthDate {
            patch["birth_date"] = .string(iso.string(from: birthDate))
        }
        if let fat = Double(bodyFat.replacingOccurrences(of: ",", with: ".")) {
            patch["body_fat_pct"] = .double(fat)
        }

        do {
            profile = try await Me.save(patch)
            fillFields()
        } catch {
            self.error = "No se pudo guardar. Revisa la conexión."
        }
    }
}
