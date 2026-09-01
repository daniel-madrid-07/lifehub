import Combine
import WatchKit
import CoreMotion
import HealthKit

/// Alarma inteligente: detecta momentos de sueño ligero en la ventana de −30 min
/// y dispara el háptico. Siempre dispara en el deadline duro como seguro.
///
/// ⚠️  Regla crítica de Apple: si una sesión de alarma no llama a notifyUser,
/// el sistema advierte al usuario y puede revocar el permiso. Aquí disparamos
/// siempre, como mínimo en el deadline.
///
/// Uso:  SmartAlarm.shared.schedule(alarmAt: wake)  — DESDE EL PRIMER PLANO.
@MainActor
final class SmartAlarm: NSObject, ObservableObject {

    static let shared = SmartAlarm()

    enum State { case idle, scheduled, active, fired }
    @Published var state: State = .idle
    @Published var batteryUsed: Float = 0   // % reportado en UI (honestidad)

    private var session: WKExtendedRuntimeSession?
    private var pendingSession: WKExtendedRuntimeSession?   // next night, pre-scheduled
    private var pendingDeadline: Date?
    private let motion = CMMotionManager()
    private let store  = HKHealthStore()

    private var deadline: Date = .distantFuture
    private var epochs: [(Date, Double)] = []   // (timestamp, activity count)
    private var fired = false
    private var batteryAtStart: Float = 0

    // Baseline de actividad: mediana + MAD de los primeros ≤10 epochs (sueño tranquilo)
    private var actMed: Double = 0
    private var actMAD: Double = 1

    // HR actual (actualizado por query anclado de HealthKit)
    private var currentHR: Double = 60
    private var hrMed: Double = 60
    private var hrMAD: Double = 5
    private var hrQuery: HKAnchoredObjectQuery?

    // MARK: - Programar alarma (llamar DESDE EL PRIMER PLANO)

