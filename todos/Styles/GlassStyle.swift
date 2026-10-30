import SwiftUI

enum TodoPalette {
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.24)
    static let blue = Color(red: 0.29, green: 0.43, blue: 0.60)
    static let done = Color(hue: 0.40, saturation: 0.45, brightness: 0.72)
    static let gold = Color(red: 0.93, green: 0.76, blue: 0.38)
}

/// Each category gets one quiet hue. It only tints the background glow, the glass highlights,
/// and the accents, so switching lists shifts the mood without adding noise.
struct TodoTheme: Equatable {
    let id: String
    let hue: Double

    var accent: Color { Color(hue: hue, saturation: 0.50, brightness: 0.86) }
    /// A deeper shade that stays readable as text on light and dark backgrounds.
    var deep: Color { Color(hue: hue, saturation: 0.55, brightness: 0.62) }
    var confetti: [Color] {
        [Color(hue: hue, saturation: 0.45, brightness: 0.95), Color(hue: hue + 0.08, saturation: 0.35, brightness: 0.98),
         TodoPalette.gold, .white, Color(hue: hue - 0.06, saturation: 0.30, brightness: 0.95)]
    }

    static let sunrise = Self(id: "sunrise", hue: 0.04)
    static let ocean = Self(id: "ocean", hue: 0.59)
    static let orchid = Self(id: "orchid", hue: 0.75)
    static let meadow = Self(id: "meadow", hue: 0.40)
    static let rose = Self(id: "rose", hue: 0.96)
    static let lagoon = Self(id: "lagoon", hue: 0.50)
    private static let rotation = [ocean, orchid, meadow, rose, lagoon, sunrise]

    static func forCategory(_ category: TaskCategory) -> Self {
        switch category.id {
        case "today": return .sunrise
        case "work": return .ocean
        case "personal": return .orchid
        default:
            // FNV-1a, because Swift's hashValue changes between launches.
            var hash: UInt32 = 2166136261
            for byte in category.id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
            return rotation[Int(hash % UInt32(rotation.count))]
        }
    }
}

private struct TodoThemeKey: EnvironmentKey { static let defaultValue = TodoTheme.sunrise }
private struct ButtonPressedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var todoTheme: TodoTheme {
        get { self[TodoThemeKey.self] }
        set { self[TodoThemeKey.self] = newValue }
    }
    /// True while the surrounding button is being pressed, so a label can animate along with it.
    var buttonIsPressed: Bool {
        get { self[ButtonPressedKey.self] }
        set { self[ButtonPressedKey.self] = newValue }
    }
}

extension TaskCategory {
    var theme: TodoTheme { .forCategory(self) }
    var accent: Color { theme.accent }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A calm canvas washed in the current category's colour. Switching tabs sweeps the hue across
/// the shortest path of the colour wheel, so the change is felt as well as seen.
struct AmbientBackground: View {
    @Environment(\.todoTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownHue: Double?

    var body: some View {
        Glow(hue: shownHue ?? theme.hue, dark: scheme == .dark)
            .ignoresSafeArea().accessibilityHidden(true)
            .onChange(of: theme.hue, initial: true) { _, target in
                guard let current = shownHue else { shownHue = target; return }
                var delta = (target - current).truncatingRemainder(dividingBy: 1)
                if delta > 0.5 { delta -= 1 } else if delta < -0.5 { delta += 1 }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) { shownHue = current + delta }
            }
    }

    private struct Glow: View, Animatable {
        var hue: Double
        let dark: Bool
        var animatableData: Double {
            get { hue }
            set { hue = newValue }
        }

        private func color(_ shift: Double, _ saturation: Double, _ brightness: Double) -> Color {
            let h = hue + shift
            return Color(hue: h - floor(h), saturation: saturation, brightness: brightness)
        }

        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    dark ? color(0, 0.50, 0.095) : color(0, 0.09, 0.975)
                    Ellipse().fill(dark ? color(0, 0.85, 0.50) : color(0, 0.42, 1.0))
                        .frame(width: w * 1.3, height: h * 0.45).blur(radius: 80)
                        .position(x: w * 0.95, y: h * 0.05).opacity(dark ? 0.55 : 0.65)
                    Ellipse().fill(dark ? color(0.07, 0.80, 0.48) : color(0.07, 0.45, 1.0))
                        .frame(width: w * 1.3, height: h * 0.5).blur(radius: 90)
                        .position(x: w * 0.05, y: h * 0.95).opacity(dark ? 0.60 : 0.75)
                }
            }
        }
    }
}

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(.secondarySystemBackground))
                } else {
                    Color.clear.glassEffect(.regular, in: shape)
                }
            }
            .overlay {
                shape.strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.7), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.05), radius: 14, y: 6)
    }
}

/// Native Liquid Glass confined to the tile surface so labels stay crisp.
struct GlassTile: ViewModifier {
    var tint: Color = .clear
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(.secondarySystemBackground))
                } else {
                    Color.clear.glassEffect(.regular.tint(tint.opacity(0.10)), in: shape)
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.28 : 0.9), .white.opacity(0.04),
                                            .white.opacity(scheme == .dark ? 0.10 : 0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.75)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.05), radius: 12, y: 5)
    }
}

struct PrimaryTaskButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.buttonIsPressed, configuration.isPressed)
            .foregroundStyle(scheme == .dark ? TodoPalette.ink : Color.white)
            .background(scheme == .dark ? Color(red: 0.90, green: 0.93, blue: 0.95) : TodoPalette.ink,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: TodoPalette.ink.opacity(0.14), radius: 14, y: 7)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.45), value: configuration.isPressed)
    }
}
