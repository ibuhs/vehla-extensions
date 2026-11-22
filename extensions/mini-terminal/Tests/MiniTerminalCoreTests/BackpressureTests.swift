import Foundation
import Testing
@testable import MiniTerminalCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    func add(_ n: Int) -> Int { lock.lock(); defer { lock.unlock() }; total += n; return total }
    var value: Int { lock.lock(); defer { lock.unlock() }; return total }
}

@Suite struct BackpressureTests {
    @Test func queueReportsFullAndRoom() {
        let q = OutputQueue()
        #expect(q.push(Data(count: 10)) == (true, false))
        #expect(q.push(Data(count: OutputQueue.highWater)) == (false, true))
        #expect(!q.hasRoom)
        var seen = 0
        while true {
            let slice = q.take(16 * 1024)
            seen += slice.data.count
            if !slice.more { #expect(slice.room); break }
        }
        #expect(seen == OutputQueue.highWater + 10 && q.hasRoom && q.count == 0)
        #expect(q.push(Data([1])).schedule)
    }

    @Test func queueKeepsTheBytesInOrder() {
        let q = OutputQueue()
        let sent = Data((0..<50_000).map { UInt8($0 % 251) })
        _ = q.push(sent.prefix(20_000)); _ = q.push(Data(sent.dropFirst(20_000)))
        var got = Data()
        while q.count > 0 { got += q.take(777).data }
        #expect(got == sent)
    }

    @Test func aFloodStopsWhilePausedAndContinuesAfterwards() async throws {
        let pty = try PTYSession(executable: "/usr/bin/yes", arguments: [], environment: ["TERM": "xterm"],
                                 directory: "/", cols: 80, rows: 24)
        defer { pty.terminate() }
        let counter = Counter()
        pty.start(onData: { [weak pty] d in if counter.add(d.count) > 100_000 { pty?.pauseReading() } }, onExit: { _ in })
        try await Task.sleep(for: .milliseconds(600))
        let held = counter.value
        #expect(held > 100_000 && held < 400_000)
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == held)
        pty.resumeReading()
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value > held)
    }

    @Test func endingAPausedSessionIsSafe() async throws {
        for _ in 0..<5 {
            let pty = try PTYSession(executable: "/usr/bin/yes", arguments: [], environment: ["TERM": "xterm"],
                                     directory: "/", cols: 80, rows: 24)
            pty.start(onData: { [weak pty] _ in pty?.pauseReading() }, onExit: { _ in })
            try await Task.sleep(for: .milliseconds(60))
            pty.terminate()
        }
    }

    @Test func historyKeepsOnlyWhatWasWrittenAndStaysNearItsLimit() {
        let t = TerminalEmulator(cols: 100, rows: 4)
        t.scrollbackLimit = 800
        for i in 0..<5000 { t.feed("line \(i)\r\n") }
        #expect(t.scrollback.count >= 800 && t.scrollback.count <= 900)
        #expect(t.scrollback.allSatisfy { $0.count <= 9 })
        #expect(t.text(from: (0, 0), to: (0, 99)).hasPrefix("line "))
    }
}
