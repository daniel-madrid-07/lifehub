import Foundation

// Un método por endpoint — espejo de frontend/src/api.ts.
extension API {

    // ── Hábitos ─────────────────────────────────────────────────────────
    func today() async throws -> [Habit] { try await request("/today") }
    func habits() async throws -> [Habit] { try await request("/habits") }
    func createHabit(_ data: [String: JSONValue]) async throws -> Habit {
        try await request("/habits", method: "POST", body: JSONValue.object(data))
    }
    func updateHabit(_ id: Int, _ data: [String: JSONValue]) async throws -> Habit {
        try await request("/habits/\(id)", method: "PATCH", body: JSONValue.object(data))
    }
    func deleteHabit(_ id: Int) async throws -> StatusResponse {
        try await request("/habits/\(id)", method: "DELETE")
    }
    func markDone(_ id: Int) async throws -> Habit { try await request("/habits/\(id)/done", method: "POST") }
    func undoDone(_ id: Int) async throws -> Habit { try await request("/habits/\(id)/undo", method: "POST") }
    func habitHistory(_ id: Int, days: Int = 28) async throws -> [HabitLog] {
        try await request("/habits/\(id)/history?days=\(days)")
    }

    // ── Módulos de consulta ─────────────────────────────────────────────
    func studies(refresh: Bool = false) async throws -> StudyOverview {
        try await request("/studies\(refresh ? "?refresh=1" : "")")
    }
    func mail() async throws -> MailOverview { try await request("/mail") }
    func calendar() async throws -> CalendarOverview { try await request("/calendar") }
    func financeAlpaca() async throws -> PortfolioOverview { try await request("/finance/alpaca") }
    func financeBitvavo() async throws -> PortfolioOverview { try await request("/finance/bitvavo") }
    func financeSummary() async throws -> FinanceSummary { try await request("/finance/summary") }
    func health() async throws -> [HealthDay] { try await request("/health") }
    func authStatus() async throws -> AuthStatus { try await request("/auth/status") }
    func authGoogleURL() async throws -> GoogleURLResponse { try await request("/auth/google/url") }
    func claudeUsage() async throws -> ClaudeUsage { try await request("/claude/usage") }

    // ── IA ──────────────────────────────────────────────────────────────
    func aiToday() async throws -> AIText { try await request("/ai/today") }
    func aiWorkout(_ id: Int) async throws -> AIText { try await request("/ai/workout/\(id)") }
    func aiMacros(kcal: Int, kcalTarget: Int, protein: Double, proteinTarget: Double) async throws -> AIText {
        try await request("/ai/macros?kcal=\(kcal)&kcal_target=\(kcalTarget)&protein=\(protein)&protein_target=\(proteinTarget)")
    }
    func aiStudies() async throws -> AIText { try await request("/ai/studies") }
    func aiFinance() async throws -> AIText { try await request("/ai/finance") }
    func aiMail() async throws -> AIText { try await request("/ai/mail") }
    @discardableResult
    func aiPrewarm() async throws -> StatusResponse { try await request("/ai/prewarm", method: "POST") }

    // ── Comida / Dieta / Compra ─────────────────────────────────────────
    func foodDay() async throws -> FoodDay { try await request("/food") }
    func addFood(name: String, kcal: Double, protein: Double) async throws -> FoodItem {
        try await request("/food", method: "POST", body: JSONValue.object([
            "name": .string(name), "kcal": .double(kcal), "protein": .double(protein),
        ]))
    }
    func removeFood(_ id: Int) async throws -> StatusResponse {
        try await request("/food/\(id)", method: "DELETE")
    }
    func dietPlan() async throws -> DietPlan { try await request("/diet/plan") }
    func dietLogMeal(_ dish: String) async throws -> FoodItem {
        try await request("/diet/log-meal", method: "POST", body: JSONValue.object(["dish": .string(dish)]))
    }
    struct AddedResponse: Codable { let added: Int }
    func dietAddToShopping(scope: String = "remaining") async throws -> AddedResponse {
        try await request("/diet/shopping?scope=\(scope)", method: "POST")
    }
    func shoppingList() async throws -> [ShopItem] { try await request("/food/shopping") }
    func shoppingAdd(_ text: String) async throws -> ShopItem {
        try await request("/food/shopping", method: "POST", body: JSONValue.object(["text": .string(text)]))
    }
    func shoppingToggle(_ id: Int) async throws -> ShopItem {
        try await request("/food/shopping/\(id)", method: "PATCH")
    }
    func shoppingRemove(_ id: Int) async throws -> StatusResponse {
        try await request("/food/shopping/\(id)", method: "DELETE")
    }
    func shoppingClearDone() async throws -> StatusResponse {
        try await request("/food/shopping", method: "DELETE")
    }

