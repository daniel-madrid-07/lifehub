import { useEffect, useState } from "react"
import { api } from "../api"
import { useLoad } from "../hooks"
import { enablePush, isSubscribed, pushPermission, pushSupported } from "../push"
import { ROUTINE_CATEGORIES, CATEGORY_LABELS } from "../types"
import CheckButton from "../components/CheckButton"
import {
  CalendarIcon,
  ChecklistIcon,
  CoinsIcon,
  DumbbellIcon,
  PulseIcon,
} from "../components/icons"
import { CoachNote, SkeletonList } from "../components/ui"

export type HomeDest = "routines" | "gym" | "tasks" | "calendar" | "finance"

export default function Home({ onGo }: { onGo: (m: HomeDest) => void }) {
  const { data: habits, setData: setHabits } = useLoad(api.today)

  const dateLabel = new Date().toLocaleDateString("es-ES", {
    weekday: "long",
    day: "numeric",
    month: "long",
  })
  const greeting = (() => {
    const h = new Date().getHours()
    if (h < 6) return "Buenas noches"
    if (h < 14) return "Buenos días"
    if (h < 21) return "Buenas tardes"
    return "Buenas noches"
  })()

  const markDone = async (id: number) => {
    try {
      const updated = await api.done(id)
      setHabits((prev) => (prev ? prev.map((x) => (x.id === id ? updated : x)) : prev))
    } catch {
      /* ignore */
    }
  }

  const routineHabits = (habits ?? []).filter((h) => ROUTINE_CATEGORIES.includes(h.category))
  const pending = routineHabits.filter((h) => h.due_today)
  const doneCount = routineHabits.length - pending.length

  return (
    <div>
      <header className="mb-8">
        <div className="text-muted text-xs uppercase tracking-[0.25em] mb-2">{dateLabel}</div>
        <h1 className="font-display text-4xl lg:text-5xl leading-[1.05] tracking-tight">
          {greeting}.
        </h1>
      </header>

      <CoachNote fetcher={api.ai.today} />

      {/* Rutinas de hoy */}
      <Card icon={PulseIcon} title="Rutinas" onGo={() => onGo("routines")}>
        {!habits ? (
          <SkeletonList rows={2} />
        ) : pending.length === 0 ? (
          <p className="text-muted">
            {routineHabits.length === 0 ? "Nada programado." : "Todo hecho por hoy."}
          </p>
        ) : (
          <>
            <p className="text-muted text-sm mb-3 tnum">
              {doneCount} de {routineHabits.length} al día · quedan {pending.length}
            </p>
            <div className="space-y-1">
              {pending.slice(0, 4).map((h) => (
                <div key={h.id} className="flex items-center justify-between gap-3 py-1.5">
                  <div className="min-w-0">
                    <div className="text-xs text-muted uppercase tracking-[0.12em]">
                      {CATEGORY_LABELS[h.category]}
                      {h.next_time && <> · {h.next_time}</>}
                    </div>
                    <div className="font-medium truncate">{h.name}</div>
                  </div>
                  <CheckButton onClick={() => markDone(h.id)} label={`Marcar ${h.name}`} />
                </div>
              ))}
              {pending.length > 4 && (
                <div className="text-muted text-sm pt-1">+{pending.length - 4} más</div>
              )}
            </div>
          </>
        )}
      </Card>

      <GymCard onGo={() => onGo("gym")} />
      <AgendaCard onGo={() => onGo("calendar")} />
      <TasksCard onGo={() => onGo("tasks")} />
      <MoneyCard onGo={() => onGo("finance")} />
      <PushCard />
    </div>
  )
}

function PushCard() {
  const [state, setState] = useState<"checking" | "off" | "on" | "denied" | "hide">("checking")
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!pushSupported()) {
      setState("hide")
      return
    }
    if (pushPermission() === "denied") {
      setState("denied")
      return
    }
    isSubscribed().then((sub) => setState(sub ? "on" : "off"))
  }, [])

  if (state === "checking" || state === "hide" || state === "on") return null

  const activate = async () => {
    setBusy(true)
    try {
      const r = await enablePush()
      setState(r === "ok" ? "on" : r === "denied" ? "denied" : "hide")
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="mb-4 rounded-3xl border border-accent/40 bg-surface p-5">
      <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1">Notificaciones</div>
      {state === "denied" ? (
        <p className="text-muted leading-relaxed text-sm">
          Las bloqueaste. Para activarlas: Ajustes del iPhone → Life Hub → Notificaciones.
        </p>
      ) : (
        <>
          <p className="text-muted leading-relaxed text-sm mb-3">
            Activa los avisos en este iPhone para recibir recordatorios sin abrir la app.
          </p>
          <button
            onClick={activate}
            disabled={busy}
            className="w-full py-3 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
          >
            {busy ? "Activando…" : "Activar notificaciones"}
          </button>
        </>
      )}
    </section>
  )
}

