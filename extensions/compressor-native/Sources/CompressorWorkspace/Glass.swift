import SwiftUI

/// Whether the window uses the indigo-tinted style. Off by default: plain
/// system Liquid Glass with no tint and no coloured backdrop.
private struct GlassTintedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glassTinted: Bool {
        get { self[GlassTintedKey.self] }
        set { self[GlassTintedKey.self] = newValue }
    }
}

/// The Compressor's blue/indigo palette.
enum Brand {
    static let indigo = Color(red: 0.36, green: 0.34, blue: 0.98)
    static let blue = Color(red: 0.20, green: 0.52, blue: 1.00)
    static let sky = Color(red: 0.36, green: 0.78, blue: 1.00)
    static let violet = Color(red: 0.56, green: 0.36, blue: 0.98)
}

/// Tinted Liquid Glass on macOS 26+, tinted material before that.
struct GlassCard: ViewModifier {
    @Environment(\.glassTinted) private var tinted
    var cornerRadius: CGFloat
    var tint: Color
    var strength: Double
    var interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            let glass = tinted ? Glass.regular.tint(tint.opacity(strength)) : Glass.regular
            content.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tinted ? tint.opacity(strength * 0.7) : Color.clear, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
        }
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 22,
        tint: Color = Brand.indigo,
        strength: Double = 0.20,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint, strength: strength, interactive: interactive))
    }
}

/// The main call to action: saturated indigo glass that stays vivid even when
/// the window is inactive.
struct PrimaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryGlassLabel(configuration: configuration)
    }

    private struct PrimaryGlassLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.glassTinted) private var tinted

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(tinted ? Color.white : Color.primary)
                .padding(.horizontal, 20).padding(.vertical, 11)
                .glassCard(cornerRadius: 22, tint: Brand.indigo, strength: 0.9, interactive: true)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.smooth(duration: 0.15), value: configuration.isPressed)
        }
    }
}

/// Secondary actions: blue glass with full-contrast text, so it stays legible
/// whether or not the window is active.
struct SecondaryGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryGlassLabel(configuration: configuration)
    }

    private struct SecondaryGlassLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassCard(cornerRadius: 16, tint: Brand.blue, strength: 0.5, interactive: true)
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.smooth(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct GlassButton: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        if prominent {
            content.buttonStyle(PrimaryGlassButtonStyle())
        } else {
            content.buttonStyle(SecondaryGlassButtonStyle())
        }
    }
}

extension View {
    func glassButton(prominent: Bool = false) -> some View {
        modifier(GlassButton(prominent: prominent))
    }
}

/// Soft colour blobs behind the glass, so there is something to refract.
struct GlassBackdrop: View {
    let base: Color
    let isDark: Bool
    let tinted: Bool

    var body: some View {
        if tinted { colourful } else { Color.clear.ignoresSafeArea() }
    }

    private var colourful: some View {
        ZStack {
            base
            LinearGradient(
                colors: [Brand.indigo.opacity(isDark ? 0.34 : 0.22), Brand.blue.opacity(isDark ? 0.18 : 0.12), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Brand.violet.opacity(isDark ? 0.45 : 0.30))
                .frame(width: 300, height: 300).blur(radius: 90).offset(x: -170, y: -230)
            Circle().fill(Brand.sky.opacity(isDark ? 0.40 : 0.28))
                .frame(width: 280, height: 280).blur(radius: 90).offset(x: 190, y: 40)
            Circle().fill(Brand.blue.opacity(isDark ? 0.42 : 0.26))
                .frame(width: 320, height: 320).blur(radius: 100).offset(x: -80, y: 290)
        }
        .ignoresSafeArea()
    }
}
