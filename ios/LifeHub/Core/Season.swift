import Foundation

/// Temporada del plan de gym. En verano (jun–sep) se usa el plan de verano
/// (Front Day / Back Day); el resto del año, el plan normal.
enum Season {
    /// Nombres de las rutinas del plan de verano (el backend desplegado no manda
    /// el campo `group`, así que distinguimos por nombre).
    static let summerNames: Set<String> = ["Front Day", "Back Day"]

    static var isSummer: Bool {
        (6...9).contains(Calendar.current.component(.month, from: .now))
    }

    /// Filtra una lista de rutinas dejando solo las de la temporada actual.
    static func filter<T>(_ routines: [T], name: (T) -> String) -> [T] {
        routines.filter { summerNames.contains(name($0)) == isSummer }
    }

    /// Rutina que toca hoy en verano (Front Day martes, Back Day viernes).
    static var todaySummerRoutine: String? {
        guard isSummer else { return nil }
        switch Calendar.current.component(.weekday, from: .now) {
        case 3: return "Front Day"   // martes
        case 6: return "Back Day"    // viernes
        default: return nil          // descanso
        }
    }
}
