import Foundation

/// Almacén local: la app funciona en el iPhone sin ningún servidor.
///
/// Guarda hábitos, gimnasio, comidas, peso, tareas y notas en un JSON dentro
/// del App Group (compartido con los widgets). Es el modo por defecto: montar
/// un backend es opcional, y solo hace falta para los módulos que dependen de
/// servicios externos (correo, agenda, finanzas, IA).
///
/// `APIClient` lo consulta antes de tocar la red, así que las vistas no saben
/// en qué modo están.
final class LocalStore {
    static let shared = LocalStore()

    private let queue = DispatchQueue(label: "lifehub.localstore")
    private var data = StoreData()

    private var fileURL: URL {
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("lifehub-local.json")
    }

    private init() {
        load()
    }

    // ── Persistencia ────────────────────────────────────────────────────

    private func load() {
        guard let raw = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: raw)
        else {
            data = StoreData()
            seedIfEmpty()
            return
        }
        data = decoded
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }

    /// Contenido inicial para que la app no arranque vacía: el catálogo de
    /// ejercicios y unos hábitos de ejemplo, todos borrables.
    private func seedIfEmpty() {
        var changed = false

        if data.exercises.isEmpty {
            data.exercises = ExerciseCatalog.all.enumerated().map { index, item in
                LocalExercise(id: index + 1, name: item.0, muscle: item.1, equipment: item.2)
            }
            changed = true
        }

        if data.habits.isEmpty {
            let examples: [(String, String, [String])] = [
                ("Agua", "water", ["09:00", "12:00", "15:00", "18:00", "21:00"]),
                ("Desayuno", "diet", ["08:00"]),
                ("Comida", "diet", ["14:00"]),
                ("Cena", "diet", ["21:00"]),
                ("Entrenar", "exercise", ["18:00"]),
                ("Rutina de dormir", "sleep", ["23:00"]),
            ]
            data.habits = examples.enumerated().map { index, item in
                LocalHabit(id: index + 1, name: item.0, category: item.1,
                           scheduleType: "daily_times", times: item.2)
            }
            changed = true
        }

        if changed { persist() }
    }

    /// Acceso serializado al estado.
    func read<T>(_ body: (StoreData) -> T) -> T {
        queue.sync { body(data) }
    }

    @discardableResult
    func write<T>(_ body: (inout StoreData) -> T) -> T {
        queue.sync {
            let result = body(&data)
            persist()
            return result
        }
    }

    /// Borra todo lo local (al conectar un servidor, o desde Ajustes).
    func reset() {
        write { store in
            store = StoreData()
        }
        seedIfEmpty()
    }

    /// Siguiente id libre de una colección.
    static func nextID<T: LocalIdentifiable>(_ items: [T]) -> Int {
        (items.map(\.id).max() ?? 0) + 1
    }
}

// ── Modelo persistido ───────────────────────────────────────────────────────

protocol LocalIdentifiable {
    var id: Int { get }
}

struct StoreData: Codable {
    var profile = LocalProfile()
    var habits: [LocalHabit] = []
    var habitLogs: [LocalHabitLog] = []
    var exercises: [LocalExercise] = []
    var routines: [LocalRoutine] = []
    var routineDays: [Int: Int] = [:]        // weekday -> routine id
    var workouts: [LocalWorkout] = []
    var sets: [LocalSet] = []
    var bodyWeights: [LocalBodyWeight] = []
    var measures: [LocalMeasure] = []
    var foodLogs: [LocalFood] = []
    var tasks: [LocalTask] = []
    var notes: [LocalNote] = []
    var shopping: [LocalShopping] = []
}

struct LocalProfile: Codable {
    var name: String?
    var heightCm: Double = 175
    var birthDate: Date?
    var sex = "m"
    var activityFactor: Double = 1.5
    var goal = "Mantener"
    var goalKcalDelta: Double = 0
    var proteinPerKg: Double = 1.8
    var bodyFatPct: Double?
    var fallbackWeight: Double = 70
    var barWeight: Double = 20
    var plates: [Double] = [20, 10, 5, 2.5, 1.25]
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var configured = false
}

struct LocalHabit: Codable, LocalIdentifiable {
    var id: Int
    var name: String
    var category: String
    var scheduleType: String
    var times: [String] = []
    var intervalDays: Int?
    var weekdays: [Int] = []
    var active = true
}

struct LocalHabitLog: Codable, LocalIdentifiable {
    var id: Int
    var habitId: Int
    var doneAt: Date
}

struct LocalExercise: Codable, LocalIdentifiable {
    var id: Int
    var name: String
    var muscle: String
    var equipment: String
    var custom = false
}

struct LocalRoutine: Codable, LocalIdentifiable {
    var id: Int
    var name: String
    var position = 0
    var items: [LocalRoutineItem] = []
}

struct LocalRoutineItem: Codable {
    var exerciseId: Int
    var position: Int
    var sets: Int
    var repsMin: Int
    var repsMax: Int
}

struct LocalWorkout: Codable, LocalIdentifiable {
    var id: Int
    var routineId: Int?
    var startedAt: Date
    var finishedAt: Date?
}

struct LocalSet: Codable, LocalIdentifiable {
    var id: Int
    var workoutId: Int
    var exerciseId: Int
    var setNumber: Int
    var weight: Double
    var reps: Int
    var createdAt: Date
}

struct LocalBodyWeight: Codable, LocalIdentifiable {
    var id: Int
    var at: Date
    var weight: Double
}

struct LocalMeasure: Codable, LocalIdentifiable {
    var id: Int
    var at: Date
    var site: String
    var value: Double
}

struct LocalFood: Codable, LocalIdentifiable {
    var id: Int
    var at: Date
    var name: String
    var kcal: Int
    var protein: Double
}

struct LocalTask: Codable, LocalIdentifiable {
    var id: Int
    var text: String
    var done = false
    var due: Date?
    var createdAt: Date
    var doneAt: Date?
}

struct LocalNote: Codable, LocalIdentifiable {
    var id: Int
    var text: String
    var createdAt: Date
}

struct LocalShopping: Codable, LocalIdentifiable {
    var id: Int
    var text: String
    var done = false
}
