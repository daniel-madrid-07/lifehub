import { useState } from "react"
import { motion, AnimatePresence } from "framer-motion"
import { api, getToken } from "../api"
import { useLoad } from "../hooks"
import { useProfile } from "../me"
import type { MeasureEntry, Measures } from "../types"
import { CameraIcon, CheckIcon, PlusIcon, XIcon } from "../components/icons"
import { ErrorCard, PageHeader, SkeletonList } from "../components/ui"

const MEASURE_SITES: { id: string; label: string }[] = [
  { id: "brazo", label: "Brazo" },
  { id: "pecho", label: "Pecho" },
  { id: "cintura", label: "Cintura" },
  { id: "pierna", label: "Pierna" },
]

function activityLabel(factor: number): string {
  if (factor < 1.35) return "sedentario"
  if (factor < 1.55) return "actividad ligera"
  if (factor < 1.75) return "actividad moderada"
  return "muy activo"
}

export default function GymHealth() {
  const { data: weights, error, reload } = useLoad(api.gym.bodyweight)
  const me = useProfile()

  if (error) return <ErrorCard detail={error} onRetry={reload} />
  if (!weights) return <SkeletonList rows={4} tall />

  const latest = weights[0]
  const weight = latest?.weight ?? me.fallbackWeight

  const h = me.heightCm
  const hm = h / 100
  const imc = weight / (hm * hm)
  const imcLabel =
    imc < 18.5 ? "bajo peso" : imc < 25 ? "saludable" : imc < 30 ? "sobrepeso" : "obesidad"
  const bmr = me.bmr
  const tdee = me.tdee
  const kcal = me.kcalTarget
  const protein = me.proteinTarget
  const waterL = (weight * 35) / 1000
  const idealMin = 18.5 * hm * hm
  const idealMax = 24.9 * hm * hm
  const lean = me.bodyFatPct != null ? weight * (1 - me.bodyFatPct / 100) : null
  const ffmi = lean != null ? lean / (hm * hm) + 6.1 * (1.8 - hm) : null

  return (
    <div>
      <PageHeader eyebrow="Gym" title="Salud" />

      <div className="px-4 py-3.5 rounded-2xl border border-line bg-surface/50 mb-2 flex items-baseline justify-between gap-3">
        <div>
          <div className="text-muted text-xs uppercase tracking-[0.15em]">{me.name ?? "Tu perfil"}</div>
          <div className="text-sm text-muted mt-0.5">
            {h} cm{me.age != null ? ` · ${me.age} años` : ""} · {activityLabel(me.activityFactor)}
          </div>
        </div>
        <div className="text-right shrink-0">
          <div className="font-display text-3xl tnum">
            {fmt(weight)} <span className="text-base text-muted">kg</span>
          </div>
          {!latest && (
            <div className="text-muted/60 text-xs">estimado — apunta tu peso en Progreso</div>
          )}
        </div>
      </div>

      <div className="px-4 py-3.5 rounded-2xl border border-accent/40 bg-surface mb-6">
        <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1">
          Objetivo actual: {me.goal}
        </div>
        <p className="text-sm leading-relaxed">
          <span className="font-display text-2xl tnum mr-2">{kcal.toLocaleString("es-ES")} kcal</span>
          <span className="text-muted">
            y {protein} g de proteína al día (TDEE {me.goalKcalDelta >= 0 ? "+" : ""}
            {me.goalKcalDelta}). Es lo que usa Macros automáticamente, recalculado con tu peso.
          </span>
        </p>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Stat label="IMC" value={imc.toFixed(1)} sub={imcLabel} highlight={imcLabel === "saludable"} />
        <Stat label="Peso saludable" value={`${idealMin.toFixed(0)}–${idealMax.toFixed(0)}`} sub="kg (IMC 18,5–25)" />
        <Stat label="Metabolismo basal" value={Math.round(bmr).toLocaleString("es-ES")} sub="kcal/día en reposo" />
        <Stat label="Gasto diario (TDEE)" value={Math.round(tdee).toLocaleString("es-ES")} sub="kcal/día con tu actividad" />
        <Stat label="Proteína" value={`${protein} g`} sub="al día (2 g/kg)" />
        <Stat label="Agua" value={`${waterL.toFixed(1)} L`} sub="al día (35 ml/kg)" />
        {lean != null && (
          <Stat label="Masa magra" value={`${lean.toFixed(1)} kg`} sub={`con ${me.bodyFatPct}% graso`} />
        )}
        {ffmi != null && (
          <Stat
            label="FFMI"
            value={ffmi.toFixed(1)}
            sub={ffmi < 18 ? "principiante" : ffmi < 20 ? "intermedio" : ffmi < 22 ? "avanzado" : "élite"}
          />
        )}
      </div>

      {me.bodyFatPct == null && (
        <p className="text-muted/60 text-xs mt-4">
          Cuando te midas el % graso, dímelo y activo masa magra y FFMI.
        </p>
      )}

      <AppleHealthSection />
      <MeasuresSection />
      <PhotosSection />
    </div>
  )
}

