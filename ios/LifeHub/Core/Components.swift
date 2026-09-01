import SwiftUI

/// Estado de carga genérico — heredero de useLoad() del frontend.
enum Loadable<T> {
    case loading
    case error(String)
    case loaded(T)
}

/// Carga async con skeleton, error con retry y contenido.
struct LoadView<T, Content: View>: View {
    let load: () async throws -> T
    @ViewBuilder let content: (T) -> Content

    @State private var state: Loadable<T> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                SkeletonList()
            case .error(let detail):
                ErrorCard(detail: detail) { await reload() }
            case .loaded(let value):
                content(value)
            }
        }
        .task { await reload() }
    }

    func reload() async {
        do {
            state = .loaded(try await load())
        } catch is CancellationError {
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

struct SkeletonList: View {
    var rows = 4
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface)
                    .frame(height: 72)
            }
        }
        .opacity(pulse ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}

struct ErrorCard: View {
    let detail: String
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Algo falló")
                .font(.display(20))
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(Theme.dFootnote)
                .foregroundStyle(Theme.muted)
                .lineLimit(4)
            Button {
                Task { await retry() }
            } label: {
                Text("Reintentar")
                    .font(Theme.dSubheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .card()
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.dCaption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

/// Tarjeta de coach IA: carga el texto en segundo plano y aparece cuando llega.
struct CoachCard: View {
    let load: () async throws -> AIText
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                    Text(text)
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.ink)
                }
                .card()
            }
        }
        .task {
            text = try? await load().text
        }
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.dSubheadline)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }
}

/// Fondo + scroll estándar de todas las pantallas.
/// Tirar hacia abajo recrea el contenido (cambia su identidad), lo que
/// relanza los .task de carga de cualquier hijo — pull-to-refresh universal.
struct Screen<Content: View>: View {
    let title: String
    var refresh: (() async -> Void)? = nil
    @ViewBuilder let content: Content

    @State private var reloadKey = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.display(34, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                content
                    .id(reloadKey)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .refreshable {
            if let refresh {
                await refresh()
            } else {
                reloadKey = UUID()
            }
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
    }
}

// ── Fechas ──────────────────────────────────────────────────────────────────

enum Fmt {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoNoFrac = ISO8601DateFormatter()

    private static let plain: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Parsea fechas ISO del backend (con o sin fracción de segundo, con o sin
    /// zona). El backend suele mandar "2026-06-14T14:33:04.725369" (microsegundos
    /// y SIN zona), que los ISO8601 formatters no aceptan.
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        if let d = isoNoFrac.date(from: s) { return d }
        if s.contains("T") {
            // Quita la fracción de segundo (todo tras el punto) y parsea la base.
            let base = s.split(separator: ".").first.map(String.init) ?? s
            plain.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            if let d = plain.date(from: base) { return d }
            plain.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let d = plain.date(from: base) { return d }
        }
        plain.dateFormat = "yyyy-MM-dd"
        return plain.date(from: String(s.prefix(10)))
    }

    /// Fecha en claro y en español: "4 de julio".
    static func short(_ s: String?) -> String {
        guard let d = date(s) else { return s ?? "" }
        return d.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_ES")))
    }

    static func time(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        return d.formatted(.dateTime.hour().minute())
    }
}
