import SwiftUI

/// Estética de Life Hub: café oscuro + brasa coral. Colores EXACTOS de la web
/// (index.css @theme). Display en Fraunces, cuerpo en DM Sans.
enum Theme {
    static let bg = Color(hex: 0x14100c)        // café casi negro
    static let surface = Color(hex: 0x1e1812)
    static let surface2 = Color(hex: 0x2a2119)
    static let line = Color(hex: 0x362c21)
    static let ink = Color(hex: 0xf5eee3)
    static let muted = Color(hex: 0xa39587)
    static let accent = Color(hex: 0xff7a45)    // brasa coral
    static let accent2 = Color(hex: 0xffb03b)
    static let accentInk = Color(hex: 0x1a0f08)
    static let good = Color(hex: 0x5fc98b)      // gain
    static let bad = Color(hex: 0xff5d5d)       // danger

    // Cuerpo en DM Sans, reemplazando los estilos de sistema (SF Pro) por la
    // fuente de la web. Tamaños alineados a los text styles de iOS, pesos finos.
    static let dTitle: Font = .sans(28, weight: .regular)
    static let dTitle2: Font = .sans(22, weight: .semibold)
    static let dTitle3: Font = .sans(20, weight: .medium)
    static let dHeadline: Font = .sans(17, weight: .medium)
    static let dBody: Font = .sans(17, weight: .regular)
    static let dCallout: Font = .sans(16, weight: .regular)
    static let dSubheadline: Font = .sans(15, weight: .regular)
    static let dFootnote: Font = .sans(13, weight: .regular)
    static let dCaption: Font = .sans(12, weight: .regular)
    static let dCaption2: Font = .sans(11, weight: .regular)
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

extension Font {
    /// Titulares con carácter — Fraunces (serif de la web), jerarquía dramática.
    /// Instancias estáticas: mapeamos el peso al nombre PostScript exacto.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Fraunces-Bold"
        case .regular, .light, .thin, .ultraLight: name = "Fraunces-Regular"
        default: name = "Fraunces-SemiBold"
        }
        return .custom(name, size: size)
    }
    /// Cuerpo — DM Sans (nombre PostScript por peso).
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "DMSans-Bold"
        case .semibold: name = "DMSans-SemiBold"
        case .medium: name = "DMSans-Medium"
        default: name = "DMSans-Regular"
        }
        return .custom(name, size: size)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardStyle(padding: padding)) }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

extension View {
    /// Acción principal: Liquid Glass prominente (iOS 26+) tintado, o relleno sólido.
    @ViewBuilder
    func actionGlass(_ tint: Color = Theme.accent) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(tint)
        } else {
            self.buttonStyle(.borderedProminent).tint(tint)
        }
    }

    /// Acción secundaria: Liquid Glass claro (iOS 26+) o bordeado.
    @ViewBuilder
    func secondaryGlass(_ tint: Color = Theme.ink) -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).tint(tint)
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }
}

/// Botón con háptico integrado — respuesta táctil consistente en toda la app.
/// Sustituye a Button cuando quieres el "tic" sutil al pulsar.
struct HButton<Label: View>: View {
    var haptic: () -> Void = Haptics.light
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            haptic()
            action()
        } label: {
            label()
        }
    }
}
