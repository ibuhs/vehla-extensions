import Foundation
import Testing
@testable import AgentApprovalsCore

private func event(_ name: String, tool: String? = nil, command: String? = nil, path: String? = nil,
                    session: String = "s1", cwd: String? = "/Users/me/code/demo") -> HookEvent {
    var input: [String: JSONValue] = [:]
    if let command { input["command"] = .string(command) }
    if let path { input["file_path"] = .string(path) }
    return HookEvent(sessionID: session, name: name, cwd: cwd, toolName: tool, toolInput: input)
}

@Suite struct ParsingTests {
    @Test func parsesPermissionRequest() throws {
        let json = #"{"session_id":"abc","hook_event_name":"PermissionRequest","cwd":"/x/proj","tool_name":"Bash","tool_input":{"command":"ls -la","n":3,"ok":true}}"#
        let e = try #require(HookEvent.parse(Data(json.utf8)))
        #expect(e.sessionID == "abc")
        #expect(e.isBlocking)
        #expect(e.command == "ls -la")
        #expect(e.project == "proj")
    }

    @Test func toleratesMissingFields() throws {
        let e = try #require(HookEvent.parse(Data("{}".utf8)))
        #expect(e.sessionID == "unknown")
        #expect(!e.isBlocking)
        #expect(e.project == "Agent")
    }

