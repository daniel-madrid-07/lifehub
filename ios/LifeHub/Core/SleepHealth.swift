import Foundation
import HealthKit

/// Shared UserDefaults between LifeHub app and LifeHubWidgets extension.
let sleepUD = UserDefaults(suiteName: "group.com.example.lifehub") ?? .standard

// MARK: - Data models

struct SleepNight {
    var start: Date
    var end: Date
    var inBed: TimeInterval        // span desde primer hasta último asleep* (deduplicado)
    var asleep: TimeInterval       // TST real (deduplicado, Watch source)
    var waso: TimeInterval         // Wake After Sleep Onset
    var deep: TimeInterval
    var rem: TimeInterval
    var core: TimeInterval
    var awake: TimeInterval
    var avgHR: Double?
    var minHR: Double?
    var avgHRV: Double?
    var avgResp: Double?
    var wristTemp: Double?
    var avgSpO2: Double?
    var rmssd: Double?          // RMSSD from heartbeat series (ms); more robust than SDNN
    var hrNadirH: Double?       // hour of HR nadir [0, 24]
    var hrDip: Double?          // (rhrBaseline − hrMin) / rhrBaseline [0, 1]
    var possibleAlcohol: Bool = false
    var remEpisodes: Int = 0
    var confidence: NightConfidence = .normal

    var efficiency: Double { inBed > 0 ? min(1, asleep / inBed) : 0 }
}

enum NightConfidence { case normal, imputed, lowQuality }

struct SleepHistoryNight: Identifiable {
    let id = UUID()
    let date: Date
    let asleep: TimeInterval
    let isNap: Bool
}

// MARK: - Robust math helpers

/// Median of an array (unsorted OK)
func sleepMedian(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let s = values.sorted()
    let n = s.count
    return n % 2 == 0 ? (s[n/2 - 1] + s[n/2]) / 2 : s[n/2]
}

/// Median Absolute Deviation
func sleepMAD(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let m = sleepMedian(values)
    return sleepMedian(values.map { abs($0 - m) })
}

/// Robust z-score: 0.6745 · (x − median) / MAD  (comparable to σ under normality)
func robustZ(_ x: Double, med: Double, mad: Double) -> Double {
    guard mad > 0 else { return 0 }
    return 0.6745 * (x - med) / mad
}

/// Circular mean of hours in [0, 24]  — handles midnight wraparound correctly
func circularMean(_ hours: [Double]) -> Double {
    guard !hours.isEmpty else { return 0 }
    let w = 2 * Double.pi / 24
    let s = hours.reduce(0.0) { $0 + sin($1 * w) }
    let c = hours.reduce(0.0) { $0 + cos($1 * w) }
    var m = atan2(s, c) / w
    if m < 0 { m += 24 }
    return m
}

/// Resultant vector length R ∈ [0,1]: 1 = perfectly regular, 0 = random
func circularConcentration(_ hours: [Double]) -> Double {
    guard !hours.isEmpty else { return 0 }
    let w = 2 * Double.pi / 24
    let n = Double(hours.count)
    let s = hours.reduce(0.0) { $0 + sin($1 * w) } / n
    let c = hours.reduce(0.0) { $0 + cos($1 * w) } / n
    return sqrt(s * s + c * c)
}

/// Merge overlapping DateIntervals (input need not be sorted)
func mergeIntervals(_ ivs: [DateInterval]) -> [DateInterval] {
    let sorted = ivs.sorted { $0.start < $1.start }
    var out: [DateInterval] = []
    for iv in sorted {
        if let last = out.last, iv.start <= last.end {
            out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, iv.end))
        } else {
            out.append(iv)
        }
    }
    return out
}

// MARK: - SleepManager

@MainActor
final class SleepManager: ObservableObject {
    @Published var lastNight: SleepNight?
    @Published var history: [SleepHistoryNight] = []
    @Published var loaded = false
    @Published var denied = false

