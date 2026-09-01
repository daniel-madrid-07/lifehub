import { useEffect, useRef } from "react"
import { CheckIcon } from "./icons"
import { haptic } from "../haptics"

/**
 * Botón de "marcar hecho".
 *
 * En iOS 26.5+ Apple bloqueó disparar hápticos por código. Lo único que aún
 * vibra es que el usuario toque DIRECTAMENTE un `<input type="checkbox" switch>`.
 * Por eso aquí el control real es ese input (invisible, superpuesto, con su
 * apariencia nativa intacta para conservar el Taptic); encima va el diseño
 * circular. `haptic()` sigue llamándose como fallback (Android / iOS < 26.5).
 */
export default function CheckButton({
  onClick,
  label = "Marcar hecho",
  large = false,
}: {
  onClick: () => void
  label?: string
  large?: boolean
}) {
  const size = large ? "w-16 h-16" : "w-12 h-12"
  const icon = large ? "w-7 h-7" : "w-5 h-5"
  const ref = useRef<HTMLInputElement>(null)

  useEffect(() => {
    // atributo propietario de Safari; setearlo por JS evita líos de tipos
    ref.current?.setAttribute("switch", "")
  }, [])

  const handle = () => {
    if (ref.current) ref.current.checked = false // mantenerlo sin estado visible
    haptic("medium")
    onClick()
  }

  return (
    <span
      className={`relative inline-flex ${size} shrink-0 rounded-full active:scale-[0.82] transition-transform`}
    >
      <span
        aria-hidden
        className={`${size} rounded-full border-2 border-accent flex items-center justify-center text-accent`}
      >
        <CheckIcon className={icon} />
      </span>
      <input
        ref={ref}
        type="checkbox"
        aria-label={label}
        onChange={handle}
        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer m-0 outline-none"
      />
    </span>
  )
}
