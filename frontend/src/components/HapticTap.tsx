import { useEffect, useRef, type CSSProperties, type ReactNode } from "react"
import { haptic, type Haptic } from "../haptics"

/**
 * Envuelve cualquier control para que VIBRE en iOS 26.5+.
 *
 * En esa versión Apple solo deja disparar el Taptic cuando el usuario toca
 * DIRECTAMENTE un `<input type="checkbox" switch>`. Así que se superpone uno
 * invisible (con su apariencia nativa intacta, solo `opacity:0`) que recibe el
 * toque; el diseño visual va detrás en `children`. `haptic()` se llama además
 * como fallback (Android / iOS < 26.5).
 *
 * Se comporta como un botón: dispara `onTap` al tocarlo.
 */
export default function HapticTap({
  onTap,
  children,
  className = "",
  style,
  label,
  current,
  kind = "light",
}: {
  onTap: () => void
  children: ReactNode
  className?: string
  style?: CSSProperties
  label: string
  current?: boolean
  kind?: Haptic
}) {
  const ref = useRef<HTMLInputElement>(null)

  useEffect(() => {
    ref.current?.setAttribute("switch", "") // atributo propietario de Safari
  }, [])

  return (
    <span className={`relative ${className}`} style={style}>
      {children}
      <input
        ref={ref}
        type="checkbox"
        aria-label={label}
        aria-current={current ? "page" : undefined}
        onChange={() => {
          if (ref.current) ref.current.checked = false
          haptic(kind)
          onTap()
        }}
        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer m-0 outline-none"
      />
    </span>
  )
}
