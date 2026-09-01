import UIKit

/// Aperturas hacia apps externas, prefiriendo la app nativa sobre el navegador.
enum AppLinks {
    /// Abre en la app propietaria vía universal link (WhatsApp, Gmail…), y solo
    /// cae al navegador si esa app no está instalada.
    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
            if !opened { UIApplication.shared.open(url) }
        }
    }

    /// Abre Google Maps en modo "Cómo llegar" hacia una dirección. Usa la app de
    /// Google Maps si está instalada; si no, su universal link web.
    static func directions(to place: String) {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
        if let app = URL(string: "comgooglemaps://?daddr=\(q)&directionsmode=driving"),
           UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
            return
        }
        if let web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(q)") {
            UIApplication.shared.open(web)
        }
    }

    /// True si el evento es un cumpleaños (para abrir WhatsApp y avisar).
    static func isBirthday(_ event: CalendarEvent) -> Bool {
        let t = event.title.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if t.contains("cumpleanos") || t.contains("birthday") { return true }
        return (event.link ?? "").contains("wa.me") || (event.link ?? "").contains("whatsapp")
    }

    /// "Cumpleaños de Ferreriño" → "Ferreriño".
    static func birthdayName(_ event: CalendarEvent) -> String {
        let t = event.title
        for prefix in ["Cumpleaños de ", "Cumpleanos de ", "Birthday of ", "Cumpleaños ", "Cumpleanos "] {
            if t.hasPrefix(prefix) { return String(t.dropFirst(prefix.count)) }
        }
        return t
    }

    /// Acción al pulsar un evento: WhatsApp (cumpleaños/link wa), su link, o
    /// Google Maps si tiene una ubicación real.
    static func tap(_ event: CalendarEvent) {
        if let link = event.link, let url = URL(string: link) {
            open(url)
            return
        }
        if let loc = event.location, !loc.isEmpty, loc.lowercased() != "felicitar por whatsapp" {
            directions(to: loc)
        }
    }
}
