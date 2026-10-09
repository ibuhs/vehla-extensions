import AppKit

/// A paragraph, list run or heading: one tick on the scroll rail.
struct NoteOutlineBlock: Equatable, Sendable {
    var location: Int
    var title: String
    var preview: String
    var heading: Bool

    static let limit = 400

    /// Blocks are separated by blank lines; every heading is its own block.
    static func blocks(in text: String) -> [NoteOutlineBlock] {
        var blocks: [NoteOutlineBlock] = []
        var start = 0, lines: [String] = []
        func flush() {
            guard let first = lines.first else { return }
            blocks.append(NoteOutlineBlock(location: start, title: clean(first),
                                           preview: lines.dropFirst().map(clean).joined(separator: " "), heading: false))
            lines = []
        }
        var offset = 0
        for raw in text.components(separatedBy: "\n") {
            defer { offset += raw.utf16.count + 1 }
            guard blocks.count < limit else { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.range(of: #"^#{1,6} "#, options: .regularExpression) != nil {
                flush()
                blocks.append(NoteOutlineBlock(location: offset, title: clean(line), preview: "", heading: true))
                continue
            }
            if lines.isEmpty { start = offset }
            lines.append(line)
        }
        if blocks.count < limit { flush() }
        return blocks
    }

    /// Marker-free text for the hover card.
    static func clean(_ line: String) -> String {
        let stripped = line.replacingOccurrences(of: #"^(?:#{1,6} |- \[[ xX]?\] ?|\[[ xX]?\] ?|[-*] |\d+\. )"#,
                                                 with: "", options: .regularExpression)
        return String(stripped.prefix(160))
    }
}

/// Codex-style outline scrollbar: a column of ticks, one per block. Ticks on
/// screen are brighter; hovering one previews it and clicking scrolls there.
@MainActor
final class NoteScrollRail: NSView {
    static let width: CGFloat = 26
    static let spacing: CGFloat = 8

    weak var textView: NSTextView?
    var color: NSColor = .labelColor { didSet { needsDisplay = true; card.color = color } }
    /// Scrolls the note to a y offset; animated for clicks, immediate while dragging.
    var onJump: (CGFloat, Bool) -> Void = { _, _ in }

    private(set) var blocks: [NoteOutlineBlock] = []
    private var offsets: [CGFloat] = []
    private var visible: Set<Int> = []
    private var hovered: Int?
    private var scrollable = false
    let card = NoteRailCard()

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Without this a transparent view lets the host treat clicks as window drags.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Note outline")
    }

    required init?(coder: NSCoder) { nil }

    /// Ticks shown: every block, or an even sample when they would not fit.
    var slots: [Int] {
        guard scrollable, blocks.count > 1 else { return [] }
        let capacity = max(2, Int((bounds.height - 32) / Self.spacing))
        guard blocks.count > capacity else { return Array(blocks.indices) }
        return (0..<capacity).map { $0 * blocks.count / capacity }
    }

    private func slotY(_ slot: Int, of count: Int) -> CGFloat {
        let column = CGFloat(count - 1) * Self.spacing
        return max(16, (bounds.height - column) / 2) + CGFloat(slot) * Self.spacing
    }

    func reload() {
        guard let textView else { return }
        blocks = NoteOutlineBlock.blocks(in: textView.string)
        hovered = nil
        card.isHidden = true
        refreshPositions()
    }

    /// Recomputes where blocks sit in the laid-out text and which are on screen.
    func refreshPositions() {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let clip = textView.enclosingScrollView?.contentView else { return }
        let length = (textView.string as NSString).length
        offsets = blocks.map { block in
            guard block.location < length else { return textView.bounds.height }
            let glyph = layoutManager.glyphIndexForCharacter(at: block.location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: false).minY
                + textView.textContainerOrigin.y
        }
        _ = container
        let shown = clip.bounds
        scrollable = textView.frame.height > shown.height + 1
        visible = Set(blocks.indices.filter { index in
            let top = offsets[index]
            let bottom = index + 1 < offsets.count ? offsets[index + 1] : textView.frame.height
            return bottom > shown.minY + 4 && top < shown.maxY - 4
        })
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let slots = self.slots
        for (slot, index) in slots.enumerated() {
            let y = slotY(slot, of: slots.count)
            let isHovered = hovered == slot
            let onScreen = visible.contains(index)
            var length: CGFloat = blocks[index].heading ? 11 : 8
            if onScreen { length += 5 }
            if isHovered { length = 18 }
            let alpha: CGFloat = isHovered ? 1 : onScreen ? 0.9 : 0.28
            color.withAlphaComponent(alpha).setFill()
            // Ticks hang from the right edge and grow toward the text.
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 6 - length, y: y - 0.75, width: length, height: isHovered || onScreen ? 2 : 1.5),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        if !slots.isEmpty { addCursorRect(bounds, cursor: .pointingHand) }
    }

