import Foundation
import AVFoundation

struct LofiTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let url: URL
    let seconds: Int
    static let empty = LofiTrack(id: "", title: "Choose your music folder", artist: "Your music, your space", url: URL(fileURLWithPath: "/"), seconds: 0)
}

enum LofiLibrary {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]
    static func scan(_ folder: URL) async throws -> [LofiTrack] {
        let listing = Task.detached(priority: .utility) { try Self.audioURLs(folder) }
        let urls = try await withTaskCancellationHandler(operation: { try await listing.value }, onCancel: { listing.cancel() })
        var tracks: [LofiTrack] = []
        for url in urls {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            let duration = try? await asset.load(.duration)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            var title = url.deletingPathExtension().lastPathComponent
            var artist = ""
            for item in metadata {
                if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue), !value.isEmpty { title = value }
                if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue) { artist = value }
            }
            let seconds = duration?.seconds ?? 0
            tracks.append(.init(id: url.path, title: title, artist: artist, url: url,
                seconds: seconds.isFinite ? Int(max(0, min(seconds, Double(Int.max / 2)))) : 0))
        }
        return tracks
    }
    private static func audioURLs(_ folder: URL) throws -> [URL] {
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            var enumerationError: (any Error)?
            guard let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) else {
                throw CocoaError(.fileReadNoPermission)
            }
            var urls: [URL] = []
            for case let url as URL in entries {
                try Task.checkCancellation()
                let info = try url.resourceValues(forKeys: Set(keys))
                if info.isSymbolicLink == true { continue }
                guard info.isRegularFile == true, Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
                urls.append(url)
            }
            if let enumerationError { throw enumerationError }
            return urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

}
