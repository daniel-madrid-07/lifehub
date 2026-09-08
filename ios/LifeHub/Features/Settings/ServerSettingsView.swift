import SwiftUI

/// Conectar (o desconectar) un servidor propio.
///
/// La app funciona sola guardando todo en el iPhone. Un backend añade los
/// módulos que dependen de servicios externos —correo, agenda, finanzas,
/// estudios, resúmenes con IA— y sincroniza entre dispositivos.
struct ServerSettingsView: View {
    @State private var baseURL = AppConfig.baseURL
    @State private var token = AppConfig.token
    @State private var checking = false
    @State private var connected = AppConfig.isConfigured
    @State private var message: String?
    @State private var isError = false
    @State private var confirmDisconnect = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: connected ? "checkmark.circle.fill" : "iphone")
                        .foregroundStyle(connected ? .green : Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connected ? "Conectado a tu servidor" : "Funcionando en este iPhone")
                            .font(.subheadline)
                        Text(connected
                             ? "Los datos se guardan en tu backend."
                             : "Los datos se guardan solo aquí.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !connected {
                Section {
                    Text("Sin servidor tienes hábitos, gimnasio, comidas, peso, tareas y notas. Correo, agenda, finanzas y los resúmenes con IA necesitan un backend porque hablan con servicios externos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("https://mihub.example.com", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Clave de la API", text: $token)
            } header: {
                Text("Conexión")
            } footer: {
                Text("La URL de tu Life Hub y el APP_PASSWORD de su .env. Se guardan en el Keychain, nunca en el código.")
            }

            if let message {
                Section {
                    Label(message, systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(isError ? .red : .green)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text(connected ? "Guardar cambios" : "Conectar")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(baseURL.isEmpty || token.isEmpty || checking)

                if connected {
                    Button("Desconectar", role: .destructive) {
                        confirmDisconnect = true
                    }
                }
            }

            Section {
                Text("Para montar tu propio servidor, las instrucciones están en el README del proyecto. Es opcional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Servidor")
        .navigationBarTitleDisplayMode(.inline)
        .alert("¿Desconectar el servidor?", isPresented: $confirmDisconnect) {
            Button("Cancelar", role: .cancel) {}
            Button("Desconectar", role: .destructive) { disconnect() }
        } message: {
            Text("La app volverá a guardar los datos solo en este iPhone. Lo que esté en el servidor no se borra.")
        }
    }

    private func connect() async {
        checking = true
        message = nil
        defer { checking = false }

        let previousURL = AppConfig.baseURL
        let previousToken = AppConfig.token

        let clean = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        AppConfig.baseURL = clean.hasPrefix("http") ? clean : "https://\(clean)"
        AppConfig.token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            // Una llamada real valida a la vez la URL y la clave.
            _ = try await API.shared.profile()
            await Me.refresh()
            connected = true
            isError = false
            message = "Conectado."
            Haptics.success()
        } catch APIError.unauthorized {
            AppConfig.baseURL = previousURL
            AppConfig.token = previousToken
            isError = true
            message = "La clave no es válida para ese servidor."
        } catch {
            AppConfig.baseURL = previousURL
            AppConfig.token = previousToken
            isError = true
            message = "No se pudo conectar. Revisa la URL."
        }
    }

    private func disconnect() {
        AppConfig.reset()
        baseURL = ""
        token = ""
        connected = false
        message = nil
        Task { await Me.refresh() }
        Haptics.warning()
    }
}
