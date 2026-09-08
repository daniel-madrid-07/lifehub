import SwiftUI

@main
struct LifeHubApp: App {
    /// El onboarding solo sale la primera vez: pide los datos corporales y
    /// deja elegir entre usar la app sola o conectar un servidor.
    @AppStorage("lifehub.onboarded") private var onboarded = false

    init() {
        Notifs.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    RootView()
                        .task {
                            // El perfil primero: las vistas lo leen de la caché.
                            await Me.refresh()
                            // Con servidor, programa los avisos de cumpleaños.
                            if AppConfig.isConfigured,
                               let cal = try? await API.shared.calendar(), cal.status == "ok" {
                                Notifs.shared.scheduleBirthdays(cal.events ?? [])
                            }
                        }
                } else {
                    OnboardingView { onboarded = true }
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .onReceive(NotificationCenter.default.publisher(for: API.unauthorizedNotification)) { _ in
                // La clave del servidor dejó de valer: se vuelve al modo local
                // en vez de dejar la app inservible.
                AppConfig.reset()
            }
        }
    }
}
