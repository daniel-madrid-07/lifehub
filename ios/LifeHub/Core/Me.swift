import Foundation

/// Datos personales de Daniel — la app es SOLO suya, nada configurable.
/// Espejo de frontend/src/me.ts.
enum Me {
    static let heightCm = 180.0
    static let birthDate = DateComponents(calendar: .current, year: 2007, month: 3, day: 6).date!
    /// Sedentario fuera del gym + 5 días de pesas M·X·J·V·D
    static let activityFactor = 1.5
    /// Objetivo actual: volumen (TDEE +300). Definición sería −400.
    static let goal = "Volumen"
    static let goalKcalDelta = 300.0
    static let bodyFatPct: Double? = 15
    /// Peso de respaldo hasta que haya registros en la báscula
    static let fallbackWeight = 70.0
    /// Su gym: barra olímpica de 20 kg y discos por lado (kg)
    static let barWeight = 20.0
    static let plates: [Double] = [20, 10, 5, 2.5, 1.25]

    static var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0
    }

    /// Mifflin-St Jeor (hombre)
    static func bmr(weight: Double) -> Double {
        10 * weight + 6.25 * heightCm - 5 * Double(age) + 5
    }

    static func tdee(weight: Double) -> Double { bmr(weight: weight) * activityFactor }

    /// Kcal diarias según su objetivo actual
    static func kcalTarget(weight: Double) -> Int { Int((tdee(weight: weight) + goalKcalDelta).rounded()) }

    /// Proteína diaria: 2 g/kg (entrena al fallo, construyendo músculo)
    static func proteinTarget(weight: Double) -> Double { (weight * 2).rounded() }

    /// Calculadora de discos: qué poner por lado para un peso total con barra.
    static func platesPerSide(total: Double) -> (plates: [Double], leftover: Double) {
        var perSide = (total - barWeight) / 2
        guard perSide > 0 else { return ([], 0) }
        var out: [Double] = []
        for plate in plates {
            while perSide >= plate - 1e-9 {
                out.append(plate)
                perSide -= plate
            }
        }
        return (out, (perSide * 100).rounded() / 100)
    }
}
