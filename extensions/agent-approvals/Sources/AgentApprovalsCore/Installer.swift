import Foundation

/// The hook script and the Claude Code settings that wire it up.
public enum HookInstaller {
    public static var directory: String { NSHomeDirectory() + "/.vehla/agent-approvals" }
    public static var socketPath: String { directory + "/hook.sock" }
    public static var scriptPath: String { directory + "/hook.py" }

    /// Relays hook stdin to the Notch and prints its answer. If the Notch is off or silent it
    /// prints nothing and exits 0, so Claude Code falls back to its normal prompt.
    public static let script = #"""
    #!/usr/bin/python3
    import os, socket, sys

    SOCK = os.environ.get("VEHLA_AGENT_HOOK_SOCK") or os.path.expanduser("~/.vehla/agent-approvals/hook.sock")
    WAIT = float(os.environ.get("VEHLA_AGENT_HOOK_WAIT", "110"))

    data = sys.stdin.buffer.read()
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1.5)
        s.connect(SOCK)
        s.sendall(data)
        s.shutdown(socket.SHUT_WR)
        s.settimeout(WAIT)
        out = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            out += chunk
        sys.stdout.buffer.write(out)
    except Exception:
        pass
    sys.exit(0)
    """# + "\n"

    @discardableResult
    public static func installScript() throws -> String {
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        return scriptPath
    }

    public static var scriptInstalled: Bool {
        (try? String(contentsOfFile: scriptPath, encoding: .utf8)) == script
    }

    /// A `hooks` block to merge into `~/.claude/settings.json`. Nothing is written for you.
    public static func settingsSnippet() -> String {
        let command = "/usr/bin/python3 \(scriptPath)"
        func entry(_ extra: [String: Any] = [:]) -> [[String: Any]] {
            var hook: [String: Any] = ["type": "command", "command": command]
            for (k, v) in extra { hook[k] = v }
            return [["hooks": [hook]]]
        }
        let hooks: [String: Any] = [
            "PermissionRequest": entry(["timeout": 120]),
            "SessionStart": entry(["async": true]),
            "UserPromptSubmit": entry(["async": true]),
            "PreToolUse": entry(["async": true]),
            "Stop": entry(["async": true]),
            "SessionEnd": entry(["async": true]),
        ]
        let data = try? JSONSerialization.data(
            withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
