import Foundation
import Testing
@testable import NotchKit

@Suite struct PersistenceTests {
    struct Sample: Codable, Equatable, Sendable { var count: Int; var when: Date }

    @Test func roundTrips() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NKJSONStore<Sample>(directory: dir, name: "s.json")
        #expect(store.load() == nil)
        let value = Sample(count: 3, when: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(store.save(value))
        #expect(store.load() == value)
    }

    @Test func hexFormatting() {
        #expect(NK.hex(255, 0, 128) == "#FF0080")
    }
}
