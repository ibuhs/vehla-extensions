import Foundation
import Darwin

struct SocketIdentity: Hashable, Sendable {
    let pid: Int32
    let processPath: String
    let localAddress: String
    let localPort: Int
    let remoteAddress: String
    let remotePort: Int
    let direction: RuleDirection
    let protocolName: String
}

struct SocketObservation: Sendable {
    var connection: Connection
    let identity: SocketIdentity
}

struct ActiveConnectionTracker: Sendable {
    private struct Session: Sendable {
        let id: UUID
        let firstSeen: Date
    }

    private var active: [SocketIdentity: Session] = [:]

    /// Carry identity only while a socket is present in consecutive snapshots.
    /// Once it disappears, a later reuse of the same 5-tuple is a new session.
    mutating func reconcile(_ observations: [SocketObservation], seenAt: Date) -> [Connection] {
        var next: [SocketIdentity: Session] = [:]
        var seen: Set<SocketIdentity> = []
        var connections: [Connection] = []
        connections.reserveCapacity(observations.count)

        for observation in observations where seen.insert(observation.identity).inserted {
            var connection = observation.connection
            if let session = active[observation.identity] {
                connection.id = session.id
                connection.firstSeen = session.firstSeen
            } else {
                connection.id = UUID()
                connection.firstSeen = seenAt
            }
            connection.lastSeen = seenAt
            next[observation.identity] = Session(id: connection.id, firstSeen: connection.firstSeen)
            connections.append(connection)
        }
        active = next
        return connections
    }

    mutating func reset() {
        active.removeAll(keepingCapacity: true)
    }
}

final class NetMonitor: @unchecked Sendable {
    private var lsofTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.kailalabs.vehla.puresnitch.netmon", qos: .utility)
    private let lifecycleLock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var nettopOutput: FileHandle?
    private var generation = 0
    private var running = false
    private let lsofExecutable: URL
    private let nettopExecutable: URL
    private let pollingInterval: TimeInterval
    private var connectionTracker = ActiveConnectionTracker()

    var onConnections: (([Connection]) -> Void)?
    var onSample: ((TrafficSample) -> Void)?