    /// The nearest tick; with `clamped`, positions past either end pick the end tick.
    private func slot(at point: NSPoint, clamped: Bool = false) -> Int? {
        let slots = self.slots
        guard !slots.isEmpty else { return nil }
        let first = slotY(0, of: slots.count), last = slotY(slots.count - 1, of: slots.count)
        guard clamped || (point.y >= first - Self.spacing && point.y <= last + Self.spacing) else { return nil }
        return min(slots.count - 1, max(0, Int(((point.y - first) / Self.spacing).rounded())))
    }

    /// A document offset that moves continuously between ticks while scrubbing.
    func scrubOffset(at point: NSPoint) -> CGFloat? {
        let slots = self.slots
        guard slots.count > 1, offsets.count == blocks.count else { return nil }
        let first = slotY(0, of: slots.count)
        let position = min(max(0, (point.y - first) / Self.spacing), CGFloat(slots.count - 1))
        let lower = Int(position.rounded(.down)), upper = min(lower + 1, slots.count - 1)
        let fraction = position - CGFloat(lower)
        return offsets[slots[lower]] + (offsets[slots[upper]] - offsets[slots[lower]]) * fraction
    }

    override func mouseMoved(with event: NSEvent) { hover(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hover(nil) }

    func hover(_ point: NSPoint?, clamped: Bool = false) {
        let slot = point.flatMap { self.slot(at: $0, clamped: clamped) }
        guard slot != hovered else { return }
        hovered = slot
        needsDisplay = true
        guard let slot, let superview = card.superview else { card.isHidden = true; return }
        let slots = self.slots
        let block = blocks[slots[slot]]
        card.show(title: block.title, preview: block.preview, heading: block.heading)
        let anchor = convert(NSPoint(x: 0, y: slotY(slot, of: slots.count)), to: superview)
        let size = card.fittingSize
        var y = anchor.y - size.height / 2
        y = max(4, min(y, superview.bounds.height - size.height - 4))
        card.frame = NSRect(x: max(4, anchor.x - size.width - 6), y: y, width: size.width, height: size.height)
        card.isHidden = false
    }

    private var dragged = false

    override func mouseDown(with event: NSEvent) { dragged = false }

    /// Dragging scrubs through the note, following the pointer between ticks.
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let y = scrubOffset(at: point) else { return }
        dragged = true
        hover(point, clamped: true)
        onJump(y, false)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { dragged = false }
        guard !dragged, let slot = slot(at: point, clamped: true) else { return }
        jump(toSlot: slot)
    }

    func jump(toSlot slot: Int) {
        let slots = self.slots
        guard slots.indices.contains(slot), offsets.indices.contains(slots[slot]) else { return }
        onJump(offsets[slots[slot]], true)
    }
}

/// An opaque backing, so floating panels stay readable over note text in
/// the host's translucent popup.
@MainActor
func floatingSurface(for text: NSColor) -> NSColor {
    let brightness = text.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
    return brightness > 0.5 ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.99, alpha: 1)
}

/// The preview shown beside a hovered tick.
@MainActor
final class NoteRailCard: NSView {
    var color: NSColor = .labelColor { didSet { apply() } }
    private let title = NSTextField(wrappingLabelWithString: "")
    private let preview = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 10, right: 12)
        for label in [title, preview] {
            label.isSelectable = false
            label.preferredMaxLayoutWidth = 216
            stack.addArrangedSubview(label)
        }
        title.maximumNumberOfLines = 2
        preview.maximumNumberOfLines = 3
        title.lineBreakMode = .byTruncatingTail
        preview.lineBreakMode = .byTruncatingTail
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 240),
        ])
        isHidden = true
        apply()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(title text: String, preview body: String, heading: Bool) {
        title.stringValue = text.isEmpty ? "Untitled" : text
        title.font = .systemFont(ofSize: 12, weight: heading ? .bold : .semibold)
        preview.stringValue = body
        preview.isHidden = body.isEmpty
        layoutSubtreeIfNeeded()
    }

    private func apply() {
        title.textColor = color
        preview.textColor = color.withAlphaComponent(0.6)
        preview.font = .systemFont(ofSize: 11)
        layer?.borderColor = color.withAlphaComponent(0.14).cgColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        floatingSurface(for: color).setFill()
        bounds.fill()
    }
}
