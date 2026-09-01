import SwiftUI

// ── Vista principal: pegar texto → detectar eventos ──────────────────────────

struct EventDetectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var detected: [DetectedEvent] = []
    @State private var detecting = false
    @State private var detectError: String?
    @State private var added: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pasteSection
                    if detecting { SkeletonList(rows: 2) }
                    if let err = detectError {
                        Text(err).font(Theme.dCaption).foregroundStyle(Theme.bad).card()
                    }
                    if !detected.isEmpty { resultsSection }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Detectar evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Theme.muted)
                }
            }
        }
    }

    var pasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PEGA UN MENSAJE DE WHATSAPP, EMAIL O LO QUE SEA")
                .font(Theme.dCaption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                    .font(Theme.dBody)
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if text.isEmpty {
                    Text("Ej: \"Quedamos mañana a las 7 en el polideportivo para el futbol\"")
                        .font(Theme.dBody)
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 10) {
                HButton(haptic: Haptics.light) {
                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                        text = clip
                    }
                } label: {
                    Label("Pegar portapapeles", systemImage: "doc.on.clipboard")
                        .font(Theme.dCaption.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .secondaryGlass()

                HButton(haptic: Haptics.medium) {
                    Task { await detect() }
                } label: {
                    Group {
                        if detecting { ProgressView().tint(Theme.accentInk) }
                        else { Text("Detectar").font(Theme.dHeadline) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .actionGlass()
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || detecting)
            }
        }
    }

    var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "\(detected.count) evento\(detected.count == 1 ? "" : "s") detectado\(detected.count == 1 ? "" : "s")")

            ForEach($detected) { $event in
                DetectedEventCard(event: $event,
                                  isAdded: added.contains(event.id)) {
                    Task { await addToCalendar(event) }
                }
            }
        }
    }

    func detect() async {
        detecting = true; detectError = nil; detected = []
        do {
            let response = try await API.shared.detectEvent(text)
            detected = response.events
            if response.events.isEmpty {
                detectError = "No detecte ningun evento en ese texto. Prueba con algo mas concreto (nombre, dia, hora)."
            }
        } catch {
            detectError = error.localizedDescription
        }
        detecting = false
    }

    func addToCalendar(_ event: DetectedEvent) async {
        guard let start = event.start_iso else { return }
        do {
            _ = try await API.shared.createCalendarEvent(
                title: event.title,
                startIso: start,
                endIso: event.end_iso,
                location: event.location
            )
            Haptics.success()
            added.insert(event.id)
        } catch {
            detectError = error.localizedDescription
        }
    }
}

// ── Tarjeta de evento detectado con edición inline ────────────────────────────

struct DetectedEventCard: View {
    @Binding var event: DetectedEvent
    let isAdded: Bool
    let onAdd: () -> Void

