import Foundation

/// Configuración del reloj. Los valores no van en el código: se introducen una
/// vez desde el iPhone (Ajustes → Reloj) y se guardan en el almacenamiento
/// local del Watch.
///
/// - `baseURL`: la URL de tu backend, ej. https://mihub.example.com
/// - `deviceToken`: GYM_DEVICE_TOKEN del .env del servidor. Solo vale para
///   /api/gym/device/*, así que si se filtra el daño es limitado.
/// - `appPassword`: APP_PASSWORD del .env. Necesaria para marcar hábitos y
///   comidas, que van por los endpoints normales /api/* con Bearer.
enum Config {
    private static let ud = UserDefaults.standard

    static var baseURL: String {
        get {
            let v = ud.string(forKey: "cfg_base_url") ?? ""
            return v.hasSuffix("/") ? String(v.dropLast()) : v
        }
        set { ud.set(newValue, forKey: "cfg_base_url") }
    }

    static var deviceToken: String {
        get { ud.string(forKey: "cfg_device_token") ?? "" }
        set { ud.set(newValue, forKey: "cfg_device_token") }
    }

    static var appPassword: String {
        get { ud.string(forKey: "cfg_app_password") ?? "" }
        set { ud.set(newValue, forKey: "cfg_app_password") }
    }

    /// Hay servidor y credenciales: el reloj puede sincronizar.
    static var isConfigured: Bool {
        !baseURL.isEmpty && !appPassword.isEmpty
    }

    /// Aplica la configuración que llega del iPhone por WatchConnectivity.
    static func apply(from payload: [String: Any]) {
        if let v = payload["baseURL"] as? String, !v.isEmpty { baseURL = v }
        if let v = payload["deviceToken"] as? String, !v.isEmpty { deviceToken = v }
        if let v = payload["appPassword"] as? String, !v.isEmpty { appPassword = v }
    }
}