    // Personalised science — all derived robustly from history
    @Published var cycleLen: TimeInterval = 90 * 60
    @Published var cycleLenConfidence: Double = 0
    @Published var recoveryPoor = false
    @Published var chronoMidH: Double = 0
    @Published var chronoConcentration: Double = 0
    @Published var missingLastNight = false

    // Fase 1: two-process model state
    @Published var sNow: Double = 0.5             // current homeostatic pressure S
    @Published var debtHours: Double = 0          // D_fast + D_slow (hours)
    @Published var needSecs: TimeInterval = 8 * 3600
    @Published var habitualBedH: Double = 0       // circular mean of bed hours [0,24]
    @Published var habitualWakeH: Double = 0      // circular mean of wake hours [0,24]
    @Published var spielmanGuard: Bool = false     // efficiency < 85% → don't extend TIB

    // Fase 2: recovery + light
    @Published var readiness: ReadinessScore?
    @Published var sri: Double = .nan             // Sleep Regularity Index
    @Published var lightMinutesYesterday: Double? // timeInDaylight yesterday (min)
    @Published var validNightCount: Int = 0       // for readiness confidence
    @Published var sjlHours: Double = 0           // social jet lag (calendar-derived MSFsc)
    @Published var phaseDrift: TimeInterval?      // HR nadir drift vs 3–4 weeks ago (seconds)

