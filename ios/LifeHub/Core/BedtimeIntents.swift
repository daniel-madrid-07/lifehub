import AppIntents
import Foundation

/// Cálculo de hora de dormir / alarma, reutilizable desde la app y desde Atajos.
enum BedtimeEngine {
    static let latency: TimeInterval = 15 * 60

    /// Plan de sueño usando el optimizador de dos procesos (valores persistidos por SleepManager).
    static func plan() async -> (wake: Date, bed: Date) {
        let ud = sleepUD

        let sNow    = ud.double(forKey: "sleep_s_now").isNaN ? 0.5 : max(0.01, ud.double(forKey: "sleep_s_now"))
        let debt    = max(0, ud.double(forKey: "sleep_debt_hours"))
        let need    = ud.double(forKey: "sleep_need_secs") > 0 ? ud.double(forKey: "sleep_need_secs") : 8 * 3600
        let bedH    = ud.double(forKey: "sleep_habitual_bed_h")
        let wakeH   = ud.double(forKey: "sleep_habitual_wake_h")
        let midH    = ud.double(forKey: "sleep_mid_h")

        // Deadline from first event tomorrow
        var deadline: Date? = nil
        if let events = (try? await API.shared.calendar())?.events {
            let cal = Calendar.current
            if let ev = events.filter({ e in
                    guard let d = Fmt.date(e.start) else { return false }
                    return cal.isDateInTomorrow(d) && (e.start ?? "").contains("T")
                }).min(by: { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }),
               let s = Fmt.date(ev.start) {
                deadline = s.addingTimeInterval(-45 * 60)
            }
        }

        // Use optimizer if habitual times are available, else heuristic
        if bedH > 0 {
            let rec = BedtimeOptimizer.run(
                sNow: sNow > 0 ? sNow : 0.5,
                model: TwoProcess(),
                debtHours: debt,
                needSecs: need,
                habitualBedH: bedH,
                habitualWakeH: wakeH > 0 ? wakeH : 7.5,
                msfsc: midH > 0 ? midH : 4.0,
                deadline: deadline,
                spielmanGuard: false,
                now: Date()
            )
            return (rec.wake, rec.bedtime)
        }

        // Heuristic fallback
        let cycle = ud.double(forKey: "sleep_cycle_secs") > 0 ? ud.double(forKey: "sleep_cycle_secs") : 90 * 60
        let n = max(4, min(6, Int(((need + ud.double(forKey: "sleep_recovery_extra_secs")) / cycle).rounded())))
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        var wake = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)!
        if midH > 0 {
            let clk = midH.truncatingRemainder(dividingBy: 24)
            if let mid = cal.date(bySettingHour: Int(clk), minute: Int((clk - floor(clk)) * 60), second: 0, of: tomorrow) {
                wake = mid.addingTimeInterval(Double(n) * cycle / 2)
            }
        }
        if let d = deadline, d < wake { wake = d }
        return (wake, wake.addingTimeInterval(-(latency + Double(n) * cycle)))
    }

    static func recommendedWake() async -> Date { await plan().wake }
    static func recommendedBedtime() async -> Date { await plan().bed }
}

/// Atajo: devuelve la hora de alarma recomendada (para encadenar con "Crear alarma").
struct RecommendedAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Hora de alarma recomendada"
    static var description = IntentDescription("Calcula a qué hora poner la alarma según tu agenda de mañana y tu objetivo de sueño.")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let alarm = await BedtimeEngine.recommendedWake()
        let hm = alarm.formatted(.dateTime.hour().minute())
        return .result(value: alarm, dialog: "Pon la alarma a las \(hm).")
    }
}

/// Atajo: devuelve la hora de dormir recomendada.
struct RecommendedBedtimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Hora de dormir recomendada"
    static var description = IntentDescription("Calcula a qué hora acostarte para llegar a tu objetivo de sueño.")

    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let bedtime = await BedtimeEngine.recommendedBedtime()
        let hm = bedtime.formatted(.dateTime.hour().minute())
        return .result(value: bedtime, dialog: "Acuéstate a las \(hm).")
    }
}

struct LifeHubShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecommendedAlarmIntent(),
                    phrases: ["Hora de alarma de \(.applicationName)"],
                    shortTitle: "Alarma recomendada",
                    systemImageName: "alarm")
        AppShortcut(intent: RecommendedBedtimeIntent(),
                    phrases: ["Hora de dormir de \(.applicationName)"],
                    shortTitle: "Hora de dormir",
                    systemImageName: "moon.stars")
    }
}
