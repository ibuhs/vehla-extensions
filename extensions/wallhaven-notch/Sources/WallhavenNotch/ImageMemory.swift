import AppKit
import ImageIO

/// Decodes images no larger than they will be shown. A wallpaper decoded at its own size costs 20-50 MB each,
/// and AppKit keeps both the decoded pixels and the downloaded file for as long as the image is alive.
enum ImageDecoder {
    /// A decoded copy whose longest side is at most `maxPixel`. It doesn't hold on to `data`.
    static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        autoreleasepool { downsample(CGImageSourceCreateWithData(data as CFData, uncached), maxPixel: maxPixel) }
    }

    /// The same from a file, which is read as needed and never held in memory whole.
    static func downsample(contentsOf file: URL, maxPixel: Int) -> CGImage? {
        autoreleasepool { downsample(CGImageSourceCreateWithURL(file as CFURL, uncached), maxPixel: maxPixel) }
    }

    private static var uncached: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    private static func downsample(_ source: CGImageSource?, maxPixel: Int) -> CGImage? {
        guard let source else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).flatMap(ownCopy)
    }

    /// Plain pixels that go away with the image. ImageIO's own decoded copy stays in a cache shared by the process.
    private static func ownCopy(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Whether the file is a readable image, checked without decoding its pixels.
    static func isImage(_ file: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, uncached),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return properties[kCGImagePropertyPixelWidth] != nil
    }
}

enum MemoryRelief {
    /// After images have been let go, hands the freed pages back to macOS. Without it the allocator keeps them
    /// mapped and Vehla goes on looking larger than what it holds.
    static func schedule(after delay: TimeInterval = 1.5) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
}

/// A small most-recently-used cache with a hard limit. (`NSCache` limits are only hints, and with none set it
/// keeps everything until the whole system is short of memory.)
struct RecentImages<Key: Hashable> {
    private var images: [Key: NSImage] = [:]
    private var order: [Key] = []
    let limit: Int

    init(limit: Int) { self.limit = max(1, limit) }

    var count: Int { images.count }

    mutating func image(for key: Key) -> NSImage? {
        guard let image = images[key] else { return nil }
        touch(key)
        return image
    }

    mutating func store(_ image: NSImage, for key: Key) {
        images[key] = image
        touch(key)
        while order.count > limit { images[order.removeFirst()] = nil }
    }

    mutating func removeAll() { images = [:]; order = [] }

    private mutating func touch(_ key: Key) {
        if order.last == key { return }
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}
