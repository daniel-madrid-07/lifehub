import { useEffect, useState } from "react"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { GymExercise, GymProgress as Progress } from "../types"
import ExercisePicker from "../components/ExercisePicker"
import { CheckIcon, XIcon } from "../components/icons"
import { EmptyState, ErrorCard, PageHeader, SkeletonList } from "../components/ui"

export default function GymProgress() {
  const [exercises, setExercises] = useState<GymExercise[]>([])
  const [selected, setSelected] = useState<GymExercise | null>(null)
  const [progress, setProgress] = useState<Progress | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [picking, setPicking] = useState(false)

  useEffect(() => {
    api.gym.exercises().then(setExercises).catch((e) => setError(String(e)))
  }, [])

  useEffect(() => {
    if (!selected) return
    setProgress(null)
    setError(null)
    api.gym
      .progress(selected.id)
      .then(setProgress)
      .catch((e) => setError(e instanceof Error ? e.message : String(e)))
  }, [selected])

  return (
    <div>
      <PageHeader eyebrow="Gym" title="Progreso" />

      <WeeklyVolume />
      <BodyWeightCard />

      <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">Por ejercicio</div>
      <button
        onClick={() => setPicking(true)}
        className="w-full mb-6 px-4 py-3.5 rounded-xl border border-line bg-surface-2 text-left flex items-center justify-between gap-3 active:border-accent transition-colors"
      >
        <span className={selected ? "font-medium" : "text-muted"}>
          {selected ? selected.name : "Elige un ejercicio…"}
        </span>
        <span className="text-muted text-sm shrink-0">Cambiar</span>
      </button>

      {!selected && (
        <EmptyState
          title="Tu progreso, por ejercicio"
          hint="Elige un ejercicio para ver PR, 1RM estimado y tus últimas sesiones."
        />
      )}

      {selected && error && <ErrorCard detail={error} />}
      {selected && !error && !progress && <SkeletonList rows={3} tall />}

      {progress && (
        <div>
          {progress.sessions.length === 0 ? (
            <EmptyState
              title="Sin datos todavía"
              hint="Cuando registres series de este ejercicio, aquí verás tu evolución."
            />
          ) : (
            <>
              <div className="grid grid-cols-2 gap-2 mb-6">
                <StatCard label="PR (peso máximo)" value={`${fmt(progress.pr_weight)} kg`} />
                <StatCard label="1RM estimado" value={`${fmt(progress.pr_1rm)} kg`} />
              </div>

              <div className="relative overflow-hidden bg-surface border border-line rounded-2xl p-5 mb-6">
                <div className="text-accent text-xs uppercase tracking-[0.2em] mb-1.5">
                  Próxima sesión
                </div>
                <p className="leading-relaxed text-sm">
                  {progress.recommendation.weight != null && (
                    <span className="font-display text-2xl mr-2 tnum">
                      {fmt(progress.recommendation.weight)} kg × {progress.recommendation.reps}
                    </span>
                  )}
                  <span className="text-muted">{progress.recommendation.note}</span>
                </p>
              </div>

              {progress.sessions.length >= 2 && (
                <div className="mb-6">
                  <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">
                    1RM estimado · últimas {progress.sessions.length} sesiones
                  </div>
                  <Sparkline values={progress.sessions.map((s) => s.est_1rm)} />
                </div>
              )}

              <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">Sesiones</div>
              <div className="space-y-1">
                {[...progress.sessions].reverse().map((s, i) => (
                  <div key={i} className="flex items-center justify-between gap-3 px-1 py-2.5">
                    <div className="min-w-0">
                      <div className="font-medium tnum">
                        {fmt(s.top_weight)} kg × {s.top_reps}
                        <span className="text-muted font-normal"> mejor serie</span>
                      </div>
                      <div className="text-muted text-sm tnum">
                        {fmtDate(s.date)} · {s.sets} series · {fmt(s.volume)} kg vol
                      </div>
                    </div>
                    <span className="text-accent text-sm tnum shrink-0">
                      1RM {fmt(s.est_1rm)}
                    </span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      )}

      <ExercisePicker
        open={picking}
        exercises={exercises}
        onClose={() => setPicking(false)}
        onSelect={(ex) => {
          setSelected(ex)
          setPicking(false)
        }}
        onCreated={(ex) => setExercises((prev) => [...prev, ex])}
      />
    </div>
  )
}

function WeeklyVolume() {
  const { data } = useLoad(api.gym.weeklyStats)
  if (!data || data.muscles.length === 0) return null
  const maxSets = Math.max(...data.muscles.map((m) => m.sets))
  return (
    <section className="mb-6" aria-label="Volumen semanal">
      <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">
        Últimos 7 días · {data.total_sets} series
      </div>
      <div className="space-y-1.5">
        {data.muscles.map((m) => (
          <div key={m.muscle} className="flex items-center gap-3">
            <span className="w-20 text-sm text-muted shrink-0">{m.muscle}</span>
            <div className="flex-1 h-5 rounded-full bg-surface-2 overflow-hidden">
              <div
                className="h-full rounded-full bg-accent/70"
                style={{ width: `${(m.sets / maxSets) * 100}%` }}
              />
            </div>
            <span className="w-14 text-right text-sm tnum text-muted shrink-0">
              {m.sets} ser.
            </span>
          </div>
        ))}
      </div>
    </section>
  )
}

function BodyWeightCard() {
  const { data, setData } = useLoad(api.gym.bodyweight)
  const [value, setValue] = useState("")
  const [saving, setSaving] = useState(false)

  const submit = async () => {
    const w = parseFloat(value.replace(",", "."))
    if (!Number.isFinite(w) || w <= 20 || w >= 400 || saving) return
    setSaving(true)
    try {
      const entry = await api.gym.addBodyweight(w)
      setData((prev) => [entry, ...(prev ?? [])])
      setValue("")
    } finally {
      setSaving(false)
    }
  }

  const entries = data ?? []
  const latest = entries[0]
  const series = [...entries].reverse().map((e) => e.weight)

  return (
    <section className="mb-8 px-4 py-4 rounded-2xl border border-line bg-surface/50" aria-label="Peso corporal">
      <div className="flex items-center justify-between gap-3 mb-3">
        <div>
          <div className="text-muted text-xs uppercase tracking-[0.15em]">Peso corporal</div>
          {latest ? (
            <div className="font-display text-3xl tnum">
              {fmt(latest.weight)} <span className="text-base text-muted">kg</span>
            </div>
          ) : (
            <div className="text-muted text-sm mt-1">Sin registros aún</div>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <input
            type="text"
            inputMode="decimal"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="kg"
            aria-label="Peso de hoy en kg"
            className="w-20 bg-surface-2 border border-line rounded-xl px-3 py-2.5 outline-none focus:border-accent text-center tnum"
          />
          <button
            onClick={submit}
            disabled={saving || !value.trim()}
            aria-label="Apuntar peso"
            className="w-11 h-11 rounded-full border-2 border-accent text-accent flex items-center justify-center active:bg-accent active:text-accent-ink transition-colors disabled:opacity-40"
          >
            <CheckIcon className="w-5 h-5" />
          </button>
        </div>
      </div>
      {series.length >= 2 && <Sparkline values={series} />}
      {entries.length > 0 && (
        <div className="mt-2 flex items-center justify-between text-xs text-muted/70 tnum">
          <span>{fmtDate(entries[entries.length - 1].at)}</span>
          {latest && (
            <button
              onClick={async () => {
                await api.gym.deleteBodyweight(latest.id)
                setData((prev) => (prev ?? []).filter((e) => e.id !== latest.id))
              }}
              className="flex items-center gap-1 active:text-danger"
              aria-label="Borrar último registro de peso"
            >
              <XIcon className="w-3 h-3" /> borrar último
            </button>
          )}
          <span>{fmtDate(entries[0].at)}</span>
        </div>
      )}
    </section>
  )
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="px-4 py-4 rounded-2xl border border-line bg-surface/50">
      <div className="text-muted text-xs uppercase tracking-[0.15em] mb-1">{label}</div>
      <div className="font-display text-3xl tnum">{value}</div>
    </div>
  )
}

function Sparkline({ values }: { values: number[] }) {
  const w = 320
  const h = 72
  const pad = 6
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1
  const points = values.map((v, i) => {
    const x = pad + (i / (values.length - 1)) * (w - pad * 2)
    const y = h - pad - ((v - min) / range) * (h - pad * 2)
    return `${x},${y}`
  })
  return (
    <svg
      viewBox={`0 0 ${w} ${h}`}
      className="w-full h-20"
      role="img"
      aria-label={`Evolución del 1RM estimado de ${fmt(min)} a ${fmt(max)} kg`}
    >
      <polyline
        points={points.join(" ")}
        fill="none"
        stroke="var(--color-accent)"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {points.map((p, i) => {
        const [x, y] = p.split(",").map(Number)
        return <circle key={i} cx={x} cy={y} r="3" fill="var(--color-accent)" />
      })}
    </svg>
  )
}

function fmt(n: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 }).format(n)
}

function fmtDate(iso: string): string {
  const d = new Date(iso.endsWith("Z") ? iso : iso + "Z")
  return d.toLocaleDateString("es-ES", { day: "numeric", month: "short" })
}