    // ── Gym ─────────────────────────────────────────────────────────────
    func gymExercises() async throws -> [GymExercise] { try await request("/gym/exercises") }
    func gymCreateExercise(name: String, muscle: String, equipment: String) async throws -> GymExercise {
        try await request("/gym/exercises", method: "POST", body: JSONValue.object([
            "name": .string(name), "muscle": .string(muscle), "equipment": .string(equipment),
        ]))
    }
    func gymRecommendation(_ exerciseId: Int, repsMin: Int = 6, repsMax: Int = 8) async throws -> RecommendationResponse {
        try await request("/gym/exercises/\(exerciseId)/recommendation?reps_min=\(repsMin)&reps_max=\(repsMax)")
    }
    func gymRoutines() async throws -> [GymRoutine] { try await request("/gym/routines") }
    func gymRoutineMode() async throws -> RoutineModeResponse { try await request("/gym/routine-mode") }
    func gymSetRoutineMode(_ mode: String) async throws -> RoutineModeResponse {
        try await request("/gym/routine-mode", method: "POST", body: JSONValue.object(["mode": .string(mode)]))
    }
    func gymCreateRoutine(name: String, exercises: [JSONValue]) async throws -> GymRoutine {
        try await request("/gym/routines", method: "POST", body: JSONValue.object([
            "name": .string(name), "exercises": .array(exercises),
        ]))
    }
    func gymUpdateRoutine(_ id: Int, name: String, exercises: [JSONValue]) async throws -> GymRoutine {
        try await request("/gym/routines/\(id)", method: "PATCH", body: JSONValue.object([
            "name": .string(name), "exercises": .array(exercises),
        ]))
    }
    func gymDeleteRoutine(_ id: Int) async throws -> StatusResponse {
        try await request("/gym/routines/\(id)", method: "DELETE")
    }
    func gymActiveWorkout() async throws -> GymWorkout? { try await request("/gym/workouts/active") }
    func gymWorkouts() async throws -> [GymWorkoutSummary] { try await request("/gym/workouts") }
    func gymStartWorkout(routineId: Int?) async throws -> GymWorkout {
        try await request("/gym/workouts", method: "POST", body: JSONValue.object([
            "routine_id": routineId.map { JSONValue.int($0) } ?? .null,
        ]))
    }
    func gymWorkout(_ id: Int) async throws -> GymWorkout { try await request("/gym/workouts/\(id)") }
    func gymAddSet(workoutId: Int, exerciseId: Int, weight: Double, reps: Int) async throws -> GymSet {
        try await request("/gym/workouts/\(workoutId)/sets", method: "POST", body: JSONValue.object([
            "exercise_id": .int(exerciseId), "weight": .double(weight), "reps": .int(reps),
        ]))
    }
    func gymDeleteSet(workoutId: Int, setId: Int) async throws -> StatusResponse {
        try await request("/gym/workouts/\(workoutId)/sets/\(setId)", method: "DELETE")
    }
    func gymFinishWorkout(_ id: Int) async throws -> GymWorkout {
        try await request("/gym/workouts/\(id)/finish", method: "POST")
    }
    func gymDiscardWorkout(_ id: Int) async throws -> StatusResponse {
        try await request("/gym/workouts/\(id)", method: "DELETE")
    }
    func gymProgress(_ exerciseId: Int) async throws -> GymProgress {
        try await request("/gym/progress/\(exerciseId)")
    }
    func gymWeeklyStats() async throws -> WeeklyStats { try await request("/gym/stats/weekly") }
    func gymBodyweight() async throws -> [BodyWeightEntry] { try await request("/gym/bodyweight") }
    func gymAddBodyweight(_ weight: Double) async throws -> BodyWeightEntry {
        try await request("/gym/bodyweight", method: "POST", body: JSONValue.object(["weight": .double(weight)]))
    }
    func gymDeleteBodyweight(_ id: Int) async throws -> StatusResponse {
        try await request("/gym/bodyweight/\(id)", method: "DELETE")
    }
    func gymMeasures() async throws -> Measures { try await request("/gym/measures") }
    func gymAddMeasure(site: String, value: Double) async throws -> MeasureEntry {
        try await request("/gym/measures", method: "POST", body: JSONValue.object([
            "site": .string(site), "value": .double(value),
        ]))
    }
    func gymDeleteMeasure(_ id: Int) async throws -> StatusResponse {
        try await request("/gym/measures/\(id)", method: "DELETE")
    }
    func gymPhotos() async throws -> [ProgressPhotoItem] { try await request("/gym/photos") }
    func gymUploadPhoto(_ data: Data) async throws -> ProgressPhotoItem {
        try await upload("/gym/photos", imageData: data, filename: "progress.jpg")
    }
    func gymDeletePhoto(_ id: Int) async throws -> StatusResponse {
        try await request("/gym/photos/\(id)", method: "DELETE")
    }

