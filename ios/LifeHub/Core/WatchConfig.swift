import Foundation
import WatchConnectivity

/// Manda la configuración de la instancia al Apple Watch.
///
/// El reloj necesita la URL y las credenciales, y escribirlas ahí es un
/// suplicio: se envían desde aquí por WatchConnectivity.
final class WatchConfigSender: NSObject, WCSessionDelegate {
    static let shared = WatchConfigSender()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Envía la configuración actual. `deviceToken` es el GYM_DEVICE_TOKEN del
    /// servidor: solo sirve para los endpoints del reloj.
    @discardableResult
    func send(deviceToken: String) -> Bool {
        guard let session, session.activationState == .activated else { return false }
        let payload: [String: Any] = [
            "baseURL": AppConfig.baseURL,
            "appPassword": AppConfig.token,
            "deviceToken": deviceToken,
        ]
        // El contexto sobrevive a que el reloj esté apagado; el mensaje es
        // instantáneo si está a mano. Se intentan los dos.
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        return true
    }

    var isPaired: Bool {
        session?.isPaired ?? false
    }

    // ── WCSessionDelegate ───────────────────────────────────────────────

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()  // reactivar tras cambiar de reloj
    }
}
