import { useEffect, useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { Category, Habit, ScheduleType, WeekSchedule } from "../types"
import { CATEGORY_LABELS } from "../types"
import {
  FlameIcon,
  PauseIcon,
  PencilIcon,
  PlayIcon,
  PlusIcon,
  TrashIcon,
  XIcon,
} from "../components/icons"
import { EmptyState, ErrorCard, PageHeader, Select, SkeletonList } from "../components/ui"

export default function Habits({
  categories,
  title,
  singular,
}: {
  categories: Category[]
  title: string
  singular: string
}) {
  const { data: habits, error, reload } = useLoad(api.habits)
  const [editing, setEditing] = useState<Habit | null>(null)
  const [creating, setCreating] = useState(false)

  const remove = async (id: number) => {
    await api.remove(id)
    reload()
  }

  const toggleActive = async (h: Habit) => {
    await api.update(h.id, { active: !h.active })
    reload()
  }

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!habits) return <SkeletonList rows={5} tall />

  const filtered = habits.filter((h) => categories.includes(h.category))

  return (
    <div>
      <PageHeader
        title={title}
        action={
          <button
            onClick={() => setCreating(true)}
            className="bg-accent text-accent-ink h-11 px-4 rounded-full font-medium flex items-center gap-1.5 active:scale-95 transition-transform shrink-0"
          >
            <PlusIcon className="w-4 h-4" />
            Nueva
          </button>
        }
      />

      {filtered.length === 0 && (
        <EmptyState title={`Sin ${singular}s todavía`} hint={`Crea la primera con "Nueva".`} />
      )}

      <div className="space-y-2">
        {filtered.map((h) => (
          <div
            key={h.id}
            className={`px-4 py-3.5 rounded-2xl border border-line bg-surface/50 transition-opacity ${
              h.active ? "" : "opacity-45"
            }`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="text-xs text-muted uppercase tracking-[0.15em]">
                  {CATEGORY_LABELS[h.category]}
                  {!h.active && <> · pausada</>}
                </div>
                <div className="font-display text-xl leading-snug">{h.name}</div>
                <div className="text-muted text-sm mt-0.5">{scheduleSummary(h)}</div>
              </div>
              {h.streak > 0 && (
                <div className="flex items-center gap-1 text-accent shrink-0 mt-1" title={`Racha de ${h.streak} días`}>
                  <FlameIcon className="w-4 h-4" />
                  <span className="text-sm font-semibold tnum">{h.streak}</span>
                </div>
              )}
            </div>
            <div className="flex items-center justify-end gap-1 mt-2 -mb-1 -mr-2">
              <ActionButton
                label={h.active ? "Pausar" : "Activar"}
                onClick={() => toggleActive(h)}
              >
                {h.active ? <PauseIcon className="w-5 h-5" /> : <PlayIcon className="w-5 h-5" />}
              </ActionButton>
              <ActionButton label="Editar" onClick={() => setEditing(h)}>
                <PencilIcon className="w-5 h-5" />
              </ActionButton>
              <DeleteButton onConfirm={() => remove(h.id)} />
            </div>
          </div>
        ))}
      </div>

      <HabitSheet
        open={creating || editing !== null}
        habit={editing}
        categories={categories}
        singular={singular}
        onClose={() => {
          setCreating(false)
          setEditing(null)
        }}
        onSaved={() => {
          setCreating(false)
          setEditing(null)
          reload()
        }}
      />
    </div>
  )
}

function ActionButton({
  label,
  onClick,
  children,
}: {
  label: string
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      title={label}
      className="w-11 h-11 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
    >
      {children}
    </button>
  )
}

/** Borrado en dos toques: el primero arma, el segundo confirma. */
function DeleteButton({ onConfirm }: { onConfirm: () => void }) {
  const [armed, setArmed] = useState(false)

  useEffect(() => {
    if (!armed) return
    const t = setTimeout(() => setArmed(false), 3000)
    return () => clearTimeout(t)
  }, [armed])

  if (armed) {
    return (
      <button
        onClick={onConfirm}
        className="h-11 px-4 rounded-full bg-danger/15 text-danger text-sm font-semibold active:scale-95 transition-transform"
      >
        ¿Borrar?
      </button>
    )
  }
  return (
    <ActionButton label="Borrar" onClick={() => setArmed(true)}>
      <TrashIcon className="w-5 h-5" />
    </ActionButton>
  )
}

function HabitSheet({
  open,
  habit,
  categories,
  singular,
  onClose,
  onSaved,
}: {
  open: boolean
  habit: Habit | null
  categories: Category[]
  singular: string
  onClose: () => void
  onSaved: () => void
}) {
  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            className="fixed inset-0 bg-black/60 z-40"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />
          <motion.div
            role="dialog"
            aria-modal="true"
            aria-label={habit ? `Editar ${singular}` : `Nueva ${singular}`}
            className="fixed z-50 inset-x-0 bottom-0 md:inset-x-auto md:left-1/2 md:bottom-auto md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:max-w-md bg-surface border-t md:border border-line rounded-t-3xl md:rounded-3xl max-h-[88dvh] overflow-y-auto overscroll-contain"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 380, damping: 38 }}
          >
            <div aria-hidden className="mx-auto mt-3 h-1 w-10 rounded-full bg-line md:hidden" />
            <HabitForm
              habit={habit}
              categories={categories}
              singular={singular}
              onClose={onClose}
              onSaved={onSaved}
            />
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}

