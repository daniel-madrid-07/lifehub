import { useState } from "react"
import { api } from "../api"
import { useLoad } from "../hooks"
import { haptic } from "../haptics"
import { useSetting, setSetting, type NavStyle } from "../settings"
import { ROUTINE_CATEGORIES, NUTRITION_CATEGORIES } from "../types"
import { BowlIcon, DumbbellIcon, GridIcon, MailIcon, PulseIcon } from "../components/icons"
import { ErrorCard, PageHeader } from "../components/ui"
import GymRoutines from "./GymRoutines"
import Habits from "./Habits"
import Shopping from "./Shopping"

type Section = "home" | "navbar" | "gym" | "habits" | "shopping" | "conexiones"

const SECTIONS: { id: Section; label: string; hint: string; icon: typeof PulseIcon }[] = [
  { id: "gym", label: "Rutinas de gym", hint: "Crear y editar rutinas y ejercicios", icon: DumbbellIcon },
  { id: "habits", label: "Hábitos y comidas", hint: "Crear, editar o pausar tus rutinas diarias", icon: PulseIcon },
  { id: "shopping", label: "Lista de la compra", hint: "Añadir o quitar productos", icon: BowlIcon },
  { id: "conexiones", label: "Conexiones", hint: "Token de Google y sesión del intra", icon: MailIcon },
  { id: "navbar", label: "Barra de navegación", hint: "Carrusel o clásica", icon: GridIcon },
]

export default function Settings() {
  const [section, setSection] = useState<Section>("home")

  if (section !== "home") {
    return (
      <div>
        <button
          onClick={() => {
            haptic("light")
            setSection("home")
          }}
          className="text-muted text-sm mb-4 -ml-1 active:text-ink transition-colors"
        >
          ‹ Ajustes
        </button>
        {section === "navbar" && <NavbarSection />}
        {section === "gym" && <GymRoutines />}
        {section === "habits" && (
          <Habits
            categories={[...ROUTINE_CATEGORIES, ...NUTRITION_CATEGORIES]}
            title="Hábitos y comidas"
            singular="hábito"
          />
        )}
        {section === "shopping" && <Shopping editable />}
        {section === "conexiones" && <ConexionesSection />}
      </div>
    )
  }

  return (
    <div>
      <PageHeader eyebrow="Personal" title="Ajustes" />
      <p className="text-muted text-sm leading-relaxed mb-5">
        Todo lo que se edita vive aquí. La app del día a día queda limpia: solo marcar, apuntar y
        consultar.
      </p>
      <div className="space-y-2">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            onClick={() => {
              haptic("light")
              setSection(s.id)
            }}
            className="w-full flex items-center gap-3.5 px-4 py-4 rounded-2xl border border-line bg-surface/50 text-left active:bg-surface transition-colors"
          >
            <s.icon className="w-5 h-5 text-accent shrink-0" />
            <span className="min-w-0 flex-1">
              <span className="font-medium block">{s.label}</span>
              <span className="text-muted text-sm block truncate">{s.hint}</span>
            </span>
            <span className="text-muted shrink-0">›</span>
          </button>
        ))}
      </div>
    </div>
  )
}

