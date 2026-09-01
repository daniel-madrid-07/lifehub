import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v11 — dos caminos (tiempo real + recuento offline).
//
// Camino 1 (tiempo real, causal): pipeline v10 (aceleración → paso-alto →
// integra a velocidad → paso-alto → PCA en streaming → conteo por ciclo). Da el
// háptico y un contador PROVISIONAL en vivo.
//
// Camino 2 (offline, al terminar la serie): se guarda toda la serie de `velHP`
// 3D en un buffer y al terminar se recalcula el número REAL con un pase batch:
//  - PCA sobre la serie completa → eje exacto (incluida la 1ª repe).
//  - Suavizado ida y vuelta (fase cero) → extremos bien alineados.
//  - Umbral global por percentil de amplitud + refractario adaptativo.
//  - Se excluye la ventana de gracia inicial y la de la sacudida final.
// Ese número (`reconciledCount()`) es el que se envía al backend.
//
// Memoria de calibración por ejercicio (UserDefaults, clave = exercise_id):
// mediana de amplitud y de periodo, para fijar el suelo y el refractario de
// cada ejercicio (arregla recorridos cortos sin bajar el suelo global).
final class RepDetector: ObservableObject {
    @Published var reps = 0                 // contador provisional en vivo
    @Published var running = false
    @Published var manual = false
    @Published var shakeCount = 0

