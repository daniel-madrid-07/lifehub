import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { NoteItem, Task } from "../types"
import { PlusIcon, TrashIcon, XIcon } from "../components/icons"
import { haptic } from "../haptics"
import CheckButton from "../components/CheckButton"
import { EmptyState, ErrorCard, Segmented, SkeletonList } from "../components/ui"

type Tab = "tasks" | "notes"

const TABS: { id: Tab; label: string }[] = [
  { id: "tasks", label: "Tareas" },
  { id: "notes", label: "Notas" },
]

export default function Tasks() {
  const [tab, setTab] = useState<Tab>("tasks")
  return (
    <div>
      <Segmented tabs={TABS} value={tab} onChange={setTab} label="Tareas o notas" layoutId="tasks-pill" />
      {tab === "tasks" ? <TasksList /> : <NotesList />}
    </div>
  )
}

function TasksList() {
  const { data, setData, error, reload } = useLoad(api.tasks.list)
  const [text, setText] = useState("")
  const [due, setDue] = useState("")
  const [saving, setSaving] = useState(false)

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!data) return <SkeletonList rows={5} />

  const add = async () => {
    const t = text.trim()
    if (!t || saving) return
    haptic("light")
    setSaving(true)
    try {
      // la fecha (date input) la mando como ISO de medianoche local
      const dueIso = due ? new Date(due + "T23:59:00").toISOString() : null
      const task = await api.tasks.create(t, dueIso)
      setData((prev) => sortTasks([...(prev ?? []), task]))
      setText("")
      setDue("")
    } finally {
      setSaving(false)
    }
  }

  const toggle = async (task: Task) => {
    const updated = await api.tasks.update(task.id, { done: !task.done })
    setData((prev) => sortTasks((prev ?? []).map((t) => (t.id === task.id ? updated : t))))
  }

  const remove = async (id: number) => {
    await api.tasks.remove(id)
    setData((prev) => (prev ?? []).filter((t) => t.id !== id))
  }

  const pending = data.filter((t) => !t.done)
  const done = data.filter((t) => t.done)

  return (
    <div>
      <header className="mb-6">
        <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">Pendientes sueltos</div>
        <h1 className="font-display text-4xl lg:text-5xl leading-tight tracking-tight">
          {pending.length === 0 ? (
            <>Todo <em className="text-accent">al día.</em></>
          ) : (
            <>
              <span className="text-accent tnum">{pending.length}</span> por hacer
            </>
          )}
        </h1>
      </header>

      <div className="mb-6">
        <div className="flex items-center gap-2">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder="Nueva tarea o proyecto…"
            aria-label="Nueva tarea"
            className="flex-1 bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent"
          />
          <button
            onClick={add}
            disabled={!text.trim() || saving}
            aria-label="Añadir tarea"
            className="w-12 h-12 shrink-0 rounded-full bg-accent text-accent-ink flex items-center justify-center active:scale-90 transition-transform disabled:opacity-40"
          >
            <PlusIcon className="w-5 h-5" />
          </button>
        </div>
        <input
          type="date"
          value={due}
          onChange={(e) => setDue(e.target.value)}
          aria-label="Fecha límite (opcional)"
          className="mt-2 bg-surface-2 border border-line rounded-xl px-4 py-2.5 outline-none focus:border-accent text-sm text-muted"
        />
        <span className="text-muted/60 text-xs ml-2">fecha límite (opcional)</span>
      </div>

      {data.length === 0 && <EmptyState title="Sin tareas" hint="Apunta lo que no quieras olvidar." />}

      <div className="space-y-1">
        <AnimatePresence initial={false}>
          {pending.map((t) => (
            <TaskRow key={t.id} task={t} onToggle={() => toggle(t)} onRemove={() => remove(t.id)} />
          ))}
        </AnimatePresence>
      </div>

      {done.length > 0 && (
        <div className="mt-8">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">Hechas</div>
          <div className="space-y-1">
            <AnimatePresence initial={false}>
              {done.map((t) => (
                <TaskRow key={t.id} task={t} onToggle={() => toggle(t)} onRemove={() => remove(t.id)} />
              ))}
            </AnimatePresence>
          </div>
        </div>
      )}
    </div>
  )
}

