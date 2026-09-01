import { useState } from "react"
import { motion } from "framer-motion"
import { api } from "../api"
import { useLoad } from "../hooks"
import type { FinanceSummary, PortfolioOverview } from "../types"
import { CoachNote, EmptyState, ErrorCard, PageHeader, RefreshButton, SkeletonList } from "../components/ui"
import HapticTap from "../components/HapticTap"

type Wallet = "alpaca" | "bitvavo"

const WALLETS: { id: Wallet; label: string; sub: string }[] = [
  { id: "alpaca", label: "Alpaca", sub: "paper · USD" },
  { id: "bitvavo", label: "Bitvavo", sub: "real · EUR" },
]

export default function Finance() {
  const [wallet, setWallet] = useState<Wallet>("alpaca")
  const { data: summary } = useLoad(api.financeSummary)

  return (
    <div>
      {summary?.status === "ok" && summary.total_eur != null && (
        <div className="px-4 py-3.5 rounded-2xl border border-line bg-surface/50 mb-4 flex items-baseline justify-between gap-3">
          <div>
            <div className="text-muted text-xs uppercase tracking-[0.15em]">Patrimonio total</div>
            <div className="text-muted text-xs mt-0.5 tnum">
              {money(summary.alpaca_eur ?? 0, "EUR")} bolsa + {money(summary.bitvavo_eur ?? 0, "EUR")} cripto
            </div>
          </div>
          <div className="font-display text-3xl tnum shrink-0">
            {money(summary.total_eur, "EUR")}
          </div>
        </div>
      )}

      <CoachNote fetcher={api.ai.finance} />

      {summary?.status === "ok" && summary.history.length >= 2 && (
        <EquityChart history={summary.history} />
      )}
      <div
        role="tablist"
        aria-label="Cartera"
        className="flex p-1 rounded-full bg-surface border border-line mb-8"
      >
        {WALLETS.map((w) => {
          const active = wallet === w.id
          return (
            <HapticTap
              key={w.id}
              label={w.label}
              current={active}
              onTap={() => setWallet(w.id)}
              className="flex-1 py-2 rounded-full text-center"
            >
              {active && (
                <motion.span
                  layoutId="wallet-pill"
                  className="absolute inset-0 rounded-full bg-surface-2 border border-line"
                  transition={{ type: "spring", stiffness: 500, damping: 38 }}
                />
              )}
              <span className="relative block">
                <span className={`font-medium ${active ? "text-ink" : "text-muted"}`}>
                  {w.label}
                </span>
                <span className={`block text-[10px] uppercase tracking-[0.15em] ${active ? "text-accent" : "text-muted/60"}`}>
                  {w.sub}
                </span>
              </span>
            </HapticTap>
          )
        })}
      </div>

      {wallet === "alpaca" ? (
        <WalletView key="alpaca" title="Alpaca" eyebrow="Bolsa · cuenta paper" fetcher={api.financeAlpaca} />
      ) : (
        <WalletView key="bitvavo" title="Bitvavo" eyebrow="Cripto · dinero real" fetcher={api.financeBitvavo} />
      )}
    </div>
  )
}

