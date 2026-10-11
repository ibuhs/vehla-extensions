import XCTest
@testable import CompressorWorkspace

/// Runs the real engine on a large file. Runs only when LARGE_FILE and LARGE_OUT are set.
final class LargeFileTests: XCTestCase {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var last = -1.0
        let start = Date()
        func record(_ value: Double) {
            lock.lock(); defer { lock.unlock() }
            let step = (value * 20).rounded(.down) / 20 // every 5%
            guard step > last else { return }
            last = step
            let elapsed = Int(Date().timeIntervalSince(start))
            FileHandle.standardError.write(Data("PROGRESS \(Int(step * 100))% after \(elapsed)s\n".utf8))
        }
    }

    func testLargeFile() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["LARGE_FILE"], let output = env["LARGE_OUT"] else { throw XCTSkip("LARGE_FILE not set") }
        let source = URL(fileURLWithPath: input)
        let destination = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let log = Log()
        let result = await CompressionEngine(destination: destination)
            .compress(source, isDirectory: false) { log.record($0) }
        let elapsed = Int(Date().timeIntervalSince(log.start))

        FileHandle.standardError.write(Data("""
        RESULT status=\(result.status) before=\(Format.bytes(result.before)) after=\(Format.bytes(result.after)) \
        saved=\(Int(result.savedFraction * 100))% elapsed=\(elapsed)s output=\(result.outputName ?? "-") note=\(result.message ?? "-")

        """.utf8))
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
    }
}
