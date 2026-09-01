import { useState } from "react"
import { api } from "../api"
import { useLoad } from "../hooks"
import { haptic } from "../haptics"
import { ME, myKcalTarget, myProteinTarget } from "../me"
import type { FoodItem } from "../types"
import { PlusIcon, XIcon } from "../components/icons"
import { CoachNote, EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

export default function Macros() {
  const { data, setData, error, reload } = useLoad(() => api.food.day())
  const { data: weights } = useLoad(api.gym.bodyweight)
  const { data: plan } = useLoad(api.diet.plan)

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!data) return <SkeletonList rows={4} />

  // Objetivos automáticos según su peso real y su objetivo actual (me.ts)
  const weight = weights?.[0]?.weight ?? ME.fallbackWeight
  const kcalTarget = myKcalTarget(weight)
  const proteinTarget = myProteinTarget(weight)

  const addItem = (item: FoodItem) =>
    setData((prev) =>
      prev
        ? {
            items: [...prev.items, item],
            total_kcal: prev.total_kcal + item.kcal,
            total_protein: Math.round((prev.total_protein + item.protein) * 10) / 10,
          }
        : prev,
    )

  // Platos de hoy según el plan, para registrar con un toque
  const today = plan?.days.find((d) => d.is_today)
  const quickDishes = today
    ? ([
        ["Desayuno", today.breakfast],
        ["Comida", today.lunch],
        ["Merienda", today.snack],
        ["Cena", today.dinner],
      ] as const)
    : []

  const remove = async (id: number) => {
    await api.food.remove(id)
    setData((prev) => {
      if (!prev) return prev
      const items = prev.items.filter((i) => i.id !== id)
      return {
        items,
        total_kcal: items.reduce((a, i) => a + i.kcal, 0),
        total_protein: Math.round(items.reduce((a, i) => a + i.protein, 0) * 10) / 10,
      }
    })
  }

  return (
    <div>
      <PageHeader eyebrow={`Nutrición · hoy · objetivo ${ME.goal.toLowerCase()}`} title="Macros" />

      <div className="mb-6">
        <MacroBar label="Calorías" value={data.total_kcal} target={kcalTarget} unit="kcal" />
        <MacroBar label="Proteína" value={data.total_protein} target={proteinTarget} unit="g" />
      </div>

      {data.items.length > 0 && (
        <CoachNote
          fetcher={() =>
            api.ai.macros(data.total_kcal, kcalTarget, data.total_protein, proteinTarget)
          }
        />
      )}

      {quickDishes.length > 0 && plan && (
        <div className="mb-4">
          <div className="text-muted text-xs uppercase tracking-[0.15em] mb-2">Platos de hoy</div>
          <div className="grid grid-cols-2 gap-2">
            {quickDishes.map(([meal, dish]) => {
              const m = plan.macros[dish]
              return (
                <button
                  key={meal}
                  onClick={async () => {
                    haptic("medium")
                    addItem(await api.diet.logMeal(dish))
                  }}
                  className="text-left px-3 py-2.5 rounded-xl border border-line bg-surface-2/40 active:scale-[0.98] transition-transform"
                >
                  <div className="text-muted text-[10px] uppercase tracking-[0.12em]">{meal}</div>
                  <div className="font-medium text-sm truncate">{dish}</div>
                  {m && <div className="text-muted text-xs tnum">{m.kcal} kcal · {m.protein} g</div>}
                </button>
              )
            })}
          </div>
        </div>
      )}

      <AddFood onAdded={addItem} />

      {data.items.length === 0 ? (
        <EmptyState title="Nada apuntado hoy" hint="Añade lo que comas: nombre, kcal y proteína." />
      ) : (
        <div className="space-y-1 mt-6">
          {data.items.map((i) => (
            <div key={i.id} className="flex items-center justify-between gap-3 px-1 py-2">
              <div className="min-w-0">
                <div className="font-medium truncate">{i.name}</div>
                <div className="text-muted text-sm tnum">
                  {i.kcal} kcal · {i.protein} g proteína
                </div>
              </div>
              <button
                onClick={() => remove(i.id)}
                aria-label={`Borrar ${i.name}`}
                className="w-10 h-10 shrink-0 rounded-full flex items-center justify-center text-muted/60 active:text-danger"
              >
                <XIcon className="w-4 h-4" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function MacroBar({
  label,
  value,
  target,
  unit,
}: {
  label: string
  value: number
  target: number
  unit: string
}) {
  const pct = Math.min(100, (value / target) * 100)
  const over = value > target
  return (
    <div className="mb-3">
      <div className="flex items-baseline justify-between mb-1">
        <span className="text-sm text-muted">{label}</span>
        <span className="text-sm tnum">
          <span className={over ? "text-danger font-semibold" : "font-semibold"}>{fmtN(value)}</span>
          <span className="text-muted"> / {fmtN(target)} {unit}</span>
        </span>
      </div>
      <div
        className="h-2.5 rounded-full bg-surface-2 overflow-hidden"
        role="progressbar"
        aria-valuenow={Math.round(value)}
        aria-valuemin={0}
        aria-valuemax={target}
        aria-label={label}
      >
        <div
          className={`h-full rounded-full ${over ? "bg-danger" : "bg-accent"}`}
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  )
}

function AddFood({ onAdded }: { onAdded: (item: { id: number; at: string; name: string; kcal: number; protein: number }) => void }) {
  const [name, setName] = useState("")
  const [kcal, setKcal] = useState("")
  const [protein, setProtein] = useState("")
  const [saving, setSaving] = useState(false)

  const valid = name.trim().length > 0 && Number.isFinite(parseInt(kcal, 10))

  const submit = async () => {
    if (!valid || saving) return
    setSaving(true)
    try {
      const item = await api.food.add({
        name: name.trim(),
        kcal: parseInt(kcal, 10) || 0,
        protein: parseFloat(protein.replace(",", ".")) || 0,
      })
      onAdded(item)
      setName("")
      setKcal("")
      setProtein("")
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="p-4 rounded-2xl border border-line bg-surface/50">
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Qué has comido"
        aria-label="Comida"
        className="w-full bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent mb-2"
      />
      <div className="flex items-center gap-2">
        <input
          type="text"
          inputMode="numeric"
          value={kcal}
          onChange={(e) => setKcal(e.target.value)}
          placeholder="kcal"
          aria-label="Calorías"
          className="flex-1 bg-surface-2 border border-line rounded-xl px-3 py-2.5 outline-none focus:border-accent text-center tnum"
        />
        <input
          type="text"
          inputMode="decimal"
          value={protein}
          onChange={(e) => setProtein(e.target.value)}
          placeholder="g prot"
          aria-label="Proteína en gramos"
          className="flex-1 bg-surface-2 border border-line rounded-xl px-3 py-2.5 outline-none focus:border-accent text-center tnum"
        />
        <button
          onClick={submit}
          disabled={!valid || saving}
          aria-label="Añadir comida"
          className="w-11 h-11 shrink-0 rounded-full bg-accent text-accent-ink flex items-center justify-center active:scale-90 transition-transform disabled:opacity-40"
        >
          <PlusIcon className="w-5 h-5" />
        </button>
      </div>
    </div>
  )
}

function fmtN(n: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 }).format(n)
}