function WalletView({
  title,
  eyebrow,
  fetcher,
}: {
  title: string
  eyebrow: string
  fetcher: () => Promise<PortfolioOverview>
}) {
  const { data, error, refreshing, reload } = useLoad(fetcher)

  const header = (
    <PageHeader
      eyebrow={eyebrow}
      title={title}
      action={<RefreshButton onClick={reload} busy={refreshing} />}
    />
  )

  if (error)
    return (
      <div>
        {header}
        <ErrorCard detail={error} onRetry={reload} />
      </div>
    )
  if (!data)
    return (
      <div>
        {header}
        <SkeletonList rows={4} tall />
      </div>
    )
  if (data.status === "error")
    return (
      <div>
        {header}
        <ErrorCard detail={data.detail ?? "No se pudo cargar la cartera."} onRetry={reload} />
      </div>
    )

  const currency = data.currency ?? "EUR"
  const equity = data.equity ?? 0
  const cash = data.cash ?? 0
  const dayChange = data.day_change ?? 0
  const dayPct = data.day_change_pct ?? 0
  const positions = data.positions ?? []

  return (
    <div>
      {header}

      <div className="relative overflow-hidden bg-surface border border-line rounded-3xl p-6 mb-8">
        <div
          aria-hidden
          className="absolute -top-16 -right-16 w-44 h-44 rounded-full bg-accent/10 blur-2xl pointer-events-none"
        />
        <div className="text-muted text-xs uppercase tracking-[0.2em] mb-2">Valor total</div>
        <div className="font-display text-5xl tracking-tight tnum">
          {money(equity, currency)}
        </div>
        <div className="flex items-center gap-4 mt-3 text-sm">
          <span className={`font-semibold tnum ${tone(dayChange)}`}>
            {sign(dayChange)}
            {money(Math.abs(dayChange), currency)} hoy ({pct(dayPct)})
          </span>
          <span className="text-muted tnum">
            {money(cash, currency)} en efectivo
          </span>
        </div>
      </div>

      {positions.length === 0 ? (
        <EmptyState title="Sin posiciones abiertas" hint="Todo el capital está en efectivo." />
      ) : (
        <div>
          <div className="text-muted text-xs uppercase tracking-[0.2em] mb-3">
            Posiciones ({positions.length})
          </div>
          <div className="space-y-1">
            {positions.map((p) => (
              <div
                key={p.symbol}
                className="flex items-center justify-between gap-4 px-3 py-3 -mx-3 rounded-2xl"
              >
                <div className="min-w-0">
                  <div className="font-semibold tracking-wide">{p.symbol}</div>
                  <div className="text-muted text-sm tnum">
                    {qty(p.qty)} × {money(p.price, currency)}
                  </div>
                </div>
                <div className="text-right shrink-0">
                  <div className="font-medium tnum">{money(p.value, currency)}</div>
                  <div className="text-sm tnum space-x-2">
                    <span className={tone(p.day_pct)}>{pct(p.day_pct)} hoy</span>
                    {p.pnl_pct != null && (
                      <span className={`${tone(p.pnl_pct)} opacity-80`}>
                        {pct(p.pnl_pct)} total
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function EquityChart({ history }: { history: FinanceSummary["history"] }) {
  // total combinado si hay tipo de cambio; si no, solo Alpaca
  const values = history.map((h) => h.total_eur ?? h.alpaca_usd)
  const w = 320
  const h = 88
  const pad = 8
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1
  const pts = values.map((v, i) => {
    const x = pad + (i / (values.length - 1)) * (w - pad * 2)
    const y = h - pad - ((v - min) / range) * (h - pad * 2)
    return `${x},${y}`
  })
  const first = values[0]
  const last = values[values.length - 1]
  const up = last >= first
  const fmtDay = (iso: string) =>
    new Date(iso + "T12:00").toLocaleDateString("es-ES", { day: "numeric", month: "short" })
  return (
    <div className="mb-6">
      <svg
        viewBox={`0 0 ${w} ${h}`}
        className="w-full h-24"
        role="img"
        aria-label={`Evolución del patrimonio de ${Math.round(first)} a ${Math.round(last)}`}
      >
        <polyline
          points={pts.join(" ")}
          fill="none"
          stroke={up ? "var(--color-gain)" : "var(--color-danger)"}
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
      <div className="flex justify-between text-xs text-muted/70 tnum px-1">
        <span>{fmtDay(history[0].date)}</span>
        <span className={up ? "text-gain" : "text-danger"}>
          {up ? "+" : "−"}
          {Math.abs(((last - first) / first) * 100).toFixed(1)}% desde el inicio
        </span>
        <span>{fmtDay(history[history.length - 1].date)}</span>
      </div>
    </div>
  )
}

function money(n: number, currency: string): string {
  return new Intl.NumberFormat("es-ES", {
    style: "currency",
    currency,
    maximumFractionDigits: Math.abs(n) >= 1000 ? 0 : 2,
  }).format(n)
}

function qty(n: number): string {
  return new Intl.NumberFormat("es-ES", { maximumFractionDigits: 6 }).format(n)
}

function pct(n: number): string {
  return `${n >= 0 ? "+" : "−"}${Math.abs(n).toFixed(1)}%`
}

function sign(n: number): string {
  return n >= 0 ? "+" : "−"
}

function tone(n: number): string {
  if (n > 0.005) return "text-gain"
  if (n < -0.005) return "text-danger"
  return "text-muted"
}
