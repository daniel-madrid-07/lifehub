import { useEffect, useState, type ReactNode } from "react"
import { motion } from "framer-motion"
import { getToken, setToken } from "../api"

type State = "checking" | "locked" | "open"

/** Comprueba la clave contra la API; si el backend no tiene APP_PASSWORD
 * (dev local) responde 200 sin token y la app abre directa. */
async function probe(token: string): Promise<boolean> {
  const res = await fetch("/api/today", {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  })
  return res.status !== 401
}

export default function AuthGate({ children }: { children: ReactNode }) {
  const [state, setState] = useState<State>("checking")
  const [value, setValue] = useState("")
  const [wrong, setWrong] = useState(false)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    probe(getToken())
      .then((ok) => setState(ok ? "open" : "locked"))
      .catch(() => setState("open")) // sin red: deja pasar, las paginas ya muestran su error
    const onUnauthorized = () => setState("locked")
    window.addEventListener("lifehub:unauthorized", onUnauthorized)
    return () => window.removeEventListener("lifehub:unauthorized", onUnauthorized)
  }, [])

  if (state === "open") return <>{children}</>
  if (state === "checking") {
    return (
      <div className="min-h-dvh flex items-center justify-center">
        <div className="font-display text-2xl text-muted animate-pulse">Life Hub</div>
      </div>
    )
  }

  const submit = async () => {
    const candidate = value.trim()
    if (!candidate || busy) return
    setBusy(true)
    setWrong(false)
    try {
      if (await probe(candidate)) {
        setToken(candidate)
        setState("open")
      } else {
        setWrong(true)
      }
    } catch {
      setWrong(true)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="min-h-dvh flex items-center justify-center p-6 pt-safe pb-safe">
      <div className="w-full max-w-sm">
        <div className="font-display text-4xl tracking-tight mb-1">Life Hub</div>
        <div className="text-muted text-xs uppercase tracking-[0.25em] mb-10">
          Centro de mando
        </div>

        <label htmlFor="access-key" className="block text-sm text-muted mb-1.5">
          Clave de acceso
        </label>
        <motion.div animate={wrong ? { x: [0, -8, 8, -5, 5, 0] } : {}} transition={{ duration: 0.35 }}>
          <input
            id="access-key"
            type="password"
            autoComplete="current-password"
            value={value}
            onChange={(e) => {
              setValue(e.target.value)
              setWrong(false)
            }}
            onKeyDown={(e) => e.key === "Enter" && submit()}
            className={`w-full bg-surface-2 border rounded-xl px-4 py-3.5 outline-none transition-colors ${
              wrong ? "border-danger" : "border-line focus:border-accent"
            }`}
          />
        </motion.div>
        {wrong && (
          <p role="alert" className="text-danger text-sm mt-2">
            Clave incorrecta.
          </p>
        )}

        <button
          onClick={submit}
          disabled={!value.trim() || busy}
          className="w-full mt-5 py-3.5 rounded-xl bg-accent text-accent-ink font-semibold active:scale-[0.98] transition-transform disabled:opacity-40"
        >
          {busy ? "Comprobando…" : "Entrar"}
        </button>
      </div>
    </div>
  )
}
