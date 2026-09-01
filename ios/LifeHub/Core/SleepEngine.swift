import Foundation

// MARK: - Fase 1: Modelo de dos procesos (Borbély 1982; Daan et al. 1984)

struct TwoProcess {
    var tauRise: Double = 18.2 * 3600   // homeostatic rise constant
    var tauFall: Double =  4.2 * 3600   // homeostatic fall constant
    var mu:      Double = 1.00
    var h0Upper: Double = 0.60
    var h0Lower: Double = 0.17
    var amp:     Double = 0.10

    func sAfter(_ S: Double, dt: TimeInterval, asleep: Bool) -> Double {
        asleep ? S * exp(-dt / tauFall)
               : mu - (mu - S) * exp(-dt / tauRise)
    }

    // 4-harmonic circadian process C (Daan et al. 1984)
    func C(hours: Double, phi: Double) -> Double {
        let w = 2 * Double.pi / 24, t = hours - phi
        return 0.97*sin(w*t) + 0.22*sin(2*w*t) + 0.07*sin(3*w*t) + 0.03*sin(4*w*t)
    }

    /// Simulate S over asleep intervals. Returns S at `to`.
    func simulate(asleepIntervals: [DateInterval], from: Date, to: Date,
                  S0: Double = 0.35, dt: TimeInterval = 300) -> Double {
        var S = S0, t = from
        while t < to {
            S = sAfter(S, dt: dt, asleep: asleepIntervals.contains { $0.contains(t) })
            t = t.addingTimeInterval(dt)
        }
        return S
    }

    /// Analytic S at wake for a candidate (bed, wake) pair, given current S at `now`.
    func sAtWake(sNow: Double, now: Date, bed: Date, wake: Date) -> Double {
        let dtAwake  = max(0, bed.timeIntervalSince(now))
        let dtAsleep = max(0, wake.timeIntervalSince(bed))
        return sAfter(sAfter(sNow, dt: dtAwake, asleep: false), dt: dtAsleep, asleep: true)
    }
}

// MARK: - Fase 1: Deuda de dos escalas (Van Dongen 2003; McCauley 2009)

struct SleepDebtModel: Codable {
    var dFast: Double = 0   // acute, τ = 2 days
    var dSlow: Double = 0   // chronic, τ = 21 days
    // Asymmetry: easy to accumulate (κ⁺ = 0.35), slow to pay (κ⁻ = 0.15)
    mutating func update(tst: TimeInterval, need: TimeInterval) {
        let deficit = (need - tst) / 3600   // hours (negative = surplus)
        dFast = max(0, dFast * exp(-1.0 / 2.0)  + deficit)
        dSlow = max(0, dSlow * exp(-1.0 / 21.0)
                       + 0.35 * max(0, deficit)
                       + 0.15 * min(0, deficit))
    }
    var total: Double { dFast + dSlow }

    static func load() -> SleepDebtModel {
        guard let data = sleepUD.data(forKey: "sleep_debt_model"),
              let model = try? JSONDecoder().decode(SleepDebtModel.self, from: data)
        else { return SleepDebtModel() }
        return model
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            sleepUD.set(data, forKey: "sleep_debt_model")
        }
    }
}

// MARK: - Fase 1: Optimizador (grid search sobre función de coste)

struct SleepRecommendation {
    let bedtime: Date
    let wake: Date
    let intervalMins: Int
    let reason: String
    let bullets: [String]
    let debtHours: Double
    let needHours: Double
}

enum BedtimeOptimizer {

