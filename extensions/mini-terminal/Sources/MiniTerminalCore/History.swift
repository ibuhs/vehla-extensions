import Foundation

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var command: String
    public var cwd: String?
    public var exitCode: Int?
    public var duration: Double
    public var date: Date
    public var pinned: Bool
    /// How many times this command has been run.
    public var runs: Int

    public init(id: UUID = UUID(), command: String, cwd: String? = nil, exitCode: Int? = nil,
                duration: Double = 0, date: Date = Date(), pinned: Bool = false, runs: Int = 1) {
        self.id = id; self.command = command; self.cwd = cwd; self.exitCode = exitCode
        self.duration = duration; self.date = date; self.pinned = pinned; self.runs = runs
    }

    public var succeeded: Bool? { exitCode.map { $0 == 0 } }
}

/// Every command run in the terminal: searchable, pinnable, and kept on this Mac only.
public struct CommandHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [HistoryEntry] = []   // newest first
    public static let limit = 500

    public init() {}

    /// Lines that look like they carry a secret are never stored, and a leading space opts a command out
    /// (the usual shell convention).
    public static func shouldRecord(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !command.hasPrefix(" ") else { return false }
        let pattern = #"(?i)(pass(word|wd)?|secret|token|api[_-]?key|authorization|bearer)\s*[=:]|--(password|token|secret)|\b(AKIA[0-9A-Z]{12,}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})"#
        return trimmed.range(of: pattern, options: .regularExpression) == nil
    }

    /// Adds a finished command. Running the same command again moves it to the top and updates its result
    /// instead of piling up duplicates; pinned commands are never dropped.
    @discardableResult
    public mutating func record(command: String, cwd: String?, exitCode: Int?, duration: Double, at date: Date = Date()) -> Bool {
        guard Self.shouldRecord(command) else { return false }
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var pinned = false, runs = 1
        if let i = entries.firstIndex(where: { $0.command == text }) {
            pinned = entries[i].pinned
            runs = entries[i].runs + 1
            entries.remove(at: i)
        }
        entries.insert(HistoryEntry(command: text, cwd: cwd, exitCode: exitCode, duration: duration, date: date,
                                    pinned: pinned, runs: runs), at: 0)
        trim()
        return true
    }

    private mutating func trim() {
        var unpinned = 0
        entries = entries.filter { entry in
            if entry.pinned { return true }
            unpinned += 1
            return unpinned <= Self.limit
        }
    }

    public mutating func togglePin(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].pinned.toggle()
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clearUnpinned() { entries.removeAll { !$0.pinned } }

    public var pinned: [HistoryEntry] { entries.filter(\.pinned) }

    /// Entries matching every word of `query` (any order, any case). Prefix matches rank first, then pinned,
    /// then newest.
    public func search(_ query: String) -> [HistoryEntry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        let matches = entries.enumerated().filter { _, e in
            let hay = e.command.lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        let first = words[0]
        return matches.sorted { a, b in
            let pa = a.element.command.lowercased().hasPrefix(first), pb = b.element.command.lowercased().hasPrefix(first)
            if pa != pb { return pa }
            if a.element.pinned != b.element.pinned { return a.element.pinned }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The commands you run most often, most frequent first.
    public func frequent(limit: Int = 5) -> [String] {
        entries.enumerated()
            .sorted { $0.element.runs == $1.element.runs ? $0.offset < $1.offset : $0.element.runs > $1.element.runs }
            .prefix(limit).map(\.element.command)
    }
}
