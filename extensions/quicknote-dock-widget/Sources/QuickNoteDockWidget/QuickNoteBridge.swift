import AppKit
import ApplicationServices
import Foundation

enum QuickNotePushResult: Equatable, Sendable {
    case saved
    case conflict(current: String)
    case failed(String)
}

/// Sends edits through Antinote itself. Antinote keeps notes in memory and
/// ignores outside writes to its database. When Antinote already shows the
/// note, the text is replaced through Accessibility without surfacing
/// Antinote. Otherwise the note is opened with `promoteAndOpen`, confirmed,
/// written, and Antinote is put back the way it was; `QuickNoteSuppressor`
/// keeps it out of sight meanwhile.
@MainActor
enum QuickNoteBridge {
    static func push(
        noteID: String,
        content: String,
        baseline: String,
        stored: @escaping @MainActor () async -> String?
    ) async -> QuickNotePushResult {
        guard AXIsProcessTrusted() else {
            return .failed("Vehla needs Accessibility permission (System Settings › Privacy & Security › Accessibility) to confirm the note before changing it in Antinote.")
        }
        guard let openURL = QuickNoteLinks.open(noteID: noteID),
              let overwriteURL = QuickNoteLinks.overwriteCurrent(content: content)
        else { return .failed("Could not build the Antinote link.") }

        let before = QuickNoteAppState.capture()
        var shown = QuickNoteAccessibility.currentNoteText()
        let isTarget: (String) -> Bool = { NoteText.matches($0, baseline) || NoteText.matches($0, content) }
        var switched = false

        var suppressor: QuickNoteSuppressor?
        if shown.map(isTarget) != true {
            switched = true
            suppressor = QuickNoteSuppressor(before)
            guard await QuickNoteLauncher.deliverInBackground(openURL) else {
                suppressor?.stop()
                return .failed("Could not reach Antinote.")
            }
            shown = await waitForText(where: isTarget)
        }
        guard let shown else {
            suppressor?.stop()
            before.restore()
            let current = QuickNoteAccessibility.currentNoteText()
            QuickNoteDiagnostics.note("push: Antinote shows a different note (\(current?.count ?? -1) chars); not overwriting")
            if let current { return .conflict(current: current) }
            return .failed("Could not read the note Antinote opened, so nothing was changed. Your text is on the clipboard.")
        }

        let alreadyStored = await stored()
        var saved = NoteText.same(shown, content) && NoteText.same(alreadyStored ?? "", content)
        if !saved, QuickNoteAccessibility.setCurrentNoteText(content) {
            saved = await waitForStored(content, stored)
            QuickNoteDiagnostics.note("push: Accessibility write \(saved ? "stored" : "not stored")")
        }
        if !saved {
            if suppressor == nil { suppressor = QuickNoteSuppressor(before) }
            if await QuickNoteLauncher.deliverInBackground(overwriteURL) {
                saved = await waitForStored(content, stored)
                QuickNoteDiagnostics.note("push: overwriteCurrent \(saved ? "stored" : "not stored")")
            }
        }
        suppressor?.stop()
        if switched || before.changed() {
            before.restore()
        }
        QuickNoteDiagnostics.note("push: switched=\(switched) saved=\(saved) hides=\(suppressor?.hides ?? 0)")
        return saved ? .saved : .failed("Antinote did not save the new text. Your text is on the clipboard.")
    }

    enum CreateResult {
        case created(QuickNoteNote)
        case sent
        case failed(String)
    }

    /// Creates a note with Antinote's `createNote` action without leaving
    /// Antinote in front, then finds the new note in Antinote's database.
    static func create(
        content: String,
        existingIDs: Set<String>,
        load: @escaping @MainActor () async -> [QuickNoteNote]?
    ) async -> CreateResult {
        guard let url = QuickNoteLinks.createNote(content: content) else {
            return .failed("Could not build the Antinote link.")
        }
        let before = QuickNoteAppState.capture()
        let suppressor = QuickNoteSuppressor(before)
        defer { suppressor?.stop() }
        guard await QuickNoteLauncher.deliverInBackground(url) else {
            return .failed("Could not reach Antinote. Your note is still here.")
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(6)
        var found: QuickNoteNote?
        var foundAt: ContinuousClock.Instant?
        var restores = 0
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
            if before.changed() {
                before.restore()
                restores += 1
            }
            if found == nil {
                found = await load()?.first { !existingIDs.contains($0.id) && NoteText.same($0.content, content) }
                if found != nil { foundAt = clock.now }
            }
            if let foundAt, clock.now - foundAt > .milliseconds(600) { break }
        }
        QuickNoteDiagnostics.note("create: found=\(found != nil) restores=\(restores)")
        return found.map(CreateResult.created) ?? .sent
    }

    private static func waitForText(
        timeout: Duration = .seconds(2.5),
        where accept: (String) -> Bool
    ) async -> String? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let text = QuickNoteAccessibility.currentNoteText(), accept(text) {
                return text
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return nil
    }

