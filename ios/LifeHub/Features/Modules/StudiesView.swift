import SwiftUI

/// Estudios (Epitech vía intra-bot): resumen IA, proyectos y actividades
/// activos. Si no hay nada, no se muestra nada (fin de curso = normal).
struct StudiesView: View {
    @State private var overview: StudyOverview?
    @State private var error: String?
    @State private var refreshing = false
    @State private var claude: ClaudeUsage?

    var body: some View {
        Screen(title: "Estudios", refresh: { await load() }) {
            CoachCard { try await API.shared.aiStudies() }

            if let claude { ClaudeUsageCard(usage: claude) }

            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let o = overview {
                if o.status == "error" {
                    Text(o.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else {
                    if let summary = o.summary, !summary.isEmpty {
                        Text(summary)
                            .font(Theme.dSubheadline)
                            .foregroundStyle(Theme.ink)
                            .card()
                    }

                    if let projects = o.projects, !projects.isEmpty {
                        SectionHeader(title: "Proyectos en curso")
                        ForEach(projects, id: \.title) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title)
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                HStack {
                                    if let deadline = p.deadline {
                                        Label(deadline, systemImage: "clock")
                                    }
                                    if let progress = p.progress {
                                        Label(progress, systemImage: "chart.bar.fill")
                                    }
                                }
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                            }
                            .card()
                        }
                    }

                    if let activities = o.activities, !activities.isEmpty {
                        SectionHeader(title: "Próximas actividades")
                        ForEach(activities, id: \.title) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title)
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                if let start = a.start {
                                    Label(start, systemImage: "calendar")
                                        .font(Theme.dCaption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .card()
                        }
                    }

                    if let notes = o.notes, !notes.isEmpty {
                        SectionHeader(title: "Notas")
                        ForEach(notes, id: \.title) { n in
                            HStack {
                                Text(n.title)
                                    .font(Theme.dSubheadline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(n.note ?? "—")
                                    .font(Theme.dSubheadline.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .card(padding: 13)
                        }
                    }

                    if (o.projects ?? []).isEmpty && (o.activities ?? []).isEmpty {
                        EmptyState(text: "Nada activo en Epitech ahora mismo.")
                    }

                    Button {
                        Task { await load(refresh: true) }
                    } label: {
                        Label(refreshing ? "Actualizando…" : "Actualizar datos", systemImage: "arrow.clockwise")
                            .font(Theme.dSubheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .disabled(refreshing)
                }
            } else {
                SkeletonList()
            }
        }
        .task { await load() }
    }

    func load(refresh: Bool = false) async {
        if refresh { refreshing = true }
        claude = try? await API.shared.claudeUsage()
        do {
            overview = try await API.shared.studies(refresh: refresh)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refreshing = false
    }
}

/// Uso de Claude (sesión de 5 h y semanal) con la cuenta atrás hasta el reinicio.
struct ClaudeUsageCard: View {
    let usage: ClaudeUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Theme.accent)
                Text("Uso de Claude")
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
            }
            if let s = usage.session { row("Sesión (5 h)", s) }
            if let w = usage.weekly { row("Semanal", w) }
        }
        .card()
    }

    @ViewBuilder
    func row(_ label: String, _ w: ClaudeUsage.Window) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(Theme.dSubheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(w.pct)%").font(Theme.dSubheadline.weight(.bold)).foregroundStyle(Theme.ink)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(w.pct >= 90 ? Theme.bad : Theme.accent)
                        .frame(width: g.size.width * CGFloat(min(w.pct, 100)) / 100)
                }
            }
            .frame(height: 5)
            if let c = countdown(w.reset) {
                Text("reinicia en \(c)").font(Theme.dCaption2).foregroundStyle(Theme.muted)
            }
        }
    }

    func countdown(_ iso: String?) -> String? {
        guard let d = Fmt.date(iso) else { return nil }
        let s = d.timeIntervalSinceNow
        if s <= 0 { return "ahora" }
        let days = Int(s) / 86400, hours = (Int(s) % 86400) / 3600, mins = (Int(s) % 3600) / 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(mins) min" }
        return "\(mins) min"
    }
}