    func schedule(alarmAt: Date) {
        cancel()
        deadline = alarmAt
        fired    = false
        epochs.removeAll()

        // Persist wake hour for auto-rescheduling and SleepAlarmView default
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: alarmAt)) + Double(cal.component(.minute, from: alarmAt)) / 60
        UserDefaults.standard.set(h, forKey: "sleep_alarm_wake_h")

        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start(at: alarmAt.addingTimeInterval(-30 * 60))
        session = s
        state   = .scheduled
    }

    func cancel() {
        session?.invalidate()
        session = nil
        pendingSession?.invalidate()
        pendingSession = nil
        pendingDeadline = nil
        motion.stopAccelerometerUpdates()
        if let q = hrQuery { store.stop(q); hrQuery = nil }
        state = .idle
        fired = false
    }

    // MARK: - Auto-reprogramación de la siguiente noche

    /// Schedules tomorrow's session while the current session is alive (workaround for
    /// WKExtendedRuntimeSession's "foreground-only" scheduling restriction).
    private func scheduleNextNight() {
        let wakeH = UserDefaults.standard.double(forKey: "sleep_alarm_wake_h")
        guard wakeH > 0 else { return }
        let cal = Calendar.current
        let h = Int(wakeH), m = Int((wakeH - Double(h)) * 60)
        let tomorrowBase = cal.date(byAdding: .day, value: 1, to: deadline)!
        guard let nextWake = cal.date(bySettingHour: h, minute: m, second: 0, of: tomorrowBase) else { return }

        let next = WKExtendedRuntimeSession()
        next.delegate = self
        next.start(at: nextWake.addingTimeInterval(-30 * 60))
        pendingSession  = next
        pendingDeadline = nextWake
    }

    // MARK: - Actigrafía CoreMotion (25 Hz, épocas de 30 s)

    private func startActigraphy() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 25.0
        var buf: [Double] = []
        var epochStart = Date()

        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.acceleration else { return }
            // Magnitud sin gravedad
            let mag = abs(sqrt(a.x*a.x + a.y*a.y + a.z*a.z) - 1.0)
            buf.append(mag)

            if Date().timeIntervalSince(epochStart) >= 30 {
                // Activity count: desviación rectificada respecto a la media de la época
                let mean  = buf.reduce(0, +) / Double(buf.count)
                let count = buf.reduce(0) { $0 + abs($1 - mean) }
                self.epochs.append((epochStart, count))
                self.updateBaseline()
                self.evaluate()
                buf.removeAll(keepingCapacity: true)
                epochStart = Date()
            }
        }
    }

    private func updateBaseline() {
        let sample = epochs.prefix(min(epochs.count, 10)).map(\.1)
        guard sample.count >= 3 else { return }
        actMed = alarmMedian(sample)
        actMAD = alarmMAD(sample)
    }

    // MARK: - Monitoreo de HR (HealthKit anclado)

    private func startHRMonitoring() {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let q = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: nil,
                                       limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            guard let self, let s = (samples as? [HKQuantitySample])?.last else { return }
            let hr = s.quantity.doubleValue(for: unit)
            Task { @MainActor in self.currentHR = hr }
        }
        q.updateHandler = { [weak self] _, samples, _, _, _ in
            guard let self, let s = (samples as? [HKQuantitySample])?.last else { return }
            let hr = s.quantity.doubleValue(for: unit)
            Task { @MainActor in self.currentHR = hr }
        }
        store.execute(q)
        hrQuery = q
    }

    // MARK: - Regla de disparo (umbral que decae linealmente)

    private func evaluate() {
        guard !fired, let last = epochs.last else { return }
        let remaining = deadline.timeIntervalSince(last.0)

        if remaining <= 30 { fire(reason: "deadline"); return }

        // z-scores robustos
        let zAct: Double = actMAD > 0 ? 0.6745 * (last.1  - actMed)  / actMAD  : 0
        let zHR:  Double = hrMAD  > 0 ? 0.6745 * (currentHR - hrMed) / hrMAD   : 0
        let score = 0.7 * zAct + 0.3 * zHR

        // Umbral lineal: 2.0 con 30 min restantes → 0.0 en el deadline
        let theta = 2.0 * (remaining / (30 * 60))
        if score > theta { fire(reason: "arousal") }
    }

    private func fire(reason: String) {
        guard !fired else { return }
        fired = true
        motion.stopAccelerometerUpdates()
        if let q = hrQuery { store.stop(q); hrQuery = nil }
        state = .fired

        let levelNow = WKInterfaceDevice.current().batteryLevel
        batteryUsed = max(0, batteryAtStart - levelNow)

        // Notificar siempre — si no lo hacemos, Apple puede revocar el permiso.
        session?.notifyUser(hapticType: .notification) { type in
            type.pointee = .notification
            return 2.0   // repetir cada 2 s hasta que el usuario lo silencie
        }
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension SmartAlarm: WKExtendedRuntimeSessionDelegate {

    func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {
        // If the pending session is the one starting, it's the next night
        if s === pendingSession {
            if let pd = pendingDeadline { deadline = pd }
            pendingSession  = nil
            pendingDeadline = nil
            fired = false
            epochs.removeAll()
            session = s
        }
        state = .active
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        batteryAtStart = WKInterfaceDevice.current().batteryLevel
        startActigraphy()
        startHRMonitoring()
        scheduleNextNight()   // while app has runtime, queue the night after
    }

    func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {
        // La sesión está a punto de expirar — disparar si no lo hemos hecho.
        fire(reason: "willExpire")
    }

    func extendedRuntimeSession(_ s: WKExtendedRuntimeSession,
                                 didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                 error: Error?) {
        if !fired { fire(reason: "invalidated") }
        if state != .fired { state = .idle }
    }
}

// MARK: - Math helpers (watch target no comparte los del iOS app)

private func alarmMedian(_ v: [Double]) -> Double {
    let s = v.sorted(), n = s.count
    return n % 2 == 0 ? (s[n/2-1] + s[n/2]) / 2 : s[n/2]
}
private func alarmMAD(_ v: [Double]) -> Double {
    let m = alarmMedian(v)
    return alarmMedian(v.map { abs($0 - m) })
}
