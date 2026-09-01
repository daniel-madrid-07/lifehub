import { api } from "../api"
import { useLoad } from "../hooks"
import { CoachNote, EmptyState, ErrorCard, PageHeader, RefreshButton, SkeletonList } from "../components/ui"

export default function Mail() {
  const { data, error, refreshing, reload } = useLoad(api.mail)

  const header = (
    <PageHeader
      eyebrow="Gmail · importantes sin leer"
      title="Correo"
      action={<RefreshButton onClick={reload} busy={refreshing} />}
    />
  )

  if (error)
    return (
      <div>
        {header}
        <ErrorCard detail={error} onRetry={reload} />
      </div>
    )
  if (!data)
    return (
      <div>
        {header}
        <SkeletonList rows={5} tall />
      </div>
    )

  if (data.status === "error") {
    return (
      <div>
        {header}
        <ErrorCard detail={data.detail ?? "No se pudo cargar el correo."} onRetry={reload} />
      </div>
    )
  }

  const messages = data.messages ?? []

  return (
    <div>
      {header}

      {messages.length > 0 && <CoachNote fetcher={api.ai.mail} />}

      {messages.length === 0 ? (
        <EmptyState title="Bandeja al día" hint="No hay correos sin leer." />
      ) : (
        <div className="space-y-1">
          {messages.map((m, i) => (
            <a
              key={i}
              href={m.link ?? undefined}
              target="_blank"
              rel="noreferrer"
              className="flex items-start gap-3.5 px-3 py-3.5 -mx-3 rounded-2xl active:bg-surface transition-colors"
            >
              <span
                aria-hidden
                className="w-11 h-11 shrink-0 rounded-full bg-surface-2 border border-line flex items-center justify-center font-display text-lg text-accent"
              >
                {senderName(m.from).charAt(0).toUpperCase() || "@"}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-baseline justify-between gap-3">
                  <span className="text-sm text-muted truncate">{senderName(m.from)}</span>
                  {m.date && (
                    <span className="text-xs text-muted/70 shrink-0 tnum">{relDate(m.date)}</span>
                  )}
                </div>
                <div className="font-medium leading-snug mt-0.5">{m.subject}</div>
                <p className="text-muted text-sm mt-0.5 line-clamp-2">{decodeEntities(m.snippet)}</p>
              </div>
            </a>
          ))}
        </div>
      )}
    </div>
  )
}

/** Gmail devuelve el snippet con entidades HTML escapadas */
function decodeEntities(s: string): string {
  const el = document.createElement("textarea")
  el.innerHTML = s
  return el.value
}

/** `"Nombre" <correo@x>` → `Nombre` */
function senderName(from: string): string {
  const name = from.replace(/<[^>]*>/g, "").replace(/"/g, "").trim()
  return name || from.replace(/[<>]/g, "")
}

/** internalDate de Gmail viene en ms desde epoch (string) */
function relDate(ms: string): string {
  const t = Number(ms)
  if (!Number.isFinite(t)) return ""
  const mins = Math.floor((Date.now() - t) / 60000)
  if (mins < 1) return "ahora"
  if (mins < 60) return `hace ${mins} min`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `hace ${hours} h`
  if (hours < 48) return "ayer"
  return new Date(t).toLocaleDateString("es-ES", { day: "numeric", month: "short" })
}