    private var lastIn: Int64 = 0
    private var lastOut: Int64 = 0
    private var lastSampleTime = Date()
    private var hasBaseline = false
    private var pending = ""
    private var frame: [String] = []
    var isRunning: Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return running
    }

    init(lsofExecutable: URL = URL(fileURLWithPath: "/usr/sbin/lsof"),
         nettopExecutable: URL = URL(fileURLWithPath: "/usr/bin/nettop"),
         pollingInterval: TimeInterval = 2) {
        self.lsofExecutable = lsofExecutable
        self.nettopExecutable = nettopExecutable
        self.pollingInterval = pollingInterval
    }

    func start() {
        lifecycleLock.lock()
        guard !running else { lifecycleLock.unlock(); return }
        running = true
        generation &+= 1
        let epoch = generation
        lifecycleLock.unlock()
        queue.async { [weak self] in
            guard let self, self.isCurrent(epoch) else { return }
            self.pending = ""; self.frame = []; self.hasBaseline = false
            self.lastIn = 0; self.lastOut = 0
            self.connectionTracker.reset()
            self.startLsofPolling(epoch: epoch)
            self.startNettop(epoch: epoch)
        }
    }

    func stop() {
        lifecycleLock.lock()
        running = false
        generation &+= 1
        let timer = lsofTimer
        lsofTimer = nil
        let output = nettopOutput
        nettopOutput = nil
        let children = Array(processes.values)
        processes.removeAll()
        lifecycleLock.unlock()
        timer?.cancel()
        // EOF leaves a pipe readable forever. Detach its handler on both EOF
        // and explicit stop, otherwise an old nettop spins the helper at 100%.
        output?.readabilityHandler = nil
        children.forEach(Self.terminate)
    }

    private func isCurrent(_ epoch: Int) -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        return running && generation == epoch
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func launch(_ process: Process, epoch: Int) -> Bool {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        guard running, generation == epoch else { return false }
        do {
            try process.run()
            processes[ObjectIdentifier(process)] = process
            return true
        } catch {
            PSLog.error(PSLog.netmon, "monitor subprocess failed: \(error)")
            return false
        }
    }

    private func forget(_ process: Process) {
        lifecycleLock.lock(); defer { lifecycleLock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    private func startLsofPolling(epoch: Int) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: pollingInterval)
        t.setEventHandler { [weak self] in self?.pollLsof(epoch: epoch) }
        lifecycleLock.lock()
        let current = running && generation == epoch
        if current { lsofTimer = t }
        lifecycleLock.unlock()
        if !current { t.cancel() }
        t.resume()
    }

    private func pollLsof(epoch: Int) {
        guard isCurrent(epoch) else { return }
        let p = Process()
        p.executableURL = lsofExecutable
        p.arguments = ["-i", "-n", "-P", "-F", "pcnPT"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard launch(p, epoch: epoch) else { return }
        defer { forget(p) }
        let timeout = DispatchWorkItem { Self.terminate(p) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6, execute: timeout)
        defer { timeout.cancel() }
        // Drain the pipe BEFORE waiting. `lsof -i` on a busy Mac easily exceeds
        // the 64 KB pipe buffer, and waiting first deadlocks the monitor queue
        // permanently: lsof blocks writing, we block waiting, and the
        // connection list never updates again.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard isCurrent(epoch), let txt = String(data: data, encoding: .utf8) else { return }

        var observations: [SocketObservation] = []
        var pid: Int32 = 0
        var pname = ""
        var protocolName = "tcp"
        var processInfo: [Int32: (String, String?)] = [:]
        for line in txt.split(separator: "\n") {
            guard let first = line.first else { continue }
            let rest = String(line.dropFirst())
            switch first {
            case "p":
                pid = Int32(rest) ?? 0
                protocolName = "tcp"
            case "c":
                pname = rest
            case "P":
                protocolName = rest.lowercased()
            case "n":
                guard isCurrent(epoch) else { return }
                if processInfo[pid] == nil {
                    let path = pidPath(pid)
                    processInfo[pid] = (path, bundleID(forPath: path))
                }
                let info = processInfo[pid] ?? ("", nil)
                if let observation = parseN(
                    line: rest,
                    pid: pid,
                    name: pname,
                    protocolName: protocolName,
                    processPath: info.0,
                    bundleID: info.1
                ) {
                    observations.append(observation)
                }
            default: break
            }
        }
        let conns = connectionTracker.reconcile(observations, seenAt: Date())
        guard isCurrent(epoch) else { return }
        onConnections?(conns)
    }

    private func parseN(
        line: String,
        pid: Int32,
        name: String,
        protocolName: String,
        processPath path: String,
        bundleID bundle: String?
    ) -> SocketObservation? {
        guard line.contains("->") else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        let addrPart = parts.first ?? line
        let halves = addrPart.split(separator: "-", maxSplits: 1).map(String.init)
        guard halves.count == 2 else { return nil }
        let local = halves[0]
        let remoteRaw = halves[1].hasPrefix(">") ? String(halves[1].dropFirst()) : halves[1]
        guard let (lip, lport) = splitHostPort(local) else { return nil }
        guard let (rip, rport) = splitHostPort(remoteRaw) else { return nil }
        let normalizedProtocol = protocolName.isEmpty ? "tcp" : protocolName.lowercased()
        let connection = Connection(
            pid: pid,
            processName: name,
            processPath: path,
            processBundleId: bundle,
            localPort: lport,
            remoteHost: rip,
            remoteIP: rip,
            remotePort: rport,
            direction: .outgoing,
            status: .established,
            protocolName: normalizedProtocol
        )
        let identity = SocketIdentity(
            pid: pid,
            processPath: path,
            localAddress: lip,
            localPort: lport,
            remoteAddress: rip,
            remotePort: rport,
            direction: .outgoing,
            protocolName: normalizedProtocol
        )
        return SocketObservation(connection: connection, identity: identity)
    }

    private func splitHostPort(_ s: String) -> (String, Int)? {
        if s.hasPrefix("[") {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let host = String(s[s.index(after: s.startIndex)..<close])
            let after = s.index(after: close)
            guard after < s.endIndex, s[after] == ":" else { return nil }
            let port = Int(s[s.index(after: after)...]) ?? 0
            return (host, port)
        }
        guard let lastColon = s.lastIndex(of: ":") else { return nil }
        let host = String(s[s.startIndex..<lastColon])
        let portStr = s[s.index(after: lastColon)...]
        return (host, Int(portStr) ?? 0)
    }

    private func pidPath(_ pid: Int32) -> String {
        // libproc's PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN (4096).
        // That compound C macro is not imported into Swift.
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    private func bundleID(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var p = path
        if let r = p.range(of: ".app/", options: .backwards) { p = String(p[..<r.upperBound]) }
        let plist = (p as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)) else { return nil }
        guard let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return d["CFBundleIdentifier"] as? String
    }

    private func startNettop(epoch: Int) {
        let p = Process()
        p.executableURL = nettopExecutable
        p.arguments = ["-P", "-x", "-L", "0", "-J", "bytes_in,bytes_out", "-s", "1"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard launch(p, epoch: epoch) else { return }
        lifecycleLock.lock()
        guard running, generation == epoch else { lifecycleLock.unlock(); return }
        nettopOutput = pipe.fileHandleForReading
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Self.terminate(p)
                self.forget(p)
                return
            }
            self.queue.async { [weak self] in
                guard let self, self.isCurrent(epoch), let s = String(data: data, encoding: .utf8) else { return }
                self.ingestNettop(s)
            }
        }
        lifecycleLock.unlock()
    }

    /// nettop writes one *frame* per interval: a `,bytes_in,bytes_out,` header
    /// followed by one cumulative line per process. A pipe read is not a frame -
    /// it can split mid-line or carry half a frame - so summing whatever arrived
    /// and diffing it against the previous sum produced nonsense rates
    /// (multi-GB/s spikes). Buffer, cut on the header, and only diff whole frames.
    private func ingestNettop(_ chunk: String) {
        pending += chunk
        while let nl = pending.firstIndex(of: "\n") {
            let line = String(pending[pending.startIndex..<nl])
            pending = String(pending[pending.index(after: nl)...])
            if line.hasPrefix(",bytes_in") {
                if !frame.isEmpty { completeFrame(frame) }
                frame = []
            } else if !line.isEmpty {
                frame.append(line)
            }
        }
    }

    private func completeFrame(_ lines: [String]) {
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0
        for line in lines {
            let parts = line.split(separator: ",")
            guard parts.count >= 3,
                  let bin = Int64(parts[parts.count - 2]),
                  let bout = Int64(parts[parts.count - 1]) else { continue }
            totalIn += bin
            totalOut += bout
        }
        let now = Date()

        // The first frame is only a baseline: nettop counters are cumulative
        // since it started, so emitting a rate here would report the whole
        // history as if it happened in one second.
        guard hasBaseline else {
            hasBaseline = true
            lastIn = totalIn; lastOut = totalOut; lastSampleTime = now
            return
        }

        let dt = now.timeIntervalSince(lastSampleTime)
        guard dt >= 0.4 else { return }
        // Counters only go up while nettop lives; a drop means processes exited,
        // so treat it as a fresh baseline instead of a negative or huge delta.
        guard totalIn >= lastIn, totalOut >= lastOut else {
            lastIn = totalIn; lastOut = totalOut; lastSampleTime = now
            return
        }
        let deltaIn = totalIn - lastIn
        let deltaOut = totalOut - lastOut
        lastIn = totalIn; lastOut = totalOut; lastSampleTime = now
        let sample = TrafficSample(timestamp: now,
                                   bytesIn: Int64(Double(deltaIn) / dt),
                                   bytesOut: Int64(Double(deltaOut) / dt))
        onSample?(sample)
    }
}
