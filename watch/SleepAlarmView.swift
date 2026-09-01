import SwiftUI

struct SleepAlarmView: View {
    @StateObject private var alarm = SmartAlarm.shared
    @State private var targetWake: Date = Self.defaultWake()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)
                    Text(stateLabel)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(stateColor)
                }

                switch alarm.state {
                case .idle, .fired:
                    idleContent
                case .scheduled, .active:
                    activeContent
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Alarma")
    }

    // MARK: - Idle / fired UI

    @ViewBuilder
    var idleContent: some View {
        if alarm.state == .fired {
            Text("Buenas dias")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.accent)
            if alarm.batteryUsed > 0 {
                Text("Bateria usada: \(Int(alarm.batteryUsed * 100))%")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Divider()
        }

        DatePicker("", selection: $targetWake, displayedComponents: .hourAndMinute)
            .labelsHidden()

        Button {
            alarm.schedule(alarmAt: targetWake)
        } label: {
            Label("Activar", systemImage: "moon.zzz.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)

        Text("La sesion arranca 30 min antes. Pon tambien una alarma normal como seguro.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
    }

    // MARK: - Scheduled / active UI

    @ViewBuilder
    var activeContent: some View {
        VStack(spacing: 6) {
            Text("Despertar: \(hm(targetWake))")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("Ventana: \(hm(targetWake.addingTimeInterval(-30 * 60))) – \(hm(targetWake))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)

            if alarm.state == .active {
                Text("Monitorizando movimiento")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
            }
        }

        Button {
            alarm.cancel()
        } label: {
            Label("Cancelar", systemImage: "xmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    // MARK: - Helpers

    var stateLabel: String {
        switch alarm.state {
        case .idle:      return "Inactiva"
        case .scheduled: return "Programada"
        case .active:    return "Activa"
        case .fired:     return "Disparada"
        }
    }

    var stateColor: Color {
        switch alarm.state {
        case .idle:      return Theme.muted
        case .scheduled: return Theme.accent
        case .active:    return .green
        case .fired:     return Theme.accent
        }
    }

    func hm(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }

    static func defaultWake() -> Date {
        let saved = UserDefaults.standard.double(forKey: "sleep_alarm_wake_h")
        let cal   = Calendar.current
        let base  = cal.date(byAdding: .day, value: 1, to: .now)!
        guard saved > 0 else {
            return cal.date(bySettingHour: 7, minute: 30, second: 0, of: base) ?? base
        }
        let h = Int(saved), m = Int((saved - Double(h)) * 60)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
    }
}
