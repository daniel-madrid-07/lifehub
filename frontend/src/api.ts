import type {
  BodyWeightEntry,
  CalendarOverview,
  FinanceSummary,
  FoodDay,
  FoodItem,
  GymExercise,
  GymProgress,
  GymRecommendation,
  GymRoutine,
  GymSet,
  GymWorkout,
  GymWorkoutSummary,
  Habit,
  DietPlan,
  HabitLog,
  HealthDay,
  MailOverview,
  Measures,
  NoteItem,
  PortfolioOverview,
  ProfileDTO,
  ProgressPhotoItem,
  ShopItem,
  StudyOverview,
  Task,
  WeeklyStats,
} from "./types"

const BASE = "/api"
const TOKEN_KEY = "lifehub_token"

export function getToken(): string {
  return localStorage.getItem(TOKEN_KEY) ?? ""
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const token = getToken()
  const res = await fetch(BASE + path, {
    ...init,
    // sin esto, un backend colgado deja el skeleton infinito
    signal: AbortSignal.timeout(60_000),
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  })
  if (res.status === 401) {
    clearToken()
    window.dispatchEvent(new Event("lifehub:unauthorized"))
    throw new Error("No autorizado")
  }
  if (!res.ok) throw new Error(await res.text())
  return res.json()
}

