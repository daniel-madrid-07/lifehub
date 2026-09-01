import { useMemo, useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import type { GymExercise } from "../types"
import { PlusIcon, XIcon } from "./icons"
import { Select } from "./ui"

export const MUSCLES = ["Pecho", "Espalda", "Hombros", "Biceps", "Triceps", "Pierna", "Core", "Cardio"]
export const EQUIPMENT = ["barra", "mancuernas", "maquina", "polea", "peso corporal"]

const EQUIPMENT_LABELS: Record<string, string> = {
  barra: "Barra",
  mancuernas: "Mancuernas",
  maquina: "Máquina",
  polea: "Polea",
  "peso corporal": "Peso corporal",
}

export default function ExercisePicker({
  open,
  exercises,
  onSelect,
  onClose,
  onCreated,
}: {
  open: boolean
  exercises: GymExercise[]
  onSelect: (ex: GymExercise) => void
  onClose: () => void
  onCreated: (ex: GymExercise) => void
}) {
  const [query, setQuery] = useState("")
  const [muscle, setMuscle] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [newMuscle, setNewMuscle] = useState(MUSCLES[0])
  const [newEquipment, setNewEquipment] = useState(EQUIPMENT[0])
  const [saving, setSaving] = useState(false)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return exercises.filter(
      (e) =>
        (!muscle || e.muscle === muscle) &&
        (!q || e.name.toLowerCase().includes(q)),
    )
  }, [exercises, query, muscle])

  // Lista seccionada estilo iOS: los primeros 80 agrupados por material
  const groups = useMemo(() => {
    const visible = filtered.slice(0, 80)
    const byEquip = new Map<string, GymExercise[]>()
    for (const e of visible) {
      const list = byEquip.get(e.equipment) ?? []
      list.push(e)
      byEquip.set(e.equipment, list)
    }
    const order = [...EQUIPMENT, ...byEquip.keys()]
    const seen = new Set<string>()
    return order
      .filter((eq) => byEquip.has(eq) && !seen.has(eq) && seen.add(eq))
      .map((eq) => ({ equipment: eq, items: byEquip.get(eq)! }))
  }, [filtered])

  const create = async () => {
    const name = query.trim()
    if (!name || saving) return
    setSaving(true)
    try {
      const ex = await api.gym.createExercise({
        name,
        muscle: newMuscle,
        equipment: newEquipment,
      })
      onCreated(ex)
      onSelect(ex)
      setQuery("")
      setCreating(false)
    } finally {
      setSaving(false)
    }
  }

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
            aria-label="Elegir ejercicio"
            className="fixed z-50 inset-x-0 bottom-0 md:inset-x-auto md:left-1/2 md:bottom-auto md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 md:w-full md:max-w-md bg-surface border-t md:border border-line rounded-t-3xl md:rounded-3xl h-[82dvh] md:h-[70vh] flex flex-col"
            initial={{ y: "100%" }}
            animate={{ y: 0 }}
            exit={{ y: "100%" }}
            transition={{ type: "spring", stiffness: 380, damping: 38 }}
          >
            <div aria-hidden className="mx-auto mt-3 h-1 w-10 rounded-full bg-line md:hidden shrink-0" />
            <div className="p-5 pb-3 shrink-0">
              <div className="flex items-center justify-between mb-4">
                <h2 className="font-display text-2xl">Ejercicios</h2>
                <button
                  onClick={onClose}
                  aria-label="Cerrar"
                  className="w-11 h-11 -mr-2 rounded-full flex items-center justify-center text-muted active:text-ink active:scale-90 transition-[transform,color]"
                >
                  <XIcon className="w-5 h-5" />
                </button>
              </div>
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Buscar…"
                className="w-full bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent mb-3"
              />
              <div className="flex gap-1.5 overflow-x-auto no-scrollbar -mx-5 px-5">
                {[null, ...MUSCLES].map((m) => (
                  <button
                    key={m ?? "all"}
                    onClick={() => setMuscle(m)}
                    className={`shrink-0 px-3.5 py-1.5 rounded-full border text-sm font-medium transition-colors ${
                      muscle === m
                        ? "border-accent text-accent bg-accent/10"
                        : "border-line text-muted"
                    }`}
                  >
                    {m ?? "Todos"}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex-1 overflow-y-auto overscroll-contain px-5 pb-safe">
              {groups.map((group) => (
                <section key={group.equipment}>
                  <div className="sticky top-0 z-10 -mx-5 px-5 py-1.5 bg-surface/95 backdrop-blur-sm flex items-center justify-between">
                    <span className="text-accent text-xs font-semibold uppercase tracking-[0.18em]">
                      {EQUIPMENT_LABELS[group.equipment] ?? group.equipment}
                    </span>
                    <span className="text-muted/50 text-xs tnum">{group.items.length}</span>
                  </div>
                  {group.items.map((e) => (
                    <button
                      key={e.id}
                      onClick={() => onSelect(e)}
                      className="w-full text-left flex items-center justify-between gap-3 px-3 py-3 -mx-3 rounded-xl active:bg-surface-2 transition-colors"
                    >
                      <div className="min-w-0">
                        <div className="font-medium">{e.name}</div>
                        <div className="text-muted text-xs uppercase tracking-[0.12em]">
                          {e.muscle}
                        </div>
                      </div>
                    </button>
                  ))}
                </section>
              ))}

              {filtered.length > 80 && (
                <p className="text-muted/60 text-xs text-center py-2">
                  {filtered.length - 80} más — escribe para afinar la búsqueda
                </p>
              )}

              {filtered.length === 0 && (
                <p className="text-muted/60 text-sm text-center py-6">
                  Nada encontrado. Créalo abajo.
                </p>
              )}

              {!creating ? (
                <button
                  onClick={() => setCreating(true)}
                  className="w-full mt-2 mb-6 py-3 rounded-xl border border-dashed border-line text-muted font-medium flex items-center justify-center gap-2 active:text-accent active:border-accent transition-colors"
                >
                  <PlusIcon className="w-4 h-4" />
                  {query.trim() ? `Crear "${query.trim()}"` : "Crear ejercicio nuevo"}
                </button>
              ) : (
                <div className="mt-2 mb-6 p-4 rounded-2xl border border-line bg-surface-2/50">
                  <div className="text-sm text-muted mb-2">
                    Nuevo: <span className="text-ink font-medium">{query.trim() || "(escribe el nombre arriba)"}</span>
                  </div>
                  <div className="grid grid-cols-2 gap-2 mb-3">
                    <Select
                      value={newMuscle}
                      onChange={(e) => setNewMuscle(e.target.value)}
                      aria-label="Grupo muscular"
                    >
                      {MUSCLES.map((m) => (
                        <option key={m}>{m}</option>
                      ))}
                    </Select>
                    <Select
                      value={newEquipment}
                      onChange={(e) => setNewEquipment(e.target.value)}
                      aria-label="Material"
                    >
                      {EQUIPMENT.map((m) => (
                        <option key={m}>{m}</option>
                      ))}
                    </Select>
                  </div>
                  <button
                    onClick={create}
                    disabled={!query.trim() || saving}
                    className="w-full py-2.5 rounded-xl bg-accent text-accent-ink font-semibold disabled:opacity-40 active:scale-[0.98] transition-transform"
                  >
                    Crear y elegir
                  </button>
                </div>
              )}
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
