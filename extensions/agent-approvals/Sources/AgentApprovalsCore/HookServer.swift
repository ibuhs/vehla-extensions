import Darwin
import Foundation

/// A Unix-domain-socket server. A client connects, sends one JSON document, half-closes its
/// write side, and reads one reply. The handler may take a while to answer; the connection
/// waits (up to `replyTimeout`) and then closes with no reply.
public final class HookServer: @unchecked Sendable {
    public typealias Reply = @Sendable (Data?) -> Void
    public typealias Handler = @Sendable (Data, @escaping Reply) -> Void

    public enum ServerError: Error { case pathTooLong, socket(Int32), bind(Int32), listen(Int32) }

    public let path: String
    private let handler: Handler
    private let replyTimeout: TimeInterval
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private let acceptQueue = DispatchQueue(label: "agent-approvals.accept")
    private let workQueue = DispatchQueue(label: "agent-approvals.work", attributes: .concurrent)
    private static let maxRequest = 1 << 20

    public init(path: String, replyTimeout: TimeInterval = 100, handler: @escaping Handler) {
        self.path = path
        self.replyTimeout = replyTimeout
        self.handler = handler
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socket(errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { close(fd); throw ServerError.pathTooLong }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else { let e = errno; close(fd); throw ServerError.bind(e) }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { let e = errno; close(fd); throw ServerError.listen(e) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: fd) }
        source.setCancelHandler { close(fd) }
        lock.lock(); listener = fd; self.source = source; lock.unlock()
        source.resume()
    }

    public func stop() {
        lock.lock(); let source = self.source; self.source = nil; listener = -1; lock.unlock()
        source?.cancel()
        unlink(path)
    }

    private func acceptPending(on fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            workQueue.async { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        // Blocking reads: the accepted socket may inherit O_NONBLOCK on some systems.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)

        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            request.append(buffer, count: n)
            if request.count > Self.maxRequest { return }
        }
        guard !request.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        let once = Once()
        handler(request) { data in
            guard once.claim() else { return }
            box.data = data
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + replyTimeout) == .success, let data = box.data else { return }
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(client, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}

private final class ReplyBox: @unchecked Sendable { var data: Data? }

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