    enum Mode { case auto, manual }
    struct Profile { var mode: Mode; var floor: Double; var frac: Double; var minRep: Double }

    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        if n.contains("leg extension") || n.contains("leg curl") || n.contains("leg press")
            || n.contains("extension de cuadriceps") || n.contains("extensión de cuádriceps")
            || n.contains("curl femoral") || n.contains("femoral")
            || n.contains("prensa") || n.contains("quad") {
            return Profile(mode: .manual, floor: 0, frac: 0, minRep: 0)
        }
        return Profile(mode: .auto, floor: 0.045, frac: 0.40, minRep: 0.7)
    }

    private var profile = Profile(mode: .auto, floor: 0.045, frac: 0.40, minRep: 0.7)
    private let graceStart = 1.0

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    private var counting = false
    private var setStartT: TimeInterval = -1
    private var exerciseId = 0
    private var loadedFloor = 0.045
    private var loadedMinGap = 0.6
    private var lastShakeT: TimeInterval = 0

    // Filtros (por eje)
    private var aPrev = [0.0, 0.0, 0.0]
    private var aHP = [0.0, 0.0, 0.0]
    private var vel = [0.0, 0.0, 0.0]
    private var velPrev = [0.0, 0.0, 0.0]
    private var velHP = [0.0, 0.0, 0.0]
    // PCA streaming
    private var c00 = 0.0, c01 = 0.0, c02 = 0.0, c11 = 0.0, c12 = 0.0, c22 = 0.0
    private var pc = [1.0, 0.0, 0.0]
    // Ciclo streaming
    private var sm = 0.0, envelope = 0.0
    private var seenPos = false, seenNeg = false
    private var lastRep: TimeInterval = 0, lastT: TimeInterval = 0
    // Sacudida
    private var spikeTimes: [TimeInterval] = []
    private var lastShake: TimeInterval = 0
    // Buffer para el recuento offline
    private var bt: [Double] = [], bx: [Double] = [], by: [Double] = [], bz: [Double] = []

    // ── Ciclo de vida ────────────────────────────────────────────────────────

    func startMonitoring() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.process(d)
        }
    }

    func stopMonitoring() {
        counting = false; running = false
        motion.stopDeviceMotionUpdates()
    }

    func beginSet(for exerciseName: String, id: Int) {
        profile = Self.profile(for: exerciseName)
        exerciseId = id
        loadCalibration()
        reps = 0
        aPrev = [0,0,0]; aHP = [0,0,0]; vel = [0,0,0]; velPrev = [0,0,0]; velHP = [0,0,0]
        c00 = 0; c01 = 0; c02 = 0; c11 = 0; c12 = 0; c22 = 0; pc = [1,0,0]
        sm = 0; envelope = 0; seenPos = false; seenNeg = false; lastRep = 0
        setStartT = -1
        bt.removeAll(keepingCapacity: true); bx.removeAll(keepingCapacity: true)
        by.removeAll(keepingCapacity: true); bz.removeAll(keepingCapacity: true)
        counting = true; running = true
        manual = profile.mode == .manual
        startMonitoring()
    }

    func endSet() {
        counting = false; running = false
        lastShakeT = lastShake
    }

    // ── Proceso por muestra ──────────────────────────────────────────────────

    private func process(_ d: CMDeviceMotion) {
        let t = d.timestamp
        let dt = lastT > 0 ? min(0.1, t - lastT) : 1.0 / 50.0
        lastT = t

        detectShake(d, t: t)

        guard counting else { return }
        // Pierna (máquina): la muñeca no se traslada, así que cada repe se marca
        // con un TOQUE seco (mano en el muslo o flick de muñeca) → pico de
        // aceleración claro, por encima del ruido de estar quieto.
        if manual { detectTap(d, t: t); return }

        if setStartT < 0 { setStartT = t }
        let elapsed = t - setStartT
        let warming = elapsed < graceStart

        let a = [d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z]
        let hpA = 1.0 / (1.0 + dt)
        let hpV = 1.5 / (1.5 + dt)
        for i in 0..<3 {
            aHP[i] = hpA * (aHP[i] + a[i] - aPrev[i]); aPrev[i] = a[i]
            vel[i] += aHP[i] * 9.81 * dt
            velHP[i] = hpV * (velHP[i] + vel[i] - velPrev[i]); velPrev[i] = vel[i]
        }

        // Guarda para el recuento offline (limita a ~120 s por seguridad).
        if bt.count < 6000 { bt.append(t); bx.append(velHP[0]); by.append(velHP[1]); bz.append(velHP[2]) }

        // PCA streaming con "anneal": converge rápido al principio.
        let aCov = elapsed < 2.0 ? 0.15 : 0.04
        let x = velHP
        c00 += aCov*(x[0]*x[0]-c00); c01 += aCov*(x[0]*x[1]-c01); c02 += aCov*(x[0]*x[2]-c02)
        c11 += aCov*(x[1]*x[1]-c11); c12 += aCov*(x[1]*x[2]-c12); c22 += aCov*(x[2]*x[2]-c22)
        for _ in 0..<2 {
            let m0 = c00*pc[0]+c01*pc[1]+c02*pc[2]
            let m1 = c01*pc[0]+c11*pc[1]+c12*pc[2]
            let m2 = c02*pc[0]+c12*pc[1]+c22*pc[2]
            let mn = (m0*m0+m1*m1+m2*m2).squareRoot()
            if mn > 1e-9 {
                var nv = [m0/mn, m1/mn, m2/mn]
                if nv[0]*pc[0]+nv[1]*pc[1]+nv[2]*pc[2] < 0 { nv = [-nv[0], -nv[1], -nv[2]] }
                pc = nv
            }
        }

        let s = velHP[0]*pc[0] + velHP[1]*pc[1] + velHP[2]*pc[2]
        sm = 0.4 * s + 0.6 * sm

        let mag = abs(sm)
        if mag > envelope { envelope += 0.15*(mag-envelope) } else { envelope += 0.02*(mag-envelope) }
        if warming { return }

        let hi = max(loadedFloor, envelope * profile.frac)
        let lo = hi * 0.30
        if sm > hi { seenPos = true }
        if sm < -hi { seenNeg = true }
        if abs(sm) < lo, seenPos, seenNeg {
            if t - lastRep > loadedMinGap, envelope > loadedFloor {
                lastRep = t; seenPos = false; seenNeg = false
                DispatchQueue.main.async { self.reps += 1; WKInterfaceDevice.current().play(.notification) }
            } else { seenPos = false; seenNeg = false }
        }
    }

    private var lastTapT: TimeInterval = 0
    /// Cuenta un toque/impulso seco por repe (ejercicios de pierna en máquina).
    private func detectTap(_ d: CMDeviceMotion, t: TimeInterval) {
        let a = d.userAcceleration
        let acc = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if acc > 0.85, t - lastTapT > 0.45 {
            lastTapT = t
            DispatchQueue.main.async {
                self.reps += 1
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }

    private func detectShake(_ d: CMDeviceMotion, t: TimeInterval) {
        let a = d.userAcceleration, r = d.rotationRate
        let acc = (a.x*a.x + a.y*a.y + a.z*a.z).squareRoot()
        let rot = (r.x*r.x + r.y*r.y + r.z*r.z).squareRoot()
        if acc > 1.6 || rot > 9.0 {
            if spikeTimes.last.map({ t - $0 > 0.08 }) ?? true { spikeTimes.append(t) }
        }
        spikeTimes.removeAll { t - $0 > 0.9 }
        if spikeTimes.count >= 4, t - lastShake > 1.5 {
            lastShake = t; spikeTimes.removeAll()
            DispatchQueue.main.async { WKInterfaceDevice.current().play(.success); self.shakeCount += 1 }
        }
    }

    // ── Recuento offline (número que se guarda) ───────────────────────────────

    /// Recalcula el número real de repes sobre toda la serie grabada.
    func reconciledCount() -> Int {
        let n = bt.count
        guard n > 30 else { return reps }
        let tEnd = bt.last!
        let startCut = (setStartT < 0 ? bt.first! : setStartT) + graceStart
        // Excluye la ventana de la sacudida final (si terminaste sacudiendo).
        let endCut = (lastShakeT > tEnd - 2.0) ? min(tEnd, lastShakeT - 0.6) : tEnd - 0.4

        var idx: [Int] = []
        for i in 0..<n where bt[i] >= startCut && bt[i] <= endCut { idx.append(i) }
        guard idx.count > 30 else { return reps }

        // PCA sobre toda la ventana (eje exacto, con la 1ª repe).
        var C = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        for i in idx {
            let x = bx[i], y = by[i], z = bz[i]
            C[0]+=x*x; C[1]+=x*y; C[2]+=x*z; C[3]+=y*y; C[4]+=y*z; C[5]+=z*z
        }
        var v = [1.0, 0.0, 0.0]
        for _ in 0..<24 {
            let m0 = C[0]*v[0]+C[1]*v[1]+C[2]*v[2]
            let m1 = C[1]*v[0]+C[3]*v[1]+C[4]*v[2]
            let m2 = C[2]*v[0]+C[4]*v[1]+C[5]*v[2]
            let mn = (m0*m0+m1*m1+m2*m2).squareRoot()
            if mn < 1e-12 { break }
            v = [m0/mn, m1/mn, m2/mn]
        }

        // Proyección + suavizado de fase cero (ida y vuelta).
        var s = idx.map { bx[$0]*v[0] + by[$0]*v[1] + bz[$0]*v[2] }
        let ts = idx.map { bt[$0] }
        ema(&s, 0.4); s.reverse(); ema(&s, 0.4); s.reverse()

        // Umbral global por percentil de amplitud.
        let absSorted = s.map { abs($0) }.sorted()
        let p80 = absSorted[min(absSorted.count - 1, Int(0.8 * Double(absSorted.count)))]
        let hi = max(loadedFloor, 0.45 * p80)
        let lo = hi * 0.30

        // Detección de ciclos.
        var seenP = false, seenN = false, last = -1e9
        var times: [Double] = []
        var amps: [Double] = []
        var curMax = 0.0, curMin = 0.0
        for k in 0..<s.count {
            let val = s[k]
            curMax = max(curMax, val); curMin = min(curMin, val)
            if val > hi { seenP = true }
            if val < -hi { seenN = true }
            if abs(val) < lo, seenP, seenN {
                if ts[k] - last > loadedMinGap {
                    times.append(ts[k]); amps.append(curMax - curMin); last = ts[k]
                }
                seenP = false; seenN = false; curMax = 0; curMin = 0
            }
        }

        // Rechazo de outliers de periodo (dobles cuentas por titubeos).
        times = rejectPeriodOutliers(times)

        saveCalibration(times: times, amps: amps)
        return times.count
    }

    private func ema(_ x: inout [Double], _ a: Double) {
        guard !x.isEmpty else { return }
        var y = x[0]
        for i in 0..<x.count { y = a * x[i] + (1 - a) * y; x[i] = y }
    }

    private func rejectPeriodOutliers(_ times: [Double]) -> [Double] {
        guard times.count >= 4 else { return times }
        var periods: [Double] = []
        for i in 1..<times.count { periods.append(times[i] - times[i-1]) }
        let med = median(periods)
        guard med > 0 else { return times }
        // Elimina cuentas separadas por < 0.5·mediana del anterior (dobles).
        var out = [times[0]]
        for i in 1..<times.count where times[i] - out.last! >= 0.5 * med {
            out.append(times[i])
        }
        return out
    }

    private func median(_ a: [Double]) -> Double {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted(); let m = s.count / 2
        return s.count % 2 == 0 ? (s[m-1] + s[m]) / 2 : s[m]
    }

    // ── Memoria de calibración por ejercicio ──────────────────────────────────

    private func loadCalibration() {
        let d = UserDefaults.standard
        let amp = d.double(forKey: "cal_amp_\(exerciseId)")
        let per = d.double(forKey: "cal_per_\(exerciseId)")
        let f = d.double(forKey: "cal_floor_\(exerciseId)")   // aprendido de tus +/−
        loadedFloor = f > 0 ? f : (amp > 0 ? max(0.03, 0.35 * amp) : profile.floor)
        loadedMinGap = per > 0 ? min(2.5, max(0.5, 0.55 * per)) : 0.6
    }

    private func saveCalibration(times: [Double], amps: [Double]) {
        guard times.count >= 3 else { return }
        var periods: [Double] = []
        for i in 1..<times.count { periods.append(times[i] - times[i-1]) }
        let d = UserDefaults.standard
        // Suaviza con lo anterior (media) para estabilidad.
        let newAmp = median(amps), newPer = median(periods)
        let oldAmp = d.double(forKey: "cal_amp_\(exerciseId)")
        let oldPer = d.double(forKey: "cal_per_\(exerciseId)")
        d.set(oldAmp > 0 ? 0.5*(oldAmp+newAmp) : newAmp, forKey: "cal_amp_\(exerciseId)")
        d.set(oldPer > 0 ? 0.5*(oldPer+newPer) : newPer, forKey: "cal_per_\(exerciseId)")
    }

    func adjust(_ delta: Int) {
        reps = max(0, reps + delta)
        if delta > 0 { WKInterfaceDevice.current().play(.click) }
        // Aprende de tu corrección: "+" (nos faltaban) baja el suelo de detección
        // de este ejercicio; "−" (contamos de más) lo sube. Persiste por ejercicio
        // y afecta ya al recuento offline de esta misma serie.
        guard profile.mode == .auto, exerciseId != 0, delta != 0 else { return }
        loadedFloor = delta > 0 ? max(0.02, loadedFloor * 0.88) : min(0.5, loadedFloor * 1.12)
        UserDefaults.standard.set(loadedFloor, forKey: "cal_floor_\(exerciseId)")
    }
}