    private static func waitForStored(
        _ content: String,
        _ stored: @MainActor () async -> String?,
        timeout: Duration = .seconds(4)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let text = await stored(), NoteText.same(text, content) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}

/// Remembers whether Antinote was hidden, behind, or frontmost so a save
/// that had to surface it can put it back.
@MainActor
struct QuickNoteAppState {
    var app: NSRunningApplication?
    var wasActive: Bool
    var wasHidden: Bool
    var hadVisibleWindow: Bool
    var previousFront: NSRunningApplication?

    static func capture() -> QuickNoteAppState {
        let app = QuickNoteAccessibility.runningApp()
        return QuickNoteAppState(
            app: app,
            wasActive: app?.isActive ?? false,
            wasHidden: app?.isHidden ?? false,
            hadVisibleWindow: app.map { visibleWindowCount($0.processIdentifier) > 0 } ?? false,
            previousFront: NSWorkspace.shared.frontmostApplication
        )
    }

    func changed() -> Bool {
        guard let app else { return false }
        return app.isActive != wasActive
            || app.isHidden != wasHidden
            || (Self.visibleWindowCount(app.processIdentifier) > 0) != hadVisibleWindow
    }

    func restore() {
        guard let app, !wasActive else { return }
        if wasHidden || !hadVisibleWindow {
            app.hide()
        }
        if let previousFront, previousFront.processIdentifier != app.processIdentifier {
            if previousFront.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                NSApp.activate(ignoringOtherApps: true)
            } else {
                previousFront.activate(options: [])
            }
        }
        QuickNoteDiagnostics.note("restore: hid=\(wasHidden || !hadVisibleWindow) front=\(previousFront?.bundleIdentifier ?? "nil")")
    }

    static func visibleWindowCount(_ pid: pid_t) -> Int {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.filter {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }.count
    }
}

/// Antinote brings itself forward whenever it handles a link. Accessibility
/// reads and writes work while it is hidden, so when the user wasn't looking
/// at Antinote it is hidden again the moment it appears.
@MainActor
final class QuickNoteSuppressor {
    private var task: Task<Void, Never>?
    private(set) var hides = 0

    init?(_ state: QuickNoteAppState) {
        guard let app = state.app, !state.wasActive, state.wasHidden || !state.hadVisibleWindow else { return nil }
        task = Task { [weak self] in
            while !Task.isCancelled {
                if app.isActive || !app.isHidden || QuickNoteAppState.visibleWindowCount(app.processIdentifier) > 0 {
                    state.restore()
                    self?.hides += 1
                    try? await Task.sleep(for: .milliseconds(30))
                } else {
                    try? await Task.sleep(for: .milliseconds(4))
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

enum NoteText {
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    /// Antinote shortens pasted URLs on screen, so an exact match is not
    /// always possible. A matching first line identifies the same note.
    static func matches(_ shown: String, _ expected: String) -> Bool {
        if same(shown, expected) { return true }
        let shownLine = firstLine(shown)
        return !shownLine.isEmpty && shownLine == firstLine(expected)
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { normalized(String($0)) }
            .first { !$0.isEmpty } ?? ""
    }
}

@MainActor
enum QuickNoteAccessibility {
    static let bundleIDs = ["com.chabomakers.Antinote", "com.chabomakers.Antinote-setapp"]

    static func currentNoteText() -> String? {
        guard let area = noteTextArea() else { return nil }
        return string(area, "AXValue")
    }

    static func setCurrentNoteText(_ text: String) -> Bool {
        guard let area = noteTextArea() else { return false }
        return AXUIElementSetAttributeValue(area, "AXValue" as CFString, text as CFString) == .success
    }

    static func runningApp() -> NSRunningApplication? {
        bundleIDs.lazy.compactMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        }.first
    }

    private static func noteTextArea() -> AXUIElement? {
        guard let app = runningApp() else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1.0)
        var windows: [AXUIElement] = []
        for attribute in ["AXFocusedWindow", "AXMainWindow"] {
            if let window = element(root, attribute) { windows.append(window) }
        }
        windows += elements(root, "AXWindows")
        for window in windows {
            var areas: [AXUIElement] = []
            collectTextAreas(window, depth: 0, into: &areas)
            if let largest = areas.max(by: { area($0) < area($1) }) {
                return largest
            }
        }
        return nil
    }

    private static func collectTextAreas(_ element: AXUIElement, depth: Int, into areas: inout [AXUIElement]) {
        guard depth < 14 else { return }
        if string(element, "AXRole") == "AXTextArea" {
            areas.append(element)
            return
        }
        for child in elements(element, "AXChildren") {
            collectTextAreas(child, depth: depth + 1, into: &areas)
        }
    }

    private static func area(_ element: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return 0 }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size.width * size.height
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}
