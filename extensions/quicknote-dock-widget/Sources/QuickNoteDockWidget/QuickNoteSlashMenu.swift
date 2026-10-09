import AppKit

/// One entry in the `/` command menu.
struct SlashCommand: Equatable, Sendable {
    let name: String
    let detail: String
    let symbol: String

    static let all: [SlashCommand] = [
        .init(name: "/list", detail: "Checklist item", symbol: "checklist"),
        .init(name: "/math", detail: "Answers lines ending in =", symbol: "function"),
        .init(name: "/sum", detail: "Totals the numbers below", symbol: "sum"),
        .init(name: "/average", detail: "Averages the numbers below", symbol: "chart.bar"),
        .init(name: "/count", detail: "Counts words and characters", symbol: "number"),
        .init(name: "/code", detail: "Monospaced block", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(name: "/text", detail: "Ends the current section", symbol: "text.alignleft"),
        .init(name: "/checkbox", detail: "Checkbox", symbol: "checkmark.square"),
        .init(name: "/bullet", detail: "Bulleted item", symbol: "list.bullet"),
        .init(name: "/numbered", detail: "Numbered item", symbol: "list.number"),
        .init(name: "/date", detail: "Today’s date", symbol: "calendar"),
        .init(name: "/time", detail: "The current time", symbol: "clock"),
        .init(name: "/new", detail: "New note", symbol: "square.and.pencil"),
        .init(name: "/search", detail: "Search your notes", symbol: "magnifyingglass"),
        .init(name: "/copy", detail: "Copy this note", symbol: "doc.on.doc"),
        .init(name: "/paste", detail: "Collect copies with AutoPaste", symbol: "clipboard"),
        .init(name: "/timer", detail: "Timer, e.g. /timer 5: Tea", symbol: "timer"),
        .init(name: "/import", detail: "Import notes", symbol: "square.and.arrow.down"),
        .init(name: "/export", detail: "Export this note", symbol: "square.and.arrow.up"),
    ]

    /// Commands whose name starts with the query first, then ones containing it.
    static func matching(_ query: String) -> [SlashCommand] {
        let needle = query.lowercased()
        let typed = needle.hasPrefix("/") ? String(needle.dropFirst()) : needle
        guard !typed.isEmpty else { return all }
        let prefixed = all.filter { $0.name.dropFirst().hasPrefix(typed) }
        // Descriptions only match once a word is forming, so "/s" stays short.
        let containing = all.filter {
            !prefixed.contains($0) && ($0.name.dropFirst().contains(typed) || (typed.count >= 3 && $0.detail.lowercased().contains(typed)))
        }
        return prefixed + containing
    }
}

/// The `/` suggestions, drawn inside the editor under the caret. A native
/// completion window is a separate window, which the host's nonactivating
/// popup does not reliably show or route keys to.
@MainActor
final class SlashMenuView: NSView {
    static let rowHeight: CGFloat = 30
    static let footerHeight: CGFloat = 24
    static let width: CGFloat = 290
    static let visibleRows = 7

    var items: [SlashCommand] = [] { didSet { if items != oldValue { selection = 0 }; rows.needsDisplay = true } }
    var selection = 0 { didSet { rows.needsDisplay = true } }
    var textColor: NSColor = .labelColor { didSet { rows.needsDisplay = true; needsLayout = true } }
    var onChoose: (SlashCommand) -> Void = { _ in }

    private let background = NSVisualEffectView()
    private let rows = RowsView()

    var preferredHeight: CGFloat {
        CGFloat(min(items.count, Self.visibleRows)) * Self.rowHeight + Self.footerHeight + 8
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.alphaValue = 0.5
        background.autoresizingMask = [.width, .height]
        rows.autoresizingMask = [.width, .height]
        rows.owner = self
        addSubview(background)
        addSubview(rows)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Commands")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        background.frame = bounds
        rows.frame = bounds
        layer?.borderColor = textColor.withAlphaComponent(0.15).cgColor

    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = (selection + delta + items.count) % items.count
    }

    /// The first row shown, so the selection always stays in view.
    fileprivate var firstVisible: Int {
        max(0, min(selection - Self.visibleRows + 1, items.count - Self.visibleRows))
    }

    fileprivate final class RowsView: NSView {
        weak var owner: SlashMenuView?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            guard let menu = owner else { return }
            floatingSurface(for: menu.textColor).setFill()
            bounds.fill()
            let color = menu.textColor
            let first = menu.firstVisible
            let shown = menu.items.dropFirst(first).prefix(SlashMenuView.visibleRows)
            for (offset, item) in shown.enumerated() {
                let index = first + offset
                let row = NSRect(x: 4, y: 4 + CGFloat(offset) * SlashMenuView.rowHeight, width: bounds.width - 8, height: SlashMenuView.rowHeight)
                if index == menu.selection {
                    color.withAlphaComponent(0.14).setFill()
                    NSBezierPath(roundedRect: row, xRadius: 6, yRadius: 6).fill()
                }
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                    .applying(.init(paletteColors: [color.withAlphaComponent(0.8)]))
                if let image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                    let size = image.size
                    image.draw(in: NSRect(x: row.minX + 10 + (16 - size.width) / 2, y: row.midY - size.height / 2,
                                          width: size.width, height: size.height),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                let name = NSAttributedString(string: item.name, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: color,
                ])
                let nameSize = name.size()
                name.draw(at: NSPoint(x: row.minX + 34, y: row.midY - nameSize.height / 2))
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                let detail = NSAttributedString(string: item.detail, attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: color.withAlphaComponent(0.55), .paragraphStyle: paragraph,
                ])
                let detailX = row.minX + 34 + max(nameSize.width, 78) + 10
                let detailHeight = detail.size().height
                detail.draw(in: NSRect(x: detailX, y: row.midY - detailHeight / 2, width: row.maxX - detailX - 8, height: detailHeight))
            }
            let footerY = 4 + CGFloat(shown.count) * SlashMenuView.rowHeight
            color.withAlphaComponent(0.1).setFill()
            NSRect(x: 0, y: footerY + 2, width: bounds.width, height: 0.5).fill()
            let hint = NSAttributedString(string: "↑↓ choose   ↩ insert   esc dismiss", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: color.withAlphaComponent(0.45),
            ])
            hint.draw(at: NSPoint(x: 14, y: footerY + 7))
        }

        override func mouseDown(with event: NSEvent) {
            guard let menu = owner else { return }
            let point = convert(event.locationInWindow, from: nil)
            let offset = Int((point.y - 4) / SlashMenuView.rowHeight)
            let index = menu.firstVisible + offset
            guard offset >= 0, offset < SlashMenuView.visibleRows, menu.items.indices.contains(index) else { return }
            menu.selection = index
            menu.onChoose(menu.items[index])
        }
    }
}
