/**
 * Perfil del usuario. Los datos y las fórmulas viven en el backend
 * (backend/app/profile.py) para que web, iOS y reloj no se desincronicen.
 *
 * Este módulo cachea el perfil en memoria y lo expone con `useProfile`, para
 * que las pantallas no tengan que recargarlo cada una por su cuenta.
 */
import { useSyncExternalStore } from "react"
import { api } from "./api"
import type { ProfileDTO } from "./types"

export interface Profile {
  name: string | null
  heightCm: number
  birthDate: string | null
  age: number | null
  sex: "m" | "f"
  activityFactor: number
  goal: string
  goalKcalDelta: number
  proteinPerKg: number
  bodyFatPct: number | null
  fallbackWeight: number
  barWeight: number
  plates: number[]
  latitude: number | null
  longitude: number | null
  city: string | null
  /** Derivados que calcula el backend con el último peso registrado */
  weight: number
  bmr: number
  tdee: number
  kcalTarget: number
  proteinTarget: number
  /** false hasta que se completa el onboarding */
  configured: boolean
}

/** Valores neutros mientras carga o si el backend no responde. */
const FALLBACK: Profile = {
  name: null,
  heightCm: 175,
  birthDate: null,
  age: null,
  sex: "m",
  activityFactor: 1.5,
  goal: "Mantener",
  goalKcalDelta: 0,
  proteinPerKg: 1.8,
  bodyFatPct: null,
  fallbackWeight: 70,
  barWeight: 20,
  plates: [20, 10, 5, 2.5, 1.25],
  latitude: null,
  longitude: null,
  city: null,
  weight: 70,
  bmr: 0,
  tdee: 0,
  kcalTarget: 0,
  proteinTarget: 0,
  configured: false,
}

function fromDTO(raw: ProfileDTO): Profile {
  return {
    name: raw.name,
    heightCm: raw.height_cm,
    birthDate: raw.birth_date,
    age: raw.age,
    sex: raw.sex,
    activityFactor: raw.activity_factor,
    goal: raw.goal,
    goalKcalDelta: raw.goal_kcal_delta,
    proteinPerKg: raw.protein_per_kg,
    bodyFatPct: raw.body_fat_pct,
    fallbackWeight: raw.fallback_weight,
    barWeight: raw.bar_weight,
    plates: raw.plates,
    latitude: raw.latitude,
    longitude: raw.longitude,
    city: raw.city,
    weight: raw.weight,
    bmr: raw.bmr,
    tdee: raw.tdee,
    kcalTarget: raw.kcal_target,
    proteinTarget: raw.protein_target,
    configured: raw.configured,
  }
}

let cache: Profile = FALLBACK
let loading = false
const listeners = new Set<() => void>()

function emit() {
  listeners.forEach((l) => l())
}

export async function loadProfile(): Promise<Profile> {
  cache = fromDTO(await api.profile.get())
  emit()
  return cache
}

export async function saveProfile(patch: Partial<ProfileDTO>): Promise<Profile> {
  cache = fromDTO(await api.profile.update(patch))
  emit()
  return cache
}

/** Perfil actual (el de respaldo hasta que carga). */
export function getProfile(): Profile {
  return cache
}

/** Perfil reactivo: se recarga solo la primera vez que alguien lo pide. */
export function useProfile(): Profile {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb)
      if (!loading) {
        loading = true
        void loadProfile().catch(() => {
          loading = false
        })
      }
      return () => {
        listeners.delete(cb)
      }
    },
    () => cache,
    () => FALLBACK,
  )
}

/**
 * Calculadora de discos: qué poner por lado para un peso total con barra.
 * Se calcula en local porque se usa en cada serie mientras entrenas.
 */
export function platesPerSide(total: number): { plates: number[]; leftover: number } {
  const { barWeight, plates } = cache
  let perSide = (total - barWeight) / 2
  if (perSide <= 0) return { plates: [], leftover: 0 }
  const out: number[] = []
  for (const plate of [...plates].sort((a, b) => b - a)) {
    while (perSide >= plate - 1e-9) {
      out.push(plate)
      perSide -= plate
    }
  }
  return { plates: out, leftover: Math.round(perSide * 100) / 100 }
}