    @State private var editingTitle = false
    @State private var editingTime = false
    @State private var editingLocation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    titleRow
                    timeRow
                    locationRow
                }
                Spacer(minLength: 10)
                confidenceBadge
            }

            if let snippet = event.source_snippet {
                Text("«\(snippet)»")
                    .font(Theme.dCaption2.italic())
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }

            Divider().background(Theme.line)

            if isAdded {
                Label("Añadido a Agenda", systemImage: "checkmark.circle.fill")
                    .font(Theme.dCaption.weight(.medium))
                    .foregroundStyle(Theme.good)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HButton(haptic: Haptics.success, action: onAdd) {
                    Label("Añadir a Agenda", systemImage: "calendar.badge.plus")
                        .font(Theme.dHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .actionGlass()
                .disabled(event.start_iso == nil)
            }
        }
        .card()
    }

    var titleRow: some View {
        Group {
            if editingTitle {
                TextField("Titulo", text: $event.title, onCommit: { editingTitle = false })
                    .textFieldStyle(.plain)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
            } else {
                Text(event.title)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                    .onTapGesture { editingTitle = true }
            }
        }
    }

    var timeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").font(Theme.dCaption2).foregroundStyle(Theme.accent)
            if editingTime {
                TextField("2026-07-15T19:00:00", text: Binding(
                    get: { event.start_iso ?? "" },
                    set: { event.start_iso = $0.isEmpty ? nil : $0 }
                ), onCommit: { editingTime = false })
                .textFieldStyle(.plain)
                .font(Theme.dCaption)
                .foregroundStyle(Theme.ink)
            } else {
                Text(Fmt.eventTime(event.start_iso, end: event.end_iso))
                    .font(Theme.dCaption)
                    .foregroundStyle(event.start_iso == nil ? Theme.bad : Theme.muted)
                    .onTapGesture { editingTime = true }
            }
        }
    }

    @ViewBuilder
    var locationRow: some View {
        if editingLocation || event.location != nil {
            HStack(spacing: 6) {
                Image(systemName: "location").font(Theme.dCaption2).foregroundStyle(Theme.accent)
                if editingLocation {
                    TextField("Ubicacion (opcional)", text: Binding(
                        get: { event.location ?? "" },
                        set: { event.location = $0.isEmpty ? nil : $0 }
                    ), onCommit: { editingLocation = false })
                    .textFieldStyle(.plain)
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.ink)
                } else {
                    Text(event.location ?? "")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                        .onTapGesture { editingLocation = true }
                }
            }
        } else {
            Button {
                Haptics.light()
                editingLocation = true
            } label: {
                Label("Añadir ubicacion", systemImage: "plus")
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
    }

    var confidenceBadge: some View {
        let pct = Int(event.confidence * 100)
        return Text("\(pct)%")
            .font(Theme.dCaption2.weight(.semibold))
            .foregroundStyle(event.confidence >= 0.7 ? Theme.good : Theme.accent2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((event.confidence >= 0.7 ? Theme.good : Theme.accent2).opacity(0.15))
            )
    }
}

// ── Sección de eventos detectados en correo (usada en CalendarView) ───────────

struct MailEventsSection: View {
    @State private var events: [DetectedEvent] = []
    @State private var loading = true
    @State private var added: Set<String> = []
    @State private var error: String?
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "Detectado en correo")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if loading {
                    SkeletonList(rows: 2)
                } else if let err = error {
                    Text(err).font(Theme.dCaption).foregroundStyle(Theme.muted).card(padding: 12)
                } else if events.isEmpty {
                    Text("Sin eventos detectados en los ultimos correos.")
                        .font(Theme.dCaption)
                        .foregroundStyle(Theme.muted)
                        .card(padding: 12)
                } else {
                    VStack(spacing: 10) {
                        ForEach(events) { event in
                            MailEventRow(event: event, isAdded: added.contains(event.id)) {
                                Task { await add(event) }
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        loading = true
        do { events = try await API.shared.mailEvents().events }
        catch { self.error = "No se pudo analizar el correo." }
        loading = false
    }

    func add(_ event: DetectedEvent) async {
        guard let start = event.start_iso else { return }
        do {
            _ = try await API.shared.createCalendarEvent(
                title: event.title, startIso: start,
                endIso: event.end_iso, location: event.location
            )
            Haptics.success()
            added.insert(event.id)
        } catch {}
    }
}

struct MailEventRow: View {
    let event: DetectedEvent
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(Fmt.eventTime(event.start_iso, end: event.end_iso))
                    .font(Theme.dCaption)
                    .foregroundStyle(Theme.muted)
                if let loc = event.location {
                    Label(loc, systemImage: "location")
                        .font(Theme.dCaption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good)
            } else {
                HButton(haptic: Haptics.medium, action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 14)
    }
}

// ── Fmt.eventTime helper ──────────────────────────────────────────────────────

extension Fmt {
    static func eventTime(_ start: String?, end: String?) -> String {
        guard let start else { return "Sin hora detectada" }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out = df.date(from: start)
        if out == nil { df.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]; out = df.date(from: start) }
        guard let d = out else { return start }
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "EEE d MMM, HH:mm"
        var result = fmt.string(from: d)
        if let endStr = end, let de = df.date(from: endStr) {
            let efmt = DateFormatter(); efmt.dateFormat = "HH:mm"
            result += " – \(efmt.string(from: de))"
        }
        return result
    }
}
