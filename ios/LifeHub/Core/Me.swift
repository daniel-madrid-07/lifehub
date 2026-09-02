import Foundation

/// Perfil del usuario, servido por el backend (`/api/profile`).
///
/// Antes esto era una lista de constantes personales. Ahora los valores y las
/// fórmulas viven en el servidor y aquí solo se cachean: así la web, la app y
/// el reloj no se desincronizan nunca.
///
/// La caché se guarda en el App Group para que los widgets la lean sin
/// esperar a una petición de red.
struct ProfileDTO: Codable {
    var name: String?
    var height_cm: Double
    var birth_date: String?
    var age: Int?
    var sex: String
    var activity_factor: Double
    var goal: String
    var goal_kcal_delta: Double
    var protein_per_kg: Double
    var body_fat_pct: Double?
    var fallback_weight: Double
    var bar_weight: Double
    var plates: [Double]
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var weight: Double
    var bmr: Double
    var tdee: Double
    var kcal_target: Int
    var protein_target: Double
    var configured: Bool

    /// Perfil neutro mientras no hay nada cacheado.
    static let placeholder = ProfileDTO(
        name: nil, height_cm: 175, birth_date: nil, age: nil, sex: "m",
        activity_factor: 1.5, goal: "Mantener", goal_kcal_delta: 0,
        protein_per_kg: 1.8, body_fat_pct: nil, fallback_weight: 70,
        bar_weight: 20, plates: [20, 10, 5, 2.5, 1.25],
        latitude: nil, longitude: nil, city: nil,
        weight: 70, bmr: 0, tdee: 0, kcal_target: 0, protein_target: 0,
        configured: false
    )
}

enum Me {
    private static let cacheKey = "lifehub.profile"

    /// Caché compartida con los widgets vía App Group.
    private static var store: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static var cached: ProfileDTO = {
        guard let data = store.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(ProfileDTO.self, from: data)
        else { return .placeholder }
        return decoded
    }()

    /// Perfil actual (el de respaldo hasta que se refresca).
    static var current: ProfileDTO { cached }

    /// Pide el perfil al backend y lo cachea.
    @discardableResult
    static func refresh() async -> ProfileDTO {
        guard let fresh = try? await API.shared.profile() else { return cached }
        cached = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            store.set(data, forKey: cacheKey)
        }
        return fresh
    }

    /// Guarda cambios del perfil y actualiza la caché.
    @discardableResult
    static func save(_ patch: [String: JSONValue]) async throws -> ProfileDTO {
        let updated = try await API.shared.updateProfile(patch)
        cached = updated
        if let data = try? JSONEncoder().encode(updated) {
            store.set(data, forKey: cacheKey)
        }
        return updated
    }

    // ── Accesos usados por las vistas ───────────────────────────────────

    static var heightCm: Double { cached.height_cm }
    static var age: Int { cached.age ?? 0 }
    static var goal: String { cached.goal }
    static var goalKcalDelta: Double { cached.goal_kcal_delta }
    static var bodyFatPct: Double? { cached.body_fat_pct }
    static var fallbackWeight: Double { cached.fallback_weight }
    static var barWeight: Double { cached.bar_weight }
    static var plates: [Double] { cached.plates }
    static var isConfigured: Bool { cached.configured }

    /// Objetivos: los calcula el servidor con el último peso de la báscula.
    /// El parámetro se mantiene por compatibilidad con las vistas.
    static func kcalTarget(weight: Double = 0) -> Int { cached.kcal_target }
    static func proteinTarget(weight: Double = 0) -> Double { cached.protein_target }
    static func bmr(weight: Double = 0) -> Double { cached.bmr }
    static func tdee(weight: Double = 0) -> Double { cached.tdee }

    /// Calculadora de discos: qué poner por lado para un peso total con barra.
    /// En local porque se usa en cada serie mientras entrenas.
    static func platesPerSide(total: Double) -> (plates: [Double], leftover: Double) {
        var perSide = (total - cached.bar_weight) / 2
        guard perSide > 0 else { return ([], 0) }
        var out: [Double] = []
        for plate in cached.plates.sorted(by: >) {
            while perSide >= plate - 1e-9 {
                out.append(plate)
                perSide -= plate
            }
        }
        return (out, (perSide * 100).rounded() / 100)
    }
}