function HabitForm({
  habit,
  categories,
  singular,
  onClose,
  onSaved,
}: {
  habit: Habit | null
  categories: Category[]
  singular: string
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(habit?.name ?? "")
  const [category, setCategory] = useState<Category>(habit?.category ?? categories[0])
  const [scheduleType, setScheduleType] = useState<ScheduleType>(
    habit?.schedule_type ?? "daily_times",
  )
  const [times, setTimes] = useState<string[]>(() => {
    if (habit?.schedule_type === "daily_times") return habit.schedule as string[]
    if (habit?.schedule_type === "week_days") return (habit.schedule as WeekSchedule).times
    return []
  })
  const [days, setDays] = useState<number[]>(
    habit?.schedule_type === "week_days" ? (habit.schedule as WeekSchedule).days : [],
  )
  const [interval, setInterval] = useState<number>(
    habit?.schedule_type === "interval_days" ? (habit.schedule as number) : 1,
  )
  const [newTime, setNewTime] = useState("08:00")
  const [saving, setSaving] = useState(false)

  const valid =
    name.trim().length > 0 &&
    (scheduleType === "interval_days"
      ? interval >= 1
      : scheduleType === "week_days"
        ? days.length > 0 && times.length > 0
        : times.length > 0)

  const addTime = () => {
    if (!times.includes(newTime)) setTimes([...times, newTime].sort())
  }

  const toggleDay = (d: number) => {
    setDays(days.includes(d) ? days.filter((x) => x !== d) : [...days, d].sort())
  }

  const submit = async () => {
    if (!valid || saving) return
    setSaving(true)
    try {
      const schedule =
        scheduleType === "daily_times"
          ? times
          : scheduleType === "week_days"
            ? { days, times }
            : interval
      const data = { name: name.trim(), category, schedule_type: scheduleType, schedule }
      if (habit) await api.update(habit.id, data)
      else await api.create({ ...data, active: true })
      onSaved()
    } finally {
      setSaving(false)
    }
  }

  const inputCls =
    "w-full bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent transition-colors"

  return (
    <div className="p-6 pb-safe">
      <div className="flex items-center justify-between mb-6">
        <h2 className="font-display text-2xl">
          {habit ? `Editar ${singular}` : `Nueva ${singular}`}
        </h2>
        <button
          onClick={onClose}
          aria-label="Cerrar"
          className="w-11 h-11 -mr-2 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
        >
          <XIcon className="w-5 h-5" />
        </button>
      </div>

      <label className="block text-sm text-muted mb-1.5" htmlFor="habit-name">
        Nombre
      </label>
      <input
        id="habit-name"
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder={`Mi ${singular}`}
        className={`${inputCls} mb-5`}
      />

      {categories.length > 1 && (
        <>
          <label className="block text-sm text-muted mb-1.5" htmlFor="habit-cat">
            Categoría
          </label>
          <Select
            id="habit-cat"
            value={category}
            onChange={(e) => setCategory(e.target.value as Category)}
            className="w-full mb-5"
          >
            {categories.map((c) => (
              <option key={c} value={c}>
                {CATEGORY_LABELS[c]}
              </option>
            ))}
          </Select>
        </>
      )}

      <span className="block text-sm text-muted mb-1.5">Repetición</span>
      <div className="grid grid-cols-3 gap-2 mb-5" role="radiogroup" aria-label="Tipo de repetición">
        {(
          [
            ["daily_times", "Cada día"],
            ["week_days", "Días semana"],
            ["interval_days", "Cada N días"],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            role="radio"
            aria-checked={scheduleType === value}
            onClick={() => setScheduleType(value)}
            className={`py-3 rounded-xl border text-sm font-medium transition-colors ${
              scheduleType === value
                ? "border-accent text-accent bg-accent/10"
                : "border-line text-muted"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {scheduleType === "week_days" && (
        <div className="mb-5">
          <span className="block text-sm text-muted mb-1.5">Qué días</span>
          <div className="flex gap-1.5" role="group" aria-label="Días de la semana">
            {DAY_LETTERS.map((letter, d) => {
              const on = days.includes(d)
              return (
                <button
                  key={d}
                  onClick={() => toggleDay(d)}
                  aria-pressed={on}
                  aria-label={DAY_NAMES[d]}
                  className={`flex-1 aspect-square max-w-12 rounded-full border text-sm font-semibold transition-colors ${
                    on ? "border-accent bg-accent/15 text-accent" : "border-line text-muted"
                  }`}
                >
                  {letter}
                </button>
              )
            })}
          </div>
        </div>
      )}

      {scheduleType !== "interval_days" ? (
        <div className="mb-5">
          <label className="block text-sm text-muted mb-1.5" htmlFor="habit-time">
            Horarios
          </label>
          {times.length > 0 && (
            <div className="flex flex-wrap gap-2 mb-3">
              {times.map((t) => (
                <span
                  key={t}
                  className="bg-surface-2 border border-line rounded-full pl-3.5 pr-1.5 py-1.5 text-sm flex items-center gap-1 tnum"
                >
                  {t}
                  <button
                    onClick={() => setTimes(times.filter((x) => x !== t))}
                    aria-label={`Quitar ${t}`}
                    className="w-7 h-7 rounded-full flex items-center justify-center text-muted active:text-danger"
                  >
                    <XIcon className="w-3.5 h-3.5" />
                  </button>
                </span>
              ))}
            </div>
          )}
          <div className="flex gap-2">
            <input
              id="habit-time"
              type="time"
              value={newTime}
              onChange={(e) => setNewTime(e.target.value)}
              className="flex-1 bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent"
            />
            <button
              onClick={addTime}
              className="px-5 py-3 rounded-xl border border-line font-medium active:border-accent active:text-accent transition-colors"
            >
              Añadir
            </button>
          </div>
        </div>
      ) : (
        <div className="mb-5">
          <label className="block text-sm text-muted mb-1.5" htmlFor="habit-interval">
            Cada cuántos días
          </label>
          <input
            id="habit-interval"
            type="number"
            inputMode="numeric"
            min={1}
            value={interval}
            onChange={(e) => setInterval(Math.max(1, Number(e.target.value)))}
            className={inputCls}
          />
        </div>
      )}

      <button
        onClick={submit}
        disabled={!valid || saving}
        className="w-full mt-2 py-3.5 rounded-xl bg-accent text-accent-ink font-semibold text-base active:scale-[0.98] transition-transform disabled:opacity-40 disabled:active:scale-100"
      >
        {saving ? "Guardando…" : "Guardar"}
      </button>
    </div>
  )
}

const DAY_LETTERS = ["L", "M", "X", "J", "V", "S", "D"]
const DAY_NAMES = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]

function scheduleSummary(h: Habit) {
  if (h.schedule_type === "daily_times") {
    const times = h.schedule as string[]
    return times.length ? times.join(" · ") : "sin horarios"
  }
  if (h.schedule_type === "week_days") {
    const s = h.schedule as WeekSchedule
    const days = (s.days ?? []).map((d) => DAY_LETTERS[d]).join("·")
    return `${days || "sin días"} a las ${(s.times ?? []).join(", ") || "—"}`
  }
  return `cada ${h.schedule} días`
}
