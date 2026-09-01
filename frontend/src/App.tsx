import { useState, useRef, useEffect } from "react"
import { motion, AnimatePresence } from "framer-motion"
import Today from "./pages/Today"
import History from "./pages/History"
import Finance from "./pages/Finance"
import Gym from "./pages/Gym"
import Studies from "./pages/Studies"
import Mail from "./pages/Mail"
import Calendar from "./pages/Calendar"
import Macros from "./pages/Macros"
import Shopping from "./pages/Shopping"
import Diet from "./pages/Diet"
import TasksPage from "./pages/Tasks"
import Home, { type HomeDest } from "./pages/Home"
import Settings from "./pages/Settings"
import { api } from "./api"
import HapticTap from "./components/HapticTap"
import { haptic } from "./haptics"
import { useSetting } from "./settings"
import { NUTRITION_CATEGORIES, ROUTINE_CATEGORIES } from "./types"
import {
  BowlIcon,
  CalendarIcon,
  CapIcon,
  ChecklistIcon,
  CoinsIcon,
  DumbbellIcon,
  GearIcon,
  GridIcon,
  HomeIcon,
  MailIcon,
  PulseIcon,
} from "./components/icons"

type ModuleId =
  | "home"
  | "routines"
  | "nutrition"
  | "gym"
  | "tasks"
  | "finance"
  | "mail"
  | "calendar"
  | "studies"
  | "settings"
type SubTab = "today" | "habits" | "history" | "macros" | "shopping" | "diet"

const MODULES: { id: ModuleId; label: string; icon: typeof PulseIcon }[] = [
  { id: "home", label: "Hoy", icon: HomeIcon },
  { id: "routines", label: "Rutinas", icon: PulseIcon },
  { id: "nutrition", label: "Comida", icon: BowlIcon },
  { id: "gym", label: "Gym", icon: DumbbellIcon },
  { id: "tasks", label: "Tareas", icon: ChecklistIcon },
  { id: "mail", label: "Correo", icon: MailIcon },
  { id: "calendar", label: "Agenda", icon: CalendarIcon },
  { id: "studies", label: "Estudios", icon: CapIcon },
  { id: "finance", label: "Dinero", icon: CoinsIcon },
  { id: "settings", label: "Ajustes", icon: GearIcon },
]

// Orden del carrusel infinito (uso diario primero)
const SCROLL_IDS: ModuleId[] = [
  "home", "gym", "nutrition", "finance", "routines",
  "tasks", "mail", "calendar", "studies", "settings",
]
// Barra clásica: 4 fijas (uso diario) + "Más" (lo de consultar)
const PRIMARY_IDS: ModuleId[] = ["home", "gym", "nutrition", "finance"]
const MORE_IDS: ModuleId[] = ["routines", "tasks", "mail", "calendar", "studies", "settings"]
const moduleById = (id: ModuleId) => MODULES.find((m) => m.id === id)!

// La gestión de hábitos vive en Ajustes; aquí solo se marcan y se consulta.
const ROUTINE_TABS: { id: SubTab; label: string }[] = [
  { id: "today", label: "Hoy" },
  { id: "history", label: "Historial" },
]

const NUTRITION_TABS: { id: SubTab; label: string }[] = [
  { id: "today", label: "Hoy" },
  { id: "diet", label: "Dieta" },
  { id: "macros", label: "Macros" },
  { id: "shopping", label: "Compra" },
  { id: "history", label: "Historial" },
]

