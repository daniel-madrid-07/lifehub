/**
 * Hápticos / "tics" táctiles.
 *
 * Estado real (junio 2026):
 * - Android y navegadores con Vibration API → `navigator.vibrate(patrón)`. Funciona.
 * - iOS Safari NUNCA implementó la Vibration API. El único truco era togglear un
 *   `<input type="checkbox" switch>` haciendo `.click()` sobre su `<label>`, lo
 *   que disparaba el Taptic Engine. FUNCIONA en iOS 17.4–26.4.
 * - iOS 26.5+ (mayo 2026): Apple parcheó ese truco. Ya NO se puede disparar
 *   háptico por código; solo cuando el usuario toca DIRECTAMENTE un switch real.
 *   En esas versiones esta función simplemente no vibra (no hay alternativa web).
 *
 * Se intenta de todas formas: en iOS < 26.5 sigue funcionando y en Android va por
 * vibrate. Siempre se llama desde un gesto del usuario (onClick).
 */

export type Haptic = "light" | "medium" | "heavy" | "success" | "warning"

const PATTERNS: Record<Haptic, number | number[]> = {
  light: 8,
  medium: 15,
  heavy: 30,
  success: [12, 40, 14],
  warning: [22, 50, 22],
}

const canVibrate =
  typeof navigator !== "undefined" && typeof navigator.vibrate === "function"

/** iOS < 26.5: el tic se dispara clicando el LABEL (no el input) de un
 * `<input type="checkbox" switch>`. Se recrea en cada llamada (más fiable). */
function iosTick(): void {
  try {
    const label = document.createElement("label")
    label.setAttribute("aria-hidden", "true")
    label.style.cssText =
      "position:fixed;top:0;left:0;opacity:0;pointer-events:none;z-index:-1"
    const input = document.createElement("input")
    input.type = "checkbox"
    input.setAttribute("switch", "") // atributo propietario de Safari → háptico
    label.appendChild(input)
    document.body.appendChild(label)
    label.click() // CLAVE: el click va al label, no al input
    requestAnimationFrame(() => label.remove())
  } catch {
    /* silencioso */
  }
}

/** Dispara un tic háptico del tipo indicado (por defecto "light"). */
export function haptic(kind: Haptic = "light"): void {
  if (canVibrate) {
    try {
      navigator.vibrate(PATTERNS[kind])
    } catch {
      /* sin hardware: silencioso */
    }
    return
  }
  // iOS: un tick por toggle. success/warning = doble pulso.
  iosTick()
  if (Array.isArray(PATTERNS[kind])) window.setTimeout(iosTick, 70)
}
