export type Category = "water" | "medicine" | "exercise" | "sleep" | "chore" | "custom" | "diet"
export type ScheduleType = "daily_times" | "interval_days" | "week_days"

/** Dias 0-6, lunes=0 (weekday() de Python) */
export interface WeekSchedule {
  days: number[]
  times: string[]
}

export interface Habit {
  id: number
  name: string
  category: Category
  schedule_type: ScheduleType
  schedule: string[] | number | WeekSchedule
  active: boolean
  created_at: string
  streak: number
  done_today: boolean
  due_today: boolean
  next_time: string | null
  progress_label: string
  last_done: string | null
}

export interface HabitLog {
  id: number
  habit_id: number
  done_at: string
  note: string | null
}

export const CATEGORY_LABELS: Record<Category, string> = {
  water: "Agua",
  medicine: "Medicina",
  exercise: "Ejercicio",
  sleep: "Sueño",
  chore: "Tarea doméstica",
  custom: "Rutina",
  diet: "Comida",
}

export const CATEGORIES: Category[] = ["water", "medicine", "exercise", "sleep", "chore", "custom", "diet"]

export const ROUTINE_CATEGORIES: Category[] = ["water", "medicine", "exercise", "sleep", "chore", "custom"]

export const NUTRITION_CATEGORIES: Category[] = ["diet"]

export interface StudyProject {
  title: string
  deadline: string | null
  progress: string | null
  link: string | null
}

export interface StudyActivity {
  title: string
  module: string | null
  start: string | null
  register_deadline: string | null
  link: string | null
}

export interface StudyNote {
  title: string
  note: string | null
}

export interface StudyOverview {
  status: "ok" | "error"
  detail?: string
  fetched_at?: string
  summary?: string | null
  projects?: StudyProject[]
  activities?: StudyActivity[]
  notes?: StudyNote[]
}

export interface MailMessage {
  subject: string
  from: string
  snippet: string
  date: string | null
  link: string | null
}

export interface MailOverview {
  status: "ok" | "error"
  detail?: string
  messages?: MailMessage[]
}

// ── Gym ────────────────────────────────────────────────────────────────────

export interface GymExercise {
  id: number
  name: string
  muscle: string
  equipment: string
  custom: boolean
}

export interface GymRoutineExercise {
  exercise_id: number
  name: string
  muscle: string
  equipment: string
  sets: number
  reps_min: number
  reps_max: number
}

export interface GymRoutine {
  id: number
  name: string
  today?: boolean
  exercises: GymRoutineExercise[]
}

export interface GymSet {
  id: number
  exercise_id: number
  set_number: number
  weight: number
  reps: number
  pr?: "peso" | "1rm" | null
}

export interface BodyWeightEntry {
  id: number
  at: string
  weight: number
}

export interface WeeklyStats {
  muscles: { muscle: string; sets: number; volume: number }[]
  total_sets: number
}

export interface GymRecommendation {
  weight: number | null
  reps: number
  note: string
}

export interface GymPlanItem {
  exercise: GymExercise
  target_sets: number
  reps_min: number
  reps_max: number
  recommendation: GymRecommendation
  last: { weight: number; reps: number }[]
  sets: GymSet[]
}

export interface WorkoutSummary {
  duration_min: number
  volume: number
  sets: number
  exercises: number
  prs: { exercise: string; kind: "peso" | "1rm"; value: number }[]
  vs_last: { date: string; last_volume: number; volume_delta: number } | null
}

export interface GymWorkout {
  id: number
  routine_id: number | null
  routine_name: string | null
  started_at: string
  finished_at: string | null
  plan: GymPlanItem[]
  summary?: WorkoutSummary | null
}

export interface GymWorkoutSummary {
  id: number
  started_at: string
  finished_at: string
  routine_name: string | null
  exercises: number
  sets: number
  volume: number
  duration_min: number
}

export interface GymProgress {
  exercise: GymExercise
  sessions: {
    date: string
    top_weight: number
    top_reps: number
    est_1rm: number
    volume: number
    sets: number
  }[]
  pr_weight: number
  pr_1rm: number
  recommendation: GymRecommendation
}

export interface Task {
  id: number
  text: string
  done: boolean
  due: string | null
  created_at: string
  done_at: string | null
}

export interface NoteItem {
  id: number
  text: string
  created_at: string
}

export interface MeasureEntry {
  id: number
  at: string
  value: number
}

export type Measures = Record<string, MeasureEntry[]>

export interface ProgressPhotoItem {
  id: number
  at: string
  url: string
  note?: string | null
}

export interface ShopItem {
  id: number
  text: string
  done: boolean
}

export interface DietDay {
  weekday: string
  is_today: boolean
  breakfast: string
  lunch: string
  snack: string
  dinner: string
}

export interface DietPlan {
  days: DietDay[]
  dishes: Record<string, [string, number, string][]>
  macros: Record<string, { kcal: number; protein: number }>
}

export interface HealthDay {
  day: string
  steps: number | null
  sleep_hours: number | null
  resting_hr: number | null
  active_kcal: number | null
}

export interface FinanceSummary {
  status: "ok" | "error"
  detail?: string
  rate: number | null
  alpaca_usd: number | null
  alpaca_eur: number | null
  bitvavo_eur: number | null
  total_eur: number | null
  day_change_pct: number | null
  history: { date: string; alpaca_usd: number; bitvavo_eur: number; total_eur: number | null }[]
}

export interface FoodItem {
  id: number
  at: string
  name: string
  kcal: number
  protein: number
}

export interface FoodDay {
  items: FoodItem[]
  total_kcal: number
  total_protein: number
}

export interface PortfolioPosition {
  symbol: string
  qty: number
  price: number
  value: number
  pnl: number | null
  pnl_pct: number | null
  day_pct: number
}

export interface PortfolioOverview {
  status: "ok" | "error"
  detail?: string
  currency?: string
  equity?: number
  cash?: number
  day_change?: number
  day_change_pct?: number
  positions?: PortfolioPosition[]
}

export interface CalendarEvent {
  title: string
  start: string | null
  end: string | null
  location: string | null
  link: string | null
}

export interface CalendarOverview {
  status: "ok" | "error"
  detail?: string
  events?: CalendarEvent[]
}

/** Perfil del usuario, tal cual lo devuelve /api/profile (snake_case). */
export interface ProfileDTO {
  name: string | null
  height_cm: number
  birth_date: string | null
  age: number | null
  sex: "m" | "f"
  activity_factor: number
  goal: string
  goal_kcal_delta: number
  protein_per_kg: number
  body_fat_pct: number | null
  fallback_weight: number
  bar_weight: number
  plates: number[]
  latitude: number | null
  longitude: number | null
  city: string | null
  weight: number
  bmr: number
  tdee: number
  kcal_target: number
  protein_target: number
  configured: boolean
}

/** Plantilla de rutina que se puede aplicar de una vez. */
export interface RoutineTemplate {
  id: string
  name: string
  description: string
  days_per_week: number
  routines: string[]
}
