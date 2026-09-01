import { api } from "../api"
import { useLoad } from "../hooks"
import type { CalendarEvent } from "../types"
import { EmptyState, ErrorCard, PageHeader, RefreshButton, SkeletonList } from "../components/ui"

export default function Calendar() {
  const { data, error, refreshing, reload } = useLoad(api.calendar)

  const header = (
    <PageHeader
      eyebrow="iCloud · calendario del iPhone"
      title="Agenda"
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
        <SkeletonList rows={5} />
      </div>
    )

  if (data.status === "error") {
    return (
      <div>
        {header}
        <ErrorCard detail={data.detail ?? "No se pudo cargar el calendario."} onRetry={reload} />
      </div>
    )
  }

  const events = data.events ?? []
  const groups = groupByDay(events)

  return (
    <div>
      {header}

      {events.length === 0 ? (
        <EmptyState title="Agenda despejada" hint="No hay eventos próximos." />
      ) : (
        <div className="space-y-8">
          {groups.map(({ label, items }) => (
            <section key={label} aria-label={label}>
              <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">{label}</div>
              <div className="space-y-1">
                {items.map((e, i) => (
                  <a
                    key={i}
                    href={e.link ?? undefined}
                    target="_blank"
                    rel="noreferrer"
                    className="flex items-center gap-4 px-3 py-3 -mx-3 rounded-2xl active:bg-surface transition-colors"
                  >
                    <div className="w-14 shrink-0 text-right">
                      {isAllDay(e.start) ? (
                        <div className="text-xs text-accent uppercase tracking-wide leading-tight">
                          Todo el día
                        </div>
                      ) : (
                        <>
                          <div className="font-display text-lg text-accent tnum leading-tight">
                            {timeOf(e.start) ?? "—"}
                          </div>
                          {timeOf(e.end) && (
                            <div className="text-xs text-muted/70 tnum">{timeOf(e.end)}</div>
                          )}
                        </>
                      )}
                    </div>
                    <div className="w-px self-stretch bg-line" aria-hidden />
                    <div className="min-w-0">
                      <div className="font-medium leading-snug">{e.title}</div>
                      {e.location && (
                        <div className="text-muted text-sm mt-0.5 truncate">{e.location}</div>
                      )}
                    </div>
                  </a>
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  )
}

function isAllDay(start: string | null): boolean {
  return !!start && !start.includes("T")
}

function timeOf(iso: string | null): string | null {
  if (!iso || isAllDay(iso)) return null
  return new Date(iso).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" })
}

function dayLabel(iso: string | null): string {
  if (!iso) return "Sin fecha"
  const d = isAllDay(iso) ? new Date(iso + "T12:00") : new Date(iso)
  const today = new Date()
  const tomorrow = new Date()
  tomorrow.setDate(today.getDate() + 1)
  const same = (a: Date, b: Date) => a.toDateString() === b.toDateString()
  if (same(d, today)) return "Hoy"
  if (same(d, tomorrow)) return "Mañana"
  return d.toLocaleDateString("es-ES", {
    weekday: "long",
    day: "numeric",
    month: "long",
    ...(d.getFullYear() !== today.getFullYear() && { year: "numeric" }),
  })
}

function groupByDay(events: CalendarEvent[]) {
  const groups: { label: string; items: CalendarEvent[] }[] = []
  for (const e of events) {
    const label = dayLabel(e.start)
    const last = groups[groups.length - 1]
    if (last && last.label === label) last.items.push(e)
    else groups.push({ label, items: [e] })
  }
  return groups
}
