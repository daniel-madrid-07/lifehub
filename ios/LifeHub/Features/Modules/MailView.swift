import SwiftUI

/// Correo: no leídos importantes de Gmail (proxy cacheado del backend).
struct MailView: View {
    var body: some View {
        Screen(title: "Correo") {
            CoachCard { try await API.shared.aiMail() }

            LoadView {
                try await API.shared.mail()
            } content: { (overview: MailOverview) in
                if overview.status == "error" {
                    Text(overview.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else if (overview.messages ?? []).isEmpty {
                    EmptyState(text: "Bandeja limpia.")
                } else {
                    ForEach(overview.messages ?? [], id: \.subject) { msg in
                        if let link = msg.link, let url = URL(string: link) {
                            Button {
                                Haptics.light()
                                openInMailApp(url)
                            } label: {
                                MailRow(msg: msg)
                            }
                            .buttonStyle(.plain)
                        } else {
                            MailRow(msg: msg)
                        }
                    }
                }
            }
        }
    }
}

/// Abre el correo en la app de Gmail si está instalada (universal link),
/// y solo cae al navegador si no lo está.
private func openInMailApp(_ url: URL) {
    UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
        if !opened { UIApplication.shared.open(url) }
    }
}

struct MailRow: View {
    let msg: MailMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(msg.from)
                    .font(Theme.dCaption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Spacer()
                Text(Fmt.short(msg.date))
                    .font(Theme.dCaption2)
                    .foregroundStyle(Theme.muted)
            }
            Text(msg.subject)
                .font(Theme.dHeadline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(msg.snippet)
                .font(Theme.dCaption)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .card()
    }
}
