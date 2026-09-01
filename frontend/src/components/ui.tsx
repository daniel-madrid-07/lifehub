import { useEffect, useRef, useState, type ReactNode, type SelectHTMLAttributes } from "react"
import { motion } from "framer-motion"
import { ChevronUpDownIcon, RefreshIcon } from "./icons"
import HapticTap from "./HapticTap"

/** Nota del coach IA. Carga UNA vez al montar (bajo demanda); si no hay texto
 * (IA apagada o sin datos), no muestra nada. */
export function CoachNote({ fetcher }: { fetcher: () => Promise<{ text: string | null }> }) {
  const [text, setText] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const fetcherRef = useRef(fetcher)
  fetcherRef.current = fetcher

  useEffect(() => {
    let alive = true
    fetcherRef.current()
      .then((r) => alive && setText(r.text))
      .catch(() => {})
      .finally(() => alive && setLoading(false))
    return () => {
      alive = false
    }
  }, [])

  if (loading) {
    return <div className="h-16 rounded-2xl bg-surface animate-pulse mb-4" />
  }
  if (!text) return null
  return (
    <div className="rounded-2xl border border-accent/40 bg-surface p-4 mb-4">
      <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1.5">Coach</div>
      <p className="text-sm leading-relaxed">{text}</p>
    </div>
  )
}

/** Control segmentado (pestañas tipo iOS) con vibración al cambiar. */
export function Segmented<T extends string>({
  tabs,
  value,
  onChange,
  label,
  layoutId,
}: {
  tabs: { id: T; label: string }[]
  value: T
  onChange: (id: T) => void
  label: string
  layoutId: string
}) {
  return (
    <div
      role="tablist"
      aria-label={label}
      className="flex p-1 rounded-full bg-surface border border-line mb-8"
    >
      {tabs.map((t) => {
        const active = value === t.id
        return (
          <HapticTap
            key={t.id}
            label={t.label}
            current={active}
            onTap={() => onChange(t.id)}
            className="flex-1 flex items-center justify-center py-2.5 text-sm rounded-full"
          >
            {active && (
              <motion.span
                layoutId={layoutId}
                className="absolute inset-0 rounded-full bg-surface-2 border border-line"
                transition={{ type: "spring", stiffness: 500, damping: 38 }}
              />
            )}
            <span className={`relative font-medium ${active ? "text-ink" : "text-muted"}`}>
              {t.label}
            </span>
          </HapticTap>
        )
      })}
    </div>
  )
}

/** Select con estética iOS: pastilla redondeada + chevron doble, pero por
 * debajo es un <select> nativo — en el iPhone abre la rueda de Apple. */
export function Select({ className = "", children, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <span className={`relative inline-flex ${className}`}>
      <select
        {...props}
        className="w-full appearance-none bg-surface-2 border border-line rounded-xl pl-4 pr-9 py-2.5 outline-none focus:border-accent transition-colors"
      >
        {children}
      </select>
      <ChevronUpDownIcon
        aria-hidden
        className="w-4 h-4 text-muted absolute right-3 top-1/2 -translate-y-1/2 pointer-events-none"
      />
    </span>
  )
}

export function PageHeader({
  eyebrow,
  title,
  action,
}: {
  eyebrow?: string
  title: ReactNode
  action?: ReactNode
}) {
  return (
    <header className="mb-8 flex items-end justify-between gap-4">
      <div className="min-w-0">
        {eyebrow && (
          <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">{eyebrow}</div>
        )}
        <h1 className="font-display text-4xl lg:text-5xl leading-[1.05] tracking-tight">
          {title}
        </h1>
      </div>
      {action}
    </header>
  )
}

export function IconButton({
  label,
  onClick,
  children,
  spinning = false,
}: {
  label: string
  onClick: () => void
  children: ReactNode
  spinning?: boolean
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className="w-11 h-11 shrink-0 rounded-full border border-line bg-surface flex items-center justify-center text-muted active:scale-90 active:text-ink transition-[transform,color] duration-150"
    >
      <span className={spinning ? "animate-spin [animation-duration:0.8s]" : ""}>{children}</span>
    </button>
  )
}

export function RefreshButton({ onClick, busy }: { onClick: () => void; busy: boolean }) {
  return (
    <IconButton label="Actualizar" onClick={onClick} spinning={busy}>
      <RefreshIcon className="w-5 h-5" />
    </IconButton>
  )
}

export function SkeletonList({ rows = 4, tall = false }: { rows?: number; tall?: boolean }) {
  return (
    <div className="space-y-2" role="status" aria-label="Cargando">
      {Array.from({ length: rows }).map((_, i) => (
        <div
          key={i}
          className={`rounded-2xl bg-surface animate-pulse ${tall ? "h-24" : "h-16"}`}
          style={{ animationDelay: `${i * 120}ms` }}
        />
      ))}
      <span className="sr-only">Cargando…</span>
    </div>
  )
}

export function ErrorCard({ detail, onRetry }: { detail: string; onRetry?: () => void }) {
  return (
    <div className="bg-surface border border-line rounded-2xl p-6">
      <div className="text-accent text-xs uppercase tracking-[0.2em] mb-2">Sin conexión</div>
      <p className="text-muted leading-relaxed break-words">{detail}</p>
      {onRetry && (
        <button
          onClick={onRetry}
          className="mt-4 px-5 py-2.5 rounded-xl border border-line text-sm font-medium active:scale-95 transition-transform"
        >
          Reintentar
        </button>
      )}
    </div>
  )
}

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="px-4 py-10 text-center">
      <div className="font-display text-2xl text-muted">{title}</div>
      {hint && <p className="text-muted/70 text-sm mt-2">{hint}</p>}
    </div>
  )
}