function AppleHealthSection() {
  const { data } = useLoad(api.health)
  if (!data) return null

  const latest = data[data.length - 1]
  const hasData = data.length > 0 && latest

  if (!hasData) {
    return (
      <section className="mt-10 p-4 rounded-2xl border border-line bg-surface/50" aria-label="Apple Health">
        <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">Apple Health</div>
        <p className="text-muted text-sm leading-relaxed">
          Conecta tus pasos, sueño y pulsaciones con un Atajo de iOS (te paso los pasos exactos).
          En cuanto envíe el primer dato, aparecerá aquí.
        </p>
      </section>
    )
  }

  const stepsSeries = data.map((d) => d.steps ?? 0)
  return (
    <section className="mt-10" aria-label="Apple Health">
      <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
        Apple Health · {fmtDay(latest.day)}
      </div>
      <div className="grid grid-cols-2 gap-2">
        {latest.steps != null && (
          <Stat label="Pasos" value={latest.steps.toLocaleString("es-ES")} sub="hoy" />
        )}
        {latest.sleep_hours != null && (
          <Stat label="Sueño" value={`${latest.sleep_hours.toFixed(1)} h`} sub="anoche" />
        )}
        {latest.resting_hr != null && (
          <Stat label="FC reposo" value={`${latest.resting_hr}`} sub="ppm" />
        )}
        {latest.active_kcal != null && (
          <Stat label="Kcal activas" value={latest.active_kcal.toLocaleString("es-ES")} sub="hoy" />
        )}
      </div>
      {stepsSeries.filter((s) => s > 0).length >= 2 && (
        <div className="mt-3">
          <div className="text-muted/70 text-xs mb-1 tnum">Pasos · {data.length} días</div>
          <Sparkline values={stepsSeries} />
        </div>
      )}
    </section>
  )
}

function fmtDay(iso: string): string {
  return new Date(iso + "T12:00").toLocaleDateString("es-ES", { day: "numeric", month: "short" })
}

