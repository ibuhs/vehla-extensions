import Foundation

public struct TranscriptStats: Equatable, Sendable {
    public var messages = 0
    public var tokens = 0
    public var model: String?
    public init(messages: Int = 0, tokens: Int = 0, model: String? = nil) {
        self.messages = messages; self.tokens = tokens; self.model = model
    }
}

/// Reads message and token counts from a session's JSONL transcript, incrementally: each call
/// only parses what was appended since the last one.
public actor TranscriptReader {
    private struct Cursor { var offset: UInt64 = 0; var stats = TranscriptStats() }
    private var cursors: [String: Cursor] = [:]
    private let chunkLimit = 16 << 20

    public init() {}

    public func stats(at path: String) -> TranscriptStats? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var cursor = cursors[path] ?? Cursor()
        if size < cursor.offset { cursor = Cursor() } // truncated or replaced
        if size > cursor.offset {
            try? handle.seek(toOffset: cursor.offset)
            let data = handle.readData(ofLength: min(Int(size - cursor.offset), chunkLimit))
            // Only whole lines: a partially written last line waits for the next call.
            if let lastNewline = data.lastIndex(of: 0x0A) {
                let complete = data.prefix(through: lastNewline)
                Self.accumulate(complete, into: &cursor.stats)
                cursor.offset += UInt64(complete.count)
            }
        }
        cursors[path] = cursor
        return cursor.stats
    }

    public func forget(_ path: String) { cursors[path] = nil }

    static func accumulate(_ data: Data, into stats: inout TranscriptStats) {
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  object["isSidechain"] as? Bool != true,
                  let type = object["type"] as? String,
                  let message = object["message"] as? [String: Any] else { continue }
            switch type {
            case "user":
                if countsAsUserMessage(message["content"]) { stats.messages += 1 }
            case "assistant":
                stats.messages += 1
                if let usage = message["usage"] as? [String: Any] {
                    for key in ["input_tokens", "output_tokens", "cache_creation_input_tokens"] {
                        stats.tokens += (usage[key] as? Int) ?? 0
                    }
                }
                if let model = message["model"] as? String, !model.hasPrefix("<") { stats.model = model }
            default: break
            }
        }
    }

    /// Tool results arrive as "user" entries but aren't messages the person wrote.
    private static func countsAsUserMessage(_ content: Any?) -> Bool {
        if content is String { return true }
        guard let parts = content as? [[String: Any]] else { return false }
        return parts.contains { ($0["type"] as? String) == "text" }
    }
}
