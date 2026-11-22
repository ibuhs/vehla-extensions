import Foundation
import Testing
@testable import ActionsHubCore

@Suite struct ConfigTests {
    @Test func defaultRoundTrips() throws {
        let data = try JSONEncoder().encode(ActionsConfig.default)
        #expect(try JSONDecoder().decode(ActionsConfig.self, from: data) == .default)
    }

    @Test func decodesHandWrittenScene() throws {
        let json = #"""
        {"scenes":[{"id":"x","name":"X","icon":"star","steps":[
          {"type":"shortcut","name":"Hi"},{"type":"app","name":"Notes"},
          {"type":"toggle","id":"mute","on":true},{"type":"url","url":"https://a.b"},{"type":"wait","seconds":2}]}],
         "apps":[{"name":"Safari"}],"toggles":["darkMode"]}
        """#
        let c = try JSONDecoder().decode(ActionsConfig.self, from: Data(json.utf8))
        #expect(c.scenes[0].steps == [.shortcut("Hi"), .app("Notes"), .toggle(.mute, on: true), .url("https://a.b"), .wait(2)])
    }

    @Test func unknownStepIsRejected() {
        let json = #"{"scenes":[{"id":"x","name":"X","icon":"s","steps":[{"type":"nope"}]}],"apps":[],"toggles":[]}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ActionsConfig.self, from: Data(json.utf8)) }
    }
}

@Suite struct ParserTests {
    @Test func shortcutsSortedAndTrimmed() {
        #expect(Parsers.shortcuts("zeta\n  Alpha \n\nbeta\n") == ["Alpha", "beta", "zeta"])
    }

    @Test func systemStateParsing() {
        #expect(Parsers.isDarkMode(ShellResult(status: 0, output: "Dark")))
        #expect(!Parsers.isDarkMode(ShellResult(status: 1, output: "does not exist")))
        #expect(Parsers.desktopIconsShown(ShellResult(status: 1, output: "")))
        #expect(!Parsers.desktopIconsShown(ShellResult(status: 0, output: "0")))
        #expect(Parsers.isTrue(" true\n"))
    }

    @Test func appleScriptEscaping() {
        #expect(Parsers.appleScriptString(#"a"b\c"#) == #"a\"b\\c"#)
    }
}

private actor Recorder: ActionExecutor {
    var ran: [Step] = []
    let failing: Set<Step>
    init(failing: Set<Step> = []) { self.failing = failing }
    func run(_ step: Step) async throws {
        ran.append(step)
        if failing.contains(step) { throw ShellError.failed("x", 1) }
    }
}

extension Step: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(summary) }
}

@Suite struct SceneTests {
    private let scene = ActionScene(id: "s", name: "S", icon: "star",
                                    steps: [.app("A"), .shortcut("Missing"), .toggle(.mute, on: true)])

    @Test func runsInOrderAndContinuesPastFailures() async {
        let recorder = Recorder(failing: [.shortcut("Missing")])
        let seen = Box()
        let failures = await SceneRunner.run(scene, executor: recorder) { done, total in seen.add((done, total)) }
        #expect(await recorder.ran == scene.steps)
        #expect(failures.map(\.step) == [.shortcut("Missing")])
        #expect(seen.values.map(\.0) == [0, 1, 2, 3])
        #expect(seen.values.allSatisfy { $0.1 == 3 })
    }

    @Test func cancellationStopsBetweenSteps() async {
        let recorder = Recorder()
        let task = Task { await SceneRunner.run(scene, executor: recorder) }
        task.cancel()
        _ = await task.value
        #expect(await recorder.ran.count < scene.steps.count)
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Int, Int)] = []
    func add(_ v: (Int, Int)) { lock.lock(); items.append(v); lock.unlock() }
    var values: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct SystemTests {
    @Test func shellRunsAndCapturesOutput() async {
        let r = await Shell.run("/bin/echo", ["hello"])
        #expect(r.ok)
        #expect(r.output == "hello")
        #expect(await Shell.run("/bin/sh", ["-c", "exit 3"]).status == 3)
        #expect(await Shell.run("/nonexistent", []).status == 127)
    }

    @Test func openRefusesOptionLookalikesAndBareStrings() async {
        let controls = SystemControls()
        for bad in ["-a Calculator", "not a url", "", "--help"] {
            await #expect(throws: ShellError.self) { try await controls.open(url: bad) }
        }
        await #expect(throws: ShellError.self) { try await controls.open(app: "-n") }
        await #expect(throws: ShellError.self) { try await controls.open(app: "") }
    }

    @Test func realBatteryAndShortcutsCallsDoNotCrash() async {
        let controls = SystemControls()
        _ = await controls.listShortcuts()
        _ = await controls.isOn(.darkMode)
    }
}
