import SwiftUI

/// Agenda: calendario del iPhone vía iCloud CalDAV (próximos 30 días).
struct CalendarView: View {
    var body: some View {
        Screen(title: "Agenda") {
            MailEventsSection()

            SectionHeader(title: "Proximos eventos")

            LoadView {
                try await API.shared.calendar()
            } content: { (overview: CalendarOverview) in
                if overview.status == "error" {
                    Text(overview.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else if (overview.events ?? []).isEmpty {
                    EmptyState(text: "Sin eventos próximos.")
                } else {
                    ForEach(overview.events ?? [], id: \.self) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}

/// Fila de evento. Cumpleaños → WhatsApp; con ubicación → Google Maps (cómo
/// llegar); resto no navegable.
struct EventRow: View {
    let event: CalendarEvent

    private var isBirthday: Bool { AppLinks.isBirthday(event) }
    private var mapsPlace: String? {
        guard let loc = event.location, !loc.isEmpty,
              loc.lowercased() != "felicitar por whatsapp" else { return nil }
        return loc
    }
    private var actionable: Bool { isBirthday || event.link != nil || mapsPlace != nil }

    var body: some View {
        let row = HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(Fmt.short(event.start))
                    .font(Theme.dCaption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                if !Fmt.time(event.start).isEmpty {
                    Text(Fmt.time(event.start))
                        .font(Theme.dCaption2)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(isBirthday ? "Cumpleaños de \(AppLinks.birthdayName(event))" : event.title)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                if isBirthday {
                    Label("Felicitar por WhatsApp", systemImage: "message")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.good)
                } else if let place = mapsPlace {
                    Label(place, systemImage: "location")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isBirthday {
                Image(systemName: "gift").foregroundStyle(Theme.accent)
            } else if mapsPlace != nil {
                Image(systemName: "arrow.triangle.turn.up.right.circle").foregroundStyle(Theme.accent)
            }
        }
        .card()

        if actionable {
            Button {
                Haptics.light()
                AppLinks.tap(event)
            } label: { row }
            .buttonStyle(.plain)
        } else {
            row
        }
    }
}
