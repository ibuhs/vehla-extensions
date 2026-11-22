import CPty
import Darwin
import Foundation

public enum PTYError: Error, LocalizedError {
    case openFailed(String)
    case spawnFailed(Int32)
    public var errorDescription: String? {
        switch self {
        case .openFailed(let what): return "Couldn't open a pseudo-terminal (\(what))."
        case .spawnFailed(let code): return "Couldn't start the shell (error \(code))."
        }
    }
}

/// A program running on a pseudo-terminal: the shell sees a real terminal, so job control, line editing and
/// full-screen programs all work.
public final class PTYSession: @unchecked Sendable {
    public let pid: pid_t
    private let master: Int32
    /// Our own handle on the slave side. macOS discards unread output when the last slave handle closes, so
    /// this stays open until the child has exited and everything has been read.
    private var slave: Int32
    private var pollTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "mini-terminal.pty")
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private let lock = NSLock()
    private var finished = false
    /// Guarded by `lock`. While paused nothing is read, so the kernel's buffer fills and the program waits.
    private var pauseRequested = false, paused = false
    private var onData: (@Sendable (Data) -> Void)?
    private var onExit: (@Sendable (Int32) -> Void)?

    public init(executable: String, arguments: [String], environment: [String: String], directory: String?,
                cols: Int, rows: Int) throws {
        // forkpty reports a bad path only in the child, so check here and fail with a clear error.
        guard access(executable, X_OK) == 0 else { throw PTYError.spawnFailed(errno == 0 ? ENOENT : errno) }
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }

        var masterFD: Int32 = -1, slaveFD: Int32 = -1
        let child = vn_spawn_pty(executable, argv, envp, directory,
                                 UInt16(clamping: rows), UInt16(clamping: cols), &masterFD, &slaveFD)
        guard child > 0, masterFD >= 0 else { throw PTYError.spawnFailed(errno) }
        master = masterFD
        slave = slaveFD
        pid = child
    }

    deinit { terminate() }

    /// Begins delivering output and the exit status. Both callbacks arrive on a background queue.
    public func start(onData: @escaping @Sendable (Data) -> Void, onExit: @escaping @Sendable (Int32) -> Void) {
        self.onData = onData
        self.onExit = onExit
        let reader = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        reader.setEventHandler { [weak self] in self?.drain() }
        readSource = reader
        reader.resume()

        let watcher = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [weak self] in self?.childExited() }
        processSource = watcher
        watcher.resume()

        // A child that exited before the watcher was attached, or a missed notification, is caught here.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 10, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            if waitpid(self.pid, &status, WNOHANG) == self.pid { self.finish(status: status) }
        }
        pollTimer = timer
        timer.resume()
    }

    /// Stops reading until `resumeReading`. Call it from `onData` when output arrives faster than it can be
    /// shown: the program is held back instead of its output piling up in memory.
    public func pauseReading() { lock.lock(); pauseRequested = true; lock.unlock() }

    public func resumeReading() {
        lock.lock(); defer { lock.unlock() }
        pauseRequested = false
        if paused { paused = false; readSource?.resume() }
    }

    /// Suspends the reader if a pause was asked for. Returns true while reading is on hold.
    private func holdIfPaused() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard pauseRequested, let readSource else { return false }
        if !paused { paused = true; readSource.suspend() }
        return true
    }

    /// Cancels the sources exactly once. A suspended source must be resumed or releasing it crashes.
    private func cancelSources() {
        lock.lock()
        let reader = readSource, watcher = processSource, timer = pollTimer, wasPaused = paused
        readSource = nil; processSource = nil; pollTimer = nil; paused = false; pauseRequested = false
        lock.unlock()
        timer?.cancel(); watcher?.cancel(); reader?.cancel()
        if wasPaused { reader?.resume() }
    }

    private func drain(upTo limit: Int = .max) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total = 0
        while total < limit {
            let n = read(master, &buffer, buffer.count)
            if n > 0 {
                total += n
                onData?(Data(buffer[0..<n]))
                if limit == .max, holdIfPaused() { return }
                continue
            }
            if n < 0 && errno == EAGAIN { return }
            return   // EOF / EIO: the child closed its end; the process source reports the exit
        }
    }

    private func childExited() {
        var status: Int32 = 0
        guard waitpid(pid, &status, 0) == pid else { return }   // already reaped by the poller
        finish(status: status)
    }

    private func finish(status: Int32) {
        drain(upTo: 1 << 20)   // a background job may still be printing; don't follow it forever
        let code: Int32 = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        cancelSources()
        if slave >= 0 { close(slave); slave = -1 }
        if !already { onExit?(code) }
    }

    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        queue.async { [master] in
            var sent = 0
            while sent < bytes.count {
                let n = bytes[sent...].withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
                if n > 0 { sent += n; continue }
                if n < 0 && errno == EAGAIN { usleep(1000); continue }
                return
            }
        }
    }

    public func write(_ string: String) { write(Array(string.utf8)) }

    public func resize(cols: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &size)
    }

    /// The foreground process group: the shell's own when idle, the running command's otherwise.
    public var foregroundProcessGroup: pid_t? {
        let pgid = tcgetpgrp(master)
        return pgid > 0 ? pgid : nil
    }

    public var isBusy: Bool {
        guard let fg = foregroundProcessGroup else { return false }
        return fg != pid
    }

    /// The name of whatever is in the foreground (e.g. "npm"), if it is not the shell itself.
    public var foregroundName: String? {
        guard let fg = foregroundProcessGroup, fg != pid else { return nil }
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(fg, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Ctrl-C: interrupts whatever is running.
    public func interrupt() { write([0x03]) }

    public func terminate() {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        guard !already else { return }
        if let fg = foregroundProcessGroup, fg != pid { killpg(fg, SIGHUP) }
        kill(pid, SIGHUP)
        cancelSources()
        if slave >= 0 { close(slave); slave = -1 }
        close(master)
        // Reap the child so it doesn't linger as a zombie, and escalate if it ignores the hang-up.
        let child = pid
        DispatchQueue.global().async {
            var status: Int32 = 0
            for _ in 0..<40 {
                if waitpid(child, &status, WNOHANG) != 0 { return }
                usleep(50_000)
            }
            kill(child, SIGKILL)
            waitpid(child, &status, 0)
        }
    }
}
