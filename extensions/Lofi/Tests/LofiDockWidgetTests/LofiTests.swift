import AppKit
import XCTest
@testable import LofiDockWidget

final class LofiTests: XCTestCase {
    func testShuffleDoesNotRepeatAcrossSmallRoundBoundaries() {
        for count in 2...5 {
            var bag = LofiShuffleBag(count: count)
            var current = 0
            for _ in 0..<100 { let next = bag.next(after: current); XCTAssertNotEqual(next, current); current = next }
        }
    }
    func testShuffleEachRoundContainsEachSongExactlyOnce() {
        var bag = LofiShuffleBag(count: 8); bag.refill(excluding: 0)
        var current = 0, round = [0]
        for _ in 0..<7 { current = bag.next(after: current); round.append(current) }
        XCTAssertEqual(Set(round), Set(0..<8))
        var next: [Int] = []
        for _ in 0..<8 { current = bag.next(after: current); next.append(current) }
        XCTAssertEqual(Set(next), Set(0..<8)); XCTAssertNotEqual(round.last, next.first)
    }
    @MainActor func testFirstUseSkipAndEmptyPlaybackRemainSafe() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let player = LofiPlayer(directory: directory)
        XCTAssertTrue(player.shouldPromptSource); XCTAssertTrue(player.tracks.isEmpty)
        player.next(); player.previous(); player.play(); XCTAssertFalse(player.isPlaying)
        player.skipSourcePrompt(); player.shutdown()
        let next = LofiPlayer(directory: directory)
        XCTAssertFalse(next.shouldPromptSource); XCTAssertTrue(next.tracks.isEmpty); next.shutdown()
    }
    func testLegacyPreferencesStillDecodeWithoutSelectingCacheAsSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"index":2,"shuffle":false,"volume":0.4,"remaining":[3]}"#.utf8).write(to: directory.appendingPathComponent("preferences.json"))
        let preferences = LofiPreferences.load(from: directory)
        XCTAssertEqual(preferences.volume, 0.4); XCTAssertNil(preferences.sourceBookmark); XCTAssertNil(preferences.sourcePromptShown)
    }
    @MainActor func testLocalFolderScanningBookmarkPlaybackAndPause() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = directory.appendingPathComponent("My Music")
        let nested = folder.appendingPathComponent("Album")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "silent", withExtension: "mp3", subdirectory: "Fixtures")))
        let song = nested.appendingPathComponent("My Song.mp3")
        try original.write(to: song)
        try Data("ignore".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.mp3"), withDestinationURL: song)
        let outside = directory.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try original.write(to: outside.appendingPathComponent("Outside.mp3"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Linked Album"), withDestinationURL: outside)
        let scanned = try await LofiLibrary.scan(folder)
        XCTAssertEqual(scanned.count, 1)
        let player = LofiPlayer(directory: directory)
        player.volume = 0; player.selectSourceFolder(folder)
        await player.waitForSourceScan()
        XCTAssertEqual(player.tracks.count, 1, player.message ?? "Still loading: \(player.isLoading)"); XCTAssertEqual(player.current.url.resolvingSymlinksInPath().path, song.resolvingSymlinksInPath().path)
        XCTAssertFalse(player.shouldPromptSource); XCTAssertNotNil(LofiPreferences.load(from: directory).sourceBookmark)
        player.play(); player.pause()
        try await Task.sleep(for: .milliseconds(20)); XCTAssertFalse(player.isPlaying)
        player.play()
        for _ in 0..<100 where !player.isPlaying { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(player.isPlaying, player.message ?? "Playback failed")
        player.shutdown()
        let restored = LofiPlayer(directory: directory)
        await restored.waitForSourceScan()
        XCTAssertEqual(restored.tracks.count, 1); XCTAssertEqual(restored.sourceFolder?.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
        restored.shutdown()
        XCTAssertEqual(try Data(contentsOf: song), original, "Playback must never modify or copy the source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("tracks").path))
    }
}
