import Foundation
import Darwin

private struct MonitoringFailure: Error { let message: String }

private func monitorRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw MonitoringFailure(message: message) }
}

private func monitorWait(_ seconds: TimeInterval, until predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if predicate() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    } while Date() < deadline
    return predicate()
}

private func fixturePIDs(_ executable: URL) -> [Int32] {
    let text = (try? String(contentsOf: executable.appendingPathExtension("pids"))) ?? ""
    return text.split(separator: "\n").compactMap { Int32($0) }
}

/// Child modes use only isolated fixture data and never invoke the real monitor.
func runMonitoringFixtureIfRequested() -> Bool {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let name = executable.lastPathComponent
    guard ["nettop-fixture", "nettop-eof-fixture", "lsof-hanging-fixture"].contains(name) else { return false }
    let path = executable.appendingPathExtension("pids")
    if !FileManager.default.fileExists(atPath: path.path) {
        FileManager.default.createFile(atPath: path.path, contents: nil)
    }
    let file = try! FileHandle(forWritingTo: path)
    try! file.seekToEnd()
    try! file.write(contentsOf: Data("\(getpid())\n".utf8))
    try! file.close()
    if name == "lsof-hanging-fixture" {
        signal(SIGTERM, SIG_IGN) // exercises bounded forced termination
    } else {
        FileHandle.standardOutput.write(Data(",bytes_in,bytes_out,\nfixture.1,100,200,\n".utf8))
        if name == "nettop-eof-fixture" { try! FileHandle.standardOutput.close() }
    }
    Thread.sleep(forTimeInterval: 60)
    return true
}

func testMonitorProcessLifecycle() throws {
    let files = FileManager.default
    let temp = files.temporaryDirectory.appendingPathComponent("puresnitch-monitor-\(UUID().uuidString)")
    try files.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: temp) }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let nettop = temp.appendingPathComponent("nettop-fixture")
    let lsof = temp.appendingPathComponent("lsof-hanging-fixture")
    let eof = temp.appendingPathComponent("nettop-eof-fixture")
    for target in [nettop, lsof, eof] { try files.copyItem(at: executable, to: target) }
    let monitor = NetMonitor(lsofExecutable: lsof, nettopExecutable: nettop, pollingInterval: 0.2)
    defer { monitor.stop() }
    monitor.start()
    monitor.start()
    try monitorRequire(monitorWait(3) { fixturePIDs(nettop).count == 1 && fixturePIDs(lsof).count == 1 },
                       "monitor did not start one nettop and one lsof")
    let firstPIDs = fixturePIDs(nettop) + fixturePIDs(lsof)
    monitor.stop()
    try monitorRequire(!monitor.isRunning, "stop did not immediately change monitoring state")
    try monitorRequire(monitorWait(3) { firstPIDs.allSatisfy { kill($0, 0) != 0 } },
                       "stop left a monitoring child running, including a hung lsof")
    monitor.start()
    try monitorRequire(monitorWait(3) { fixturePIDs(nettop).count == 2 && fixturePIDs(lsof).count == 2 },
                       "monitor did not restart after cancellation")
    monitor.stop()
    try monitorRequire(monitorWait(3) { (fixturePIDs(nettop) + fixturePIDs(lsof)).allSatisfy { kill($0, 0) != 0 } },
                       "restart left an old or new subprocess alive")

    let eofMonitor = NetMonitor(lsofExecutable: URL(fileURLWithPath: "/usr/bin/true"), nettopExecutable: eof)
    defer { eofMonitor.stop() }
    eofMonitor.start()
    try monitorRequire(monitorWait(3) {
        let pids = fixturePIDs(eof)
        return pids.count == 1 && pids.allSatisfy { kill($0, 0) != 0 }
    }, "EOF did not detach the pipe and retire its child")
}