export default function App() {
  const [module, setModuleState] = useState<ModuleId>("home")
  const [tab, setTab] = useState<SubTab>("today")
  const [moreOpen, setMoreOpen] = useState(false)
  const navStyle = useSetting("navStyle")

  // Primera apertura del dia: precalienta la IA en segundo plano para que las
  // tarjetas (Hoy, Dinero, Correo, Estudios) salgan ya sin esperar.
  useEffect(() => {
    const key = "lifehub_prewarm_day"
    const today = new Date().toISOString().slice(0, 10)
    if (localStorage.getItem(key) !== today) {
      localStorage.setItem(key, today)
      api.ai.prewarm().catch(() => {})
    }
  }, [])

  const setModule = (m: ModuleId) => {
    setModuleState(m)
    setTab("today")
    setMoreOpen(false)
    window.scrollTo({ top: 0 })
  }

  const hasTabs = module === "routines" || module === "nutrition"
  const tabs = module === "routines" ? ROUTINE_TABS : NUTRITION_TABS

  return (
    <div className="min-h-dvh lg:flex">
      {/* Sidebar — solo escritorio */}
      <aside className="hidden lg:flex lg:w-60 lg:min-h-screen border-r border-line p-6 flex-col gap-8 sticky top-0 self-start">
        <div>
          <div className="font-display text-2xl tracking-tight">Life Hub</div>
          <div className="text-muted text-xs uppercase tracking-[0.2em] mt-1">Centro de mando</div>
        </div>
        <nav className="flex flex-col gap-1" aria-label="Módulos">
          {MODULES.map((m) => (
            <button
              key={m.id}
              onClick={() => setModule(m.id)}
              aria-current={module === m.id ? "page" : undefined}
              className={`text-left px-3 py-2 rounded-lg font-medium transition-colors flex items-center gap-3 ${
                module === m.id ? "bg-surface-2 text-accent" : "text-muted hover:text-ink"
              }`}
            >
              <m.icon className="w-5 h-5" />
              {m.label}
            </button>
          ))}
        </nav>
      </aside>

      <main className="flex-1 min-w-0">
        <div className="max-w-2xl mx-auto px-5 lg:px-10 pt-safe pb-nav lg:pb-12">
          <div className="pt-4 lg:pt-10">
            {hasTabs && (
              <Segmented tabs={tabs} value={tab} onChange={setTab} groupLabel={module} />
            )}

            {module === "home" && <Home onGo={(m: HomeDest) => setModule(m)} />}
            {module === "routines" && tab === "today" && <Today categories={ROUTINE_CATEGORIES} />}
            {module === "routines" && tab === "history" && <History categories={ROUTINE_CATEGORIES} />}
            {module === "nutrition" && tab === "today" && <Today categories={NUTRITION_CATEGORIES} />}
            {module === "nutrition" && tab === "history" && <History categories={NUTRITION_CATEGORIES} />}
            {module === "nutrition" && tab === "macros" && <Macros />}
            {module === "nutrition" && tab === "diet" && <Diet />}
            {module === "nutrition" && tab === "shopping" && <Shopping />}
            {module === "gym" && <Gym />}
            {module === "tasks" && <TasksPage />}
            {module === "finance" && <Finance />}
            {module === "mail" && <Mail />}
            {module === "calendar" && <Calendar />}
            {module === "studies" && <Studies />}
            {module === "settings" && <Settings />}
          </div>
        </div>
      </main>

      {/* ── Barra CLÁSICA: 4 fijas + "Más" ── */}
      {navStyle === "classic" && (
      <>
      {/* Hoja "Más" — solo móvil */}
      <AnimatePresence>
        {moreOpen && (
          <>
            <motion.div
              className="lg:hidden fixed inset-0 bg-black/60 z-40"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setMoreOpen(false)}
            />
            <motion.div
              role="dialog"
              aria-label="Más secciones"
              className="lg:hidden fixed inset-x-0 bottom-0 z-50 bg-surface border-t border-line rounded-t-3xl pb-nav"
              initial={{ y: "100%" }}
              animate={{ y: 0 }}
              exit={{ y: "100%" }}
              transition={{ type: "spring", stiffness: 380, damping: 38 }}
            >
              <div aria-hidden className="mx-auto mt-3 h-1 w-10 rounded-full bg-line" />
              <div className="px-6 pt-4 pb-2">
                <div className="text-muted text-xs uppercase tracking-[0.2em] mb-4">Más</div>
                <div className="grid grid-cols-2 gap-3">
                  {MORE_IDS.map((id) => {
                    const m = moduleById(id)
                    const active = module === id
                    return (
                      <HapticTap
                        key={id}
                        label={m.label}
                        current={active}
                        onTap={() => setModule(id)}
                        className={`flex items-center gap-3 px-4 py-4 rounded-2xl border transition-colors ${
                          active
                            ? "border-accent bg-accent/10 text-accent"
                            : "border-line bg-surface-2/40 text-ink"
                        }`}
                      >
                        <m.icon className="w-6 h-6 shrink-0" />
                        <span className="font-medium">{m.label}</span>
                      </HapticTap>
                    )
                  })}
                </div>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>

      {/* Tab bar — solo móvil, fija abajo con blur y safe-area */}
      <nav
        aria-label="Navegación principal"
        className="lg:hidden fixed bottom-0 inset-x-0 z-40 border-t border-line bg-bg/85 backdrop-blur-xl pb-safe"
      >
        <div className="flex">
          {PRIMARY_IDS.map((id) => {
            const m = moduleById(id)
            const active = module === id
            return (
              <HapticTap
                key={id}
                label={m.label}
                current={active}
                onTap={() => setModule(id)}
                className={`flex-1 flex flex-col items-center gap-1 pt-3 pb-2 transition-colors ${
                  active ? "text-accent" : "text-muted"
                }`}
              >
                {active && (
                  <motion.span
                    layoutId="tab-dot"
                    className="absolute top-1 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-accent"
                    transition={{ type: "spring", stiffness: 500, damping: 35 }}
                  />
                )}
                <m.icon className="w-6 h-6" />
                <span className="text-[11px] font-medium tracking-wide">{m.label}</span>
              </HapticTap>
            )
          })}

          {/* "Más": muestra el módulo activo si estás en uno de ellos */}
          {(() => {
            const activeMore = MORE_IDS.includes(module)
            const display = activeMore ? moduleById(module) : null
            const Icon = display ? display.icon : GridIcon
            return (
              <HapticTap
                label={display ? display.label : "Más"}
                current={activeMore}
                onTap={() => setMoreOpen(true)}
                className={`flex-1 flex flex-col items-center gap-1 pt-3 pb-2 transition-colors ${
                  activeMore ? "text-accent" : "text-muted"
                }`}
              >
                {activeMore && (
                  <motion.span
                    layoutId="tab-dot"
                    className="absolute top-1 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-accent"
                    transition={{ type: "spring", stiffness: 500, damping: 35 }}
                  />
                )}
                <Icon className="w-6 h-6" />
                <span className="text-[11px] font-medium tracking-wide">
                  {display ? display.label : "Más"}
                </span>
              </HapticTap>
            )
          })()}
        </div>
      </nav>
      </>
      )}

      {/* ── Barra CARRUSEL INFINITO ── */}
      {navStyle === "scroll" && (
        <InfiniteNav active={module} onSelect={setModule} />
      )}
    </div>
  )
}

/**
 * Navbar tipo "fidget spinner": arrastras y suelta con inercia. La velocidad del
 * flick se mantiene y decelera por fricción; cuando casi para, un imán rápido la
 * acopla a la pestaña más cercana. Bucle infinito. Todo con transform + rAF
 * (no scroll nativo, que es lo que daba el tacto pegajoso).
 */
function InfiniteNav({
  active,
  onSelect,
}: {
  active: ModuleId
  onSelect: (m: ModuleId) => void
}) {
  const items = SCROLL_IDS.map(moduleById)
  const n = items.length
  const COPIES = 5
  const BASE = n * Math.floor(COPIES / 2) // copia central donde vive el scroll
  const loop = Array.from({ length: n * COPIES }, (_, k) => items[k % n])

  const wrapRef = useRef<HTMLDivElement>(null)
  const trackRef = useRef<HTMLDivElement>(null)
  const [itemW, setItemW] = useState(0)
  const [centerId, setCenterId] = useState<ModuleId>(active)

  const activeRef = useRef(active)
  activeRef.current = active

  // Estado físico (en refs: no provoca re-render por frame).
  const S = useRef({
    pos: 0, // px recorridos
    v: 0, // px/ms
    dragging: false,
    sx: 0,
    spos: 0,
    lx: 0,
    lt: 0,
    moved: false,
    raf: 0,
    w: 0,
    seen: null as ModuleId | null,
  })

  // Mantiene pos dentro de la copia central [BASE, BASE+n) (bucle infinito).
  const wrapPos = () => {
    const w = S.current.w
    if (!w) return
    let c = S.current.pos / w
    while (c < BASE) { S.current.pos += n * w; c += n }
    while (c >= BASE + n) { S.current.pos -= n * w; c -= n }
  }

  // Pinta la posición actual y refresca qué pestaña está en el centro.
  const apply = () => {
    const wrap = wrapRef.current
    const track = trackRef.current
    const w = S.current.w
    if (!wrap || !track || !w) return
    wrapPos()
    const c = S.current.pos / w
    track.style.transform = `translate3d(${wrap.clientWidth / 2 - (c + 0.5) * w}px,0,0)`
    const id = items[((Math.round(c) % n) + n) % n].id
    if (id !== S.current.seen) {
      S.current.seen = id
      setCenterId(id)
    }
  }

  // Mide el ancho de cada pestaña (22vw) y reposiciona.
  useEffect(() => {
    const wrap = wrapRef.current
    if (!wrap) return
    const measure = () => {
      const w = wrap.clientWidth * 0.22
      S.current.w = w
      setItemW(w)
      const base = Math.max(0, items.findIndex((m) => m.id === activeRef.current))
      S.current.pos = (BASE + base) * w
      apply()
    }
    measure()
    window.addEventListener("resize", measure)
    return () => window.removeEventListener("resize", measure)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Si el módulo cambia desde fuera (p. ej. tarjetas de Inicio), recoloca.
  useEffect(() => {
    if (!S.current.w || active === S.current.seen) return
    cancelAnimationFrame(S.current.raf)
    glideToModule(active)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active])

  const commit = () => {
    wrapPos()
    const id = items[((Math.round(S.current.pos / S.current.w) % n) + n) % n].id
    if (id !== activeRef.current) {
      haptic("light")
      onSelect(id)
    }
  }

  // Imán final: acopla rápido a la pestaña más cercana.
  const snap = () => {
    const target = Math.round(S.current.pos / S.current.w) * S.current.w
    const step = () => {
      const d = target - S.current.pos
      if (Math.abs(d) < 0.5) {
        S.current.pos = target
        apply()
        commit()
        return
      }
      S.current.pos += d * 0.28 // tirón rápido
      apply()
      S.current.raf = requestAnimationFrame(step)
    }
    S.current.raf = requestAnimationFrame(step)
  }

  // Inercia: mantiene la velocidad del flick y decelera por fricción.
  const momentum = () => {
    let last = performance.now()
    const step = () => {
      const now = performance.now()
      const dt = Math.min(40, now - last)
      last = now
      S.current.pos += S.current.v * dt
      S.current.v *= Math.exp(-0.0026 * dt) // fricción (rueda libre)
      apply()
      if (Math.abs(S.current.v) > 0.04) {
        S.current.raf = requestAnimationFrame(step)
      } else {
        snap() // a punto de parar → imán
      }
    }
    S.current.raf = requestAnimationFrame(step)
  }

  // Lleva suavemente una pestaña concreta al centro (tap o cambio externo).
  const glideToModule = (id: ModuleId) => {
    const w = S.current.w
    const cur = S.current.pos / w
    const baseIdx = Math.max(0, items.findIndex((m) => m.id === id))
    const target = (Math.round((cur - baseIdx) / n) * n + baseIdx) * w // copia más cercana
    const step = () => {
      const d = target - S.current.pos
      if (Math.abs(d) < 0.5) {
        S.current.pos = target
        apply()
        commit()
        return
      }
      S.current.pos += d * 0.22
      apply()
      S.current.raf = requestAnimationFrame(step)
    }
    S.current.raf = requestAnimationFrame(step)
  }

  // Sin setPointerCapture: así el switch de cada item recibe el toque directo
  // (necesario para el háptico en iOS). Los eventos burbujean igual al contenedor.
  const onDown = (e: React.PointerEvent) => {
    cancelAnimationFrame(S.current.raf)
    S.current.dragging = true
    S.current.moved = false
    S.current.sx = e.clientX
    S.current.spos = S.current.pos
    S.current.lx = e.clientX
    S.current.lt = performance.now()
    S.current.v = 0
  }
  const onMove = (e: React.PointerEvent) => {
    if (!S.current.dragging) return
    const dx = e.clientX - S.current.sx
    if (Math.abs(dx) > 5) S.current.moved = true
    S.current.pos = S.current.spos - dx // arrastras: el contenido sigue al dedo
    const now = performance.now()
    const dt = now - S.current.lt
    if (dt > 0) {
      S.current.v = -(e.clientX - S.current.lx) / dt
      S.current.lx = e.clientX
      S.current.lt = now
    }
    apply()
  }
  const onUp = () => {
    if (!S.current.dragging) return
    S.current.dragging = false
    if (!S.current.moved) return // fue un tap: lo gestiona el switch (HapticTap)
    S.current.v = Math.max(-4, Math.min(4, S.current.v)) // límite cordura
    if (Math.abs(S.current.v) > 0.05) momentum()
    else snap()
  }

  return (
    <nav
      aria-label="Navegación principal"
      className="lg:hidden fixed bottom-0 inset-x-0 z-40 border-t border-line bg-bg/85 backdrop-blur-xl pb-safe"
    >
      {/* Guía del centro: marca la pestaña seleccionada */}
      <span
        aria-hidden
        className="pointer-events-none absolute top-1.5 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-accent z-10"
      />
      <div
        ref={wrapRef}
        className="overflow-hidden"
        style={{ touchAction: "pan-y" }}
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={onUp}
        onPointerCancel={onUp}
      >
        <div ref={trackRef} className="flex will-change-transform">
          {loop.map((m, i) => {
            const isActive = m.id === centerId
            return (
              <HapticTap
                key={i}
                label={m.label}
                current={isActive}
                onTap={() => {
                  if (S.current.moved) return // fue arrastre, no tap
                  cancelAnimationFrame(S.current.raf)
                  glideToModule(m.id)
                }}
                style={{ width: itemW || "22vw" }}
                className={`shrink-0 flex flex-col items-center gap-1 pt-3 pb-2 transition-colors ${
                  isActive ? "text-accent" : "text-muted"
                }`}
              >
                <m.icon className="w-6 h-6" />
                <span className="text-[11px] font-medium tracking-wide">{m.label}</span>
              </HapticTap>
            )
          })}
        </div>
      </div>
    </nav>
  )
}

function Segmented({
  tabs,
  value,
  onChange,
  groupLabel,
}: {
  tabs: { id: SubTab; label: string }[]
  value: SubTab
  onChange: (t: SubTab) => void
  groupLabel: string
}) {
  return (
    <div
      role="tablist"
      aria-label={`Secciones de ${groupLabel}`}
      className="flex p-1 rounded-full bg-surface border border-line mb-8"
    >
      {tabs.map((t) => {
        const active = value === t.id
        return (
          <HapticTap
            key={t.id}
            label={t.label}
            current={active}
            onTap={() => onChange(t.id)}
            className="flex-1 flex items-center justify-center py-2.5 text-sm rounded-full"
          >
            {active && (
              <motion.span
                layoutId="seg-pill"
                className="absolute inset-0 rounded-full bg-surface-2 border border-line"
                transition={{ type: "spring", stiffness: 500, damping: 38 }}
              />
            )}
            <span className={`relative font-medium ${active ? "text-ink" : "text-muted"}`}>
              {t.label}
            </span>
          </HapticTap>
        )
      })}
    </div>
  )
}
