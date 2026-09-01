import { useCallback, useEffect, useState } from "react"
import { api } from "../api"
import type { Category, Habit, HabitLog, WeekSchedule } from "../types"
import { CATEGORY_LABELS } from "../types"
import { FlameIcon } from "../components/icons"
import { EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

const DAYS = 28
const WEEKDAYS = ["L", "M", "X", "J", "V", "S", "D"]

export default function History({ categories }: { categories: Category[] }) {
  const [habits, setHabits] = useState<Habit[] | null>(null)
  const [logs, setLogs] = useState<Record<number, HabitLog[]>>({})
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const all = await api.habits()
      const filtered = all.filter((h) => categories.includes(h.category))
      const entries = await Promise.all(
        filtered.map(async (h) => [h.id, await api.history(h.id, DAYS + 7)] as const),
      )
      setLogs(Object.fromEntries(entries))
      setHabits(filtered)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [categories])

  useEffect(() => {
    load()
  }, [load])

  if (error) return <ErrorCard detail={error} onRetry={load} />
  if (!habits) return <SkeletonList rows={3} tall />

  return (
    <div>
      <PageHeader title="Historial" eyebrow={`Últimos ${DAYS} días`} />

      {habits.length === 0 && <EmptyState title="Nada que mostrar todavía" />}

      <div className="space-y-10">
        {habits.map((h) => (
          <section key={h.id} aria-label={h.name}>
            <div className="flex items-baseline justify-between mb-3 gap-3">
              <div className="min-w-0">
                <div className="text-xs text-muted uppercase tracking-[0.15em]">
                  {CATEGORY_LABELS[h.category]}
                </div>
                <div className="font-display text-xl truncate">{h.name}</div>
              </div>
              <div className="flex items-center gap-1.5 text-accent shrink-0">
                <FlameIcon className="w-5 h-5" />
                <span className="font-display text-3xl tnum">{h.streak}</span>
                <span className="text-muted text-sm">días</span>
              </div>
            </div>
            <Heatmap logs={logs[h.id] ?? []} perDay={perDay(h)} weekDays={weekDays(h)} />
          </section>
        ))}
      </div>
    </div>
  )
}

function perDay(h: Habit): number {
  if (h.schedule_type === "daily_times") {
    return (h.schedule as string[]).length || 1
  }
  if (h.schedule_type === "week_days") {
    return (h.schedule as WeekSchedule).times?.length || 1
  }
  return 1
}

/** Días programados (0=lunes) o null si aplica todos los días */
function weekDays(h: Habit): number[] | null {
  if (h.schedule_type === "week_days") return (h.schedule as WeekSchedule).days ?? []
  return null
}

function localKey(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

function Heatmap({
  logs,
  perDay,
  weekDays,
}: {
  logs: HabitLog[]
  perDay: number
  weekDays: number[] | null
}) {
  // El backend guarda done_at en UTC sin zona: anclar a UTC y agrupar en hora local
  const counts = new Map<string, number>()
  for (const log of logs) {
    const iso = log.done_at.endsWith("Z") ? log.done_at : log.done_at + "Z"
    const key = localKey(new Date(iso))
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }

  const todayKey = localKey(new Date())
  const cells: { key: string; count: number; rest: boolean }[] = []
  for (let i = DAYS - 1; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    const key = localKey(d)
    const weekday = (d.getDay() + 6) % 7 // lunes=0
    const rest = weekDays !== null && !weekDays.includes(weekday)
    cells.push({ key, count: counts.get(key) ?? 0, rest })
  }

  // Alinear la cuadrícula a la semana (lunes primero)
  const first = new Date()
  first.setDate(first.getDate() - (DAYS - 1))
  const pad = (first.getDay() + 6) % 7

  return (
    <div className="grid grid-cols-7 gap-1.5">
      {WEEKDAYS.map((w) => (
        <div key={w} className="text-center text-[10px] text-muted/70 font-medium" aria-hidden>
          {w}
        </div>
      ))}
      {Array.from({ length: pad }).map((_, i) => (
        <div key={`pad-${i}`} aria-hidden />
      ))}
      {cells.map((c) => {
        const full = c.count >= perDay
        const partial = c.count > 0 && !full
        const label = new Date(c.key + "T12:00").toLocaleDateString("es-ES", {
          weekday: "short",
          day: "numeric",
          month: "short",
        })
        const fill = full
          ? "bg-accent"
          : partial
            ? "bg-accent/35"
            : c.rest
              ? "bg-surface-2/30"
              : "bg-surface-2"
        return (
          <div
            key={c.key}
            role="img"
            aria-label={c.rest && c.count === 0 ? `${label}: descanso` : `${label}: ${c.count} de ${perDay}`}
            title={c.rest && c.count === 0 ? `${label} · descanso` : `${label} · ${c.count}/${perDay}`}
            className={`aspect-square rounded-lg ${fill} ${
              c.key === todayKey ? "outline outline-1 outline-offset-1 outline-accent/60" : ""
            }`}
          />
        )
      })}
    </div>
  )
}