    static func run(
        sNow: Double,
        model: TwoProcess,
        debtHours: Double,
        needSecs: TimeInterval,
        habitualBedH: Double,       // circular mean, hours [0,24]
        habitualWakeH: Double,
        msfsc: Double,              // chronotype midpoint hours [0,24]
        deadline: Date?,
        spielmanGuard: Bool,        // true → don't extend TIB
        now: Date
    ) -> SleepRecommendation {

        let cal = Calendar.current
        let needH = needSecs / 3600

        // Next bed opportunity: find next occurrence of habitual bed hour
        let todayStart = cal.startOfDay(for: now)
        var bedBase = todayStart.addingTimeInterval(habitualBedH * 3600)
        if bedBase < now.addingTimeInterval(-30 * 60) { bedBase = bedBase.addingTimeInterval(86400) }

        // Habitual TIB
        let habitualTIB: TimeInterval
        if habitualWakeH > habitualBedH {
            habitualTIB = (habitualWakeH - habitualBedH) * 3600
        } else {
            habitualTIB = (24 - habitualBedH + habitualWakeH) * 3600
        }
        let wakeBase = bedBase.addingTimeInterval(max(habitualTIB, needSecs))

        // Constraints
        let bGate = bedBase.addingTimeInterval(-60 * 60)       // forbidden zone boundary
        let hardWake = deadline ?? wakeBase.addingTimeInterval(90 * 60)
        let debtExtra: TimeInterval = spielmanGuard ? 0 : min(3600, debtHours * 0.35 * 3600)
        let tibTarget = needSecs + debtExtra
        let sStar = 0.27   // target S at wake (well-rested reference)

        // Grid bounds
        let bMin = bGate
        let bMax = bedBase.addingTimeInterval(90 * 60)
        let wMin = wakeBase.addingTimeInterval(-60 * 60)
        let wMax = min(hardWake, wakeBase.addingTimeInterval(90 * 60))
        let step: TimeInterval = 5 * 60

        var bestCost = Double.infinity
        var bestB = bedBase, bestW = wakeBase

        var bCand = bMin
        while bCand <= bMax {
            var wCand = wMin
            while wCand <= wMax {
                let tib = wCand.timeIntervalSince(bCand)
                guard tib >= needSecs - 3600 && tib <= needSecs + 5400 + debtExtra else {
                    wCand = wCand.addingTimeInterval(step); continue
                }

                let sW = model.sAtWake(sNow: sNow, now: now, bed: bCand, wake: wCand)

                // Hours relative to the bed day's midnight
                let bedMidnight = cal.startOfDay(for: bCand)
                let bH = bCand.timeIntervalSince(bedMidnight) / 3600
                let wH = wCand.timeIntervalSince(bedMidnight) / 3600
                let midH = (bH + wH / 2).truncatingRemainder(dividingBy: 24)

                let cS    = pow(sW - sStar, 2)
                let cGate = pow(max(0, bGate.timeIntervalSince(bCand)) / 3600, 2)
                let cReg  = pow(bH - habitualBedH, 2) + pow((wH - 24).truncatingRemainder(dividingBy: 24) - habitualWakeH, 2)
                let cSJL  = pow(circularDiff(midH, msfsc), 2)
                let cDebt = tib < tibTarget ? pow((tibTarget - tib) / 3600, 2) : 0

                let cost = 1.0*cS + 4.0*cGate + 0.3*cReg + 0.4*cSJL + 0.8*cDebt
                if cost < bestCost { bestCost = cost; bestB = bCand; bestW = wCand }
                wCand = wCand.addingTimeInterval(step)
            }
            bCand = bCand.addingTimeInterval(step)
        }

        // Explanation
        let tibSecs = bestW.timeIntervalSince(bestB)
        let tibH = Int(tibSecs / 3600), tibM = Int(tibSecs.truncatingRemainder(dividingBy: 3600) / 60)
        var bullets: [String] = [
            "\(tibH) h \(tibM) min en cama — necesidad estimada \(Int(needH * 60)) min"
        ]
        if debtHours > 0.5 {
            bullets.append("Deuda acumulada: \(Int(debtHours * 60)) min — pagando \(Int(debtExtra / 60)) min esta noche")
        }
        if spielmanGuard {
            bullets.append("Eficiencia baja en ultimas noches — sin ampliar tiempo en cama")
        }
        let sjl = abs(circularDiff(msfsc, (habitualBedH + habitualWakeH / 2).truncatingRemainder(dividingBy: 24)))
        if sjl > 1 {
            bullets.append("Jet lag social: \(String(format: "%.1f", sjl)) h — prioriza luz matinal")
        }
        if deadline != nil { bullets.append("Alarma: limite por evento de manana") }

        let reason = deadline != nil ? "listo para tu agenda de manana" : "segun tu ritmo natural"
        return SleepRecommendation(bedtime: bestB, wake: bestW, intervalMins: 20,
                                   reason: reason, bullets: bullets,
                                   debtHours: debtHours, needHours: needH)
    }

    // Signed circular difference a − b in [−12, 12]
    private static func circularDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d >  12 { d -= 24 }
        while d < -12 { d += 24 }
        return d
    }
}

// MARK: - Fase 2: Readiness score (sleep.md §5)

struct ReadinessScore {
    let value: Double       // 0–100
    let confidence: String
    let nightCount: Int
    let components: Components

