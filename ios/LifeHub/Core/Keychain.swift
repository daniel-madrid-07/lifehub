import Foundation
import Security

/// Wrapper mínimo de Keychain para la configuración de la instancia.
///
/// Usa un access group para que la app, los widgets y los App Intents lean
/// los mismos valores. Cambia `accessGroup` por el tuyo (el prefijo es tu
/// Team ID de Apple Developer) o ponlo a nil para no compartir.
enum Keychain {
    /// nil = sin compartir entre targets (solo la app principal).
    /// Formato: "<TEAM_ID>.<bundle id compartido>"
    static let accessGroup: String? = nil

    private static func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, value: String) {
        delete(key)
        guard !value.isEmpty else { return }
        var query = baseQuery(key)
        query[kSecValueData as String] = value.data(using: .utf8)!
        // Accesible tras el primer desbloqueo: los widgets refrescan en background.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
