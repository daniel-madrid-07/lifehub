/**
 * Ajustes locales de Daniel (solo este dispositivo, sin backend).
 * Guardados en localStorage. Los componentes se suscriben con useSetting y se
 * re-renderizan al cambiar via un evento propio.
 */
import { useSyncExternalStore } from "react"

export type NavStyle = "scroll" | "classic"

export interface Settings {
  navStyle: NavStyle
}

const DEFAULTS: Settings = {
  navStyle: "scroll",
}

const KEY = "lifehub_settings"
const EVENT = "lifehub:settings"

function read(): Settings {
  try {
    return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(KEY) || "{}") }
  } catch {
    return { ...DEFAULTS }
  }
}

export function getSettings(): Settings {
  return read()
}

export function setSetting<K extends keyof Settings>(key: K, value: Settings[K]) {
  const next = { ...read(), [key]: value }
  localStorage.setItem(KEY, JSON.stringify(next))
  window.dispatchEvent(new Event(EVENT))
}

function subscribe(cb: () => void) {
  window.addEventListener(EVENT, cb)
  window.addEventListener("storage", cb)
  return () => {
    window.removeEventListener(EVENT, cb)
    window.removeEventListener("storage", cb)
  }
}

/** Lee un ajuste de forma reactiva. */
export function useSetting<K extends keyof Settings>(key: K): Settings[K] {
  return useSyncExternalStore(
    subscribe,
    () => read()[key],
    () => DEFAULTS[key],
  )
}
