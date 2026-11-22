import SwiftUI

// MARK: - Buttons

public struct NKPillButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case secondary, primary, destructive, light }

    public var kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: Kind = .secondary) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NK.Font.label)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: NK.Metric.controlHeight - 2)
            .background(Capsule().fill(fill))
            .foregroundStyle(kind == .secondary ? NK.Palette.primary : (kind == .light ? Color.black : .white))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(Capsule())
    }

    private var fill: Color {
        switch kind {
        case .secondary: return NK.Palette.surfaceRaised
        case .primary: return Color.accentColor
        case .destructive: return NK.Palette.danger
        case .light: return Color.white.opacity(0.92)
        }
    }
}

public struct NKIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color?
    var size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    public init(_ systemImage: String, help: String, tint: Color? = nil, size: CGFloat = 24,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.tint = tint
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(tint ?? NK.Palette.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? NK.Palette.surfaceRaised : NK.Palette.surface))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Surfaces

public struct NKCardModifier: ViewModifier {
    var padding: CGFloat
    var highlighted: Bool

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: NK.Metric.radius, style: .continuous)
                    .fill(highlighted ? NK.Palette.surfaceRaised : NK.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NK.Metric.radius, style: .continuous)
                    .strokeBorder(NK.Palette.stroke, lineWidth: NK.Metric.hairline)
            )
    }
}

public extension View {
    func nkCard(padding: CGFloat = 10, highlighted: Bool = false) -> some View {
        modifier(NKCardModifier(padding: padding, highlighted: highlighted))
    }

    /// The standard frame for a tab: inset, dark scheme, white text, fills the area it is given.
    /// The Notch / Island panel has large rounded corners, so content keeps well clear of them: a header
    /// or icon in the top corner would otherwise be clipped.
    func nkTab(horizontal: CGFloat = NK.Metric.cornerClearance, top: CGFloat = NK.Metric.topClearance,
               bottom: CGFloat = NK.Metric.bottomClearance) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(NK.Palette.primary)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Content

public struct NKSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack {
            Text(title.uppercased())
                .font(NK.Font.caption)
                .tracking(0.6)
                .foregroundStyle(NK.Palette.tertiary)
            Spacer(minLength: 0)
            trailing
        }
    }
}

public extension NKSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

public struct NKEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    public init(_ systemImage: String, title: String, message: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NK.Palette.tertiary)
            Text(title).font(NK.Font.title)
            if let message {
                Text(message)
                    .font(NK.Font.caption)
                    .foregroundStyle(NK.Palette.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A circular progress ring with optional centered content.
public struct NKRing<Content: View>: View {
    let progress: Double
    var lineWidth: CGFloat
    var tint: Color
    let content: Content

    public init(progress: Double, lineWidth: CGFloat = 6, tint: Color = .accentColor,
                @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(NK.Palette.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: progress)
            content
        }
    }
}

/// A transient one-line status, drawn in place so layouts do not jump.
public struct NKStatusLine: View {
    let message: String?
    public init(_ message: String?) { self.message = message }

    public var body: some View {
        Text(message ?? " ")
            .font(NK.Font.caption)
            .foregroundStyle(NK.Palette.secondary)
            .lineLimit(1)
            .animation(.easeOut(duration: 0.15), value: message)
    }
}

// MARK: - Chip

/// A small status label, like "Running" or "Opus".
public struct NKChip: View {
    public enum Tone: Sendable { case neutral, green, blue, orange, purple, red }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(tone == .neutral ? 0.12 : 0.2)))
            .foregroundStyle(tone == .neutral ? NK.Palette.secondary : color)
    }

    private var color: Color {
        switch tone {
        case .neutral: return .white
        case .green: return NK.Palette.success
        case .blue: return NK.Palette.info
        case .orange: return NK.Palette.warning
        case .purple: return NK.Palette.mindful
        case .red: return NK.Palette.danger
        }
    }
}