export const api = {
  today: () => request<Habit[]>("/today"),
  habits: () => request<Habit[]>("/habits"),
  create: (data: Partial<Habit>) =>
    request<Habit>("/habits", { method: "POST", body: JSON.stringify(data) }),
  update: (id: number, data: Partial<Habit>) =>
    request<Habit>(`/habits/${id}`, { method: "PATCH", body: JSON.stringify(data) }),
  remove: (id: number) => request<{ status: string }>(`/habits/${id}`, { method: "DELETE" }),
  done: (id: number) => request<Habit>(`/habits/${id}/done`, { method: "POST" }),
  undo: (id: number) => request<Habit>(`/habits/${id}/undo`, { method: "POST" }),
  history: (id: number, days = 28) => request<HabitLog[]>(`/habits/${id}/history?days=${days}`),
  studies: (refresh = false) => request<StudyOverview>(`/studies${refresh ? "?refresh=1" : ""}`),
  mail: () => request<MailOverview>("/mail"),
  calendar: () => request<CalendarOverview>("/calendar"),
  financeAlpaca: () => request<PortfolioOverview>("/finance/alpaca"),
  financeBitvavo: () => request<PortfolioOverview>("/finance/bitvavo"),
  financeSummary: () => request<FinanceSummary>("/finance/summary"),

  food: {
    day: (day?: string) => request<FoodDay>(`/food${day ? `?day=${day}` : ""}`),
    add: (data: { name: string; kcal: number; protein: number }) =>
      request<FoodItem>("/food", { method: "POST", body: JSON.stringify(data) }),
    remove: (id: number) => request<{ status: string }>(`/food/${id}`, { method: "DELETE" }),
  },

  diet: {
    plan: () => request<DietPlan>("/diet/plan"),
    addWeekToShopping: (scope: "remaining" | "week" = "remaining") =>
      request<{ added: number }>(`/diet/shopping?scope=${scope}`, { method: "POST" }),
    logMeal: (dish: string) =>
      request<FoodItem>("/diet/log-meal", { method: "POST", body: JSON.stringify({ dish }) }),
  },

  shopping: {
    list: () => request<ShopItem[]>("/food/shopping"),
    add: (text: string) =>
      request<ShopItem>("/food/shopping", { method: "POST", body: JSON.stringify({ text }) }),
    toggle: (id: number) => request<ShopItem>(`/food/shopping/${id}`, { method: "PATCH" }),
    remove: (id: number) => request<{ status: string }>(`/food/shopping/${id}`, { method: "DELETE" }),
    clearDone: () => request<{ status: string }>("/food/shopping", { method: "DELETE" }),
  },

  health: () => request<HealthDay[]>("/health"),

  ai: {
    today: () => request<{ text: string | null }>("/ai/today"),
    workout: (id: number) => request<{ text: string | null }>(`/ai/workout/${id}`),
    macros: (kcal: number, kcalTarget: number, protein: number, proteinTarget: number) =>
      request<{ text: string | null }>(
        `/ai/macros?kcal=${kcal}&kcal_target=${kcalTarget}&protein=${protein}&protein_target=${proteinTarget}`,
      ),
    studies: () => request<{ text: string | null }>("/ai/studies"),
    finance: () => request<{ text: string | null }>("/ai/finance"),
    mail: () => request<{ text: string | null }>("/ai/mail"),
    prewarm: () => request<{ status: string }>("/ai/prewarm", { method: "POST" }),
  },

  auth: {
    status: () =>
      request<{
        google: {
          authorized_at: string | null
          days_left: number | null
          production?: boolean
          connected: boolean
        }
        intra: { connected: boolean; days_left: number | null; expires_at: string | null }
      }>("/auth/status"),
    googleUrl: () => request<{ url: string }>("/auth/google/url"),
  },

  gym: {
    exercises: () => request<GymExercise[]>("/gym/exercises"),
    createExercise: (data: { name: string; muscle: string; equipment: string }) =>
      request<GymExercise>("/gym/exercises", { method: "POST", body: JSON.stringify(data) }),
    recommendation: (exerciseId: number, repsMin = 6, repsMax = 8) =>
      request<{ recommendation: GymRecommendation; last: { weight: number; reps: number }[] }>(
        `/gym/exercises/${exerciseId}/recommendation?reps_min=${repsMin}&reps_max=${repsMax}`,
      ),
    routines: () => request<GymRoutine[]>("/gym/routines"),
    routineMode: () => request<{ mode: string }>("/gym/routine-mode"),
    setRoutineMode: (mode: string) =>
      request<{ mode: string }>("/gym/routine-mode", { method: "POST", body: JSON.stringify({ mode }) }),
    createRoutine: (data: object) =>
      request<GymRoutine>("/gym/routines", { method: "POST", body: JSON.stringify(data) }),
    updateRoutine: (id: number, data: object) =>
      request<GymRoutine>(`/gym/routines/${id}`, { method: "PATCH", body: JSON.stringify(data) }),
    deleteRoutine: (id: number) =>
      request<{ status: string }>(`/gym/routines/${id}`, { method: "DELETE" }),
    activeWorkout: () => request<GymWorkout | null>("/gym/workouts/active"),
    workouts: () => request<GymWorkoutSummary[]>("/gym/workouts"),
    startWorkout: (routineId: number | null) =>
      request<GymWorkout>("/gym/workouts", {
        method: "POST",
        body: JSON.stringify({ routine_id: routineId }),
      }),
    workout: (id: number) => request<GymWorkout>(`/gym/workouts/${id}`),
    addSet: (workoutId: number, data: { exercise_id: number; weight: number; reps: number }) =>
      request<GymSet>(`/gym/workouts/${workoutId}/sets`, {
        method: "POST",
        body: JSON.stringify(data),
      }),
    deleteSet: (workoutId: number, setId: number) =>
      request<{ status: string }>(`/gym/workouts/${workoutId}/sets/${setId}`, { method: "DELETE" }),
    finishWorkout: (id: number) =>
      request<GymWorkout>(`/gym/workouts/${id}/finish`, { method: "POST" }),
    discardWorkout: (id: number) =>
      request<{ status: string }>(`/gym/workouts/${id}`, { method: "DELETE" }),
    progress: (exerciseId: number) => request<GymProgress>(`/gym/progress/${exerciseId}`),
    weeklyStats: () => request<WeeklyStats>("/gym/stats/weekly"),
    bodyweight: () => request<BodyWeightEntry[]>("/gym/bodyweight"),
    addBodyweight: (weight: number) =>
      request<BodyWeightEntry>("/gym/bodyweight", {
        method: "POST",
        body: JSON.stringify({ weight }),
      }),
    deleteBodyweight: (id: number) =>
      request<{ status: string }>(`/gym/bodyweight/${id}`, { method: "DELETE" }),
    measures: () => request<Measures>("/gym/measures"),
    addMeasure: (site: string, value: number) =>
      request<{ id: number; site: string; at: string; value: number }>("/gym/measures", {
        method: "POST",
        body: JSON.stringify({ site, value }),
      }),
    deleteMeasure: (id: number) =>
      request<{ status: string }>(`/gym/measures/${id}`, { method: "DELETE" }),
    photos: () => request<ProgressPhotoItem[]>("/gym/photos"),
    uploadPhoto: async (file: File) => {
      const body = new FormData()
      body.append("file", file)
      const res = await fetch("/api/gym/photos", {
        method: "POST",
        headers: { Authorization: `Bearer ${getToken()}` },
        body,
      })
      if (!res.ok) throw new Error(await res.text())
      return res.json() as Promise<ProgressPhotoItem>
    },
    deletePhoto: (id: number) =>
      request<{ status: string }>(`/gym/photos/${id}`, { method: "DELETE" }),
  },

  tasks: {
    list: () => request<Task[]>("/tasks"),
    create: (text: string, due?: string | null) =>
      request<Task>("/tasks", { method: "POST", body: JSON.stringify({ text, due: due ?? null }) }),
    update: (id: number, data: Partial<Pick<Task, "text" | "done" | "due">>) =>
      request<Task>(`/tasks/${id}`, { method: "PATCH", body: JSON.stringify(data) }),
    remove: (id: number) => request<{ status: string }>(`/tasks/${id}`, { method: "DELETE" }),
  },

  notes: {
    list: () => request<NoteItem[]>("/notes"),
    create: (text: string) =>
      request<NoteItem>("/notes", { method: "POST", body: JSON.stringify({ text }) }),
    remove: (id: number) => request<{ status: string }>(`/notes/${id}`, { method: "DELETE" }),
  },

  profile: {
    get: () => request<ProfileDTO>("/profile"),
    update: (data: Partial<ProfileDTO>) =>
      request<ProfileDTO>("/profile", { method: "PATCH", body: JSON.stringify(data) }),
  },

  push: {
    vapid: () => request<{ key: string }>("/push/vapid"),
    subscribe: (sub: object) =>
      request<{ status: string }>("/push/subscribe", { method: "POST", body: JSON.stringify(sub) }),
    unsubscribe: (endpoint: string) =>
      request<{ status: string }>("/push/unsubscribe", {
        method: "POST",
        body: JSON.stringify({ endpoint }),
      }),
    test: () => request<{ sent: number }>("/push/test", { method: "POST" }),
  },
}