function ConexionesSection() {
  const { data, error, reload } = useLoad(api.auth.status)
  const [opening, setOpening] = useState(false)

  const renew = async () => {
    setOpening(true)
    haptic("medium")
    try {
      const { url } = await api.auth.googleUrl()
      window.location.href = url // vuelve a la app tras autorizar
    } catch {
      setOpening(false)
    }
  }

  return (
    <section>
      <PageHeader eyebrow="Personal" title="Conexiones" />
      <p className="text-muted text-sm leading-relaxed mb-4">
        Estado de tus cuentas. Cuando algo caduque, se renueva desde aquí o me lo pides.
      </p>

      {error ? (
        <ErrorCard detail={error} onRetry={reload} />
      ) : !data ? (
        <div className="text-muted text-sm py-10 text-center">Comprobando estado…</div>
      ) : (
        <>
          {(() => {
            const g = data.google
            const days = g.days_left
            const tone =
              days == null
                ? g.connected
                  ? "text-gain"
                  : "text-danger"
                : days <= 2
                  ? "text-danger"
                  : days <= 7
                    ? "text-accent-2"
                    : "text-gain"
            const label =
              days == null
                ? g.connected
                  ? "Conectado"
                  : "Sin conectar"
                : days <= 0
                  ? "Caducado"
                  : `${days} ${days === 1 ? "día" : "días"}`
            return (
              <div className="rounded-2xl border border-line bg-surface/50 p-5 mb-3">
                <div className="flex items-center justify-between gap-3 mb-1">
                  <span className="font-medium">Google · Gmail y Agenda</span>
                  <span className={`text-sm font-semibold tnum ${tone}`}>{label}</span>
                </div>
                <p className="text-muted text-sm leading-relaxed mb-4">
                  {g.connected
                    ? g.production
                      ? "Correo y agenda funcionando. Sin caducidad (producción)."
                      : "Correo y agenda funcionando."
                    : "No conecta: renueva el token para volver a leer correo y agenda."}
                </p>
                {!g.connected && (
                  <button
                    onClick={renew}
                    disabled={opening}
                    className="w-full py-3 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
                  >
                    {opening ? "Abriendo Google…" : "Renovar token"}
                  </button>
                )}
              </div>
            )
          })()}

          <div className="rounded-2xl border border-line bg-surface/50 p-5">
            <div className="flex items-center justify-between gap-3 mb-1">
              <span className="font-medium">Estudios · intra</span>
              {(() => {
                const ep = data.intra
                const d = ep.days_left
                if (!ep.connected)
                  return <span className="text-sm font-semibold text-danger">Sesión caducada</span>
                if (d == null)
                  return <span className="text-sm font-semibold text-gain">Conectado</span>
                const t = d <= 3 ? "text-danger" : d <= 10 ? "text-accent-2" : "text-gain"
                return (
                  <span className={`text-sm font-semibold tnum ${t}`}>
                    {d <= 0 ? "Caduca hoy" : `~${d} ${d === 1 ? "día" : "días"}`}
                  </span>
                )
              })()}
            </div>
            <p className="text-muted text-sm leading-relaxed">
              {data.intra.connected
                ? "Estudios y el coach funcionan. Renovar la sesión necesita login de Microsoft + 2FA en el ordenador; pídemelo y lo hacemos en un momento."
                : "Sesión caída: hay que rehacer el login (Microsoft + 2FA). Dímelo y lo renovamos."}
            </p>
          </div>

          <button onClick={reload} className="text-muted text-sm mt-4 active:text-ink transition-colors">
            Actualizar estado
          </button>
        </>
      )}
    </section>
  )
}

function NavbarSection() {
  const navStyle = useSetting("navStyle")
  return (
    <section>
      <PageHeader eyebrow="Personal" title="Navegación" />
      <p className="text-muted text-sm leading-relaxed mb-4">
        Cómo se mueve la barra inferior entre apartados.
      </p>
      <div className="space-y-2">
        <NavOption
          id="scroll"
          current={navStyle}
          title="Carrusel infinito"
          desc="Deslizas entre todas las pestañas y al llegar al final vuelve al principio."
        />
        <NavOption
          id="classic"
          current={navStyle}
          title="Clásica con “Más”"
          desc="Cuatro fijas abajo y el resto dentro del botón “Más”."
        />
      </div>
    </section>
  )
}

function NavOption({
  id,
  current,
  title,
  desc,
}: {
  id: NavStyle
  current: NavStyle
  title: string
  desc: string
}) {
  const active = current === id
  return (
    <button
      onClick={() => {
        haptic("medium")
        setSetting("navStyle", id)
      }}
      aria-pressed={active}
      className={`w-full text-left p-4 rounded-2xl border transition-colors ${
        active ? "border-accent bg-accent/10" : "border-line bg-surface-2/40"
      }`}
    >
      <div className="flex items-center justify-between gap-3">
        <span className={`font-medium ${active ? "text-accent" : "text-ink"}`}>{title}</span>
        <span
          aria-hidden
          className={`w-4 h-4 rounded-full border-2 ${
            active ? "border-accent bg-accent" : "border-line"
          }`}
        />
      </div>
      <p className="text-muted text-sm mt-1 leading-relaxed">{desc}</p>
    </button>
  )
}
