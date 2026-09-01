import { useRef } from "react"
import { api } from "../api"
import { useLoad } from "../hooks"
import { CoachNote, EmptyState, ErrorCard, PageHeader, RefreshButton, SkeletonList } from "../components/ui"

export default function Studies() {
  // La carga normal usa la cache diaria del backend (instantanea); el boton
  // de refrescar fuerza una pasada real por el intra (lenta, ~10-20s)
  const forceRef = useRef(false)
  const { data, error, refreshing, reload } = useLoad(() => {
    const force = forceRef.current
    forceRef.current = false
    return api.studies(force)
  })
  const forceReload = () => {
    forceRef.current = true
    reload()
  }

  const header = (
    <PageHeader
      eyebrow="Epitech"
      title="Estudios"
      action={<RefreshButton onClick={forceReload} busy={refreshing} />}
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
        <SkeletonList rows={4} tall />
      </div>
    )

  if (data.status === "error") {
    return (
      <div>
        {header}
        <ErrorCard detail={data.detail ?? "No se pudo cargar el intra."} onRetry={reload} />
      </div>
    )
  }

  const projects = data.projects ?? []
  const activities = data.activities ?? []
  const notes = data.notes ?? []

  return (
    <div>
      {header}

      <CoachNote fetcher={api.ai.studies} />

      {data.fetched_at && (
        <p className="text-muted/60 text-xs -mt-5 mb-6 tnum">
          Actualizado{" "}
          {new Date(data.fetched_at).toLocaleString("es-ES", {
            weekday: "short",
            hour: "2-digit",
            minute: "2-digit",
          })}
        </p>
      )}

      {data.summary && (
        <div className="relative overflow-hidden bg-surface border border-accent/40 rounded-3xl p-5 mb-10">
          <div
            aria-hidden
            className="absolute -top-16 -left-16 w-40 h-40 rounded-full bg-accent/10 blur-2xl pointer-events-none"
          />
          <div className="text-accent text-xs uppercase tracking-[0.2em] mb-2">Resumen</div>
          <p className="leading-relaxed">{data.summary}</p>
        </div>
      )}

      {projects.length > 0 && (
        <section className="mb-10">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
            Proyectos en curso
          </div>
          <div className="space-y-2">
            {projects.map((p, i) => {
              const pct = p.progress != null ? Math.min(100, Number(p.progress)) : null
              return (
                <a
                  key={i}
                  href={p.link ?? undefined}
                  target="_blank"
                  rel="noreferrer"
                  className="block px-4 py-3.5 rounded-2xl border border-line bg-surface/50 active:bg-surface transition-colors"
                >
                  <div className="flex items-center justify-between gap-4">
                    <div className="font-medium leading-snug">{p.title}</div>
                    {pct != null && (
                      <span className="text-sm text-accent font-semibold tnum shrink-0">
                        {pct}%
                      </span>
                    )}
                  </div>
                  {p.deadline && (
                    <div className="text-muted text-sm mt-1">Entrega {p.deadline}</div>
                  )}
                  {pct != null && Number.isFinite(pct) && (
                    <div
                      className="mt-3 h-1.5 rounded-full bg-surface-2 overflow-hidden"
                      role="progressbar"
                      aria-valuenow={pct}
                      aria-valuemin={0}
                      aria-valuemax={100}
                    >
                      <div className="h-full rounded-full bg-accent" style={{ width: `${pct}%` }} />
                    </div>
                  )}
                </a>
              )
            })}
          </div>
        </section>
      )}

      {activities.length > 0 && (
        <section className="mb-10">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
            Próximas actividades
          </div>
          <div className="space-y-1">
            {activities.map((a, i) => (
              <a
                key={i}
                href={a.link ?? undefined}
                target="_blank"
                rel="noreferrer"
                className="flex items-center justify-between gap-4 px-3 py-3 -mx-3 rounded-2xl active:bg-surface transition-colors"
              >
                <div className="min-w-0">
                  {a.module && (
                    <div className="text-xs text-muted uppercase tracking-[0.15em]">{a.module}</div>
                  )}
                  <div className="font-medium leading-snug">{a.title}</div>
                </div>
                <div className="text-right text-sm text-muted shrink-0">
                  {a.start && <div className="tnum">{a.start}</div>}
                  {a.register_deadline && (
                    <div className="text-xs text-muted/70">inscripción: {a.register_deadline}</div>
                  )}
                </div>
              </a>
            ))}
          </div>
        </section>
      )}

      <section>
        <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">Notas recientes</div>
        {notes.length === 0 ? (
          <EmptyState title="Sin notas nuevas" />
        ) : (
          <div className="space-y-1">
            {notes.map((n, i) => (
              <div key={i} className="flex items-center justify-between gap-4 px-1 py-2.5">
                <span className="min-w-0 truncate">{n.title}</span>
                <span className="text-accent font-display text-xl shrink-0 tnum">{n.note}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
