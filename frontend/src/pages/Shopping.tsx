import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { ShopItem } from "../types"
import { haptic } from "../haptics"
import { PlusIcon, TrashIcon } from "../components/icons"
import CheckButton from "../components/CheckButton"
import { EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

export default function Shopping({ editable = false }: { editable?: boolean }) {
  const { data, setData, error, reload } = useLoad(api.shopping.list)
  const [text, setText] = useState("")
  const [saving, setSaving] = useState(false)

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!data) return <SkeletonList rows={5} />

  const add = async () => {
    const t = text.trim()
    if (!t || saving) return
    haptic("light")
    setSaving(true)
    try {
      const item = await api.shopping.add(t)
      setData((prev) => sortItems([...(prev ?? []), item]))
      setText("")
    } finally {
      setSaving(false)
    }
  }

  const toggle = async (item: ShopItem) => {
    const updated = await api.shopping.toggle(item.id)
    setData((prev) => sortItems((prev ?? []).map((i) => (i.id === item.id ? updated : i))))
  }

  const remove = async (id: number) => {
    await api.shopping.remove(id)
    setData((prev) => (prev ?? []).filter((i) => i.id !== id))
  }

  const clearDone = async () => {
    await api.shopping.clearDone()
    setData((prev) => (prev ?? []).filter((i) => !i.done))
  }

  const pending = data.filter((i) => !i.done)
  const done = data.filter((i) => i.done)

  return (
    <div>
      <PageHeader
        eyebrow="Nutrición"
        title="Compra"
        action={
          done.length > 0 ? (
            <button
              onClick={clearDone}
              className="h-11 px-4 rounded-full border border-line text-muted text-sm font-medium active:scale-95 transition-transform"
            >
              Vaciar hechos
            </button>
          ) : undefined
        }
      />

      {editable && (
        <div className="flex items-center gap-2 mb-6">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder="Añadir a la lista…"
            aria-label="Añadir producto"
            className="flex-1 bg-surface-2 border border-line rounded-xl px-4 py-3 outline-none focus:border-accent"
          />
          <button
            onClick={add}
            disabled={!text.trim() || saving}
            aria-label="Añadir"
            className="w-12 h-12 shrink-0 rounded-full bg-accent text-accent-ink flex items-center justify-center active:scale-90 transition-transform disabled:opacity-40"
          >
            <PlusIcon className="w-5 h-5" />
          </button>
        </div>
      )}

      {data.length === 0 && (
        <EmptyState
          title="Lista vacía"
          hint={editable ? "Apunta lo que necesites comprar." : "Genera la compra desde la Dieta."}
        />
      )}

      <div className="space-y-1">
        <AnimatePresence initial={false}>
          {pending.map((i) => (
            <Row
              key={i.id}
              item={i}
              editable={editable}
              onToggle={() => toggle(i)}
              onRemove={() => remove(i.id)}
            />
          ))}
        </AnimatePresence>
      </div>

      {done.length > 0 && (
        <div className="mt-8">
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">En el carro</div>
          <div className="space-y-1">
            <AnimatePresence initial={false}>
              {done.map((i) => (
                <Row
                  key={i.id}
                  item={i}
                  editable={editable}
                  onToggle={() => toggle(i)}
                  onRemove={() => remove(i.id)}
                />
              ))}
            </AnimatePresence>
          </div>
        </div>
      )}
    </div>
  )
}

function Row({
  item,
  editable,
  onToggle,
  onRemove,
}: {
  item: ShopItem
  editable: boolean
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
      <CheckButton onClick={onToggle} label={item.done ? "Quitar del carro" : "Al carro"} />
      <span className={`flex-1 ${item.done ? "line-through text-muted" : ""}`}>{item.text}</span>
      {editable && (
        <button
          onClick={onRemove}
          aria-label="Borrar"
          className="w-9 h-9 shrink-0 rounded-full flex items-center justify-center text-muted/50 active:text-danger"
        >
          <TrashIcon className="w-4 h-4" />
        </button>
      )}
    </motion.div>
  )
}

function sortItems(items: ShopItem[]): ShopItem[] {
  return [...items].sort((a, b) => (a.done === b.done ? 0 : a.done ? 1 : -1))
}
