import UIKit
import UserNotifications

/// Notificaciones locales: pide permiso y programa un aviso a las 23:59 del día
/// anterior a cada cumpleaños para poder felicitar rápido por WhatsApp.
final class Notifs: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifs()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Pide permiso de notificaciones (la primera vez muestra el diálogo del sistema).
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Programa (idempotente) un aviso la víspera de cada cumpleaños próximo.
    func scheduleBirthdays(_ events: [CalendarEvent]) {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current

        // Limpia los avisos de cumpleaños anteriores antes de reprogramar.
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix("bday-") }
            center.removePendingNotificationRequests(withIdentifiers: old)

            for event in events where AppLinks.isBirthday(event) {
                guard let day = Fmt.date(event.start) else { continue }
                // 23:59 del día anterior.
                guard let eve = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: day)) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: eve)
                comps.hour = 23; comps.minute = 59
                guard let fire = cal.date(from: comps), fire > .now else { continue }

                let name = AppLinks.birthdayName(event)
                let content = UNMutableNotificationContent()
                content.title = "Mañana es el cumpleaños de \(name)"
                content.body = "Felicítale por WhatsApp antes de que se te olvide."
                content.sound = .default
                if let link = event.link { content.userInfo = ["wa": link] }

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "bday-\(name)-\(event.start ?? "")"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    /// Programa un aviso a la hora de dormir recomendada (se repite cada día
    /// a esa hora hasta que se cancele o se reprograme).
    func scheduleBedtime(_ date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["bedtime"])
        let content = UNMutableNotificationContent()
        content.title = "Hora de dormir"
        content.body = "Acuéstate ya para llegar a tu objetivo de sueño."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "bedtime", content: content, trigger: trigger))
    }

    func cancelBedtime() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["bedtime"])
    }

    /// Al tocar la notificación, abre WhatsApp en el chat de esa persona.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let link = response.notification.request.content.userInfo["wa"] as? String,
           let url = URL(string: link) {
            AppLinks.open(url)
        }
        completionHandler()
    }

    /// Muestra el aviso aunque la app esté abierta.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
