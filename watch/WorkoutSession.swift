import HealthKit

// Sesión de entrenamiento de HealthKit. Sirve para que el reloj NO se duerma
// durante la serie (runtime extendido) y los sensores sigan activos. No
// registramos el entreno en Salud como tal; solo lo usamos para mantener vivo
// el conteo mientras haces la serie.
final class WorkoutSession: NSObject, HKWorkoutSessionDelegate {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types: Set<HKSampleType> = [HKQuantityType.workoutType()]
        try? await healthStore.requestAuthorization(toShare: types, read: [])
    }

    func start() {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            s.delegate = self
            s.startActivity(with: Date())
            session = s
        } catch {
            // sin sesión: el conteo sigue funcionando mientras la pantalla esté
            // encendida; solo perdemos el runtime extendido
        }
    }

    func end() {
        session?.end()
        session = nil
    }

    // Delegados obligatorios (no necesitamos hacer nada en ellos)
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState,
                        from: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {}
}