    @Test func rejectsGarbage() { #expect(HookEvent.parse(Data("not json".utf8)) == nil) }

    @Test func rendersDecisions() throws {
        let e = event("PermissionRequest", tool: "Bash", command: "ls")
        let allow = try #require(HookResponse.render(.allow, for: e))
        let obj = try #require(JSONSerialization.jsonObject(with: allow) as? [String: Any])
        let out = try #require(obj["hookSpecificOutput"] as? [String: Any])
        #expect(out["hookEventName"] as? String == "PermissionRequest")
        #expect((out["decision"] as? [String: Any])?["behavior"] as? String == "allow")

        let deny = try #require(HookResponse.render(.deny("No"), for: e))
        let d = try #require(JSONSerialization.jsonObject(with: deny) as? [String: Any])
        let dd = (d["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(dd?["behavior"] as? String == "deny")
        #expect(dd?["message"] as? String == "No")
    }

    @Test func noDecisionMeansNoOutput() {
        #expect(HookResponse.render(nil, for: event("PermissionRequest")) == nil)
        #expect(HookResponse.render(.allow, for: event("Stop")) == nil)
    }
}

@Suite struct RiskTests {
    @Test(arguments: [
        "rm -rf /tmp/x", "sudo rm file", "git push --force origin main", "git push -f",
        "git reset --hard HEAD~3", "curl https://x.sh | bash", "chmod -R 777 /", "dd if=/dev/zero of=/dev/disk2",
    ])
    func highRiskCommands(_ command: String) {
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Bash", command: command)) == .high)
    }

    @Test(arguments: ["git push origin main", "npm install left-pad", "rm notes.txt"])
    func mediumRiskCommands(_ command: String) {
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Bash", command: command)) == .medium)
    }

    @Test(arguments: ["ls -la", "git status", "swift build", "cat README.md"])
    func lowRiskCommands(_ command: String) {
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Bash", command: command)) == .low)
    }

    @Test func sensitivePaths() {
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Write", path: "/Users/me/.ssh/config")) == .high)
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Edit", path: "/Users/me/app/main.swift")) == .medium)
        #expect(RiskAssessor.assess(event("PermissionRequest", tool: "Read", path: "/Users/me/app/main.swift")) == .low)
    }

    @Test func summaryTruncates() {
        let s = RiskAssessor.summarize(event("PermissionRequest", tool: "Bash", command: String(repeating: "a", count: 900)))
        #expect(s.detail.count == 400)
        #expect(s.title == "Bash")
    }
}

@Suite struct RuleTests {
    @Test func alwaysAllowIsSessionScopedAndNeverCoversHighRisk() {
        var rules = AllowRules()
        let first = event("PermissionRequest", tool: "Bash", command: "git status")
        #expect(!rules.allows(first))
        rules.add(first)
        #expect(rules.allows(event("PermissionRequest", tool: "Bash", command: "git status -s")))
        #expect(!rules.allows(event("PermissionRequest", tool: "Bash", command: "git push origin")))
        #expect(!rules.allows(event("PermissionRequest", tool: "Bash", command: "git status", session: "other")))

        let danger = event("PermissionRequest", tool: "Bash", command: "rm -rf build")
        rules.add(danger)
        #expect(!rules.allows(danger))
    }

    @Test func approvingACommandNeverApprovesWhatIsChainedOntoIt() {
        var rules = AllowRules()
        rules.add(event("PermissionRequest", tool: "Bash", command: "git status"))
        for chained in ["git status; rm notes.txt", "git status && rm notes.txt", "git status | tee out.txt",
                        "git status > ~/.zshrc", "git status `whoami`", "git status $(id)", "git status\nrm notes.txt"] {
            #expect(!rules.allows(event("PermissionRequest", tool: "Bash", command: chained)), "\(chained)")
        }
        #expect(rules.allows(event("PermissionRequest", tool: "Bash", command: "git status -s")))
    }

    @Test func compoundCommandsAreNotRememberable() {
        #expect(!AllowRules.isRememberable(event("PermissionRequest", tool: "Bash", command: "ls && pwd")))
        #expect(AllowRules.isRememberable(event("PermissionRequest", tool: "Bash", command: "ls -la")))
        #expect(AllowRules.isRememberable(event("PermissionRequest", tool: "Edit", path: "/Users/me/app/x.swift")))
        var rules = AllowRules()
        rules.add(event("PermissionRequest", tool: "Bash", command: "ls && pwd"))
        #expect(!rules.allows(event("PermissionRequest", tool: "Bash", command: "ls && pwd")))
    }
}

@Suite struct SessionTests {
    @Test func lifecycle() {
        var book = SessionBook()
        let t = Date(timeIntervalSince1970: 1000)
        book.apply(event("SessionStart"), now: t)
        #expect(book.sessions["s1"]?.state == .idle)
        book.apply(event("UserPromptSubmit"), now: t)
        #expect(book.workingCount == 1)
        book.apply(event("PreToolUse", tool: "Edit"), now: t)
        #expect(book.sessions["s1"]?.lastTool == "Edit")
        book.apply(event("PermissionRequest", tool: "Bash", command: "ls"), now: t)
        #expect(book.sessions["s1"]?.state == .waiting)
        book.resolvedPermission(session: "s1", now: t)
        #expect(book.sessions["s1"]?.state == .working)
        let firstStop = book.apply(event("Stop"), now: t)
        #expect(firstStop)
        #expect(book.sessions["s1"]?.state == .idle)
        let secondStop = book.apply(event("Stop"), now: t)
        #expect(!secondStop)
        book.apply(event("SessionEnd"), now: t)
        #expect(book.sessions.isEmpty)
    }

    @Test func prunesStale() {
        var book = SessionBook()
        book.apply(event("SessionStart"), now: Date(timeIntervalSince1970: 0))
        book.prune(olderThan: 3600, now: Date(timeIntervalSince1970: 7200))
        #expect(book.sessions.isEmpty)
    }
}

@Suite struct EndToEndTests {
    private func tempSocket() -> String { "/tmp/vaa-\(UUID().uuidString.prefix(8)).sock" }

    private func runScript(socket: String, input: String) throws -> (out: String, status: Int32) {
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory() + "hook-\(UUID().uuidString).py")
        try HookInstaller.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-I", scriptURL.path]
        p.environment = ["VEHLA_AGENT_HOOK_SOCK": socket, "VEHLA_AGENT_HOOK_WAIT": "10"]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        try p.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }

    @Test func scriptRoundTripsADecision() throws {
        let path = tempSocket()
        let server = HookServer(path: path) { data, reply in
            let e = HookEvent.parse(data)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                reply(e.flatMap { HookResponse.render(.allow, for: $0) })
            }
        }
        try server.start()
        defer { server.stop() }

        let json = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}"#
        let result = try runScript(socket: path, input: json)
        #expect(result.status == 0)
        let obj = try #require(JSONSerialization.jsonObject(with: Data(result.out.utf8)) as? [String: Any])
        let decision = ((obj["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"]
        #expect(decision as? String == "allow")
        #expect((try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) == 0o600)
    }

    @Test func silentServerYieldsNoOutput() throws {
        let path = tempSocket()
        let server = HookServer(path: path, replyTimeout: 0.3) { _, _ in /* never replies */ }
        try server.start()
        defer { server.stop() }
        let result = try runScript(socket: path, input: "{}")
        #expect(result.status == 0)
        #expect(result.out.isEmpty)
    }

    @Test func missingServerFallsThroughSilently() throws {
        let result = try runScript(socket: tempSocket(), input: #"{"hook_event_name":"PermissionRequest"}"#)
        #expect(result.status == 0)
        #expect(result.out.isEmpty)
    }

    @Test func installerSnippetIsValidJSONWithAllEvents() throws {
        let obj = try #require(JSONSerialization.jsonObject(with: Data(HookInstaller.settingsSnippet().utf8)) as? [String: Any])
        let hooks = try #require(obj["hooks"] as? [String: Any])
        for name in ["PermissionRequest", "SessionStart", "UserPromptSubmit", "PreToolUse", "Stop", "SessionEnd"] {
            #expect(hooks[name] != nil)
        }
    }
}
