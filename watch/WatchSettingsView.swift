import SwiftUI
import WatchConnectivity

/// Configuración del reloj: a qué servidor apunta y con qué credenciales.
///
/// Escribir una URL en el Watch es incómodo, así que lo normal es enviarla
/// desde el iPhone (`WatchConfigSender`). Esta pantalla es el respaldo, y
/// además deja ver si el reloj ya está configurado.
struct WatchSettingsView: View {
    @State private var baseURL = Config.baseURL
    @State private var deviceToken = Config.deviceToken
    @State private var appPassword = Config.appPassword
    @State private var status: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Servidor")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)

                TextField("https://…", text: $baseURL)
                    .textContentType(.URL)

                Text("Token del reloj")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                TextField("GYM_DEVICE_TOKEN", text: $deviceToken)

                Text("Clave de la app")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                TextField("APP_PASSWORD", text: $appPassword)

                Button("Guardar") {
                    Config.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    Config.deviceToken = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    Config.appPassword = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                    status = Config.isConfigured ? "Guardado" : "Falta la URL o la clave"
                }
                .tint(Theme.accent)

                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }

                Text("Más cómodo: envíalo desde el iPhone en Ajustes → Reloj.")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Ajustes")
        .containerBackground(Theme.bg, for: .navigation)
    }
}

/// Recibe la configuración que manda el iPhone por WatchConnectivity.
final class WatchConfigReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConfigReceiver()

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Config.apply(from: context)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Config.apply(from: message)
    }
}
