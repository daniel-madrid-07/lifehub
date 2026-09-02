import SwiftUI

/// Configuración inicial: a qué servidor apunta la app, con qué clave, y los
/// datos corporales que antes estaban en el código.
///
/// Sale una sola vez; luego todo se edita desde Ajustes.
struct OnboardingView: View {
    /// Se llama cuando la instancia queda configurada y validada.
    var onDone: () -> Void

    @State private var step = 0

    // Paso 1 — servidor
    @State private var baseURL = ""
    @State private var token = ""
    @State private var checking = false
    @State private var connectionError: String?

    // Paso 2 — perfil
    @State private var name = ""
    @State private var heightCm = 175.0
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    @State private var sex = "m"
    @State private var activityFactor = 1.5
    @State private var goal = "Mantener"
    @State private var saving = false
    @State private var saveError: String?

    private let goals = ["Volumen", "Definicion", "Mantener"]
    private let activities: [(String, Double)] = [
        ("Sedentario", 1.2),
        ("Ligera (1-3 días)", 1.375),
        ("Moderada (3-5 días)", 1.55),
        ("Alta (6-7 días)", 1.725),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { serverStep } else { profileStep }
            }
            .navigationTitle(step == 0 ? "Tu servidor" : "Tu perfil")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ── Paso 1: servidor ────────────────────────────────────────────────

    private var serverStep: some View {
        Form {
            Section {
                TextField("https://mihub.example.com", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Clave de la API", text: $token)
            } header: {
                Text("Conexión")
            } footer: {
                Text("La URL de tu Life Hub y el APP_PASSWORD del .env del servidor. Se guardan en el Keychain del dispositivo, nunca en el código.")
            }

            if let connectionError {
                Section {
                    Label(connectionError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text("Conectar")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(baseURL.isEmpty || token.isEmpty || checking)
            }
        }
    }

    private func connect() async {
        checking = true
        connectionError = nil
        defer { checking = false }

        let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.baseURL = clean.hasPrefix("http") ? clean : "https://\(clean)"
        AppConfig.token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // Una llamada real: valida a la vez la URL y la clave.
            let profile = try await API.shared.profile()
            if profile.configured {
                // Ya había perfil en el servidor: no hace falta el paso 2.
                await Me.refresh()
                onDone()
            } else {
                prefill(from: profile)
                step = 1
            }
        } catch APIError.unauthorized {
            AppConfig.reset()
            connectionError = "La clave no es válida para ese servidor."
        } catch {
            AppConfig.reset()
            connectionError = "No se pudo conectar. Revisa la URL."
        }
    }

    private func prefill(from profile: ProfileDTO) {
        heightCm = profile.height_cm
        sex = profile.sex
        activityFactor = profile.activity_factor
        goal = profile.goal
    }

    // ── Paso 2: perfil ──────────────────────────────────────────────────

    private var profileStep: some View {
        Form {
            Section("Sobre ti") {
                TextField("Nombre", text: $name)
                DatePicker("Fecha de nacimiento", selection: $birthDate, displayedComponents: .date)
                Picker("Sexo", selection: $sex) {
                    Text("Hombre").tag("m")
                    Text("Mujer").tag("f")
                }
                Stepper("Altura: \(Int(heightCm)) cm", value: $heightCm, in: 120...230, step: 1)
            }

            Section {
                Picker("Actividad", selection: $activityFactor) {
                    ForEach(activities, id: \.1) { Text($0.0).tag($0.1) }
                }
                Picker("Objetivo", selection: $goal) {
                    ForEach(goals, id: \.self) { Text($0) }
                }
            } header: {
                Text("Entrenamiento")
            } footer: {
                Text("Con esto se calculan tus calorías y proteína diarias. Puedes cambiarlo cuando quieras en Ajustes.")
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Empezar")
                        Spacer()
                        if saving { ProgressView() }
                    }
                }
                .disabled(saving)
            }
        }
    }

    private func save() async {
        saving = true
        saveError = nil
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
            onDone()
        } catch {
            saveError = "No se pudo guardar el perfil."
        }
    }
}
