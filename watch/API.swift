import Foundation

// Llamadas a los endpoints del reloj de Life Hub. Autenticadas con el token de
// dispositivo (cabecera X-Device-Token).
enum API {
    private static func request(_ path: String, method: String = "GET",
                                body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: Config.baseURL + path)!)
        req.httpMethod = method
        req.setValue(Config.deviceToken, forHTTPHeaderField: "X-Device-Token")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 20
        return req
    }

    static func today() async throws -> TodayResponse {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/today"))
        return try JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func routines() async throws -> [DeviceRoutine] {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/routines"))
        return try JSONDecoder().decode([DeviceRoutine].self, from: data)
    }

    static func routine(id: Int) async throws -> TodayResponse {
        let (data, _) = try await URLSession.shared.data(for: request("/api/gym/device/routine/\(id)"))
        return try JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func logSet(exerciseId: Int, weight: Double, reps: Int) async throws -> SetResult {
        let req = request("/api/gym/device/set", method: "POST",
                          body: ["exercise_id": exerciseId, "weight": weight, "reps": reps])
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(SetResult.self, from: data)
    }

    // ── Hábitos (Bearer: los endpoints normales no usan device token) ────────
    private static func bearerRequest(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: URL(string: Config.baseURL + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(Config.appPassword)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        return req
    }

    static func habitsToday() async throws -> [WatchHabit] {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/today"))
        return try JSONDecoder().decode([WatchHabit].self, from: data)
    }

    static func markDone(_ id: Int) async throws -> WatchHabit {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/habits/\(id)/done", method: "POST"))
        return try JSONDecoder().decode(WatchHabit.self, from: data)
    }

    static func undoDone(_ id: Int) async throws -> WatchHabit {
        let (data, _) = try await URLSession.shared.data(for: bearerRequest("/api/habits/\(id)/undo", method: "POST"))
        return try JSONDecoder().decode(WatchHabit.self, from: data)
    }

    // ── Finalizar el entreno (mismo backend que el móvil, sin jerarquía) ─────
    // Las series se registran con /gym/device/set (crea el entreno activo). Al
    // terminar en el reloj se FINALIZA ese entreno para que salga en "últimos
    // entrenos" y sus pesos cuenten para las recomendaciones de la semana.
    private struct ActiveWorkout: Codable { let id: Int }

    @discardableResult
    static func finishActiveWorkout() async -> Bool {
        guard let (data, _) = try? await URLSession.shared.data(for: bearerRequest("/api/gym/workouts/active")),
              let w = try? JSONDecoder().decode(ActiveWorkout.self, from: data)
        else { return false }   // no hay entreno activo (o null → falla el decode)
        _ = try? await URLSession.shared.data(for: bearerRequest("/api/gym/workouts/\(w.id)/finish", method: "POST"))
        return true
    }
}
