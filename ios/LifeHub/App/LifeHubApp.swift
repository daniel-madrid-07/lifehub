import SwiftUI

@main
struct LifeHubApp: App {
    /// Si no hay servidor y clave, lo primero es el onboarding.
    @State private var configured = AppConfig.isConfigured

    init() {
        Notifs.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if configured {
                    RootView()
                        .task {
                            // El perfil primero: las vistas lo leen de la caché.
                            await Me.refresh()
                            // Programa los avisos de cumpleaños con la agenda del servidor.
                            if let cal = try? await API.shared.calendar(), cal.status == "ok" {
                                Notifs.shared.scheduleBirthdays(cal.events ?? [])
                            }
                        }
                } else {
                    OnboardingView { configured = true }
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .onReceive(NotificationCenter.default.publisher(for: API.unauthorizedNotification)) { _ in
                // La clave dejó de valer: vuelve al onboarding en vez de fallar en bucle.
                AppConfig.reset()
                configured = false
            }
        }
    }
}
