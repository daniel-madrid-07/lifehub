import SwiftUI

/// Envía la configuración al Apple Watch para no tener que escribirla ahí.
struct WatchPairingView: View {
    @State private var deviceToken = ""
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Servidor", value: AppConfig.baseURL.isEmpty ? "—" : AppConfig.baseURL)
            } header: {
                Text("Se enviará")
            } footer: {
                Text("El reloj recibirá esta URL y la clave de la app, que ya tienes configuradas.")
            }

            Section {
                TextField("GYM_DEVICE_TOKEN", text: $deviceToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Token del reloj")
            } footer: {
                Text("El GYM_DEVICE_TOKEN del .env del servidor. Solo vale para los endpoints del reloj, así que si se filtra el alcance es limitado. Puedes dejarlo vacío si no usas el contador de repeticiones.")
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button("Enviar al reloj") {
                    if WatchConfigSender.shared.send(deviceToken: deviceToken) {
                        sent = true
                        error = nil
                    } else {
                        error = "No hay ningún Apple Watch emparejado disponible."
                    }
                }
                if sent {
                    Label("Enviado", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Reloj")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { WatchConfigSender.shared.start() }
    }
}
