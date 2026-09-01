import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { DietPlan } from "../types"
import { haptic } from "../haptics"
import { ErrorCard, PageHeader, SkeletonList } from "../components/ui"

export default function Diet() {
  const { data, error, reload } = useLoad(api.diet.plan)
  const [open, setOpen] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [added, setAdded] = useState<number | null>(null)
  const [scope, setScope] = useState<"remaining" | "week">("remaining")

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!data) return <SkeletonList rows={5} tall />

  const addWeek = async () => {
    if (adding) return
    haptic("medium")
    setAdding(true)
    try {
      const r = await api.diet.addWeekToShopping(scope)
      setAdded(r.added)
    } finally {
      setAdding(false)
    }
  }

  const toggle = (dish: string) => {
    haptic("light")
    setOpen((o) => (o === dish ? null : dish))
  }

  return (
    <div>
      <PageHeader eyebrow="Nutrición" title="Dieta" />

      <p className="text-muted text-sm mb-4 leading-relaxed">
        Desayuno y merienda: <span className="text-ink">Yogur con fruta</span> todos los días. Cada
        plato se cocina una vez y rinde la cena de un día y la comida del siguiente.
      </p>

      <div className="flex p-1 rounded-full bg-surface border border-line mb-3 text-sm">
        {([["remaining", "Lo que falta"], ["week", "Semana entera"]] as const).map(([id, label]) => (
          <button
            key={id}
            onClick={() => { haptic("light"); setScope(id); setAdded(null) }}
            className={`flex-1 py-2 rounded-full font-medium transition-colors ${
              scope === id ? "bg-surface-2 text-ink border border-line" : "text-muted"
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <button
        onClick={addWeek}
        disabled={adding}
        className="w-full mb-8 py-3.5 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
      >
        {adding
          ? "Añadiendo…"
          : added != null
            ? `Añadidos ${added} a la compra`
            : scope === "remaining"
              ? "Añadir lo que falta a la compra"
              : "Añadir la semana entera"}
      </button>

      <div className="space-y-2">
        {data.days.map((d) => (
          <div
            key={d.weekday}
            className={`rounded-2xl border p-4 ${
              d.is_today ? "border-accent/50 bg-surface" : "border-line bg-surface/50"
            }`}
          >
            <div className="flex items-center gap-2 mb-2">
              <span className="font-display text-lg">{d.weekday}</span>
              {d.is_today && (
                <span className="text-[10px] uppercase tracking-[0.15em] text-accent border border-accent/50 rounded-full px-2 py-0.5">
                  Hoy
                </span>
              )}
            </div>
            <Meal label="Comida" dish={d.lunch} open={open === d.weekday + "L"} onToggle={() => toggle(d.weekday + "L")} dishes={data.dishes} macros={data.macros} />
            <Meal label="Cena" dish={d.dinner} open={open === d.weekday + "C"} onToggle={() => toggle(d.weekday + "C")} dishes={data.dishes} macros={data.macros} />
          </div>
        ))}
      </div>
    </div>
  )
}

function Meal({
  label,
  dish,
  open,
  onToggle,
  dishes,
  macros,
}: {
  label: string
  dish: string
  open: boolean
  onToggle: () => void
  dishes: DietPlan["dishes"]
  macros: DietPlan["macros"]
}) {
  const ingredients = dishes[dish] ?? []
  const m = macros[dish]
  return (
    <div className="border-t border-line/60 first:border-t-0 py-2">
      <button onClick={onToggle} className="w-full flex items-center justify-between gap-3 text-left">
        <span>
          <span className="text-muted text-xs uppercase tracking-[0.12em] mr-2">{label}</span>
          <span className="font-medium">{dish}</span>
          {m && (
            <span className="text-muted text-xs tnum ml-2 block mt-0.5">
              {m.kcal} kcal · {m.protein} g prot
            </span>
          )}
        </span>
        <span className="text-muted text-xs shrink-0">{open ? "−" : "ver"}</span>
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="overflow-hidden"
          >
            <div className="pt-2 pl-1 space-y-0.5">
              {ingredients.map(([name, qty, unit], i) => (
                <div key={i} className="text-sm text-muted tnum">
                  {name} — {qty}
                  {unit === "u" ? " ud" : " g"}
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
