import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { Category, Habit } from "../types"
import { CATEGORY_LABELS } from "../types"
import CheckButton from "../components/CheckButton"
import { UndoIcon } from "../components/icons"
import { EmptyState, ErrorCard, SkeletonList } from "../components/ui"

export default function Today({ categories }: { categories: Category[] }) {
  const { data: habits, setData, error, reload } = useLoad(api.today)

  const replace = (h: Habit) =>
    setData((prev) => (prev ? prev.map((x) => (x.id === h.id ? h : x)) : prev))

  const markDone = async (id: number) => {
    try {
      replace(await api.done(id))
    } catch {
      reload()
    }
  }

  const undo = async (id: number) => {
    try {
      replace(await api.undo(id))
    } catch {
      reload()
    }
  }

  const dateLabel = new Date().toLocaleDateString("es-ES", {
    weekday: "long",
    day: "numeric",
    month: "long",
  })

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!habits) return <SkeletonList rows={5} />

  const filtered = habits.filter((h) => categories.includes(h.category))
  const pending = filtered.filter((h) => h.due_today)
  const clear = filtered.filter((h) => !h.due_today)
  const featured = pending[0]
  const rest = pending.slice(1)
  const doneCount = filtered.length - pending.length

  if (filtered.length === 0) {
    return (
      <div>
        <Header dateLabel={dateLabel} />
        <EmptyState
          title="Nada programado"
          hint="Crea tu primera rutina desde la pestaña de arriba."
        />
      </div>
    )
  }

  return (
    <div>
      <header className="mb-8 flex items-center justify-between gap-6">
        <div className="min-w-0">
          <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">{dateLabel}</div>
          <h1 className="font-display text-4xl lg:text-5xl leading-[1.05] tracking-tight">
            {pending.length === 0 ? (
              <>
                Todo <em className="text-accent">hecho.</em>
              </>
            ) : (
              <>
                Quedan <span className="text-accent tnum">{pending.length}</span>
              </>
            )}
          </h1>
          <p className="text-muted text-sm mt-2">
            {doneCount} de {filtered.length} al día
          </p>
        </div>
        <ProgressRing done={doneCount} total={filtered.length} />
      </header>

      {featured && (
        <motion.section
          layout
          className="relative overflow-hidden bg-surface border border-line rounded-3xl p-5 mb-6 flex items-center justify-between gap-5"
        >
          <div
            aria-hidden
            className="absolute -top-16 -right-16 w-48 h-48 rounded-full bg-accent/10 blur-2xl pointer-events-none"
          />
          <div className="min-w-0">
            <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1.5">
              {CATEGORY_LABELS[featured.category]}
              {featured.next_time && <> · a las {featured.next_time}</>}
            </div>
            <div className="font-display text-2xl lg:text-3xl leading-tight">{featured.name}</div>
            <div className="text-muted text-sm mt-1">{featured.progress_label}</div>
          </div>
          <CheckButton onClick={() => markDone(featured.id)} label={`Marcar ${featured.name}`} large />
        </motion.section>
      )}

      <div className="space-y-1">
        <AnimatePresence mode="popLayout">
          {rest.map((h) => (
            <motion.div
              key={h.id}
              layout
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.97 }}
              className="flex items-center justify-between gap-4 px-1 py-2"
            >
              <div className="min-w-0">
                <div className="text-xs text-muted uppercase tracking-[0.15em]">
                  {CATEGORY_LABELS[h.category]}
                  {h.next_time && <> · {h.next_time}</>}
                </div>
                <div className="font-medium text-lg truncate">{h.name}</div>
              </div>
              <div className="flex items-center gap-3 shrink-0">
                <span className="text-sm text-muted tnum">{h.progress_label}</span>
                <CheckButton onClick={() => markDone(h.id)} label={`Marcar ${h.name}`} />
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {clear.length > 0 && (
        <section className="mt-10">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">Al día</div>
          <div className="space-y-1">
            <AnimatePresence mode="popLayout">
              {clear.map((h) => (
                <motion.div
                  key={h.id}
                  layout
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="flex items-center justify-between gap-3 px-1 py-2 text-muted"
                >
                  <div className="min-w-0">
                    <span className={h.done_today ? "line-through decoration-line" : ""}>
                      {h.name}
                    </span>
                    <span className="text-xs ml-2 tnum">
                      {h.progress_label}
                      {h.streak > 0 && <> · racha {h.streak}</>}
                    </span>
                  </div>
                  {h.done_today && (
                    <button
                      onClick={() => undo(h.id)}
                      aria-label={`Deshacer ${h.name}`}
                      title="Deshacer"
                      className="w-11 h-11 shrink-0 rounded-full flex items-center justify-center text-muted/70 active:text-accent active:scale-90 transition-[transform,color]"
                    >
                      <UndoIcon className="w-5 h-5" />
                    </button>
                  )}
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </section>
      )}
    </div>
  )
}

function Header({ dateLabel }: { dateLabel: string }) {
  return (
    <header className="mb-8">
      <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">{dateLabel}</div>
      <h1 className="font-display text-4xl lg:text-5xl leading-tight">Hoy</h1>
    </header>
  )
}

function ProgressRing({ done, total }: { done: number; total: number }) {
  const r = 34
  const c = 2 * Math.PI * r
  const progress = total ? done / total : 0
  return (
    <svg
      width="84"
      height="84"
      viewBox="0 0 84 84"
      role="img"
      aria-label={`${done} de ${total} al día`}
      className="shrink-0 -rotate-90"
    >
      <circle cx="42" cy="42" r={r} fill="none" stroke="var(--color-surface-2)" strokeWidth="7" />
      <motion.circle
        cx="42"
        cy="42"
        r={r}
        fill="none"
        stroke="var(--color-accent)"
        strokeWidth="7"
        strokeLinecap="round"
        strokeDasharray={c}
        initial={{ strokeDashoffset: c }}
        animate={{ strokeDashoffset: c * (1 - progress) }}
        transition={{ type: "spring", stiffness: 60, damping: 16 }}
      />
      <text
        x="42"
        y="42"
        textAnchor="middle"
        dominantBaseline="central"
        transform="rotate(90 42 42)"
        className="fill-ink font-display tnum"
        fontSize="20"
      >
        {done}/{total}
      </text>
    </svg>
  )
}
