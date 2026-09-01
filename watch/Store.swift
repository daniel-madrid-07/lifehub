import Combine
import Foundation

// Estado de la app: la rutina de hoy y sus ejercicios.
@MainActor
final class Store: ObservableObject {
    @Published var routine: String?
    @Published var exercises: [DeviceExercise] = []
    @Published var loading = false
    @Published var error: String?

    let workout = WorkoutSession()

    func loadRoutine(id: Int) async {
        loading = true
        error = nil
        do {
            let t = try await API.routine(id: id)
            routine = t.routine
            exercises = t.exercises
        } catch {
            self.error = "No se pudo cargar la rutina."
        }
        loading = false
    }

    func loadToday() async {
        loading = true
        error = nil
        do {
            let t = try await API.today()
            routine = t.routine
            exercises = t.exercises
        } catch {
            self.error = "No se pudo cargar. Revisa el WiFi y el token."
        }
        loading = false
    }
}
