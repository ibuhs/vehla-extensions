import AppKit
import Testing
import UniformTypeIdentifiers
@testable import WallhavenNotch

private func encoded(_ w: Int, _ h: Int, _ type: UTType = .jpeg) -> Data {
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

@Suite struct ImageMemoryTests {
    @Test func largeImagesAreDecodedAtDisplaySize() throws {
        for type in [UTType.jpeg, .png] {
            let image = try #require(ImageDecoder.downsample(encoded(4000, 2000, type), maxPixel: 1000))
            #expect(image.width == 1000 && image.height == 500)
        }
    }

    @Test func smallImagesAreNotEnlarged() throws {
        let image = try #require(ImageDecoder.downsample(encoded(300, 200), maxPixel: 1000))
        #expect(image.width == 300 && image.height == 200)
    }

    @Test func readsFromAFileAndRejectsThingsThatAreNotImages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wallhaven-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("a"), bad = dir.appendingPathComponent("b")
        try encoded(2000, 1000, .png).write(to: good)
        try Data("<html>".utf8).write(to: bad)
        #expect(ImageDecoder.isImage(good) && !ImageDecoder.isImage(bad))
        #expect(!ImageDecoder.isImage(dir.appendingPathComponent("missing")))
        #expect(ImageDecoder.downsample(contentsOf: good, maxPixel: 500)?.width == 500)
        #expect(ImageDecoder.downsample(contentsOf: bad, maxPixel: 500) == nil)
        #expect(ImageDecoder.downsample(Data("<html>".utf8), maxPixel: 100) == nil)
    }

    @Test func theCacheNeverGoesPastItsLimitAndKeepsTheMostRecent() {
        var cache = RecentImages<Int>(limit: 3)
        for i in 0..<10 { cache.store(NSImage(), for: i) }
        #expect(cache.count == 3 && cache.image(for: 6) == nil && cache.image(for: 9) != nil)
        _ = cache.image(for: 7)             // used again, so 8 is now the oldest
        cache.store(NSImage(), for: 10)
        #expect(cache.image(for: 7) != nil && cache.image(for: 8) == nil)
        cache.removeAll()
        #expect(cache.count == 0 && cache.image(for: 9) == nil)
    }
}