    private let store = HKHealthStore()
    private var nightMidpointData: [(wakeDate: Date, midH: Double, tst: TimeInterval)] = []

    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        for id: HKQuantityTypeIdentifier in [.heartRate, .heartRateVariabilitySDNN,
                                              .respiratoryRate, .oxygenSaturation,
                                              .appleSleepingWristTemperature,
                                              .timeInDaylight] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { s.insert(t) }
        }
        s.insert(HKSeriesType.heartbeat())   // for RMSSD computation
        return s
    }

    func requestAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else { denied = true; loaded = true; return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            denied = true
        }
        await load()
    }

    func load() async {
        let now = Date()

        // Last night: 26 h window (catches late sleepers finishing past midnight)
        let rawLast = (try? await sleepSamples(from: now.addingTimeInterval(-26 * 3600), to: now)) ?? []
        let (mainLast, _) = classifyEpisodes(rawLast)

        missingLastNight = mainLast.isEmpty && rawLast.isEmpty

        if let lastGroup = groupIntoNights(mainLast).last, !lastGroup.isEmpty {
            lastNight = await buildNight(lastGroup)
            // RMSSD: only last night (enumerates individual heartbeats — expensive)
            if let ln = lastNight {
                var mln = ln
                mln.rmssd = await fetchRMSSD(from: ln.start, to: ln.end)
                lastNight = mln
            }
        }

        // History: 60 nights for robust baselines + S simulation
        let rawHistory = (try? await sleepSamples(from: now.addingTimeInterval(-60 * 86400), to: now)) ?? []
        let (mainHistory, napSamples) = classifyEpisodes(rawHistory)

        var builtNights: [SleepNight] = []
        for group in groupIntoNights(mainHistory) where !group.isEmpty {
            builtNights.append(await buildNight(group))
        }
        var napNights: [SleepNight] = []
        for group in groupIntoNights(napSamples) where !group.isEmpty {
            napNights.append(await buildNight(group))
        }

        let validNights = builtNights.filter { !isOutlier($0) }
        validNightCount = validNights.count

        // Chart: last 14 valid nights
        history = validNights.suffix(14).map { n in
            SleepHistoryNight(date: n.end, asleep: n.asleep, isNap: false)
        }

        analyzeRobust(validNights)
        computeHabitualTimes(validNights)
        runSSimulation(validNights: validNights, napNights: napNights, now: now)
        computeDebt(validNights: validNights)
        computeSpielmanGuard(validNights: validNights)
        computeNeed(validNights: validNights)

        if let n = lastNight { assessRecovery(n) }
        computeReadinessScore(lastNight: lastNight, validNights: validNights)

        // SRI and daylight
        await computeSRIFromNights(validNights)
        await fetchDaylight(now: now)

        loaded = true
    }

    // MARK: - Episode classification

    /// Splits samples into main sleep episodes and naps.
    /// Nap: starts 10:00–20:00 AND < 3 h.
    private func classifyEpisodes(_ samples: [HKCategorySample]) -> (main: [HKCategorySample], naps: [HKCategorySample]) {
        guard !samples.isEmpty else { return ([], []) }
        let cal = Calendar.current
        let sorted = samples.sorted { $0.startDate < $1.startDate }

        // Split into episodes by gaps > 2 h
        var episodes: [[HKCategorySample]] = []
        var cur: [HKCategorySample] = []
        for s in sorted {
            if let last = cur.last, s.startDate.timeIntervalSince(last.endDate) > 2 * 3600 {
                episodes.append(cur); cur = [s]
            } else {
                cur.append(s)
            }
        }
        if !cur.isEmpty { episodes.append(cur) }

        var main: [HKCategorySample] = []
        var naps: [HKCategorySample] = []
        for ep in episodes {
            guard let start = ep.first?.startDate, let end = ep.last?.endDate else { continue }
            let h = Double(cal.component(.hour, from: start)) + Double(cal.component(.minute, from: start)) / 60
            let dur = end.timeIntervalSince(start)
            if h >= 10 && h < 20 && dur < 3 * 3600 {
                naps.append(contentsOf: ep)
            } else {
                main.append(contentsOf: ep)
            }
        }
        return (main, naps)
    }

    /// Groups sorted samples into individual sleep episodes (split by gap > 6 h).
    private func groupIntoNights(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var groups: [[HKCategorySample]] = []
        var cur: [HKCategorySample] = []
        for s in sorted {
            if let last = cur.last, s.startDate.timeIntervalSince(last.endDate) > 6 * 3600 {
                if !cur.isEmpty { groups.append(cur) }
                cur = [s]
            } else {
                cur.append(s)
            }
        }
        if !cur.isEmpty { groups.append(cur) }
        return groups
    }

    // MARK: - Outlier rejection (from baselines only, not from S-model)

    private func isOutlier(_ n: SleepNight) -> Bool {
        if n.asleep < 3 * 3600 { return true }    // TST < 3 h
        if n.efficiency < 0.50 { return true }     // efficiency < 50 %
        return false
    }

    // MARK: - Robust analysis over history

    private func analyzeRobust(_ nights: [SleepNight]) {
        guard !nights.isEmpty else { return }
        let d = sleepUD

        // 1) Circular stats for chronotype (sleep midpoint)
        let midpoints = nights.map { n -> Double in
            let cal = Calendar.current
            let mid = n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) / 2)
            let h = Double(cal.component(.hour, from: mid)) + Double(cal.component(.minute, from: mid)) / 60
            return h   // [0, 24]
        }
        chronoMidH = circularMean(midpoints)
        chronoConcentration = circularConcentration(midpoints)
        d.set(chronoMidH, forKey: "sleep_mid_h")

        // 2) Theil-Sen cycle estimator with shrinkage toward 90 min
        estimateCycle(nights)

        // 3) Robust HRV / HR / respiration baselines (median + MAD)
        let hrvValues = nights.compactMap { $0.avgHRV }.filter { $0 > 0 }
        let hrValues  = nights.compactMap { $0.minHR  }.filter { $0 > 0 }
        let rrValues  = nights.compactMap { $0.avgResp }.filter { $0 > 0 }

        if !hrvValues.isEmpty {
            d.set(sleepMedian(hrvValues), forKey: "sleep_hrv_median")
            d.set(sleepMAD(hrvValues),    forKey: "sleep_hrv_mad")
        }
        if !hrValues.isEmpty {
            d.set(sleepMedian(hrValues), forKey: "sleep_hr_median")
            d.set(sleepMAD(hrValues),    forKey: "sleep_hr_mad")
        }
        if !rrValues.isEmpty {
            d.set(sleepMedian(rrValues), forKey: "sleep_resp_median")
            d.set(sleepMAD(rrValues),    forKey: "sleep_resp_mad")
        }

        // 4) RMSSD baselines (from whatever nights had it computed)
        let rmssdValues = nights.compactMap { $0.rmssd }.filter { $0 > 0 }
        if !rmssdValues.isEmpty {
            d.set(sleepMedian(rmssdValues), forKey: "sleep_rmssd_median")
            d.set(sleepMAD(rmssdValues),    forKey: "sleep_rmssd_mad")
        }

        // 5) Midpoint data for MSFsc (populated → applyCalendarEvents refines chronotype)
        let cal = Calendar.current
        nightMidpointData = nights.map { n in
            let mid = n.start.addingTimeInterval(n.end.timeIntervalSince(n.start) / 2)
            let h = Double(cal.component(.hour, from: mid)) + Double(cal.component(.minute, from: mid)) / 60
            return (n.end, h, n.asleep)
        }

        // 6) Phase drift from HR nadir history
        computePhaseDrift(nights)
    }

    /// Theil-Sen over TST/REMs + shrinkage toward 90 min prior (k = 12).
    /// With k nights: ĉ = (n/(n+12))·c̄_personal + (12/(n+12))·90 min
    private func estimateCycle(_ nights: [SleepNight]) {
        let d = sleepUD
        let prior = 90.0 * 60.0
        let k = 12.0

        // Use nights with ≥ 3 REM episodes detected
        let valid = nights.filter { $0.remEpisodes >= 3 }
        let n = Double(valid.count)

        if n >= 2 {
            // Raw estimate: median(TST / remEpisodes)
            let rawCycles = valid.map { $0.asleep / Double($0.remEpisodes) }
            let rawCycle  = sleepMedian(rawCycles)
            let clamped   = min(110 * 60, max(80 * 60, rawCycle))
            let shrunk    = (n / (n + k)) * clamped + (k / (n + k)) * prior
            cycleLen          = shrunk
            cycleLenConfidence = min(1.0, n / 40.0)   // saturates at 40 nights
        } else {
            let saved = d.double(forKey: "sleep_cycle_secs")
            cycleLen           = saved > 0 ? saved : prior
            cycleLenConfidence = 0
        }
        d.set(cycleLen, forKey: "sleep_cycle_secs")
    }

    /// Compares last night's HRV / HR against robust baselines.
    private func assessRecovery(_ n: SleepNight) {
        let d = sleepUD
        recoveryPoor = false

        let hrvMed = d.double(forKey: "sleep_hrv_median")
        let hrvMAD = d.double(forKey: "sleep_hrv_mad")
        let hrMed  = d.double(forKey: "sleep_hr_median")
        let hrMAD  = d.double(forKey: "sleep_hr_mad")

        if let hrv = n.avgHRV, hrv > 0, hrvMed > 0, hrvMAD > 0 {
            if robustZ(hrv, med: hrvMed, mad: hrvMAD) < -1.5 { recoveryPoor = true }
        }
        if let hr = n.minHR, hr > 0, hrMed > 0, hrMAD > 0 {
            if robustZ(hr, med: hrMed, mad: hrMAD) > 1.5 { recoveryPoor = true }
        }
        d.set(recoveryPoor ? cycleLen : 0, forKey: "sleep_recovery_extra_secs")
    }

    // MARK: - Fase 1: habitual times, S simulation, debt, need

    private func computeHabitualTimes(_ nights: [SleepNight]) {
        guard !nights.isEmpty else { return }
        let cal = Calendar.current
        func hourOf(_ d: Date) -> Double {
            Double(cal.component(.hour, from: d)) + Double(cal.component(.minute, from: d)) / 60
        }
        habitualBedH  = circularMean(nights.map { hourOf($0.start) })
        habitualWakeH = circularMean(nights.map { hourOf($0.end) })
        sleepUD.set(habitualBedH,  forKey: "sleep_habitual_bed_h")
        sleepUD.set(habitualWakeH, forKey: "sleep_habitual_wake_h")
    }

    private func runSSimulation(validNights: [SleepNight], napNights: [SleepNight], now: Date) {
        guard !validNights.isEmpty else { return }
        let historyStart = validNights.first!.start
        let allIntervals = (validNights + napNights)
            .sorted { $0.start < $1.start }
            .map { DateInterval(start: $0.start, end: $0.end) }
        let model = TwoProcess()
        sNow = model.simulate(asleepIntervals: allIntervals, from: historyStart, to: now)
        sleepUD.set(sNow, forKey: "sleep_s_now")
        sleepUD.set(now.timeIntervalSince1970, forKey: "sleep_s_timestamp")
    }

    /// Recomputes the two-scale debt from the last 60 nights in chronological order.
    private func computeDebt(validNights: [SleepNight]) {
        var model = SleepDebtModel()
        for night in validNights {
            model.update(tst: night.asleep, need: needSecs)
        }
        debtHours = model.total
        model.save()
        sleepUD.set(debtHours, forKey: "sleep_debt_hours")
    }

    private func computeSpielmanGuard(validNights: [SleepNight]) {
        let recent = validNights.suffix(5).map { $0.efficiency }
        spielmanGuard = recent.count >= 3 && sleepMedian(recent) < 0.85
    }

    /// Personal sleep need = median TST of nights without alarm / early events.
    /// Falls back to 8 h if fewer than 5 qualifying nights.
    private func computeNeed(validNights: [SleepNight]) {
        // Approximate free nights: TST > 7 h (user slept to natural completion)
        let freeNights = validNights.filter { $0.asleep > 7 * 3600 && $0.efficiency > 0.88 }
        if freeNights.count >= 5 {
            let rawNeed = sleepMedian(freeNights.map { $0.asleep })
            needSecs = min(9.5 * 3600, max(6.5 * 3600, rawNeed))
        } else {
            needSecs = 8 * 3600
        }
        sleepUD.set(needSecs, forKey: "sleep_need_secs")
    }

    // MARK: - Fase 2: readiness score

    private func computeReadinessScore(lastNight: SleepNight?, validNights: [SleepNight]) {
        guard let night = lastNight, validNightCount >= 7 else { return }
        let d = sleepUD

        // HRV: prefer RMSSD (from heartbeat series) over SDNN (Apple aggregate)
        let rmssdMed = d.double(forKey: "sleep_rmssd_median")
        let rmssdMAD = d.double(forKey: "sleep_rmssd_mad")
        let useRMSSD = rmssdMed > 0 && (night.rmssd ?? 0) > 0
        let hrvMed  = useRMSSD ? rmssdMed : d.double(forKey: "sleep_hrv_median")
        let hrvMAD  = useRMSSD ? rmssdMAD : d.double(forKey: "sleep_hrv_mad")
        let hrMed   = d.double(forKey: "sleep_hr_median")
        let hrMAD   = d.double(forKey: "sleep_hr_mad")
        let respMed = d.double(forKey: "sleep_resp_median")
        let respMAD = d.double(forKey: "sleep_resp_mad")

        // SJL: prefer calendar-derived sjlHours; fall back to midpoint-vs-chronotype
        let sjl: Double
        if sjlHours > 0 {
            sjl = sjlHours
        } else {
            let cal = Calendar.current
            let mid = night.start.addingTimeInterval(night.end.timeIntervalSince(night.start) / 2)
            let midH = Double(cal.component(.hour, from: mid)) + Double(cal.component(.minute, from: mid)) / 60
            var raw = abs(midH - chronoMidH); if raw > 12 { raw = 24 - raw }
            sjl = raw
        }

        // Substitute RMSSD as HRV value for the readiness function
        var nightAdj = night
        if useRMSSD { nightAdj.avgHRV = night.rmssd }

        readiness = computeReadiness(
            night: nightAdj, debtHours: debtHours, needSecs: needSecs,
            sjlHours: sjl,
            hrvMedian: hrvMed, hrvMAD: hrvMAD,
            hrMedian: hrMed,   hrMAD: hrMAD,
            respMedian: respMed, respMAD: respMAD,
            nightCount: validNightCount
        )
    }

    // MARK: - Fase 2: SRI

    private func computeSRIFromNights(_ validNights: [SleepNight]) async {
        let grid = buildSleepGrid(validNights, days: 28)
        sri = computeSRI(grid)
    }

    // MARK: - Fase 2: timeInDaylight

    private func fetchDaylight(now: Date) async {
        guard let type = HKObjectType.quantityType(forIdentifier: .timeInDaylight) else { return }
        let cal = Calendar.current
        let yesterdayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: now)!)
        let yesterdayEnd   = cal.startOfDay(for: now)
        let pred = HKQuery.predicateForSamples(withStart: yesterdayStart, end: yesterdayEnd, options: [])
        let result = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .minute()))
            }
            store.execute(q)
        }
        lightMinutesYesterday = result
    }

    // MARK: - Night builder

    private func buildNight(_ samples: [HKCategorySample]) async -> SleepNight {
        // Filter to Watch source; fall back to all sources if Watch data is absent
        let watchSamples = samples.filter {
            $0.sourceRevision.productType?.hasPrefix("Watch") == true
        }
        let stageSource = watchSamples.isEmpty ? samples : watchSamples
        let lowConf     = watchSamples.isEmpty

        // Deduplicated TST and WASO via sleepMetrics
        let (periodo, tst, waso) = sleepMetrics(from: samples)

        var deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0
        var remEpisodes = 0, prevWasREM = false
        var minStart = Date.distantFuture, maxEnd = Date.distantPast

        for s in stageSource.sorted(by: { $0.startDate < $1.startDate }) {
            let dur  = s.endDate.timeIntervalSince(s.startDate)
            let isREM = s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            if isREM && !prevWasREM { remEpisodes += 1 }
            if isREM || s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                     || s.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                prevWasREM = isREM
            }
            switch s.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: deep += dur
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:  rem  += dur
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: core += dur
            case HKCategoryValueSleepAnalysis.awake.rawValue: awake += dur
            default: break
            }
            minStart = min(minStart, s.startDate)
            maxEnd   = max(maxEnd,   s.endDate)
        }

        let start = minStart == .distantFuture ? (samples.first?.startDate ?? Date()) : minStart
        let end   = maxEnd   == .distantPast   ? (samples.last?.endDate   ?? Date()) : maxEnd

        // Use deduplicated values; fall back to raw sums if sleepMetrics returned 0
        let effectiveTST   = tst    > 0 ? tst    : deep + rem + core
        let effectiveInBed = periodo > 0 ? periodo : max(deep + rem + core + awake, end.timeIntervalSince(start))

        var n = SleepNight(start: start, end: end, inBed: effectiveInBed,
                           asleep: effectiveTST, waso: waso,
                           deep: deep, rem: rem, core: core, awake: awake)
        n.remEpisodes = remEpisodes
        n.confidence  = lowConf ? .lowQuality : .normal
        n.avgHR   = await stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteAverage)
        n.minHR   = await stat(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteMin)
        n.avgHRV  = await stat(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end, op: .discreteAverage)
        n.avgResp = await stat(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: end, op: .discreteAverage)
        n.avgSpO2 = await stat(.oxygenSaturation, unit: .percent(), from: start, to: end, op: .discreteAverage)
        n.wristTemp = await stat(.appleSleepingWristTemperature, unit: .degreeCelsius(), from: start, to: end, op: .discreteAverage)

        // HR curve features: nadir, dip depth, alcohol signature
        let rhrBaseline = sleepUD.double(forKey: "sleep_hr_median")
        let feat = await fetchHRFeatures(from: start, to: end, rhrBaseline: rhrBaseline > 30 ? rhrBaseline : 0)
        n.hrNadirH      = feat.nadirH
        n.hrDip         = feat.dip
        n.possibleAlcohol = feat.alcohol

        return n
    }

    // MARK: - sleepMetrics — deduplication (sleep.md §6.3)

    /// Filters to Apple Watch source and merges overlapping intervals to avoid double-counting.
    /// Falls back to all sources if Watch data is absent.
    func sleepMetrics(from samples: [HKCategorySample])
            -> (periodo: TimeInterval, tst: TimeInterval, waso: TimeInterval) {

        let watch  = samples.filter { $0.sourceRevision.productType?.hasPrefix("Watch") == true }
        let source = watch.isEmpty ? samples : watch

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]

        let asleepIntervals = mergeIntervals(
            source.filter { asleepValues.contains($0.value) }
                  .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        )
        let awakeIntervals = mergeIntervals(
            source.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
                  .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        )

        let tst = asleepIntervals.reduce(0.0) { $0 + $1.duration }
        guard let first = asleepIntervals.first?.start, let last = asleepIntervals.last?.end else {
            return (0, 0, 0)
        }
        let span = DateInterval(start: first, end: last)
        let waso = awakeIntervals.filter { span.intersects($0) }.reduce(0.0) { $0 + $1.duration }
        return (span.duration, tst, waso)
    }

    // MARK: - HealthKit queries

    private func sleepSamples(from: Date, to: Date) async throws -> [HKCategorySample] {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, res, err in
                if let err { cont.resume(throwing: err); return }
                cont.resume(returning: (res as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - RMSSD from heartbeat series (Fase 2)

    private func fetchRMSSD(from: Date, to: Date) async -> Double? {
        let seriesType = HKSeriesType.heartbeat()
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])

        let series: [HKHeartbeatSeriesSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: seriesType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKHeartbeatSeriesSample]) ?? [])
            }
            store.execute(q)
        }
        guard !series.isEmpty else { return nil }

        var allRR: [Double] = []
        for s in series {
            var beats: [(t: TimeInterval, gap: Bool)] = []
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let q = HKHeartbeatSeriesQuery(heartbeatSeries: s) { _, t, preceded, done, _ in
                    if !done { beats.append((t, preceded)) }
                    if done { cont.resume() }
                }
                store.execute(q)
            }
            let sorted = beats.sorted { $0.t < $1.t }
            for i in 1..<sorted.count {
                if sorted[i].gap { continue }
                let rr = sorted[i].t - sorted[i-1].t
                if rr >= 0.3 && rr <= 1.5 { allRR.append(rr) }
            }
        }
        guard allRR.count >= 10 else { return nil }

        var sq: [Double] = []
        for i in 1..<allRR.count {
            let diff = allRR[i] - allRR[i-1]
            if abs(diff) <= 0.2 * allRR[i-1] { sq.append(diff * diff) }
        }
        guard !sq.isEmpty else { return nil }
        return sqrt(sq.reduce(0, +) / Double(sq.count)) * 1000   // ms
    }

    // MARK: - HR curve features (nadir, dip, alcohol) (Fase 2)

    private func fetchHRFeatures(from: Date, to: Date, rhrBaseline: Double)
            async -> (nadirH: Double?, dip: Double?, alcohol: Bool) {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return (nil, nil, false) }
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())

        let samples: [(Date, Double)] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, res, _ in
                let pairs = (res as? [HKQuantitySample])?.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) } ?? []
                cont.resume(returning: pairs)
            }
            store.execute(q)
        }
        guard samples.count >= 10 else { return (nil, nil, false) }

        let cal = Calendar.current
        let duration = to.timeIntervalSince(from)
        let nBins = max(1, Int(duration / 1800))
        var binMinima: [(Date, Double)] = []
        for b in 0..<nBins {
            let bs = from.addingTimeInterval(Double(b) * 1800)
            let be = bs.addingTimeInterval(1800)
            let vals = samples.filter { $0.0 >= bs && $0.0 < be }.map { $0.1 }
            if !vals.isEmpty { binMinima.append((bs, sleepMedian(vals))) }
        }
        var nadirH: Double? = nil
        if let nadir = binMinima.min(by: { $0.1 < $1.1 }) {
            nadirH = Double(cal.component(.hour, from: nadir.0)) + Double(cal.component(.minute, from: nadir.0)) / 60
        }

        var dip: Double? = nil
        if rhrBaseline > 0, let minHR = samples.map({ $0.1 }).min(), rhrBaseline > minHR {
            dip = (rhrBaseline - minHR) / rhrBaseline
        }

        let midT = from.addingTimeInterval(duration / 2)
        let first  = samples.filter { $0.0 < midT }.map { $0.1 }
        let second = samples.filter { $0.0 >= midT }.map { $0.1 }
        var alcohol = false
        if !first.isEmpty && !second.isEmpty && rhrBaseline > 0 {
            alcohol = (sleepMedian(first) - sleepMedian(second)) > 0.10 * rhrBaseline
        }
        return (nadirH, dip, alcohol)
    }

    // MARK: - Phase drift detector (Fase 2)

    private func computePhaseDrift(_ nights: [SleepNight]) {
        let now = Date()
        let recent = nights.filter { now.timeIntervalSince($0.end) <= 7 * 86400 }.compactMap { $0.hrNadirH }
        let older  = nights.filter {
            let age = now.timeIntervalSince($0.end)
            return age > 21 * 86400 && age <= 28 * 86400
        }.compactMap { $0.hrNadirH }

        guard recent.count >= 3 && older.count >= 2 else { phaseDrift = nil; return }

        let recentMed = circularMean(recent)
        let olderMed  = circularMean(older)
        var diff = recentMed - olderMed
        while diff >  12 { diff -= 24 }
        while diff < -12 { diff += 24 }
        phaseDrift = abs(diff) > 0.5 ? diff * 3600 : nil
    }

    // MARK: - MSFsc from calendar events (Fase 1)

    /// Refines chronotype using Roenneberg MSFsc formula.
    /// Call after requestAndLoad() with the same calendar events used for deadline detection.
    func applyCalendarEvents(_ events: [CalendarEvent]) {
        guard !nightMidpointData.isEmpty else { return }
        let cal = Calendar.current

        var freeMids: [Double] = [], freeTSTs: [TimeInterval] = []
        var workMids: [Double] = [], workTSTs: [TimeInterval] = []

        for (wakeDate, midH, tst) in nightMidpointData {
            guard let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: wakeDate) else { continue }
            let dayStart = cal.startOfDay(for: wakeDate)
            let hasEarlyEvent = events.contains { e in
                guard let s = Fmt.date(e.start) else { return false }
                return s >= dayStart && s < nineAM
            }
            if hasEarlyEvent { workMids.append(midH); workTSTs.append(tst) }
            else             { freeMids.append(midH); freeTSTs.append(tst) }
        }

        guard freeMids.count >= 3 else { return }

        let msf     = circularMean(freeMids)
        let sdFreeH = sleepMedian(freeTSTs) / 3600
        let sdWorkH = workTSTs.isEmpty ? sdFreeH : sleepMedian(workTSTs) / 3600
        let n = Double(nightMidpointData.count), nFree = Double(freeMids.count)
        let sdWeekH = (sdWorkH * (n - nFree) + sdFreeH * nFree) / n
        let msfsc   = sdFreeH > sdWorkH ? msf - (sdFreeH - sdWeekH) / 2 : msf

        if !workMids.isEmpty {
            let msmw = circularMean(workMids)
            var sjl = msfsc - msmw
            while sjl >  12 { sjl -= 24 }
            while sjl < -12 { sjl += 24 }
            sjlHours = abs(sjl)
            sleepUD.set(sjlHours, forKey: "sleep_sjl_hours")
        }

        chronoMidH = msfsc
        sleepUD.set(msfsc, forKey: "sleep_mid_h")
    }

    private func stat(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date,
                      op: HKStatisticsOptions) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: op) { _, stats, _ in
                let qty = op == .discreteMin ? stats?.minimumQuantity()
                        : op == .discreteMax ? stats?.maximumQuantity()
                        : stats?.averageQuantity()
                cont.resume(returning: qty?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }
}