    struct Components {
        var debt:        Double = -1   // −1 = unavailable
        var duration:    Double = -1
        var hrv:         Double = -1
        var hr:          Double = -1
        var continuity:  Double = -1
        var alignment:   Double = -1
        var respiration: Double = -1
    }

    var label: String {
        switch value {
        case 80...: return "buena"
        case 60..<80: return "normal"
        default: return "menos de lo habitual"
        }
    }
}

private func sigmoid(_ x: Double) -> Double { 1.0 / (1.0 + exp(-x)) }

func computeReadiness(
    night: SleepNight,
    debtHours: Double,
    needSecs: TimeInterval,
    sjlHours: Double,
    hrvMedian: Double, hrvMAD: Double,
    hrMedian: Double,  hrMAD: Double,
    respMedian: Double, respMAD: Double,
    nightCount: Int
) -> ReadinessScore {
    let needH = needSecs / 3600
    var c = ReadinessScore.Components()

    c.debt     = max(0, min(1, 1.0 - debtHours / (2.0 * needH)))
    c.duration = max(0, min(1.05, night.asleep / needSecs))

    if let hrv = night.avgHRV, hrv > 0, hrvMAD > 0 {
        let zLn = robustZ(log(hrv), med: log(max(1, hrvMedian)), mad: hrvMAD / max(1, hrvMedian))
        c.hrv = sigmoid(max(-3, min(1.5, zLn)) / 1.5)
    }
    if let hr = night.minHR, hr > 0, hrMAD > 0 {
        let z = robustZ(hr, med: hrMedian, mad: hrMAD)
        c.hr = sigmoid(-max(-1.5, min(3, z)) / 1.5)
    }

    let wasoMin = night.waso / 60
    c.continuity = 0.5 * max(0, min(1, (night.efficiency - 0.75) / 0.15))
                 + 0.5 * exp(-wasoMin / 45.0)
    c.alignment  = exp(-pow(sjlHours / 1.5, 2))

    if let rr = night.avgResp, rr > 0, respMAD > 0 {
        let z = robustZ(rr, med: respMedian, mad: respMAD)
        c.respiration = sigmoid(-max(-1.5, min(3, z)) / 1.5)
    }

    let weighted: [(Double, Double)] = [
        (c.debt, 0.30), (c.duration, 0.15), (c.hrv, 0.20), (c.hr, 0.12),
        (c.continuity, 0.10), (c.alignment, 0.08), (c.respiration, 0.05)
    ]
    var sumW = 0.0, sumV = 0.0
    for (v, w) in weighted where v >= 0 { sumV += v * w; sumW += w }
    let score = sumW > 0 ? 100.0 * sumV / sumW : 50.0

    let conf: String
    switch nightCount {
    case ..<14:  conf = "calibrando (\(nightCount)/14)"
    case 14..<28: conf = "confianza media"
    default:     conf = "confianza alta"
    }
    return ReadinessScore(value: score, confidence: conf, nightCount: nightCount, components: c)
}

// MARK: - Fase 2: SRI (Phillips et al. 2017; Windred et al. 2024)

/// Sleep Regularity Index on a binary sleep/wake grid [day][minute 0..1439].
func computeSRI(_ grid: [[Bool]]) -> Double {
    guard grid.count >= 2 else { return .nan }
    var matches = 0, total = 0
    for d in 0..<(grid.count - 1) {
        let len = min(grid[d].count, grid[d+1].count, 1440)
        for m in 0..<len {
            if grid[d][m] == grid[d+1][m] { matches += 1 }
            total += 1
        }
    }
    return total > 0 ? 200.0 * Double(matches) / Double(total) - 100.0 : .nan
}

/// Build binary sleep/wake grid from a list of nights (last `days` calendar days).
func buildSleepGrid(_ nights: [SleepNight], days: Int = 28) -> [[Bool]] {
    let cal = Calendar.current
    let now = Date()
    return (0..<days).reversed().map { offset -> [Bool] in
        guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { return [] }
        let dayStart = cal.startOfDay(for: day)
        var row = [Bool](repeating: false, count: 1440)
        for night in nights {
            let s = max(night.start, dayStart)
            let e = min(night.end,   dayStart.addingTimeInterval(86400))
            guard e > s else { continue }
            let sMin = max(0, Int(s.timeIntervalSince(dayStart) / 60))
            let eMin = min(1440, Int(e.timeIntervalSince(dayStart) / 60))
            for m in sMin..<eMin { row[m] = true }
        }
        return row
    }
}
