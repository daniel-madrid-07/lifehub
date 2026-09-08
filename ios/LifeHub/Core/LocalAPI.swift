import Foundation

/// Resuelve las peticiones de la app contra `LocalStore`, sin red.
///
/// Habla el mismo JSON que el backend, así que `APIClient` puede decodificar
/// la respuesta con los mismos modelos y las vistas no se enteran de en qué
/// modo están.
///
/// Los módulos que dependen de servicios externos (correo, agenda, finanzas,
/// estudios, IA) no se pueden resolver en local: devuelven
/// `{"status":"error"}`, que es justo lo que esas vistas ya saben mostrar.
enum LocalAPI {

    /// Devuelve el JSON de una petición, o nil si esta ruta necesita servidor.
    static func handle(path: String, method: String, body: Data?) -> Data? {
        // Query fuera: se procesa aparte donde hace falta.
        let route = path.split(separator: "?").first.map(String.init) ?? path
        let query = queryItems(path)
        let parts = route.split(separator: "/").map(String.init)

        switch (method, parts.first) {
        case ("GET", "today"):        return json(todayHabits())
        case ("GET", "habits"):       return json(allHabits())
        case ("POST", "habits") where parts.count == 1:
            return json(createHabit(body))
        case ("PATCH", "habits") where parts.count == 2:
            return json(updateHabit(id: Int(parts[1]) ?? 0, body: body))
        case ("DELETE", "habits") where parts.count == 2:
            return deleteHabit(id: Int(parts[1]) ?? 0)
        case ("POST", "habits") where parts.count == 3 && parts[2] == "done":
            return json(markDone(id: Int(parts[1]) ?? 0))
        case ("POST", "habits") where parts.count == 3 && parts[2] == "undo":
            return json(undoDone(id: Int(parts[1]) ?? 0))
        case ("GET", "habits") where parts.count == 3 && parts[2] == "history":
            return json(history(id: Int(parts[1]) ?? 0, days: Int(query["days"] ?? "") ?? 28))

        case ("GET", "profile"):      return json(profileDict())
        case ("PATCH", "profile"):    return json(updateProfile(body))

        case ("GET", "gym"):          return gymGet(parts, query)
        case ("POST", "gym"):         return gymPost(parts, body)
        case ("PATCH", "gym"):        return gymPatch(parts, body)
        case ("DELETE", "gym"):       return gymDelete(parts)

        case ("GET", "food"):         return json(foodDay())
        case ("POST", "food") where parts.count == 1:
            return json(addFood(body))
        case ("DELETE", "food") where parts.count == 2:
            return deleteFood(id: Int(parts[1]) ?? 0)

        case ("GET", "tasks"):        return json(allTasks())
        case ("POST", "tasks"):       return json(createTask(body))
        case ("PATCH", "tasks") where parts.count == 2:
            return json(updateTask(id: Int(parts[1]) ?? 0, body: body))
        case ("DELETE", "tasks") where parts.count == 2:
            return deleteTask(id: Int(parts[1]) ?? 0)

        case ("GET", "notes"):        return json(allNotes())
        case ("POST", "notes"):       return json(createNote(body))
        case ("DELETE", "notes") where parts.count == 2:
            return deleteNote(id: Int(parts[1]) ?? 0)

        case ("GET", "routine-templates") where parts.count == 1:
            return json(RoutineTemplates.list)
        case ("POST", "routine-templates") where parts.count == 3 && parts[2] == "apply":
            return json(applyTemplate(parts[1], sets: Int(query["sets"] ?? "")))

        // Módulos que necesitan servicios externos: sin servidor no hay datos.
        case (_, "mail"), (_, "calendar"), (_, "studies"), (_, "finance"),
             (_, "ai"), (_, "claude"), (_, "auth"), (_, "health"), (_, "wardrobe"),
             (_, "diet"), (_, "push"):
            return json(["status": "error", "detail": "Necesita un servidor conectado"])

        default:
            return nil
        }
    }

