import Foundation

struct LofiPreferences: Codable {
    var index = 0
    var shuffle = true
    var volume = 0.7
    var remaining: [Int] = []
    var sourceBookmark: Data? = nil
    var sourcePromptShown: Bool? = nil
    static func load(from directory: URL) -> Self {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("preferences.json")),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("preferences.json"), options: .atomic)
        } catch { /* Playback does not depend on saving preferences. */ }
    }
}