function TaskRow({
  task,
  onToggle,
  onRemove,
}: {
  task: Task
  onToggle: () => void
  onRemove: () => void
}) {
  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.97 }}
      className="flex items-center gap-3 px-1 py-2"
    >
      <CheckButton onClick={onToggle} label={task.done ? "Desmarcar" : "Marcar hecha"} />
      <div className="flex-1 min-w-0">
        <div className={task.done ? "line-through text-muted" : ""}>{task.text}</div>
        {task.due && !task.done && <DueLabel due={task.due} />}
      </div>
      <button
        onClick={onRemove}
        aria-label="Borrar tarea"
        className="w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-muted/50 active:text-danger"
      >
        <TrashIcon className="w-4 h-4" />
      </button>
    </motion.div>
  )
}

function NotesList() {
  const { data, setData, error, reload } = useLoad(api.notes.list)
  const [text, setText] = useState("")
  const [saving, setSaving] = useState(false)

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!data) return <SkeletonList rows={4} tall />

  const add = async () => {
    const t = text.trim()
    if (!t || saving) return
    setSaving(true)
    try {
      const note = await api.notes.create(t)
      setData((prev) => [note, ...(prev ?? [])])
      setText("")
    } finally {
      setSaving(false)
    }
  }

  const remove = async (id: number) => {
    await api.notes.remove(id)
    setData((prev) => (prev ?? []).filter((n) => n.id !== id))
  }

  return (
    <div>
      <header className="mb-6">
        <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">Notas y diario</div>
        <h1 className="font-display text-4xl leading-tight tracking-tight">Notas</h1>
      </header>

      <div className="mb-6">
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Escribe algo…"
          aria-label="Nueva nota"
          rows={3}
          className="w-full bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent resize-none"
        />
        <button
          onClick={add}
          disabled={!text.trim() || saving}
          className="mt-2 w-full py-3 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
        >
          Guardar nota
        </button>
      </div>

      {data.length === 0 ? (
        <EmptyState title="Sin notas" hint="Ideas, recordatorios, lo que sea." />
      ) : (
        <div className="space-y-2">
          <AnimatePresence initial={false}>
            {data.map((n) => (
              <NoteCard key={n.id} note={n} onRemove={() => remove(n.id)} />
            ))}
          </AnimatePresence>
        </div>
      )}
    </div>
  )
}

function NoteCard({ note, onRemove }: { note: NoteItem; onRemove: () => void }) {
  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 6 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.97 }}
      className="px-4 py-3 rounded-2xl border border-line bg-surface/50"
    >
      <div className="flex items-start justify-between gap-3">
        <p className="whitespace-pre-wrap leading-relaxed flex-1">{note.text}</p>
        <button
          onClick={onRemove}
          aria-label="Borrar nota"
          className="w-8 h-8 -mt-1 -mr-1 shrink-0 rounded-full flex items-center justify-center text-muted/50 active:text-danger"
        >
          <XIcon className="w-4 h-4" />
        </button>
      </div>
      <div className="text-muted/60 text-xs mt-2 tnum">{fmtDate(note.created_at)}</div>
    </motion.div>
  )
}

function DueLabel({ due }: { due: string }) {
  const d = new Date(due)
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const target = new Date(d)
  target.setHours(0, 0, 0, 0)
  const days = Math.round((target.getTime() - today.getTime()) / 86400000)
  let text: string
  let cls: string
  if (days < 0) {
    text = `atrasada ${-days}d`
    cls = "text-danger"
  } else if (days === 0) {
    text = "hoy"
    cls = "text-danger"
  } else if (days === 1) {
    text = "mañana"
    cls = "text-accent"
  } else if (days <= 3) {
    text = `en ${days} días`
    cls = "text-accent"
  } else {
    text = d.toLocaleDateString("es-ES", { day: "numeric", month: "short" })
    cls = "text-muted"
  }
  return <div className={`text-xs ${cls} tnum`}>Límite: {text}</div>
}

function sortTasks(tasks: Task[]): Task[] {
  return [...tasks].sort((a, b) => {
    if (a.done !== b.done) return a.done ? 1 : -1
    const da = a.due ?? "9999"
    const db = b.due ?? "9999"
    if (da !== db) return da < db ? -1 : 1
    return a.created_at < b.created_at ? -1 : 1
  })
}

function fmtDate(iso: string): string {
  const d = new Date(iso.endsWith("Z") ? iso : iso + "Z")
  return d.toLocaleDateString("es-ES", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" })
}
