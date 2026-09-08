import Foundation

/// App Group compartido por la app, los widgets y los App Intents.
/// Cambia esto y los .entitlements a la vez si usas otro identificador.
let appGroupID = "group.com.example.lifehub"

/// Configuración de la instancia: a qué servidor apunta la app y con qué clave.
///
/// Nada de esto va en el código. La URL y la clave se introducen en el
/// onboarding la primera vez y se guardan en Keychain, que es compartido por
/// el App Group — así los widgets y los App Intents (Atajos) las leen sin
/// depender de que la app se haya abierto.
enum AppConfig {
    /// Cambia esto si distribuyes la app con un servidor por defecto.
    /// Vacío = la app pide la URL en el onboarding.
    static let defaultBaseURL = ""

    private static let baseURLKey = "lifehub.baseURL"
    private static let tokenKey = "lifehub.token"

    /// URL del backend, sin barra final (ej. https://mihub.example.com).
    static var baseURL: String {
        get {
            let stored = Keychain.read(baseURLKey) ?? ""
            let value = stored.isEmpty ? defaultBaseURL : stored
            return value.hasSuffix("/") ? String(value.dropLast()) : value
        }
        set {
            let clean = newValue.hasSuffix("/") ? String(newValue.dropLast()) : newValue
            Keychain.write(baseURLKey, value: clean)
        }
    }

    /// Clave de la API (APP_PASSWORD del backend).
    static var token: String {
        get { Keychain.read(tokenKey) ?? "" }
        set { Keychain.write(tokenKey, value: newValue) }
    }

    /// Hay servidor y clave: la app habla con el backend.
    static var isConfigured: Bool {
        !baseURL.isEmpty && !token.isEmpty
    }

    /// Sin servidor: la app funciona sola, guardando los datos en el iPhone.
    /// Es el modo por defecto nada más instalar.
    static var isLocalMode: Bool { !isConfigured }

    /// Borra la configuración (cerrar sesión).
    static func reset() {
        Keychain.delete(baseURLKey)
        Keychain.delete(tokenKey)
    }
}