    // ── Utilidades ──────────────────────────────────────────────────────

    private static func queryItems(_ path: String) -> [String: String] {
        guard let q = path.split(separator: "?").dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }

    private static func json(_ value: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: value)
    }

    private static func dict(_ body: Data?) -> [String: Any] {
        guard let body,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }
        return iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    private static var ok: Data? { json(["status": "ok"]) }

    // ── Hábitos ─────────────────────────────────────────────────────────

    /// Un hábito toca hoy según su tipo de programación.
    private static func dueToday(_ habit: LocalHabit, logs: [LocalHabitLog]) -> Bool {
        let calendar = Calendar.current
        switch habit.scheduleType {
        case "daily_times":
            return true
        case "weekdays":
            // weekday de Calendar: domingo=1; el backend usa lunes=0.
            let raw = calendar.component(.weekday, from: .now)
            return habit.weekdays.contains((raw + 5) % 7)
        case "interval_days":
            guard let interval = habit.intervalDays, interval > 0 else { return true }
            let last = logs.filter { $0.habitId == habit.id }.map(\.doneAt).max()
            guard let last else { return true }
            let days = calendar.dateComponents([.day], from: last, to: .now).day ?? 0
            return days >= interval
        default:
            return true
        }
    }

    private static func doneToday(_ habit: LocalHabit, logs: [LocalHabitLog]) -> Int {
        logs.filter {
            $0.habitId == habit.id && Calendar.current.isDateInToday($0.doneAt)
        }.count
    }

    /// Racha de días consecutivos marcando el hábito.
    private static func streak(_ habit: LocalHabit, logs: [LocalHabitLog]) -> Int {
        let calendar = Calendar.current
        let days = Set(logs.filter { $0.habitId == habit.id }
            .map { calendar.startOfDay(for: $0.doneAt) })
        guard !days.isEmpty else { return 0 }

        var count = 0
        var cursor = calendar.startOfDay(for: .now)
        // Si hoy aún no está marcado, la racha puede venir de ayer.
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    private static func habitDict(_ habit: LocalHabit, logs: [LocalHabitLog]) -> [String: Any] {
        let done = doneToday(habit, logs: logs)
        let total = habit.scheduleType == "daily_times" ? max(habit.times.count, 1) : 1
        var schedule: Any = habit.times
        if habit.scheduleType == "interval_days" { schedule = habit.intervalDays ?? 1 }
        if habit.scheduleType == "weekdays" { schedule = habit.weekdays }

        return [
            "id": habit.id,
            "name": habit.name,
            "category": habit.category,
            "schedule_type": habit.scheduleType,
            "schedule": schedule,
            "active": habit.active,
            "due_today": dueToday(habit, logs: logs),
            "done_today": done,
            "target_today": total,
            "next_time": habit.times.first as Any,
            "streak": streak(habit, logs: logs),
        ]
    }

    private static func allHabits() -> [[String: Any]] {
        LocalStore.shared.read { store in
            store.habits.map { habitDict($0, logs: store.habitLogs) }
        }
    }

    private static func todayHabits() -> [[String: Any]] {
        LocalStore.shared.read { store in
            store.habits
                .filter(\.active)
                .map { habitDict($0, logs: store.habitLogs) }
                .sorted {
                    let a = ($0["due_today"] as? Bool) == true
                    let b = ($1["due_today"] as? Bool) == true
                    if a != b { return a }
                    return ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "")
                }
        }
    }

    private static func habitFrom(_ payload: [String: Any], id: Int) -> LocalHabit {
        var habit = LocalHabit(
            id: id,
            name: payload["name"] as? String ?? "Sin nombre",
            category: payload["category"] as? String ?? "otro",
            scheduleType: payload["schedule_type"] as? String ?? "daily_times"
        )
        switch habit.scheduleType {
        case "interval_days": habit.intervalDays = payload["schedule"] as? Int ?? 1
        case "weekdays":      habit.weekdays = payload["schedule"] as? [Int] ?? []
        default:              habit.times = payload["schedule"] as? [String] ?? []
        }
        return habit
    }

    private static func createHabit(_ body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store in
            let habit = habitFrom(payload, id: LocalStore.nextID(store.habits))
            store.habits.append(habit)
            return habitDict(habit, logs: store.habitLogs)
        }
    }

    private static func updateHabit(id: Int, body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store in
            guard let index = store.habits.firstIndex(where: { $0.id == id }) else { return [:] }
            if let name = payload["name"] as? String { store.habits[index].name = name }
            if let active = payload["active"] as? Bool { store.habits[index].active = active }
            if let category = payload["category"] as? String { store.habits[index].category = category }
            if let type = payload["schedule_type"] as? String {
                store.habits[index].scheduleType = type
            }
            if payload["schedule"] != nil {
                let updated = habitFrom(payload, id: id)
                store.habits[index].times = updated.times
                store.habits[index].weekdays = updated.weekdays
                store.habits[index].intervalDays = updated.intervalDays
            }
            return habitDict(store.habits[index], logs: store.habitLogs)
        }
    }

    private static func deleteHabit(id: Int) -> Data? {
        LocalStore.shared.write { store in
            store.habits.removeAll { $0.id == id }
            store.habitLogs.removeAll { $0.habitId == id }
        }
        return ok
    }

    private static func markDone(id: Int) -> [String: Any] {
        LocalStore.shared.write { store in
            let log = LocalHabitLog(id: LocalStore.nextID(store.habitLogs), habitId: id, doneAt: .now)
            store.habitLogs.append(log)
            guard let habit = store.habits.first(where: { $0.id == id }) else { return [:] }
            return habitDict(habit, logs: store.habitLogs)
        }
    }

    private static func undoDone(id: Int) -> [String: Any] {
        LocalStore.shared.write { store in
            // Quita la marca más reciente de hoy.
            if let index = store.habitLogs.lastIndex(where: {
                $0.habitId == id && Calendar.current.isDateInToday($0.doneAt)
            }) {
                store.habitLogs.remove(at: index)
            }
            guard let habit = store.habits.first(where: { $0.id == id }) else { return [:] }
            return habitDict(habit, logs: store.habitLogs)
        }
    }

    private static func history(id: Int, days: Int) -> [[String: Any]] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return LocalStore.shared.read { store in
            store.habitLogs
                .filter { $0.habitId == id && $0.doneAt >= since }
                .sorted { $0.doneAt > $1.doneAt }
                .map { ["id": $0.id, "habit_id": $0.habitId, "done_at": iso.string(from: $0.doneAt)] }
        }
    }

    // ── Perfil ──────────────────────────────────────────────────────────

    private static func age(_ profile: LocalProfile) -> Int? {
        guard let birth = profile.birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birth, to: .now).year
    }

    private static func latestWeight(_ store: StoreData) -> Double {
        store.bodyWeights.sorted { $0.at > $1.at }.first?.weight ?? store.profile.fallbackWeight
    }

    private static func bmr(_ profile: LocalProfile, weight: Double) -> Double {
        let years = Double(age(profile) ?? 25)
        let base = 10 * weight + 6.25 * profile.heightCm - 5 * years
        return base + (profile.sex == "m" ? 5 : -161)
    }

    private static func profileDict() -> [String: Any] {
        LocalStore.shared.read { store in
            let p = store.profile
            let weight = latestWeight(store)
            let basal = bmr(p, weight: weight)
            let tdee = basal * p.activityFactor
            return [
                "name": p.name as Any,
                "height_cm": p.heightCm,
                "birth_date": p.birthDate.map { iso.string(from: $0) } as Any,
                "age": age(p) as Any,
                "sex": p.sex,
                "activity_factor": p.activityFactor,
                "goal": p.goal,
                "goal_kcal_delta": p.goalKcalDelta,
                "protein_per_kg": p.proteinPerKg,
                "body_fat_pct": p.bodyFatPct as Any,
                "fallback_weight": p.fallbackWeight,
                "bar_weight": p.barWeight,
                "plates": p.plates,
                "latitude": p.latitude as Any,
                "longitude": p.longitude as Any,
                "city": p.city as Any,
                "weight": weight,
                "bmr": basal.rounded(),
                "tdee": tdee.rounded(),
                "kcal_target": Int((tdee + p.goalKcalDelta).rounded()),
                "protein_target": (weight * p.proteinPerKg).rounded(),
                "configured": p.configured,
            ]
        }
    }

    /// Presets por objetivo: (delta kcal, proteína g/kg).
    private static let goalPresets: [String: (Double, Double)] = [
        "Volumen": (300, 2.0),
        "Definicion": (-400, 2.2),
        "Mantener": (0, 1.8),
    ]

    private static func updateProfile(_ body: Data?) -> [String: Any] {
        let payload = dict(body)
        LocalStore.shared.write { store in
            var p = store.profile
            if let v = payload["name"] as? String { p.name = v }
            if let v = payload["height_cm"] as? Double { p.heightCm = v }
            if let v = date(payload["birth_date"]) { p.birthDate = v }
            if let v = payload["sex"] as? String { p.sex = v }
            if let v = payload["activity_factor"] as? Double { p.activityFactor = v }
            if let v = payload["goal"] as? String {
                p.goal = v
                if let preset = goalPresets[v] {
                    if payload["goal_kcal_delta"] == nil { p.goalKcalDelta = preset.0 }
                    if payload["protein_per_kg"] == nil { p.proteinPerKg = preset.1 }
                }
            }
            if let v = payload["goal_kcal_delta"] as? Double { p.goalKcalDelta = v }
            if let v = payload["protein_per_kg"] as? Double { p.proteinPerKg = v }
            if let v = payload["body_fat_pct"] as? Double { p.bodyFatPct = v }
            if let v = payload["fallback_weight"] as? Double { p.fallbackWeight = v }
            if let v = payload["bar_weight"] as? Double { p.barWeight = v }
            if let v = payload["plates"] as? [Double] { p.plates = v }
            if let v = payload["latitude"] as? Double { p.latitude = v }
            if let v = payload["longitude"] as? Double { p.longitude = v }
            if let v = payload["city"] as? String { p.city = v }
            if p.birthDate != nil { p.configured = true }
            store.profile = p
        }
        return profileDict()
    }

    // ── Gimnasio ────────────────────────────────────────────────────────

    private static func exerciseDict(_ e: LocalExercise) -> [String: Any] {
        ["id": e.id, "name": e.name, "muscle": e.muscle,
         "equipment": e.equipment, "custom": e.custom]
    }

    private static func routineDict(_ routine: LocalRoutine, store: StoreData) -> [String: Any] {
        let byID = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0) })
        let todayName = store.routineDays[weekdayIndex()].flatMap { id in
            store.routines.first { $0.id == id }?.name
        }
        let exercises = routine.items.sorted { $0.position < $1.position }.compactMap { item -> [String: Any]? in
            guard let e = byID[item.exerciseId] else { return nil }
            return [
                "exercise_id": e.id, "name": e.name, "muscle": e.muscle,
                "equipment": e.equipment, "sets": item.sets,
                "reps_min": item.repsMin, "reps_max": item.repsMax,
            ]
        }
        return [
            "id": routine.id,
            "name": routine.name,
            "today": routine.name == todayName,
            "exercises": exercises,
        ]
    }

    /// weekday con lunes=0, como el backend.
    private static func weekdayIndex() -> Int {
        (Calendar.current.component(.weekday, from: .now) + 5) % 7
    }

    private static func workoutDict(_ w: LocalWorkout, store: StoreData) -> [String: Any] {
        let sets = store.sets.filter { $0.workoutId == w.id }
        let volume = sets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let name = w.routineId.flatMap { id in store.routines.first { $0.id == id }?.name }
        return [
            "id": w.id,
            "routine_id": w.routineId as Any,
            "routine_name": name as Any,
            "started_at": iso.string(from: w.startedAt),
            "finished_at": w.finishedAt.map { iso.string(from: $0) } as Any,
            "volume": volume,
            "sets": sets.sorted { $0.setNumber < $1.setNumber }.map {
                ["id": $0.id, "exercise_id": $0.exerciseId, "set_number": $0.setNumber,
                 "weight": $0.weight, "reps": $0.reps]
            },
        ]
    }

    private static func gymGet(_ parts: [String], _ query: [String: String]) -> Data? {
        guard parts.count >= 2 else { return nil }
        return LocalStore.shared.read { store in
            switch parts[1] {
            case "exercises" where parts.count == 2:
                return json(store.exercises.map(exerciseDict))

            case "exercises" where parts.count == 4 && parts[3] == "recommendation":
                return json(recommendation(exerciseId: Int(parts[2]) ?? 0, store: store, query: query))

            case "routines" where parts.count == 2:
                return json(store.routines
                    .sorted { $0.position < $1.position }
                    .map { routineDict($0, store: store) })

            case "routines" where parts.count == 3:
                guard let routine = store.routines.first(where: { $0.id == Int(parts[2]) }) else {
                    return json([String: Any]())
                }
                return json(routineDict(routine, store: store))

            case "routine-days":
                var days: [String: String] = [:]
                for (weekday, routineID) in store.routineDays {
                    if let name = store.routines.first(where: { $0.id == routineID })?.name {
                        days[String(weekday)] = name
                    }
                }
                return json(["days": days])

            case "workouts" where parts.count == 2:
                return json(store.workouts
                    .sorted { $0.startedAt > $1.startedAt }
                    .map { workoutDict($0, store: store) })

            case "workouts" where parts.count == 3 && parts[2] == "active":
                guard let active = store.workouts.first(where: { $0.finishedAt == nil }) else {
                    return json([String: Any]())
                }
                return json(workoutDict(active, store: store))

            case "workouts" where parts.count == 3:
                guard let w = store.workouts.first(where: { $0.id == Int(parts[2]) }) else {
                    return json([String: Any]())
                }
                return json(workoutDict(w, store: store))

            case "bodyweight":
                return json(store.bodyWeights.sorted { $0.at > $1.at }.map {
                    ["id": $0.id, "at": iso.string(from: $0.at), "weight": $0.weight]
                })

            case "measures":
                var grouped: [String: [[String: Any]]] = [:]
                for m in store.measures.sorted(by: { $0.at > $1.at }) {
                    grouped[m.site, default: []].append(
                        ["id": m.id, "at": iso.string(from: m.at), "value": m.value])
                }
                return json(grouped)

            case "photos":
                return json([[String: Any]]())   // las fotos necesitan servidor

            case "progress" where parts.count == 3:
                let id = Int(parts[2]) ?? 0
                let rows = store.sets.filter { $0.exerciseId == id }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { ["at": iso.string(from: $0.createdAt), "weight": $0.weight, "reps": $0.reps] }
                return json(["points": rows])

            case "stats" where parts.count == 3 && parts[2] == "weekly":
                return json(weeklyStats(store))

            default:
                return nil
            }
        }
    }

    private static func weeklyStats(_ store: StoreData) -> [String: Any] {
        let since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let recent = store.workouts.filter { $0.startedAt >= since }
        let volume = recent.reduce(0.0) { total, workout in
            total + store.sets.filter { $0.workoutId == workout.id }
                .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        }
        return ["workouts": recent.count, "volume": volume,
                "sets": store.sets.filter { set in recent.contains { $0.id == set.workoutId } }.count]
    }

    /// Doble progresión, igual que el backend: sube el peso cuando la mejor
    /// serie llega al tope de repes y la última no se cae del mínimo.
    private static func recommendation(exerciseId: Int, store: StoreData,
                                       query: [String: String]) -> [String: Any] {
        let repsMin = Int(query["reps_min"] ?? "") ?? 6
        let repsMax = Int(query["reps_max"] ?? "") ?? 8

        let lastWorkout = store.workouts
            .filter { $0.finishedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .first { workout in store.sets.contains { $0.workoutId == workout.id && $0.exerciseId == exerciseId } }

        guard let lastWorkout else {
            return ["weight": NSNull(), "reps": repsMax, "note": "Primera vez: empieza suave y anota."]
        }

        let sets = store.sets
            .filter { $0.workoutId == lastWorkout.id && $0.exerciseId == exerciseId }
            .sorted { $0.setNumber < $1.setNumber }
        guard let best = sets.max(by: { $0.weight * Double($0.reps) < $1.weight * Double($1.reps) }),
              let last = sets.last
        else {
            return ["weight": NSNull(), "reps": repsMax, "note": "Sin datos suficientes."]
        }

        let equipment = store.exercises.first { $0.id == exerciseId }?.equipment ?? "barra"
        let step = equipment == "mancuernas" ? 2.5 : 1.0

        if best.reps >= repsMax && last.reps >= repsMin {
            let next = (best.weight + step * 2)
            return ["weight": next, "reps": repsMin,
                    "note": "Subes peso: llegaste al tope de repes."]
        }
        return ["weight": best.weight, "reps": min(best.reps + 1, repsMax),
                "note": "Mismo peso, busca una repetición más."]
    }

    private static func gymPost(_ parts: [String], _ body: Data?) -> Data? {
        guard parts.count >= 2 else { return nil }
        let payload = dict(body)

        switch parts[1] {
        case "exercises":
            return json(LocalStore.shared.write { store -> [String: Any] in
                let e = LocalExercise(
                    id: LocalStore.nextID(store.exercises),
                    name: payload["name"] as? String ?? "Ejercicio",
                    muscle: payload["muscle"] as? String ?? "Otro",
                    equipment: payload["equipment"] as? String ?? "barra",
                    custom: true)
                store.exercises.append(e)
                return exerciseDict(e)
            })

        case "routines":
            return json(LocalStore.shared.write { store -> [String: Any] in
                var routine = LocalRoutine(
                    id: LocalStore.nextID(store.routines),
                    name: payload["name"] as? String ?? "Rutina",
                    position: store.routines.count)
                routine.items = routineItems(payload)
                store.routines.append(routine)
                return routineDict(routine, store: store)
            })

        case "routine-days":
            LocalStore.shared.write { store in
                let weekday = payload["weekday"] as? Int ?? 0
                if let routineID = payload["routine_id"] as? Int {
                    store.routineDays[weekday] = routineID
                } else {
                    store.routineDays.removeValue(forKey: weekday)
                }
            }
            return gymGet(["gym", "routine-days"], [:])

        case "workouts" where parts.count == 2:
            return json(LocalStore.shared.write { store -> [String: Any] in
                let workout = LocalWorkout(
                    id: LocalStore.nextID(store.workouts),
                    routineId: payload["routine_id"] as? Int,
                    startedAt: .now)
                store.workouts.append(workout)
                return workoutDict(workout, store: store)
            })

        case "workouts" where parts.count == 4 && parts[3] == "finish":
            return json(LocalStore.shared.write { store -> [String: Any] in
                guard let index = store.workouts.firstIndex(where: { $0.id == Int(parts[2]) })
                else { return [:] }
                store.workouts[index].finishedAt = .now
                return workoutDict(store.workouts[index], store: store)
            })

        case "workouts" where parts.count == 4 && parts[3] == "sets":
            return json(LocalStore.shared.write { store -> [String: Any] in
                let workoutID = Int(parts[2]) ?? 0
                let exerciseID = payload["exercise_id"] as? Int ?? 0
                let number = store.sets.filter {
                    $0.workoutId == workoutID && $0.exerciseId == exerciseID
                }.count + 1
                let set = LocalSet(
                    id: LocalStore.nextID(store.sets),
                    workoutId: workoutID,
                    exerciseId: exerciseID,
                    setNumber: number,
                    weight: payload["weight"] as? Double ?? 0,
                    reps: payload["reps"] as? Int ?? 0,
                    createdAt: .now)
                store.sets.append(set)
                return ["id": set.id, "exercise_id": set.exerciseId, "set_number": set.setNumber,
                        "weight": set.weight, "reps": set.reps]
            })

        case "bodyweight":
            return json(LocalStore.shared.write { store -> [String: Any] in
                let row = LocalBodyWeight(
                    id: LocalStore.nextID(store.bodyWeights),
                    at: .now,
                    weight: payload["weight"] as? Double ?? 0)
                store.bodyWeights.append(row)
                return ["id": row.id, "at": iso.string(from: row.at), "weight": row.weight]
            })

        case "measures":
            return json(LocalStore.shared.write { store -> [String: Any] in
                let row = LocalMeasure(
                    id: LocalStore.nextID(store.measures),
                    at: .now,
                    site: payload["site"] as? String ?? "brazo",
                    value: payload["value"] as? Double ?? 0)
                store.measures.append(row)
                return ["id": row.id, "at": iso.string(from: row.at),
                        "site": row.site, "value": row.value]
            })

        default:
            return nil
        }
    }

    private static func routineItems(_ payload: [String: Any]) -> [LocalRoutineItem] {
        let raw = payload["exercises"] as? [[String: Any]] ?? []
        return raw.enumerated().map { index, item in
            LocalRoutineItem(
                exerciseId: item["exercise_id"] as? Int ?? 0,
                position: index,
                sets: item["sets"] as? Int ?? 3,
                repsMin: item["reps_min"] as? Int ?? 6,
                repsMax: item["reps_max"] as? Int ?? 8)
        }
    }

    private static func gymPatch(_ parts: [String], _ body: Data?) -> Data? {
        guard parts.count == 3, parts[1] == "routines" else { return nil }
        let payload = dict(body)
        return json(LocalStore.shared.write { store -> [String: Any] in
            guard let index = store.routines.firstIndex(where: { $0.id == Int(parts[2]) })
            else { return [:] }
            if let name = payload["name"] as? String { store.routines[index].name = name }
            if payload["exercises"] != nil { store.routines[index].items = routineItems(payload) }
            return routineDict(store.routines[index], store: store)
        })
    }

    private static func gymDelete(_ parts: [String]) -> Data? {
        guard parts.count == 3, let id = Int(parts[2]) else { return nil }
        LocalStore.shared.write { store in
            switch parts[1] {
            case "routines":
                store.routines.removeAll { $0.id == id }
                store.routineDays = store.routineDays.filter { $0.value != id }
            case "bodyweight": store.bodyWeights.removeAll { $0.id == id }
            case "measures":   store.measures.removeAll { $0.id == id }
            case "workouts":
                store.workouts.removeAll { $0.id == id }
                store.sets.removeAll { $0.workoutId == id }
            default: break
            }
        }
        return ok
    }

    // ── Comidas ─────────────────────────────────────────────────────────

    private static func foodDay() -> [String: Any] {
        LocalStore.shared.read { store in
            let items = store.foodLogs.filter { Calendar.current.isDateInToday($0.at) }
            return [
                "items": items.map {
                    ["id": $0.id, "at": iso.string(from: $0.at), "name": $0.name,
                     "kcal": $0.kcal, "protein": $0.protein]
                },
                "total_kcal": items.reduce(0) { $0 + $1.kcal },
                "total_protein": (items.reduce(0.0) { $0 + $1.protein } * 10).rounded() / 10,
            ]
        }
    }

    private static func addFood(_ body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store -> [String: Any] in
            let row = LocalFood(
                id: LocalStore.nextID(store.foodLogs),
                at: .now,
                name: payload["name"] as? String ?? "Comida",
                kcal: payload["kcal"] as? Int ?? 0,
                protein: payload["protein"] as? Double ?? 0)
            store.foodLogs.append(row)
            return ["id": row.id, "at": iso.string(from: row.at), "name": row.name,
                    "kcal": row.kcal, "protein": row.protein]
        }
    }

    private static func deleteFood(id: Int) -> Data? {
        LocalStore.shared.write { store in store.foodLogs.removeAll { $0.id == id } }
        return ok
    }

    // ── Tareas y notas ──────────────────────────────────────────────────

    private static func taskDict(_ t: LocalTask) -> [String: Any] {
        ["id": t.id, "text": t.text, "done": t.done,
         "due": t.due.map { iso.string(from: $0) } as Any,
         "created_at": iso.string(from: t.createdAt)]
    }

    private static func allTasks() -> [[String: Any]] {
        LocalStore.shared.read { store in
            store.tasks.sorted { $0.createdAt > $1.createdAt }.map(taskDict)
        }
    }

    private static func createTask(_ body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store -> [String: Any] in
            let task = LocalTask(
                id: LocalStore.nextID(store.tasks),
                text: payload["text"] as? String ?? "",
                due: date(payload["due"]),
                createdAt: .now)
            store.tasks.append(task)
            return taskDict(task)
        }
    }

    private static func updateTask(id: Int, body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store -> [String: Any] in
            guard let index = store.tasks.firstIndex(where: { $0.id == id }) else { return [:] }
            if let text = payload["text"] as? String { store.tasks[index].text = text }
            if let done = payload["done"] as? Bool {
                store.tasks[index].done = done
                store.tasks[index].doneAt = done ? .now : nil
            }
            if payload["due"] != nil { store.tasks[index].due = date(payload["due"]) }
            return taskDict(store.tasks[index])
        }
    }

    private static func deleteTask(id: Int) -> Data? {
        LocalStore.shared.write { store in store.tasks.removeAll { $0.id == id } }
        return ok
    }

    private static func allNotes() -> [[String: Any]] {
        LocalStore.shared.read { store in
            store.notes.sorted { $0.createdAt > $1.createdAt }.map {
                ["id": $0.id, "text": $0.text, "created_at": iso.string(from: $0.createdAt)]
            }
        }
    }

    private static func createNote(_ body: Data?) -> [String: Any] {
        let payload = dict(body)
        return LocalStore.shared.write { store -> [String: Any] in
            let note = LocalNote(
                id: LocalStore.nextID(store.notes),
                text: payload["text"] as? String ?? "",
                createdAt: .now)
            store.notes.append(note)
            return ["id": note.id, "text": note.text, "created_at": iso.string(from: note.createdAt)]
        }
    }

    private static func deleteNote(id: Int) -> Data? {
        LocalStore.shared.write { store in store.notes.removeAll { $0.id == id } }
        return ok
    }

    // ── Plantillas de rutina ────────────────────────────────────────────

    private static func applyTemplate(_ id: String, sets: Int?) -> [String: Any] {
        guard let template = RoutineTemplates.byID[id] else {
            return ["status": "error", "created": [], "skipped": 0]
        }
        let numberOfSets = sets ?? template.sets

        return LocalStore.shared.write { store -> [String: Any] in
            var created: [String] = []
            let existing = Set(store.routines.map(\.name))
            let byName = Dictionary(
                store.exercises.map { ($0.name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first })

            for entry in template.routines where !existing.contains(entry.name) {
                var routine = LocalRoutine(
                    id: LocalStore.nextID(store.routines),
                    name: entry.name,
                    position: store.routines.count)
                routine.items = entry.exercises.enumerated().compactMap { index, name in
                    guard let exercise = byName[name.lowercased()] else { return nil }
                    return LocalRoutineItem(
                        exerciseId: exercise.id, position: index,
                        sets: numberOfSets, repsMin: 6, repsMax: 8)
                }
                store.routines.append(routine)
                store.routineDays[entry.weekday] = routine.id
                created.append(entry.name)
            }
            return ["status": "ok", "created": created,
                    "skipped": template.routines.count - created.count]
        }
    }
}
