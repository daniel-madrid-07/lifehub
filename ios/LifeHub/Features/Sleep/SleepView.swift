import SwiftUI
import Charts

struct SleepView: View {
    @StateObject private var sleep = SleepManager()
    @State private var tomorrowFirst: CalendarEvent?
    @State private var reminderOn = false
    @AppStorage("sleep_hide_readiness") private var hideReadiness = false

    var body: some View {
        Screen(title: "Sueño", refresh: { await reload() }) {
            if !sleep.loaded {
                SkeletonList()
            } else if sleep.denied {
                Text("Necesito acceso a Salud para leer tu sueño. Actívalo en Ajustes del iPhone → Salud → Life Hub, y lleva el reloj al dormir.")
                    .font(Theme.dSubheadline)
                    .foregroundStyle(Theme.muted)
                    .card()
            } else {
                if sleep.missingLastNight { missingNightCard }
                if let plan = bedtimePlan { recommendationCard(plan) }
                if let r = sleep.readiness {
                    if hideReadiness { hiddenReadinessRow }
                    else { readinessCard(r) }
                }
                if let drift = sleep.phaseDrift { phaseDriftCard(drift) }

                if let n = sleep.lastNight {
                    lastNightPanel(n)
                } else if !sleep.missingLastNight {
                    Text("Sin datos de la última noche. Lleva el Apple Watch puesto al dormir.")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.muted)
                        .card()
                }

                if !sleep.sri.isNaN { sriCard }
                if let mins = sleep.lightMinutesYesterday { daylightCard(mins) }
                if sleep.history.count > 1 { trends }
            }
        }
        .task { await reload() }
    }

    func reload() async {
        await sleep.requestAndLoad()
        if let cal = try? await API.shared.calendar() {
            let events = cal.events ?? []
            tomorrowFirst = firstEventTomorrow(events)
            sleep.applyCalendarEvents(events)   // refine MSFsc from free vs work nights
        }
        UserDefaults.standard.set(sleep.needSecs, forKey: "sleep_need_secs")
        UserDefaults.standard.set(sleep.recoveryPoor ? sleep.cycleLen : 0, forKey: "sleep_recovery_extra_secs")
    }

    // MARK: - Missing night banner

    @ViewBuilder
    var missingNightCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.muted)
            Text("Falta el dato de anoche — la recomendación de hoy es menos precisa.")
                .font(Theme.dCaption).foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: - Recommendation

    struct BedtimePlan {
        let bedtime: Date
        let alarm: Date
        let reason: String
        let bullets: [String]
        let intervalMins: Int         // ± minutes to show as confidence window
        let confidenceLabel: String
    }

    @ViewBuilder
    func recommendationCard(_ p: BedtimePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.accent)
                Text("Plan de esta noche").font(Theme.dHeadline).foregroundStyle(Theme.ink)
                Spacer()
                Text(p.confidenceLabel).font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                StatTile(icon: "bed.double",
                         value: "\(hm(p.bedtime)) ±\(p.intervalMins)min",
                         label: "acuéstate")
                StatTile(icon: "alarm", value: hm(p.alarm), label: "alarma")
            }
            Text(p.reason).font(Theme.dCaption).foregroundStyle(Theme.muted)

            if !p.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(p.bullets, id: \.self) { b in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·").foregroundStyle(Theme.muted).font(Theme.dCaption2)
                            Text(b).font(Theme.dCaption2).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }

            HButton(haptic: Haptics.medium) {
                reminderOn.toggle()
                if reminderOn { Notifs.shared.scheduleBedtime(p.bedtime) }
                else { Notifs.shared.cancelBedtime() }
            } label: {
                Label(reminderOn ? "Aviso activado" : "Avísame a la hora de dormir",
                      systemImage: reminderOn ? "bell.fill" : "bell")
                    .font(Theme.dSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .secondaryGlass(reminderOn ? Theme.accent : Theme.ink)

            HStack(spacing: 6) {
                Text("Alarma nativa: usa el Atajo 'Alarma recomendada' de Life Hub.")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
                Spacer()
                if let url = URL(string: "shortcuts://") {
                    Link("Atajos", destination: url)
                        .font(Theme.dCaption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .card()
    }

    var bedtimePlan: BedtimePlan? {
        guard sleep.habitualBedH > 0 || sleep.chronoMidH > 0 else { return legacyBedtimePlan }

        let deadline: Date? = {
            guard let ev = tomorrowFirst, let s = Fmt.date(ev.start), hasTime(ev.start) else { return nil }
            return s.addingTimeInterval(-45 * 60)
        }()

        let msfsc = sleep.chronoMidH > 0 ? sleep.chronoMidH : 4.0
        let bedH  = sleep.habitualBedH  > 0 ? sleep.habitualBedH  : 23.5
        let wakeH = sleep.habitualWakeH > 0 ? sleep.habitualWakeH : 7.5

        let rec = BedtimeOptimizer.run(
            sNow: sleep.sNow,
            model: TwoProcess(),
            debtHours: sleep.debtHours,
            needSecs: sleep.needSecs,
            habitualBedH: bedH,
            habitualWakeH: wakeH,
            msfsc: msfsc,
            deadline: deadline,
            spielmanGuard: sleep.spielmanGuard,
            now: Date()
        )

        let conc = sleep.chronoConcentration
        let confidenceLabel: String
        if conc >= 0.70 && sleep.validNightCount >= 14 { confidenceLabel = "confianza alta" }
        else if conc >= 0.40 { confidenceLabel = "confianza media" }
        else { confidenceLabel = "calibrando" }

        return BedtimePlan(bedtime: rec.bedtime, alarm: rec.wake,
                           reason: rec.reason, bullets: rec.bullets,
                           intervalMins: rec.intervalMins,
                           confidenceLabel: confidenceLabel)
    }

    // Fallback when not enough history for the optimizer
    private var legacyBedtimePlan: BedtimePlan? {
        let need: TimeInterval = 8 * 3600
        let cycle = sleep.cycleLen, latency = BedtimeEngine.latency
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        let n = max(4, min(6, Int(((need + (sleep.recoveryPoor ? cycle : 0)) / cycle).rounded())))
        var wake = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        if let ev = tomorrowFirst, let s = Fmt.date(ev.start), hasTime(ev.start),
           s.addingTimeInterval(-45*60) < wake { wake = s.addingTimeInterval(-45*60) }
        let bed = wake.addingTimeInterval(-(latency + Double(n) * cycle))
        return BedtimePlan(bedtime: bed, alarm: wake,
                           reason: "\(n) ciclos de \(Int(cycle/60)) min",
                           bullets: [], intervalMins: 40, confidenceLabel: "calibrando")
    }

    func firstEventTomorrow(_ events: [CalendarEvent]) -> CalendarEvent? {
        let cal = Calendar.current
        return events
            .filter { e in
                guard let d = Fmt.date(e.start) else { return false }
                return cal.isDateInTomorrow(d) && hasTime(e.start)
            }
            .min { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
    }
    func hasTime(_ iso: String?) -> Bool { (iso ?? "").contains("T") }

    // MARK: - Last night panel

    @ViewBuilder
    func lastNightPanel(_ n: SleepNight) -> some View {
        SectionHeader(title: "Última noche")
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dur(n.asleep)).font(.display(30, weight: .regular)).foregroundStyle(Theme.ink)
                Text("dormido").font(Theme.dCaption).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(n.efficiency * 100))%").font(Theme.dHeadline).foregroundStyle(Theme.accent)
                Text("eficiencia").font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
            StagesBar(n: n)
            HStack {
                stage("Profundo", n.deep, Theme.accent2)
                stage("REM", n.rem, Theme.accent)
                stage("Ligero", n.core, Theme.muted)
                stage("Despierto", n.awake, Theme.bad)
            }
            HStack {
                Text("En cama \(dur(n.inBed)) · \(hm(n.start))–\(hm(n.end))")
                    .font(Theme.dCaption).foregroundStyle(Theme.muted)
                if n.waso > 60 {
                    Spacer()
                    Text("WASO \(Int(n.waso / 60)) min")
                        .font(Theme.dCaption).foregroundStyle(Theme.bad)
                }
            }
            if n.possibleAlcohol {
                Text("Patron de pulso atipico en primera mitad — posible alcohol o ejercicio tardio.")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
            if n.confidence == .lowQuality {
                Text("Datos sin reloj — cifras aproximadas.")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
        }
        .card()

        let metrics = nightMetrics(n)
        if !metrics.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metrics, id: \.0) { m in
                    StatTile(icon: m.2, value: m.1, label: m.0)
                }
            }
        }
    }

    func nightMetrics(_ n: SleepNight) -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        if let v = n.avgHR   { out.append(("pulso medio",   "\(Int(v)) ppm",           "heart")) }
        if let v = n.minHR   { out.append(("pulso mínimo",  "\(Int(v)) ppm",           "heart.circle")) }
        // RMSSD preferred; show SDNN as fallback label
        if let v = n.rmssd   { out.append(("HRV RMSSD",    "\(Int(v)) ms",            "waveform.path.ecg")) }
        else if let v = n.avgHRV { out.append(("HRV media", "\(Int(v)) ms",           "waveform.path.ecg")) }
        if let v = n.avgResp { out.append(("respiración",   "\(Int(v)) rpm",           "lungs")) }
        if let v = n.avgSpO2 { out.append(("oxígeno",       "\(Int(v * 100))%",        "drop")) }
        if let v = n.wristTemp { out.append(("temp. muñeca", String(format: "%.1f°", v), "thermometer")) }
        if let v = n.hrNadirH {
            let h = Int(v), m = Int((v - Double(h)) * 60)
            out.append(("nadir pulso",  String(format: "%02d:%02d", h, m),             "arrow.down.heart"))
        }
        if let v = n.hrDip   { out.append(("descenso HR",   "\(Int(v * 100))%",        "chart.line.downtrend.xyaxis")) }
        return out
    }

    @ViewBuilder
    func stage(_ label: String, _ t: TimeInterval, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(dur(t)).font(Theme.dCaption.weight(.semibold)).foregroundStyle(color)
            Text(label).font(Theme.dCaption2).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Readiness card (Fase 2)

    @ViewBuilder
    var hiddenReadinessRow: some View {
        HStack {
            Text("Recuperacion oculta (anti-ortosomnia)")
                .font(Theme.dCaption).foregroundStyle(Theme.muted)
            Spacer()
            Button("Mostrar") { hideReadiness = false }
                .font(Theme.dCaption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .card()
    }

    @ViewBuilder
    func readinessCard(_ r: ReadinessScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.accent)
                Text("Recuperacion").font(Theme.dHeadline).foregroundStyle(Theme.ink)
                Spacer()
                Text(r.confidence).font(Theme.dCaption2).foregroundStyle(Theme.muted)
                Button("Ocultar") { hideReadiness = true }
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(r.value))").font(.display(34, weight: .regular))
                    .foregroundStyle(r.value >= 80 ? Theme.accent : r.value >= 60 ? Theme.ink : Theme.bad)
                Text("/ 100 · \(r.label)").font(Theme.dCaption).foregroundStyle(Theme.muted)
            }
            ReadinessBar(score: r.value)
            if sleep.debtHours > 0.5 {
                Text("Deuda acumulada: \(Int(sleep.debtHours * 60)) min")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    // MARK: - Phase drift card (Fase 2)

    @ViewBuilder
    func phaseDriftCard(_ drift: TimeInterval) -> some View {
        let mins = Int(abs(drift) / 60)
        let direction = drift > 0 ? "retraso" : "adelanto"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 15, weight: .light)).foregroundStyle(.orange)
                Text("Deriva de fase").font(Theme.dHeadline).foregroundStyle(Theme.ink)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(mins) min").font(.display(26, weight: .regular)).foregroundStyle(Theme.ink)
                Text("de \(direction) vs hace 3–4 semanas").font(Theme.dCaption).foregroundStyle(Theme.muted)
            }
            Text("El nadir de tu pulso se ha desplazado. Mantén horarios estables y prioriza luz matinal antes de las 9 h.")
                .font(Theme.dCaption2).foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: - SRI card (Fase 2)

    @ViewBuilder
    var sriCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.accent)
                Text("Regularidad del sueño").font(Theme.dHeadline).foregroundStyle(Theme.ink)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(sleep.sri))").font(.display(28, weight: .regular)).foregroundStyle(Theme.ink)
                Text("/ 100").font(Theme.dCaption).foregroundStyle(Theme.muted)
                Spacer()
                Text(sleep.sri >= 75 ? "buena" : sleep.sri >= 55 ? "mejorable" : "irregular")
                    .font(Theme.dCaption.weight(.semibold))
                    .foregroundStyle(sleep.sri >= 75 ? Theme.accent : sleep.sri >= 55 ? Theme.ink : Theme.bad)
            }
            Text("Adultos tipicos: 60–80. La regularidad predice el rendimiento mejor que la duracion.")
                .font(Theme.dCaption2).foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: - Daylight card (Fase 2)

    @ViewBuilder
    func daylightCard(_ mins: Double) -> some View {
        let target = 20.0
        let needsMore = mins < target
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max").font(.system(size: 15, weight: .light)).foregroundStyle(.yellow)
                Text("Luz natural ayer").font(Theme.dHeadline).foregroundStyle(Theme.ink)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(mins)) min").font(.display(26, weight: .regular))
                    .foregroundStyle(needsMore ? Theme.bad : Theme.accent)
                Text("objetivo: \(Int(target)) min").font(Theme.dCaption).foregroundStyle(Theme.muted)
            }
            if needsMore {
                Text("Sal a la calle 20 min en los primeros 90 min tras despertar. La luz matinal es la unica palanca causal sobre tu reloj biologico.")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            } else {
                Text("Bien. La exposicion matinal ayuda a mantener tu reloj biologico alineado.")
                    .font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
        }
        .card()
    }

    // MARK: - Trends chart

    @ViewBuilder
    var trends: some View {
        SectionHeader(title: "Últimas noches")
        Chart(sleep.history) { h in
            BarMark(
                x: .value("Día", h.date, unit: .day),
                y: .value("Horas", h.asleep / 3600)
            )
            .foregroundStyle(Theme.accent)
        }
        .frame(height: 160)
        .card()
    }

    // MARK: - Format helpers

    func dur(_ t: TimeInterval) -> String {
        let m = Int(t / 60); return "\(m / 60) h \(m % 60) min"
    }
    func hm(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }
}

/// Thin progress bar for readiness score
struct ReadinessBar: View {
    let score: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted.opacity(0.2)).frame(height: 6)
                Capsule()
                    .fill(score >= 80 ? Theme.accent : score >= 60 ? Theme.ink : Theme.bad)
                    .frame(width: geo.size.width * CGFloat(min(score, 100) / 100), height: 6)
            }
        }
        .frame(height: 6)
    }
}

/// Proportional sleep-stage bar
struct StagesBar: View {
    let n: SleepNight
    var body: some View {
        GeometryReader { geo in
            let total = max(1, n.deep + n.rem + n.core + n.awake)
            HStack(spacing: 2) {
                seg(n.deep,  total, geo.size.width, Theme.accent2)
                seg(n.rem,   total, geo.size.width, Theme.accent)
                seg(n.core,  total, geo.size.width, Theme.muted)
                seg(n.awake, total, geo.size.width, Theme.bad)
            }
        }
        .frame(height: 12)
    }
    @ViewBuilder
    func seg(_ v: Double, _ total: Double, _ w: CGFloat, _ c: Color) -> some View {
        if v > 0 {
            Capsule().fill(c).frame(width: max(2, w * CGFloat(v / total)))
        }
    }
}
