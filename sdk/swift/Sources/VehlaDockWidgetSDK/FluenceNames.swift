import AppKit
import SwiftUI

// Fluence names for the SDK types. These are aliases, so a widget may mix both spellings. There is a single module,
// `VehlaDockWidgetSDK`, so widgets built for Vehla keep loading; `import VehlaDockWidgetSDK` brings in the Fluence
// names and the small SwiftUI kit below as well.
public typealias FluenceDockWidgetPlugin = VehlaDockWidgetPlugin
public typealias FluenceDockWidgetDescriptor = VehlaDockWidgetDescriptor
public typealias FluenceDockWidgetContext = VehlaDockWidgetContext
public typealias FluenceDockWidgetTheme = VehlaDockWidgetTheme
public typealias FluenceDockWidgetSurface = VehlaDockWidgetSurface
public typealias FluenceDockWidgetVisibilityPhase = VehlaDockWidgetVisibilityPhase
public typealias FluenceDockWidgetSettingDescriptor = VehlaDockWidgetSettingDescriptor
public typealias FluenceDockWidgetMenuAction = VehlaDockWidgetMenuAction
public typealias FluenceDockWidgetScheduledTask = VehlaDockWidgetScheduledTask
public let FluenceDockWidgetAPIVersion = VehlaDockWidgetAPIVersion

// MARK: - A small kit, so widgets look like part of one family

/// A tile face: a symbol, a value and a caption, laid out the way the built-in widgets are.
public struct FluenceTileFace: View {
    let symbol: String
    let value: String?
    let caption: String?
    let tint: Color?

    public init(symbol: String, value: String? = nil, caption: String? = nil, tint: Color? = nil) {
        self.symbol = symbol
        self.value = value
        self.caption = caption
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(tint ?? .primary)
            if let value {
                Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if let caption {
                Text(caption).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
    }
}

/// A titled block for popup content.
public struct FluenceSection<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line graph of recent values.
public struct FluenceSparkline: View {
    let values: [Double]
    let maximum: Double?
    let tint: Color

    public init(_ values: [Double], maximum: Double? = nil, tint: Color = .accentColor) {
        self.values = values
        self.maximum = maximum
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let top = max(maximum ?? (values.max() ?? 1), 0.0001)
            Path { path in
                guard values.count > 1 else { return }
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = proxy.size.height * (1 - CGFloat(min(value / top, 1)))
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 28)
    }
}

/// A labelled meter, such as memory in use.
public struct FluenceGauge: View {
    let title: String
    let value: Double
    let detail: String?
    let tint: Color

    public init(_ title: String, value: Double, detail: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                if let detail { Text(detail).monospacedDigit().foregroundStyle(.secondary) }
            }
            ProgressView(value: min(max(value, 0), 1)).tint(tint)
        }
    }
}

/// Hosts SwiftUI content in a view controller that keeps the host's glass visible behind it.
@MainActor
public func FluenceHostingController<Content: View>(_ content: Content) -> NSViewController {
    let controller = NSHostingController(rootView: content)
    controller.sizingOptions = []
    controller.view.wantsLayer = true
    controller.view.layer?.backgroundColor = NSColor.clear.cgColor
    return controller
}
