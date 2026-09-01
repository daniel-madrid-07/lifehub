import { useEffect, useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { GymExercise, GymRoutine, GymRoutineExercise } from "../types"
import { PencilIcon, PlusIcon, TrashIcon, XIcon } from "../components/icons"
import { haptic } from "../haptics"
import ExercisePicker from "../components/ExercisePicker"
import { EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

export default function GymRoutines() {
  const { data: routines, error, reload } = useLoad(api.gym.routines)
  const { data: modeData, reload: reloadMode } = useLoad(api.gym.routineMode)
  const [editing, setEditing] = useState<GymRoutine | null>(null)
  const [creating, setCreating] = useState(false)

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!routines) return <SkeletonList rows={3} tall />

  const remove = async (id: number) => {
    await api.gym.deleteRoutine(id)
    reload()
  }

  const mode = modeData?.mode ?? "normal"
  const switchMode = async (m: string) => {
    if (m === mode) return
    haptic("medium")
    await api.gym.setRoutineMode(m)
    reloadMode()
    reload() // recalcula qué rutina toca hoy
  }

  return (
    <div>
      <PageHeader
        eyebrow="Gym"
        title="Rutinas"
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

      <div className="mb-5">
        <div className="text-muted text-xs uppercase tracking-[0.15em] mb-2">Plan activo</div>
        <div className="flex p-1 rounded-full bg-surface border border-line text-sm">
          {([["normal", "Normal"], ["summer", "Verano"]] as const).map(([id, label]) => (
            <button
              key={id}
              onClick={() => switchMode(id)}
              className={`flex-1 py-2 rounded-full font-medium transition-colors ${
                mode === id ? "bg-surface-2 text-accent border border-line" : "text-muted"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        <p className="text-muted text-sm mt-2 leading-relaxed">
          {mode === "summer"
            ? "Verano: Front Day (martes) y Back Day (viernes), 1 serie de todo."
            : "Tu split normal de 5 días."}
        </p>
      </div>

      {routines.length === 0 && (
        <EmptyState
          title="Sin rutinas todavía"
          hint="Crea una con tus ejercicios, series y rango de repes."
        />
      )}

      {(["normal", "verano"] as const).map((group) => {
        const group_routines = routines.filter((r) => (r.group ?? "normal") === group)
        if (group_routines.length === 0) return null
        return (
          <div key={group} className="mb-6">
            <div className="text-muted text-xs uppercase tracking-[0.15em] mb-2">
              {group === "normal" ? "Normal" : "Verano"}
            </div>
            <div className="space-y-2">
              {group_routines.map((r) => (
                <div key={r.id} className="px-4 py-4 rounded-2xl border border-line bg-surface/50">
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="font-display text-xl">{r.name}</div>
                      <div className="text-muted text-sm mt-1 space-y-0.5">
                        {r.exercises.map((e) => (
                          <div key={e.exercise_id} className="truncate tnum">
                            {e.name} — {e.sets}×{e.reps_min}-{e.reps_max}
                          </div>
                        ))}
                      </div>
                    </div>
                    <div className="flex items-center shrink-0 -mr-2">
                      <button
                        onClick={() => setEditing(r)}
                        aria-label={`Editar ${r.name}`}
                        className="w-11 h-11 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
                      >
                        <PencilIcon className="w-5 h-5" />
                      </button>
                      <DeleteButton onConfirm={() => remove(r.id)} />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )
      })}

      <RoutineSheet
        open={creating || editing !== null}
        routine={editing}
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
        className="h-11 px-3 rounded-full bg-danger/15 text-danger text-sm font-semibold active:scale-95 transition-transform"
      >
        ¿Borrar?
      </button>
    )
  }
  return (
    <button
      onClick={() => setArmed(true)}
      aria-label="Borrar rutina"
      className="w-11 h-11 rounded-full flex items-center justify-center text-muted active:scale-90 transition-transform"
    >
      <TrashIcon className="w-5 h-5" />
    </button>
  )
}

function RoutineSheet({
  open,
  routine,
  onClose,
  onSaved,
}: {
  open: boolean
  routine: GymRoutine | null
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
            aria-label={routine ? "Editar rutina" : "Nueva rutina"}
            className="fixed z-50 inset-x-0 bottom-0 md:inset-x-auto md:left-1/2 md:bottom-auto md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:max-w-md bg-surface border-t md:border border-line rounded-t-3xl md:rounded-3xl max-h-[88dvh] overflow-y-auto overscroll-contain"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 380, damping: 38 }}
          >
            <div aria-hidden className="mx-auto mt-3 h-1 w-10 rounded-full bg-line md:hidden" />
            <RoutineForm routine={routine} onClose={onClose} onSaved={onSaved} />
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}

function RoutineForm({
  routine,
  onClose,
  onSaved,
}: {
  routine: GymRoutine | null
  onClose: () => void
  onSaved: () => void
}) {
  const [name, setName] = useState(routine?.name ?? "")
  const [items, setItems] = useState<GymRoutineExercise[]>(routine?.exercises ?? [])
  const [exercises, setExercises] = useState<GymExercise[]>([])
  const [picking, setPicking] = useState(false)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    api.gym.exercises().then(setExercises)
  }, [])

  const addExercise = (ex: GymExercise) => {
    setPicking(false)
    if (items.some((i) => i.exercise_id === ex.id)) return
    setItems([
      ...items,
      {
        exercise_id: ex.id,
        name: ex.name,
        muscle: ex.muscle,
        equipment: ex.equipment,
        sets: 2,
        reps_min: 6,
        reps_max: 8,
      },
    ])
  }

  const updateItem = (exerciseId: number, patch: Partial<GymRoutineExercise>) => {
    setItems(items.map((i) => (i.exercise_id === exerciseId ? { ...i, ...patch } : i)))
  }

  const valid = name.trim().length > 0 && items.length > 0

  const submit = async () => {
    if (!valid || saving) return
    setSaving(true)
    try {
      const payload = {
        name: name.trim(),
        exercises: items.map((i) => ({
          exercise_id: i.exercise_id,
          sets: i.sets,
          reps_min: i.reps_min,
          reps_max: i.reps_max,
        })),
      }
      if (routine) await api.gym.updateRoutine(routine.id, payload)
      else await api.gym.createRoutine(payload)
      onSaved()
    } finally {
      setSaving(false)
    }
  }

  const numCls =
    "w-14 bg-surface-2 border border-line rounded-lg px-1 py-2 outline-none focus:border-accent text-center tnum"

  return (
    <div className="p-6 pb-safe">
      <div className="flex items-center justify-between mb-6">
        <h2 className="font-display text-2xl">{routine ? "Editar rutina" : "Nueva rutina"}</h2>
        <button
          onClick={onClose}
          aria-label="Cerrar"
          className="w-11 h-11 -mr-2 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
        >
          <XIcon className="w-5 h-5" />
        </button>
      </div>

      <label className="block text-sm text-muted mb-1.5" htmlFor="routine-name">
        Nombre
      </label>
      <input
        id="routine-name"
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Push, Pull, Pierna…"
        className="w-full bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent mb-5"
      />

      <span className="block text-sm text-muted mb-1.5">
        Ejercicios <span className="text-muted/60">(series × repes mín–máx)</span>
      </span>
      <div className="space-y-2 mb-3">
        {items.map((i) => (
          <div key={i.exercise_id} className="p-3 rounded-xl border border-line bg-surface-2/40">
            <div className="flex items-center justify-between gap-2 mb-2">
              <div className="min-w-0">
                <div className="font-medium truncate">{i.name}</div>
                <div className="text-muted text-xs uppercase tracking-[0.12em]">{i.muscle}</div>
              </div>
              <button
                onClick={() => setItems(items.filter((x) => x.exercise_id !== i.exercise_id))}
                aria-label={`Quitar ${i.name}`}
                className="w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-muted active:text-danger"
              >
                <XIcon className="w-4 h-4" />
              </button>
            </div>
            <div className="flex items-center gap-2 text-sm text-muted">
              <input
                type="number"
                inputMode="numeric"
                min={1}
                value={i.sets}
                onChange={(e) => updateItem(i.exercise_id, { sets: clamp(e.target.value, 1, 12) })}
                aria-label="Series"
                className={numCls}
              />
              <span>×</span>
              <input
                type="number"
                inputMode="numeric"
                min={1}
                value={i.reps_min}
                onChange={(e) =>
                  updateItem(i.exercise_id, { reps_min: clamp(e.target.value, 1, 100) })
                }
                aria-label="Repes mínimas"
                className={numCls}
              />
              <span>–</span>
              <input
                type="number"
                inputMode="numeric"
                min={1}
                value={i.reps_max}
                onChange={(e) =>
                  updateItem(i.exercise_id, { reps_max: clamp(e.target.value, 1, 100) })
                }
                aria-label="Repes máximas"
                className={numCls}
              />
              <span className="text-xs">repes</span>
            </div>
          </div>
        ))}
      </div>

      <button
        onClick={() => setPicking(true)}
        className="w-full py-3 rounded-xl border border-dashed border-line text-muted font-medium flex items-center justify-center gap-2 active:text-accent active:border-accent transition-colors"
      >
        <PlusIcon className="w-4 h-4" />
        Añadir ejercicio
      </button>

      <button
        onClick={submit}
        disabled={!valid || saving}
        className="w-full mt-5 py-3.5 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
      >
        {saving ? "Guardando…" : "Guardar"}
      </button>

      <ExercisePicker
        open={picking}
        exercises={exercises}
        onClose={() => setPicking(false)}
        onSelect={addExercise}
        onCreated={(ex) => setExercises((prev) => [...prev, ex])}
      />
    </div>
  )
}

function clamp(value: string, min: number, max: number): number {
  const n = parseInt(value, 10)
  if (!Number.isFinite(n)) return min
  return Math.min(max, Math.max(min, n))
}
