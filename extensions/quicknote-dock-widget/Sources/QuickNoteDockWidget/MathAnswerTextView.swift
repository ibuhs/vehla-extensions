import AppKit

/// Selectable derived text stays outside the editable document and its undo
/// history. Reused while its result is unchanged; only visible results exist.
@MainActor
final class MathAnswerTextView: NSTextView {
    var onSelect: ((MathAnswerTextView) -> Void)?
    var onCopy: ((String) -> Void)?
    var isActive = false
    private var monitor: Any?
    private var resultStorage: NSTextStorage?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let resultContainer = container ?? NSTextContainer(size: NSSize(width: 400, height: 30))
        if container == nil {
            storage.addLayoutManager(manager)
            manager.addTextContainer(resultContainer)
        }
        super.init(frame: frameRect, textContainer: resultContainer)
        if container == nil { resultStorage = storage }
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        defaultParagraphStyle = paragraph
    }
    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let range = selectedRange()
        guard types.contains(.string), range.length > 0,
              NSMaxRange(range) <= string.utf16.count else { return false }
        return pasteboard.setString((string as NSString).substring(with: range), forType: .string)
    }
    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        if writeSelection(to: clipboard, types: [.string]), let copied = clipboard.string(forType: .string) {
            onCopy?(copied)
        }
    }
    override func mouseDown(with event: NSEvent) {
        onSelect?(self)
        isActive = true
        window?.makeFirstResponder(self)
        if monitor == nil {
            // Vehla's nonactivating popup may route keys through its own
            // responder. Let ordinary fields own their keys, but handle Copy
            // for this selected result even when the host keeps focus.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.isActive, let window = self.window, window.isKeyWindow,
                          event.window === window || event.window == nil,
                          event.modifierFlags.contains(.command),
                          event.charactersIgnoringModifiers?.lowercased() == "c" else { return false }
                    if let editing = window.firstResponder as? NSTextView,
                       editing !== self, !(editing is InlineTextView) { return false }
                    self.copy(nil)
                    return true
                }
                return consumed ? nil : event
            }
        }
        super.mouseDown(with: event)
    }

    func detach() {
        isActive = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { detach() }
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { detach() }
        super.viewWillMove(toWindow: newWindow)
    }
}