function Sparkline({ values }: { values: number[] }) {
  const w = 320
  const h = 56
  const pad = 4
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1
  const points = values.map((v, i) => {
    const x = pad + (i / (values.length - 1)) * (w - pad * 2)
    const y = h - pad - ((v - min) / range) * (h - pad * 2)
    return `${x},${y}`
  })
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full h-14" role="img" aria-label="Tendencia">
      <polyline
        points={points.join(" ")}
        fill="none"
        stroke="var(--color-accent)"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function MeasuresSection() {
  const { data, setData } = useLoad(api.gym.measures)

  const onAdded = (site: string, entry: MeasureEntry) => {
    setData((prev) => {
      const next: Measures = { ...(prev ?? {}) }
      next[site] = [entry, ...(next[site] ?? [])]
      return next
    })
  }

  return (
    <section className="mt-10" aria-label="Medidas corporales">
      <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">Medidas (cm)</div>
      <div className="grid grid-cols-2 gap-2">
        {MEASURE_SITES.map((s) => (
          <MeasureCard key={s.id} site={s.id} label={s.label} entries={data?.[s.id] ?? []} onAdded={onAdded} />
        ))}
      </div>
    </section>
  )
}

function MeasureCard({
  site,
  label,
  entries,
  onAdded,
}: {
  site: string
  label: string
  entries: MeasureEntry[]
  onAdded: (site: string, entry: MeasureEntry) => void
}) {
  const [value, setValue] = useState("")
  const [open, setOpen] = useState(false)
  const [saving, setSaving] = useState(false)
  const latest = entries[0]
  const prev = entries[1]
  const delta = latest && prev ? latest.value - prev.value : null

  const submit = async () => {
    const v = parseFloat(value.replace(",", "."))
    if (!Number.isFinite(v) || v <= 5 || saving) return
    setSaving(true)
    try {
      const entry = await api.gym.addMeasure(site, v)
      onAdded(site, { id: entry.id, at: entry.at, value: entry.value })
      setValue("")
      setOpen(false)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="px-4 py-3.5 rounded-2xl border border-line bg-surface/50">
      <div className="flex items-center justify-between">
        <span className="text-muted text-xs uppercase tracking-[0.15em]">{label}</span>
        <button
          onClick={() => setOpen((o) => !o)}
          aria-label={`Apuntar ${label}`}
          className="w-7 h-7 -mr-1 rounded-full flex items-center justify-center text-muted active:text-accent active:scale-90 transition-[transform,color]"
        >
          <PlusIcon className="w-4 h-4" />
        </button>
      </div>
      <div className="font-display text-2xl tnum mt-0.5">
        {latest ? `${fmt(latest.value)}` : "—"}
        {delta != null && delta !== 0 && (
          <span className={`text-xs ml-1.5 ${delta > 0 ? "text-gain" : "text-danger"}`}>
            {delta > 0 ? "+" : "−"}
            {fmt(Math.abs(delta))}
          </span>
        )}
      </div>
      {open && (
        <div className="flex items-center gap-2 mt-2">
          <input
            type="text"
            inputMode="decimal"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && submit()}
            autoFocus
            placeholder="cm"
            aria-label={`${label} en cm`}
            className="w-full bg-surface-2 border border-line rounded-lg px-3 py-2 outline-none focus:border-accent text-center tnum"
          />
          <button
            onClick={submit}
            disabled={saving}
            aria-label="Guardar"
            className="w-9 h-9 shrink-0 rounded-full border border-accent text-accent flex items-center justify-center active:bg-accent active:text-accent-ink transition-colors"
          >
            <CheckIcon className="w-4 h-4" />
          </button>
        </div>
      )}
    </div>
  )
}

function PhotosSection() {
  const { data, setData } = useLoad(api.gym.photos)
  const [uploading, setUploading] = useState(false)
  const token = getToken()

  const onPick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ""
    if (!file) return
    setUploading(true)
    try {
      const photo = await api.gym.uploadPhoto(file)
      setData((prev) => [photo, ...(prev ?? [])])
    } finally {
      setUploading(false)
    }
  }

  const remove = async (id: number) => {
    await api.gym.deletePhoto(id)
    setData((prev) => (prev ?? []).filter((p) => p.id !== id))
  }

  const photos = data ?? []

  return (
    <section className="mt-10" aria-label="Fotos de progreso">
      <div className="flex items-center justify-between mb-3">
        <div className="text-muted text-xs uppercase tracking-[0.2em]">Fotos de progreso</div>
        <label className="text-accent text-sm font-medium flex items-center gap-1.5 active:opacity-70 cursor-pointer">
          <CameraIcon className="w-4 h-4" />
          {uploading ? "Subiendo…" : "Añadir"}
          <input
            type="file"
            accept="image/*"
            capture="environment"
            onChange={onPick}
            disabled={uploading}
            className="hidden"
          />
        </label>
      </div>
      {photos.length === 0 ? (
        <p className="text-muted/60 text-sm">Aún no hay fotos. Hazte una cada mes para comparar.</p>
      ) : (
        <div className="grid grid-cols-3 gap-2">
          <AnimatePresence initial={false}>
            {photos.map((p) => (
              <motion.div
                key={p.id}
                layout
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                className="relative aspect-[3/4] rounded-xl overflow-hidden bg-surface-2"
              >
                <img
                  src={`${p.url}?token=${token}`}
                  alt={`Progreso ${fmtDate(p.at)}`}
                  loading="lazy"
                  className="w-full h-full object-cover"
                />
                <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/70 to-transparent px-2 py-1">
                  <span className="text-[10px] text-white/90 tnum">{fmtDate(p.at)}</span>
                </div>
                <button
                  onClick={() => remove(p.id)}
                  aria-label="Borrar foto"
                  className="absolute top-1 right-1 w-7 h-7 rounded-full bg-black/50 backdrop-blur flex items-center justify-center text-white/90 active:text-danger"
                >
                  <XIcon className="w-3.5 h-3.5" />
                </button>
              </motion.div>
            ))}
          </AnimatePresence>
        </div>
      )}
    </section>
  )
}

function fmtDate(iso: string): string {
  const d = new Date(iso.endsWith("Z") ? iso : iso + "Z")
  return d.toLocaleDateString("es-ES", { day: "numeric", month: "short" })
}

function Stat({
  label,
  value,
  sub,
  highlight,
}: {
  label: string
  value: string
  sub: string
  highlight?: boolean
}) {
  return (
    <div className="px-4 py-3.5 rounded-2xl border border-line bg-surface/50">
      <div className="text-muted text-xs uppercase tracking-[0.15em]">{label}</div>
      <div className={`font-display text-2xl tnum mt-0.5 ${highlight ? "text-gain" : ""}`}>{value}</div>
      <div className="text-muted text-xs mt-0.5">{sub}</div>
    </div>
  )
}

function fmt(n: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 }).format(n)
}
