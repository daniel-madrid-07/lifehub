import SwiftUI

@main
struct LifeHubApp: App {
    init() {
        Notifs.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    // Programa los avisos de cumpleaños con la agenda del servidor.
                    if let cal = try? await API.shared.calendar(), cal.status == "ok" {
                        Notifs.shared.scheduleBirthdays(cal.events ?? [])
                    }
                }
        }
    }
}
