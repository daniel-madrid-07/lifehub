import { useCallback, useEffect, useRef, useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import type {
  GymPlanItem,
  GymRoutine,
  GymWorkout,
  GymWorkoutSummary,
  WorkoutSummary,
} from "../types"
import { CheckIcon, FlameIcon, XIcon } from "../components/icons"
import { platesPerSide } from "../me"
import { haptic } from "../haptics"
import { CoachNote, EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

const REST_SECONDS = 150 // 2:30 de descanso por defecto

// ── Cola offline: series que no llegaron al servidor (gym sin cobertura) ──
const QUEUE_KEY = "gym_pending_sets"
type QueuedSet = { workoutId: number; exercise_id: number; weight: number; reps: number }

function getQueue(): QueuedSet[] {
  try {
    return JSON.parse(localStorage.getItem(QUEUE_KEY) ?? "[]")
  } catch {
    return []
  }
}

function saveQueue(q: QueuedSet[]) {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(q))
}

function isNetworkError(e: unknown): boolean {
  return (
    e instanceof TypeError ||
    (e instanceof DOMException && (e.name === "AbortError" || e.name === "TimeoutError"))
  )
}

export default function GymTrain() {
  const [workout, setWorkout] = useState<GymWorkout | null>(null)
  const [routines, setRoutines] = useState<GymRoutine[] | null>(null)
  const [history, setHistory] = useState<GymWorkoutSummary[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loaded, setLoaded] = useState(false)
  const [detailId, setDetailId] = useState<number | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try {
      const [active, rs, hs] = await Promise.all([
        api.gym.activeWorkout(),
        api.gym.routines(),
        api.gym.workouts(),
      ])
      setWorkout(active)
      setRoutines(rs)
      setHistory(hs)
      setLoaded(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  if (error) return <ErrorCard detail={error} onRetry={load} />
  if (!loaded) return <SkeletonList rows={4} tall />

  if (workout) {
    return <ActiveWorkout workout={workout} onExit={load} />
  }

  const start = async (routineId: number | null) => {
    haptic("medium")
    try {
      setWorkout(await api.gym.startWorkout(routineId))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }

  // La rutina de hoy primero y destacada; el resto separado por grupo
  const sorted = routines ? [...routines].sort((a, b) => Number(!!b.today) - Number(!!a.today)) : []
  const todayRoutine = sorted.find((r) => r.today)
  const rest = sorted.filter((r) => !r.today)
  const restNormal = rest.filter((r) => r.group !== "verano")
  const restVerano = rest.filter((r) => r.group === "verano")

  return (
    <div>
      <PageHeader eyebrow="Gym" title="Entrenar" />

      {routines && routines.length > 0 ? (
        <div className="mb-8">
          {todayRoutine && (
            <div className="relative overflow-hidden bg-surface border border-accent/50 rounded-3xl p-5 mb-3">
              <div
                aria-hidden
                className="absolute -top-16 -right-16 w-44 h-44 rounded-full bg-accent/10 blur-2xl pointer-events-none"
              />
              <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1.5">Hoy toca</div>
              <div className="font-display text-3xl leading-tight">{todayRoutine.name}</div>
              <div className="text-muted text-sm mt-1">
                {todayRoutine.exercises.length} ejercicios ·{" "}
                {[...new Set(todayRoutine.exercises.map((e) => e.muscle))].slice(0, 3).join(", ")}
              </div>
              <button
                onClick={() => start(todayRoutine.id)}
                className="mt-4 w-full py-3.5 rounded-xl bg-accent text-accent-ink font-semibold text-base active:scale-[0.98] transition-transform"
              >
                Empezar
              </button>
            </div>
          )}

          {(restNormal.length > 0 || restVerano.length > 0) && (
            <>
              {restNormal.length > 0 && (
                <>
                  <div className="text-muted text-xs uppercase tracking-[0.2em] mt-6 mb-2">
                    {todayRoutine ? "Normal" : "Rutinas · Normal"}
                  </div>
                  <div className="space-y-2">
                    {restNormal.map((r) => <RoutineRow key={r.id} r={r} onStart={start} />)}
                  </div>
                </>
              )}
              {restVerano.length > 0 && (
                <>
                  <div className="text-muted text-xs uppercase tracking-[0.2em] mt-6 mb-2">
                    Verano
                  </div>
                  <div className="space-y-2">
                    {restVerano.map((r) => <RoutineRow key={r.id} r={r} onStart={start} />)}
                  </div>
                </>
              )}
            </>
          )}
        </div>
      ) : (
        <EmptyState
          title="Sin rutinas todavía"
          hint="Crea tu rutina en Ajustes › Rutinas de gym."
        />
      )}

      {history.length > 0 && (
        <section className="mt-10">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
            Últimos entrenos
          </div>
          <div className="space-y-1">
            {history.slice(0, 8).map((w) => (
              <button
                key={w.id}
                onClick={() => setDetailId(w.id)}
                className="w-full text-left flex items-center justify-between gap-3 px-3 py-2.5 -mx-3 rounded-xl active:bg-surface transition-colors"
              >
                <div className="min-w-0">
                  <div className="font-medium truncate">{w.routine_name ?? "Libre"}</div>
                  <div className="text-muted text-sm tnum">
                    {fmtDate(w.started_at)} · {w.sets} series · {fmtVol(w.volume)}
                  </div>
                </div>
                <span className="text-muted text-sm tnum shrink-0">{w.duration_min} min</span>
              </button>
            ))}
          </div>
        </section>
      )}

      <WorkoutDetailSheet workoutId={detailId} onClose={() => setDetailId(null)} />
    </div>
  )
}

// ── Detalle de un entreno pasado ───────────────────────────────────────────

function WorkoutDetailSheet({
  workoutId,
  onClose,
}: {
  workoutId: number | null
  onClose: () => void
}) {
  const [detail, setDetail] = useState<GymWorkout | null>(null)

  useEffect(() => {
    setDetail(null)
    if (workoutId != null) {
      api.gym.workout(workoutId).then(setDetail).catch(() => {})
    }
  }, [workoutId])

  return (
    <AnimatePresence>
      {workoutId != null && (
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
            aria-label="Detalle del entreno"
            className="fixed z-50 inset-x-0 bottom-0 md:inset-x-auto md:left-1/2 md:bottom-auto md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:max-w-md bg-surface border-t md:border border-line rounded-t-3xl md:rounded-3xl max-h-[85dvh] overflow-y-auto overscroll-contain"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 380, damping: 38 }}
          >
            <div aria-hidden className="mx-auto mt-3 h-1 w-10 rounded-full bg-line md:hidden" />
            <div className="p-6 pb-safe">
              {!detail ? (
                <SkeletonList rows={3} />
              ) : (
                <>
                  <div className="flex items-center justify-between mb-5">
                    <div>
                      <h2 className="font-display text-2xl">
                        {detail.routine_name ?? "Entrenamiento libre"}
                      </h2>
                      <div className="text-muted text-sm mt-0.5">{fmtDate(detail.started_at)}</div>
                    </div>
                    <button
                      onClick={onClose}
                      aria-label="Cerrar"
                      className="w-11 h-11 -mr-2 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
                    >
                      <XIcon className="w-5 h-5" />
                    </button>
                  </div>
                  <div className="space-y-5">
                    {detail.plan
                      .filter((p) => p.sets.length > 0)
                      .map((p) => (
                        <div key={p.exercise.id}>
                          <div className="font-medium mb-1">{p.exercise.name}</div>
                          <div className="text-muted text-sm space-y-0.5">
                            {p.sets.map((s) => (
                              <div key={s.id} className="tnum">
                                {s.set_number}. {fmtW(s.weight)} kg × {s.reps}
                              </div>
                            ))}
                          </div>
                        </div>
                      ))}
                  </div>
                </>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}

// ── Sesión activa ──────────────────────────────────────────────────────────

function ActiveWorkout({ workout, onExit }: { workout: GymWorkout; onExit: () => void }) {
  const [plan, setPlan] = useState<GymPlanItem[]>(workout.plan)
  const [elapsed, setElapsed] = useState("")
  const [restUntil, setRestUntil] = useState<number | null>(null)
  const [prBanner, setPrBanner] = useState<string | null>(null)
  const [pendingCount, setPendingCount] = useState(getQueue().length)
  const [summary, setSummary] = useState<WorkoutSummary | null>(null)
  const audioRef = useRef<AudioContext | null>(null)

  useEffect(() => {
    const started = new Date(
      workout.started_at.endsWith("Z") ? workout.started_at : workout.started_at + "Z",
    ).getTime()
    const tick = () => {
      const mins = Math.max(0, Math.floor((Date.now() - started) / 60000))
      setElapsed(mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins} min`)
    }
    tick()
    const t = setInterval(tick, 30_000)
    return () => clearInterval(t)
  }, [workout.started_at])

  // Reintenta las series en cola al montar y al recuperar conexión
  const flushQueue = useCallback(async () => {
    let queue = getQueue()
    if (queue.length === 0) return
    for (const item of [...queue]) {
      try {
        await api.gym.addSet(item.workoutId, item)
        queue = queue.filter((x) => x !== item)
        saveQueue(queue)
        setPendingCount(queue.length)
      } catch {
        return // sigue sin red: lo reintentamos luego
      }
    }
    // todo sincronizado: recarga el plan real del servidor
    try {
      const detail = await api.gym.workout(workout.id)
      setPlan(detail.plan)
    } catch {
      /* sin red otra vez: no pasa nada */
    }
  }, [workout.id])

  useEffect(() => {
    flushQueue()
    window.addEventListener("online", flushQueue)
    return () => window.removeEventListener("online", flushQueue)
  }, [flushQueue])

  useEffect(() => {
    if (!prBanner) return
    const t = setTimeout(() => setPrBanner(null), 4000)
    return () => clearTimeout(t)
  }, [prBanner])

  const ensureAudio = () => {
    // creado dentro del gesto del usuario para que iOS permita el pitido luego
    if (!audioRef.current) {
      try {
        audioRef.current = new AudioContext()
      } catch {
        /* sin audio */
      }
    }
    audioRef.current?.resume().catch(() => {})
  }

  const onSetLogged = (pr: string | null | undefined) => {
    ensureAudio()
    setRestUntil(Date.now() + REST_SECONDS * 1000)
    // el tic base ya se dio en el click; aquí solo el refuerzo de PR (Android)
    if (pr === "peso") {
      haptic("success")
      setPrBanner("¡PR! Récord de peso en este ejercicio")
    } else if (pr === "1rm") {
      haptic("success")
      setPrBanner("¡PR! Tu mejor 1RM estimado hasta ahora")
    }
  }

  const volume = plan.reduce(
    (acc, item) => acc + item.sets.reduce((a, s) => a + s.weight * s.reps, 0),
    0,
  )
  const totalSets = plan.reduce((acc, item) => acc + item.sets.length, 0)

  const updateItem = (exerciseId: number, fn: (item: GymPlanItem) => GymPlanItem) => {
    setPlan((prev) => prev.map((p) => (p.exercise.id === exerciseId ? fn(p) : p)))
  }

  // Refs a cada tarjeta para poder desplazarse al siguiente ejercicio
  const cardRefs = useRef<Record<number, HTMLElement | null>>({})
  const registerRef = (id: number, el: HTMLElement | null) => {
    cardRefs.current[id] = el
  }

  // Al completar las series de un ejercicio, baja solo al siguiente sin terminar
  const advanceToNext = (exerciseId: number) => {
    const idx = plan.findIndex((p) => p.exercise.id === exerciseId)
    if (idx === -1) return
    const next = plan.slice(idx + 1).find((p) => p.sets.length < p.target_sets)
    const el = next ? cardRefs.current[next.exercise.id] : null
    if (el) {
      // espera a que aparezca el descanso y se asiente el DOM
      setTimeout(() => el.scrollIntoView({ behavior: "smooth", block: "center" }), 400)
    }
  }

  if (summary) {
    return (
      <WorkoutSummaryView
        summary={summary}
        name={workout.routine_name}
        workoutId={workout.id}
        onClose={onExit}
      />
    )
  }

  return (
    <div>
      <header className="mb-6">
        <div className="text-accent text-xs uppercase tracking-[0.25em] mb-2">
          Entrenando · {elapsed}
        </div>
        <h1 className="font-display text-4xl leading-tight">
          {workout.routine_name ?? "Entrenamiento libre"}
        </h1>
        <p className="text-muted text-sm mt-2 tnum">
          {totalSets} series · {fmtVol(volume)}
          {pendingCount > 0 && (
            <span className="text-accent"> · {pendingCount} sin sincronizar</span>
          )}
        </p>
      </header>

      <AnimatePresence>
        {prBanner && (
          <motion.div
            initial={{ opacity: 0, y: -10, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0 }}
            className="mb-4 px-4 py-3 rounded-2xl bg-accent text-accent-ink font-semibold flex items-center gap-2"
            role="status"
          >
            <FlameIcon className="w-5 h-5" />
            {prBanner}
          </motion.div>
        )}
      </AnimatePresence>

      <div className="space-y-4">
        {plan.map((item) => (
          <ExerciseCard
            key={item.exercise.id}
            item={item}
            workoutId={workout.id}
            onChange={(fn) => updateItem(item.exercise.id, fn)}
            onSetLogged={onSetLogged}
            onQueued={() => setPendingCount(getQueue().length)}
            registerRef={registerRef}
            onAdvance={advanceToNext}
          />
        ))}
      </div>

      <div className="flex gap-2 mt-8">
        <DangerButton
          label="Descartar"
          confirmLabel="¿Descartar?"
          onConfirm={async () => {
            saveQueue([])
            await api.gym.discardWorkout(workout.id)
            onExit()
          }}
        />
        <FinishButton
          disabled={totalSets === 0}
          onConfirm={async () => {
            await flushQueue()
            const result = await api.gym.finishWorkout(workout.id)
            if (result.summary) setSummary(result.summary)
            else onExit()
          }}
        />
      </div>

      {restUntil && (
        <RestBar
          until={restUntil}
          audio={audioRef}
          onAdd={() => setRestUntil((u) => (u ?? Date.now()) + 30_000)}
          onClose={() => setRestUntil(null)}
        />
      )}
    </div>
  )
}

function RestBar({
  until,
  audio,
  onAdd,
  onClose,
}: {
  until: number
  audio: React.RefObject<AudioContext | null>
  onAdd: () => void
  onClose: () => void
}) {
  const [left, setLeft] = useState(() => Math.max(0, until - Date.now()))
  const beeped = useRef(false)

  useEffect(() => {
    beeped.current = false
  }, [until])

  useEffect(() => {
    const t = setInterval(() => {
      const remaining = Math.max(0, until - Date.now())
      setLeft(remaining)
      if (remaining === 0 && !beeped.current) {
        beeped.current = true
        beep(audio.current)
        haptic("heavy") // fin del descanso: pulso fuerte
        setTimeout(onClose, 2500)
      }
    }, 250)
    return () => clearInterval(t)
  }, [until, audio, onClose])

  const secs = Math.ceil(left / 1000)
  const mm = Math.floor(secs / 60)
  const ss = String(secs % 60).padStart(2, "0")
  const done = left === 0

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      role="timer"
      aria-label="Descanso entre series"
      className={`fixed inset-x-4 md:inset-x-auto md:right-8 md:w-72 bottom-[calc(env(safe-area-inset-bottom)+5.75rem)] md:bottom-8 z-30 rounded-2xl border px-4 py-3 flex items-center gap-3 backdrop-blur-xl ${
        done ? "bg-accent text-accent-ink border-accent" : "bg-surface/90 border-line"
      }`}
    >
      <span className="font-display text-2xl tnum w-16">
        {done ? "¡Va!" : `${mm}:${ss}`}
      </span>
      <span className={`flex-1 text-sm ${done ? "" : "text-muted"}`}>
        {done ? "Siguiente serie" : "descanso"}
      </span>
      {!done && (
        <button
          onClick={onAdd}
          className="px-3 py-1.5 rounded-full border border-line text-sm font-medium active:border-accent active:text-accent"
        >
          +30s
        </button>
      )}
      <button
        onClick={onClose}
        aria-label="Cerrar temporizador"
        className="w-9 h-9 rounded-full flex items-center justify-center active:scale-90 transition-transform"
      >
        <XIcon className="w-4 h-4" />
      </button>
    </motion.div>
  )
}

function beep(ctx: AudioContext | null) {
  if (!ctx) return
  try {
    for (const delay of [0, 0.25]) {
      const osc = ctx.createOscillator()
      const gain = ctx.createGain()
      osc.connect(gain)
      gain.connect(ctx.destination)
      osc.frequency.value = 880
      gain.gain.setValueAtTime(0.25, ctx.currentTime + delay)
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + delay + 0.18)
      osc.start(ctx.currentTime + delay)
      osc.stop(ctx.currentTime + delay + 0.2)
    }
  } catch {
    /* sin audio */
  }
}

function ExerciseCard({
  item,
  workoutId,
  onChange,
  onSetLogged,
  onQueued,
  registerRef,
  onAdvance,
}: {
  item: GymPlanItem
  workoutId: number
  onChange: (fn: (item: GymPlanItem) => GymPlanItem) => void
  onSetLogged: (pr: string | null | undefined) => void
  onQueued: () => void
  registerRef: (id: number, el: HTMLElement | null) => void
  onAdvance: (exerciseId: number) => void
}) {
  const rec = item.recommendation
  const lastLogged = item.sets[item.sets.length - 1]
  const [weight, setWeight] = useState<string>(() =>
    lastLogged ? String(lastLogged.weight) : rec.weight != null ? String(rec.weight) : "",
  )
  const [reps, setReps] = useState<string>(() => String(lastLogged ? lastLogged.reps : rec.reps))
  const [saving, setSaving] = useState(false)

  // Calculadora de discos: solo para barra, con el peso escrito
  const parsedW = parseFloat(weight.replace(",", "."))
  const plateHint =
    item.exercise.equipment === "barra" && Number.isFinite(parsedW) && parsedW > 20
      ? platesPerSide(parsedW)
      : null

  const logSet = async () => {
    const w = parseFloat(weight.replace(",", "."))
    const r = parseInt(reps, 10)
    if (!Number.isFinite(w) || w < 0 || !Number.isFinite(r) || r < 1 || saving) return
    haptic("medium") // tic inmediato en el gesto (clave para iOS)
    setSaving(true)
    try {
      const s = await api.gym.addSet(workoutId, {
        exercise_id: item.exercise.id,
        weight: w,
        reps: r,
      })
      onChange((it) => ({ ...it, sets: [...it.sets, s] }))
      onSetLogged(s.pr)
      if (item.sets.length + 1 >= item.target_sets) onAdvance(item.exercise.id)
    } catch (e) {
      if (isNetworkError(e)) {
        // sin cobertura: a la cola y seguimos entrenando
        saveQueue([...getQueue(), { workoutId, exercise_id: item.exercise.id, weight: w, reps: r }])
        onChange((it) => ({
          ...it,
          sets: [
            ...it.sets,
            { id: -Date.now(), exercise_id: item.exercise.id, set_number: it.sets.length + 1, weight: w, reps: r },
          ],
        }))
        onQueued()
        onSetLogged(null)
        if (item.sets.length + 1 >= item.target_sets) onAdvance(item.exercise.id)
      }
    } finally {
      setSaving(false)
    }
  }

  const removeSet = async (setId: number) => {
    if (setId < 0) return // serie en cola offline: se sincronizara tal cual
    await api.gym.deleteSet(workoutId, setId)
    onChange((it) => ({ ...it, sets: it.sets.filter((s) => s.id !== setId) }))
  }

  const done = item.sets.length >= item.target_sets
  const [collapsed, setCollapsed] = useState(false)
  const wasDone = useRef(false)

  // Al completar las series, se colapsa solo (se puede reabrir tocándolo)
  useEffect(() => {
    if (done && !wasDone.current) setCollapsed(true)
    if (!done) setCollapsed(false)
    wasDone.current = done
  }, [done])

  return (
    <motion.section
      layout
      ref={(el: HTMLElement | null) => registerRef(item.exercise.id, el)}
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={`px-4 py-4 rounded-2xl border transition-colors ${
        done ? "border-gain/40 bg-gain/[0.04]" : "border-line bg-surface/50"
      } ${collapsed ? "opacity-80" : ""}`}
      aria-label={item.exercise.name}
    >
      <button
        type="button"
        onClick={() => done && setCollapsed((c) => !c)}
        aria-expanded={!collapsed}
        className={`w-full flex items-baseline justify-between gap-3 text-left ${done ? "" : "cursor-default"}`}
      >
        <div className="font-display text-xl leading-snug">{item.exercise.name}</div>
        <span className={`text-sm tnum shrink-0 flex items-center gap-1 ${done ? "text-gain" : "text-muted"}`}>
          {item.sets.length}/{item.target_sets}
          {done && <CheckIcon className="w-3.5 h-3.5" />}
        </span>
      </button>

      {/* Resumen compacto cuando está colapsado */}
      <AnimatePresence initial={false}>
        {collapsed && (
          <motion.button
            type="button"
            onClick={() => setCollapsed(false)}
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="overflow-hidden w-full text-left"
          >
            <div className="text-muted text-sm tnum pt-1.5">
              {item.sets.map((s) => `${fmtW(s.weight)}×${s.reps}`).join("   ·   ")}
            </div>
          </motion.button>
        )}
      </AnimatePresence>

      {/* Detalle completo (oculto al colapsar) */}
      {!collapsed && (
        <>
      <div className="text-xs text-muted uppercase tracking-[0.12em] mb-2 mt-1">
        {item.exercise.muscle} · objetivo {item.reps_min}–{item.reps_max} repes
      </div>
      {rec.note && <p className="text-sm text-accent/90 mb-3">{rec.note}</p>}
      {item.last.length > 0 && (
        <p className="text-muted text-xs mb-3 tnum">
          Anterior: {item.last.map((s) => `${fmtW(s.weight)}×${s.reps}`).join("  ·  ")}
        </p>
      )}

      {item.sets.length > 0 && (
        <div className="space-y-1 mb-3">
          {item.sets.map((s) => (
            <div key={s.id} className="flex items-center gap-3 text-sm">
              <span className="w-6 text-muted tnum">{s.set_number}</span>
              <span className="flex-1 tnum">
                {fmtW(s.weight)} kg × {s.reps}
                {s.pr && (
                  <span className="ml-2 text-[10px] font-bold uppercase tracking-wider text-accent border border-accent/50 rounded-full px-1.5 py-0.5">
                    PR
                  </span>
                )}
                {s.id < 0 && <span className="ml-2 text-xs text-muted/60">(pendiente)</span>}
              </span>
              <CheckIcon className="w-4 h-4 text-gain" aria-label="Hecha" />
              <button
                onClick={() => removeSet(s.id)}
                aria-label={`Borrar serie ${s.set_number}`}
                className="w-9 h-9 -my-1.5 rounded-full flex items-center justify-center text-muted/60 active:text-danger"
              >
                <XIcon className="w-3.5 h-3.5" />
              </button>
            </div>
          ))}
        </div>
      )}

      {plateHint && (
        <p className="text-muted text-xs mb-2 tnum">
          Por lado:{" "}
          {plateHint.plates.length > 0 ? (
            <span className="text-ink">{plateHint.plates.map((p) => `${p}`).join(" + ")}</span>
          ) : (
            <span className="text-ink">solo barra</span>
          )}
          {plateHint.leftover > 0 && <span className="text-accent"> (+{plateHint.leftover} sin disco)</span>}
        </p>
      )}

      <div className="flex items-center gap-2">
        <div className="flex-1 flex items-center gap-2">
          <input
            type="text"
            inputMode="decimal"
            value={weight}
            onChange={(e) => setWeight(e.target.value)}
            aria-label="Peso en kg"
            placeholder="kg"
            className="w-full bg-surface-2 border border-line rounded-xl px-3 py-2.5 outline-none focus:border-accent text-center tnum"
          />
          <span className="text-muted text-sm shrink-0">×</span>
          <input
            type="text"
            inputMode="numeric"
            value={reps}
            onChange={(e) => setReps(e.target.value)}
            aria-label="Repeticiones"
            placeholder="repes"
            className="w-full bg-surface-2 border border-line rounded-xl px-3 py-2.5 outline-none focus:border-accent text-center tnum"
          />
        </div>
        <button
          onClick={logSet}
          disabled={saving}
          aria-label={`Apuntar serie de ${item.exercise.name}`}
          className="w-12 h-12 shrink-0 rounded-full border-2 border-accent text-accent flex items-center justify-center active:bg-accent active:text-accent-ink transition-colors disabled:opacity-40"
        >
          <CheckIcon className="w-5 h-5" />
        </button>
      </div>
        </>
      )}
    </motion.section>
  )
}

function WorkoutSummaryView({
  summary,
  name,
  workoutId,
  onClose,
}: {
  summary: WorkoutSummary
  name: string | null
  workoutId: number
  onClose: () => void
}) {
  const delta = summary.vs_last?.volume_delta ?? null
  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}>
      <header className="mb-8 text-center">
        <div className="text-accent text-xs uppercase tracking-[0.25em] mb-2">Entreno completado</div>
        <h1 className="font-display text-4xl leading-tight">{name ?? "Entrenamiento libre"}</h1>
      </header>

      <CoachNote fetcher={() => api.ai.workout(workoutId)} />

      <div className="grid grid-cols-3 gap-2 mb-6">
        <SummaryStat label="Volumen" value={`${fmtVol(summary.volume)}`} />
        <SummaryStat label="Series" value={String(summary.sets)} />
        <SummaryStat label="Duración" value={`${summary.duration_min}m`} />
      </div>

      {summary.vs_last && delta != null && (
        <div
          className={`px-4 py-3.5 rounded-2xl border mb-6 ${
            delta >= 0 ? "border-gain/40 bg-gain/5" : "border-line bg-surface/50"
          }`}
        >
          <div className="text-muted text-xs uppercase tracking-[0.15em] mb-1">
            Frente a la última vez
          </div>
          <div className="font-display text-2xl tnum">
            <span className={delta >= 0 ? "text-gain" : "text-danger"}>
              {delta >= 0 ? "+" : "−"}
              {fmtVol(Math.abs(delta))}
            </span>
            <span className="text-muted text-base font-sans"> de volumen</span>
          </div>
        </div>
      )}

      {summary.prs.length > 0 && (
        <div className="mb-6">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
            {summary.prs.length === 1 ? "Récord nuevo" : `${summary.prs.length} récords nuevos`}
          </div>
          <div className="space-y-1.5">
            {summary.prs.map((pr, i) => (
              <div
                key={i}
                className="flex items-center gap-2.5 px-4 py-3 rounded-2xl border border-accent/40 bg-accent/5"
              >
                <FlameIcon className="w-5 h-5 text-accent shrink-0" />
                <span className="flex-1 font-medium">{pr.exercise}</span>
                <span className="text-accent font-semibold tnum">
                  {pr.kind === "peso" ? `${fmtW(pr.value)} kg` : `1RM ${fmtW(pr.value)}`}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      <button
        onClick={onClose}
        className="w-full py-3.5 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform"
      >
        Hecho
      </button>
    </motion.div>
  )
}

function SummaryStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="px-3 py-4 rounded-2xl border border-line bg-surface/50 text-center">
      <div className="font-display text-2xl tnum">{value}</div>
      <div className="text-muted text-xs uppercase tracking-[0.12em] mt-0.5">{label}</div>
    </div>
  )
}

function FinishButton({ disabled, onConfirm }: { disabled: boolean; onConfirm: () => void }) {
  const [armed, setArmed] = useState(false)
  useEffect(() => {
    if (!armed) return
    const t = setTimeout(() => setArmed(false), 3000)
    return () => clearTimeout(t)
  }, [armed])
  return (
    <button
      onClick={() => {
        if (armed) {
          haptic("success")
          onConfirm()
        } else {
          haptic("light")
          setArmed(true)
        }
      }}
      disabled={disabled}
      className={`flex-1 py-3.5 rounded-xl font-semibold active:scale-[0.98] transition-all disabled:opacity-40 ${
        armed ? "bg-gain text-accent-ink" : "bg-accent text-accent-ink"
      }`}
    >
      {armed ? "¿Terminar entreno?" : "Terminar"}
    </button>
  )
}

function DangerButton({
  label,
  confirmLabel,
  onConfirm,
}: {
  label: string
  confirmLabel: string
  onConfirm: () => void
}) {
  const [armed, setArmed] = useState(false)
  useEffect(() => {
    if (!armed) return
    const t = setTimeout(() => setArmed(false), 3000)
    return () => clearTimeout(t)
  }, [armed])
  return (
    <button
      onClick={() => {
        haptic("warning")
        armed ? onConfirm() : setArmed(true)
      }}
      className={`px-5 py-3.5 rounded-xl font-medium transition-colors ${
        armed ? "bg-danger/15 text-danger font-semibold" : "border border-line text-muted"
      }`}
    >
      {armed ? confirmLabel : label}
    </button>
  )
}

function RoutineRow({ r, onStart }: { r: GymRoutine; onStart: (id: number) => void }) {
  return (
    <div className="px-4 py-4 rounded-2xl border border-line bg-surface/50 flex items-center justify-between gap-4">
      <div className="min-w-0">
        <div className="font-display text-xl">{r.name}</div>
        <div className="text-muted text-sm truncate">
          {r.exercises.length} ejercicios ·{" "}
          {[...new Set(r.exercises.map((e) => e.muscle))].slice(0, 3).join(", ")}
        </div>
      </div>
      <button
        onClick={() => onStart(r.id)}
        className="shrink-0 bg-surface-2 border border-line h-11 px-5 rounded-full font-semibold active:scale-95 transition-transform"
      >
        Empezar
      </button>
    </div>
  )
}

function fmtW(w: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 2 }).format(w)
}

function fmtVol(v: number): string {
  return `${new Intl.NumberFormat("es-ES", { maximumFractionDigits: 0 }).format(v)} kg`
}

function fmtDate(iso: string): string {
  const d = new Date(iso.endsWith("Z") ? iso : iso + "Z")
  return d.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" })
}
