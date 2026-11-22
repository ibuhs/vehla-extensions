import Foundation

/// Output on its way from the pseudo-terminal's background queue to the main thread, with a limit: past it the
/// reader pauses and the program waits, rather than its output piling up in memory.
public final class OutputQueue: @unchecked Sendable {
    public static let highWater = 256 * 1024
    public static let lowWater = 64 * 1024

    private let lock = NSLock()
    private var data = Data()
    private var scheduled = false

    public init() {}

    public var count: Int { lock.lock(); defer { lock.unlock() }; return data.count }
    public var hasRoom: Bool { count <= Self.lowWater }

    /// `schedule`: nothing is draining yet, so schedule a drain. `full`: stop reading until a `take` reports room.
    public func push(_ d: Data) -> (schedule: Bool, full: Bool) {
        lock.lock(); defer { lock.unlock() }
        data.append(d)
        let first = !scheduled
        scheduled = true
        return (first, data.count >= Self.highWater)
    }

    /// Up to `limit` bytes. `more`: call again. `room`: reading may resume.
    public func take(_ limit: Int) -> (data: Data, more: Bool, room: Bool) {
        lock.lock(); defer { lock.unlock() }
        let head = Data(data.prefix(limit))
        data = head.count == data.count ? Data() : Data(data.dropFirst(head.count))
        scheduled = !data.isEmpty
        return (head, scheduled, data.count <= Self.lowWater)
    }
}
