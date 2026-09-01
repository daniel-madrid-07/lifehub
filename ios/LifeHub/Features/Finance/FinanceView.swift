import SwiftUI
import Charts

/// Dinero: patrimonio total en EUR + curva histórica + carteras
/// Alpaca (paper, USD) y Bitvavo (real, EUR).
struct FinanceView: View {
    @State private var tab = 0

    var body: some View {
        Screen(title: "Dinero") {
            CoachCard { try await API.shared.aiFinance() }

            LoadView {
                try await API.shared.financeSummary()
            } content: { (summary: FinanceSummary) in
                if summary.status == "error" {
                    Text(summary.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Patrimonio total")
                            .font(Theme.dCaption.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(2)
                            .foregroundStyle(Theme.muted)
                        Text(euro(summary.total_eur))
                            .font(.display(38, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if let pct = summary.day_change_pct {
                            Text(String(format: "%+.2f%% hoy", pct))
                                .font(Theme.dSubheadline.weight(.semibold))
                                .foregroundStyle(pct >= 0 ? Theme.good : Theme.bad)
                        }
                        HStack(spacing: 16) {
                            Text("Alpaca \(euro(summary.alpaca_eur))")
                            Text("Bitvavo \(euro(summary.bitvavo_eur))")
                        }
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                    }
                    .card()

                    let points = summary.history.filter { $0.total_eur != nil }
                    if points.count > 1 {
                        let vals = points.compactMap(\.total_eur)
                        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
                        // Margen del 15% del rango (o ±1% si es casi plano) para
                        // que las variaciones pequeñas se vean bien, no planas.
                        let pad = max((hi - lo) * 0.15, hi * 0.01)
                        Chart(points, id: \.date) { p in
                            AreaMark(
                                x: .value("Fecha", Fmt.date(p.date) ?? .now),
                                y: .value("EUR", p.total_eur ?? 0)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)
                            LineMark(
                                x: .value("Fecha", Fmt.date(p.date) ?? .now),
                                y: .value("EUR", p.total_eur ?? 0)
                            )
                            .foregroundStyle(Theme.accent)
                            .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: (lo - pad)...(hi + pad))
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 180)
                        .clipped()
                        .card()
                    }
                }
            }

            Picker("", selection: $tab) {
                Text("Alpaca").tag(0)
                Text("Bitvavo").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: tab) { _, _ in Haptics.selection() }

            if tab == 0 {
                PortfolioSection { try await API.shared.financeAlpaca() }
                    .id("alpaca")
            } else {
                PortfolioSection { try await API.shared.financeBitvavo() }
                    .id("bitvavo")
            }
        }
    }
}

func euro(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
}

struct PortfolioSection: View {
    let load: () async throws -> PortfolioOverview

    var body: some View {
        LoadView(load: load) { (p: PortfolioOverview) in
            if p.status == "error" {
                Text(p.detail ?? "Error")
                    .font(Theme.dSubheadline)
                    .foregroundStyle(Theme.bad)
                    .card()
            } else {
                HStack(spacing: 10) {
                    StatTile(
                        icon: "banknote.fill",
                        value: money(p.equity, p.currency),
                        label: "cartera"
                    )
                    StatTile(
                        icon: "arrow.up.right",
                        value: p.day_change_pct.map { String(format: "%+.2f%%", $0) } ?? "—",
                        label: "hoy"
                    )
                }

                ForEach(p.positions ?? [], id: \.symbol) { pos in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pos.symbol)
                                .font(Theme.dHeadline)
                                .foregroundStyle(Theme.ink)
                            Text("\(pos.qty.clean) × \(pos.price.clean)")
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(money(pos.value, p.currency))
                                .font(Theme.dSubheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(String(format: "%+.2f%% hoy", pos.day_pct))
                                .font(Theme.dCaption)
                                .foregroundStyle(pos.day_pct >= 0 ? Theme.good : Theme.bad)
                        }
                    }
                    .card(padding: 13)
                }
            }
        }
    }

    func money(_ v: Double?, _ currency: String?) -> String {
        guard let v else { return "—" }
        return v.formatted(.currency(code: currency ?? "EUR").precision(.fractionLength(0)))
    }
}