function Card({
  icon: Icon,
  title,
  onGo,
  children,
}: {
  icon: typeof PulseIcon
  title: string
  onGo: () => void
  children: React.ReactNode
}) {
  return (
    <section className="mb-4 rounded-3xl border border-line bg-surface/50 p-5">
      <button
        onClick={onGo}
        className="w-full flex items-center justify-between gap-3 mb-3 active:opacity-70"
      >
        <span className="flex items-center gap-2.5 text-accent">
          <Icon className="w-5 h-5" />
          <span className="font-display text-xl text-ink">{title}</span>
        </span>
        <span className="text-muted text-sm">Ver ›</span>
      </button>
      {children}
    </section>
  )
}

function GymCard({ onGo }: { onGo: () => void }) {
  const { data: routines } = useLoad(api.gym.routines)
  const today = routines?.find((r) => r.today)
  return (
    <Card icon={DumbbellIcon} title="Gym" onGo={onGo}>
      {!routines ? (
        <SkeletonList rows={1} />
      ) : today ? (
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <div className="text-xs text-accent uppercase tracking-[0.15em]">Hoy toca</div>
            <div className="font-medium text-lg">{today.name}</div>
            <div className="text-muted text-sm truncate">
              {today.exercises.length} ejercicios ·{" "}
              {[...new Set(today.exercises.map((e) => e.muscle))].slice(0, 3).join(", ")}
            </div>
          </div>
          <button
            onClick={onGo}
            className="shrink-0 bg-accent text-accent-ink h-11 px-5 rounded-full font-semibold active:scale-95 transition-transform"
          >
            Empezar
          </button>
        </div>
      ) : (
        <p className="text-muted">Descanso hoy. Buen momento para recuperar.</p>
      )}
    </Card>
  )
}

function AgendaCard({ onGo }: { onGo: () => void }) {
  const { data } = useLoad(api.calendar)
  if (!data) return null
  const events = data.status === "ok" ? data.events ?? [] : []
  if (events.length === 0) return null
  return (
    <Card icon={CalendarIcon} title="Agenda" onGo={onGo}>
      <div className="space-y-2">
        {events.slice(0, 3).map((e, i) => (
          <div key={i} className="flex items-center gap-3">
            <span className="text-accent text-sm tnum w-12 shrink-0">{when(e.start)}</span>
            <span className="truncate">{e.title}</span>
          </div>
        ))}
      </div>
    </Card>
  )
}

function TasksCard({ onGo }: { onGo: () => void }) {
  const { data } = useLoad(api.tasks.list)
  if (!data) return null
  const pending = data.filter((t) => !t.done)
  if (pending.length === 0) return null
  return (
    <Card icon={ChecklistIcon} title="Tareas" onGo={onGo}>
      <div className="space-y-1.5">
        {pending.slice(0, 3).map((t) => (
          <div key={t.id} className="flex items-center gap-2.5">
            <span aria-hidden className="w-1.5 h-1.5 rounded-full bg-accent shrink-0" />
            <span className="truncate">{t.text}</span>
          </div>
        ))}
        {pending.length > 3 && (
          <div className="text-muted text-sm pl-4">+{pending.length - 3} más</div>
        )}
      </div>
    </Card>
  )
}

function MoneyCard({ onGo }: { onGo: () => void }) {
  const { data } = useLoad(api.financeSummary)
  if (!data || data.status !== "ok" || data.total_eur == null) return null
  return (
    <Card icon={CoinsIcon} title="Dinero" onGo={onGo}>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-muted text-sm">Patrimonio total</span>
        <span className="font-display text-2xl tnum">{money(data.total_eur)}</span>
      </div>
    </Card>
  )
}

function when(iso: string | null): string {
  if (!iso) return ""
  if (!iso.includes("T")) return "día"
  return new Date(iso).toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" })
}

function money(n: number): string {
  return new Intl.NumberFormat("es-ES", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  }).format(n)
}