    // ── Tareas / Notas ──────────────────────────────────────────────────
    func tasks() async throws -> [TaskItem] { try await request("/tasks") }
    func createTask(text: String, due: String?) async throws -> TaskItem {
        try await request("/tasks", method: "POST", body: JSONValue.object([
            "text": .string(text), "due": due.map { JSONValue.string($0) } ?? .null,
        ]))
    }
    func updateTask(_ id: Int, _ data: [String: JSONValue]) async throws -> TaskItem {
        try await request("/tasks/\(id)", method: "PATCH", body: JSONValue.object(data))
    }
    func removeTask(_ id: Int) async throws -> StatusResponse {
        try await request("/tasks/\(id)", method: "DELETE")
    }
    func notes() async throws -> [NoteItem] { try await request("/notes") }
    func createNote(_ text: String) async throws -> NoteItem {
        try await request("/notes", method: "POST", body: JSONValue.object(["text": .string(text)]))
    }
    func removeNote(_ id: Int) async throws -> StatusResponse {
        try await request("/notes/\(id)", method: "DELETE")
    }

    // ── Armario ─────────────────────────────────────────────────────────────────
    func wardrobe() async throws -> [ClothingItem] { try await request("/wardrobe") }
    func createClothing(_ data: [String: JSONValue]) async throws -> ClothingItem {
        try await request("/wardrobe", method: "POST", body: JSONValue.object(data))
    }
    func updateClothing(_ id: Int, _ data: [String: JSONValue]) async throws -> ClothingItem {
        try await request("/wardrobe/\(id)", method: "PATCH", body: JSONValue.object(data))
    }
    func deleteClothing(_ id: Int) async throws -> StatusResponse {
        try await request("/wardrobe/\(id)", method: "DELETE")
    }
    func uploadClothingPhoto(_ id: Int, imageData: Data) async throws -> ClothingItem {
        try await upload("/wardrobe/\(id)/photo", imageData: imageData, filename: "clothing.jpg")
    }
    func wearClothing(_ id: Int) async throws -> ClothingItem {
        try await request("/wardrobe/\(id)/wear", method: "POST")
    }
    func dirtyClothing(_ id: Int) async throws -> ClothingItem {
        try await request("/wardrobe/\(id)/dirty", method: "POST")
    }
    func washedClothing(_ id: Int) async throws -> ClothingItem {
        try await request("/wardrobe/\(id)/washed", method: "POST")
    }
    func outfitToday() async throws -> OutfitSuggestion { try await request("/wardrobe/outfit/today") }
    func aiOutfit() async throws -> AIText { try await request("/ai/outfit") }

    // ── Perfil ───────────────────────────────────────────────────────────────
    func profile() async throws -> ProfileDTO { try await request("/profile") }
    func updateProfile(_ data: [String: JSONValue]) async throws -> ProfileDTO {
        try await request("/profile", method: "PATCH", body: JSONValue.object(data))
    }

    // ── Detección de eventos ─────────────────────────────────────────────────
    func detectEvent(_ text: String) async throws -> DetectedEventsResponse {
        try await request("/ai/detect-event", method: "POST",
                          body: JSONValue.object(["text": .string(text)]))
    }
    func mailEvents() async throws -> DetectedEventsResponse {
        try await request("/ai/mail-events")
    }
    func createCalendarEvent(title: String, startIso: String, endIso: String?,
                             location: String?) async throws -> CreateEventResponse {
        try await request("/calendar/events", method: "POST",
                          body: JSONValue.object([
                            "title":     .string(title),
                            "start_iso": .string(startIso),
                            "end_iso":   endIso.map { .string($0) } ?? .null,
                            "location":  location.map { .string($0) } ?? .null,
                          ]))
    }
}
