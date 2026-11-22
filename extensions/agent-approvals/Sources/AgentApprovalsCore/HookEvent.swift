import Foundation

/// A loosely typed JSON value; hook payloads carry arbitrary tool input.
public enum JSONValue: Decodable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
}

/// The JSON a Claude Code hook receives on stdin, relayed unchanged by the hook script.
public struct HookEvent: Decodable, Sendable {
    public let sessionID: String
    public let name: String
    public let cwd: String?
    public let toolName: String?
    public let toolInput: [String: JSONValue]
    public let message: String?
    public let prompt: String?
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", name = "hook_event_name", cwd
        case toolName = "tool_name", toolInput = "tool_input", message, prompt
        case transcriptPath = "transcript_path"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = (try? c.decode(String.self, forKey: .sessionID)) ?? "unknown"
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        cwd = try? c.decode(String.self, forKey: .cwd)
        toolName = try? c.decode(String.self, forKey: .toolName)
        toolInput = (try? c.decode([String: JSONValue].self, forKey: .toolInput)) ?? [:]
        message = try? c.decode(String.self, forKey: .message)
        prompt = try? c.decode(String.self, forKey: .prompt)
        transcriptPath = try? c.decode(String.self, forKey: .transcriptPath)
    }

    public init(sessionID: String, name: String, cwd: String? = nil, toolName: String? = nil,
                toolInput: [String: JSONValue] = [:], message: String? = nil,
                prompt: String? = nil, transcriptPath: String? = nil) {
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.toolName = toolName
        self.toolInput = toolInput
        self.message = message
        self.prompt = prompt
        self.transcriptPath = transcriptPath
    }

    public static func parse(_ data: Data) -> HookEvent? {
        try? JSONDecoder().decode(HookEvent.self, from: data)
    }

    /// Only a permission request waits for the user; everything else is a notification.
    public var isBlocking: Bool { name == "PermissionRequest" }

    public var command: String? { toolInput["command"]?.stringValue }
    public var filePath: String? { toolInput["file_path"]?.stringValue ?? toolInput["path"]?.stringValue }

    public var project: String {
        guard let cwd, !cwd.isEmpty else { return "Agent" }
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty ? "Agent" : last
    }
}

public enum HookDecision: Sendable, Equatable {
    case allow
    case deny(String)
}

public enum HookResponse {
    /// The JSON written back to the hook script. `nil` yields no output, so Claude Code
    /// falls back to its normal prompt.
    public static func render(_ decision: HookDecision?, for event: HookEvent) -> Data? {
        guard let decision, event.isBlocking else { return nil }
        var inner: [String: Any]
        switch decision {
        case .allow: inner = ["behavior": "allow"]
        case .deny(let message): inner = ["behavior": "deny", "message": message]
        }
        let payload: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": inner],
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }
}
