import SwiftUI
import WidgetKit

/// Módulos que pueden ir en la barra de navegación (todos menos "Hoy").
enum NavModule: String, CaseIterable, Identifiable {
    case gym, nutrition, finance, routines, tasks, mail, calendar, studies, sleep, wardrobe, more
    var id: String { rawValue }

    /// Opciones elegibles para la barra ("Más" ya no: vive en el engranaje de Hoy).
    static var selectable: [NavModule] { allCases.filter { $0 != .more } }

    var label: String {
        switch self {
        case .gym: return "Gym"
        case .nutrition: return "Comida"
        case .finance: return "Dinero"
        case .routines: return "Rutinas"
        case .tasks: return "Tareas"
        case .mail: return "Correo"
        case .calendar: return "Agenda"
        case .studies: return "Estudios"
        case .sleep: return "Sueño"
        case .wardrobe: return "Ropa"
        case .more: return "Más"
        }
    }
    var icon: String {
        switch self {
        case .gym: return "dumbbell"
        case .nutrition: return "fork.knife"
        case .finance: return "eurosign.circle"
        case .routines: return "checklist.unchecked"
        case .tasks: return "checklist"
        case .mail: return "envelope"
        case .calendar: return "calendar"
        case .studies: return "graduationcap"
        case .sleep: return "moon.stars"
        case .wardrobe: return "tshirt.fill"
        case .more: return "square.grid.2x2"
        }
    }
}

/// Navegación principal: 4 huecos configurables + "Hoy" fija en el centro.
/// La app abre en "Hoy". Los huecos se eligen en Ajustes → Barra de navegación.
struct RootView: View {
    @AppStorage("nav_slots") private var slotsRaw = "gym,nutrition,finance,studies"
    @State private var tab = "home"

    static let defaultSlots: [NavModule] = [.gym, .nutrition, .finance, .studies]

    var slots: [NavModule] {
        let mods = slotsRaw.split(separator: ",").compactMap { NavModule(rawValue: String($0)) }
        // "Más" ya no va en la barra (migración de configs antiguas) → default.
        return (mods.count == 4 && !mods.contains(.more)) ? mods : Self.defaultSlots
    }
    /// Orden real de las pestañas para el gesto de deslizar (Hoy en el centro).
    var orderedTags: [String] {
        [slots[0].rawValue, slots[1].rawValue, "home", slots[2].rawValue, slots[3].rawValue]
    }

    var body: some View {
        TabView(selection: $tab) {
            moduleTab(slots[0])
            moduleTab(slots[1])
            NavigationStack { HomeView() }
                .tabItem { Label("Hoy", systemImage: "house.fill") }
                .tag("home")
            moduleTab(slots[2])
            moduleTab(slots[3])
        }
        .background(Theme.bg)
        .font(.sans(17))
        .onChange(of: tab) { _, _ in Haptics.selection() }
        .onChange(of: slotsRaw) { _, _ in
            if !orderedTags.contains(tab) { tab = "home" }
        }
        .onAppear { WidgetCenter.shared.reloadAllTimelines() }
        .onOpenURL { url in
            // Deep link desde un widget: lifehub://open?m=<módulo>
            guard let m = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "m" })?.value else { return }
            tab = orderedTags.contains(m) ? m : "home"
        }
        .simultaneousGesture(
            // Deslizar horizontal cambia de pestaña. Umbral suave: basta con que
            // el gesto sea más horizontal que vertical (así no hay que ser preciso),
            // pero un scroll vertical (dy domina) nunca lo dispara.
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 38, abs(dx) > abs(dy) * 1.2,
                          let i = orderedTags.firstIndex(of: tab) else { return }
                    let j = dx < 0 ? min(i + 1, orderedTags.count - 1) : max(i - 1, 0)
                    tab = orderedTags[j]
                }
        )
    }

    @ViewBuilder
    private func moduleTab(_ m: NavModule) -> some View {
        NavigationStack { destination(m) }
            .tabItem { Label(m.label, systemImage: m.icon) }
            .tag(m.rawValue)
    }

    @ViewBuilder
    private func destination(_ m: NavModule) -> some View {
        switch m {
        case .gym: GymView()
        case .nutrition: NutritionView()
        case .finance: FinanceView()
        case .routines: RoutinesView()
        case .tasks: TasksView()
        case .mail: MailView()
        case .calendar: CalendarView()
        case .studies: StudiesView()
        case .sleep: SleepView()
        case .wardrobe: WardrobeView()
        case .more: MoreView()
        }
    }
}

/// "Más": índice completo de todos los módulos + Ajustes (así todo es accesible
/// aunque no esté fijado en la barra).
struct MoreView: View {
    var body: some View {
        Screen(title: "Más") {
            VStack(spacing: 10) {
                MoreLink(icon: "dumbbell", label: "Gym") { GymView() }
                MoreLink(icon: "fork.knife", label: "Comida") { NutritionView() }
                MoreLink(icon: "eurosign.circle", label: "Dinero") { FinanceView() }
                MoreLink(icon: "checklist.unchecked", label: "Rutinas") { RoutinesView() }
                MoreLink(icon: "checklist", label: "Tareas") { TasksView() }
                MoreLink(icon: "envelope", label: "Correo") { MailView() }
                MoreLink(icon: "calendar", label: "Agenda") { CalendarView() }
                MoreLink(icon: "graduationcap", label: "Estudios") { StudiesView() }
                MoreLink(icon: "moon.stars", label: "Sueño") { SleepView() }
                MoreLink(icon: "tshirt.fill", label: "Ropa") { WardrobeView() }
                MoreLink(icon: "gearshape", label: "Ajustes") { SettingsView() }
            }
        }
    }
}

struct MoreLink<Destination: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
                .toolbarBackground(Theme.bg, for: .navigationBar)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                Text(label)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.dFootnote)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }
}
