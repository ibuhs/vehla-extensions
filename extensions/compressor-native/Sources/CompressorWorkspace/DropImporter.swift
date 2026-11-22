import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns whatever was dropped on the window into a file that stays put until
/// it has been compressed.
///
/// Finder hands over a link to a file that lives in the user's folders, so
/// its address can be kept. Apps such as Photos, Mail or a browser hand over
/// content instead: macOS writes it to a temporary receive folder
/// (`…/TemporaryItems/NSIRD_<App>_…`) that is emptied once the drop has been
/// handled. Keeping that address means reading an empty or missing file later,
/// so such items are copied into Compressor's own storage at drop time.
enum DropImporter {
    struct Received: Sendable {
        let url: URL
        /// True when `url` is Compressor's own copy rather than the user's file.
        let imported: Bool
    }

    struct Failure: Error, Sendable {
        let message: String
    }

    /// NSItemProvider's load methods may be called from any thread and call
    /// back on background queues; it just isn't annotated as Sendable.
    private final class ProviderBox: @unchecked Sendable {
        let provider: NSItemProvider
        init(_ provider: NSItemProvider) { self.provider = provider }
    }

    /// Where copies of dropped content wait until they are compressed.
    static func importsDirectory(in dataDirectory: URL) -> URL {
        dataDirectory.appendingPathComponent("Imports", isDirectory: true)
    }

    /// Files in temporary drop locations disappear soon after the drop.
    static func isVolatile(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path
        return path.hasPrefix(temp) || path.contains("/TemporaryItems/") || path.contains("/NSIRD_")
    }

    /// Calls `completion` once, on any thread, with a file that stays valid.
    static func receive(
        _ provider: NSItemProvider,
        into imports: URL,
        completion: @escaping @Sendable (Result<Received, Failure>) -> Void
    ) {
        let suggestedName = provider.suggestedName
        let contentType = bestContentType(of: provider)
        let box = ProviderBox(provider)

        // Fetch the content itself. The completion only runs once the sending
        // app has finished writing it, and the file is only valid inside it.
        @Sendable func loadContent(_ type: UTType, linkedName: String? = nil) {
            box.provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    completion(.failure(Failure(message: "Couldn't read the dropped item: \(error?.localizedDescription ?? "no data")")))
                    return
                }
                completion(copyIntoStorage(url, linkedName: linkedName, suggestedName: suggestedName, type: type, imports: imports))
            }
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            if let contentType { loadContent(contentType) } else {
                completion(.failure(Failure(message: "That item can't be compressed: it isn't a file.")))
            }
            return
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, !isVolatile(url) {
                completion(.success(Received(url: url, imported: false))) // a real file, e.g. from Finder
            } else if let contentType {
                // The loaded copy is renamed by macOS ("JPEG image"), so carry the link's name over.
                loadContent(contentType, linkedName: url?.lastPathComponent)
            } else if let url {
                completion(copyIntoStorage(url, linkedName: nil, suggestedName: suggestedName, type: nil, imports: imports))
            } else {
                completion(.failure(Failure(message: "Couldn't read the dropped item.")))
            }
        }
    }

    /// The most specific file-like content on offer: media first, then any data.
    static func bestContentType(of provider: NSItemProvider) -> UTType? {
        let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
            .filter { !$0.conforms(to: .url) }
        let media: [UTType] = [.image, .movie, .audiovisualContent, .audio, .pdf]
        return types.first { type in media.contains { type.conforms(to: $0) } }
            ?? types.first { $0.conforms(to: .data) || $0.conforms(to: .package) }
    }

    /// Copies a dropped file into its own folder under `imports`.
    static func copyIntoStorage(_ url: URL, linkedName: String?, suggestedName: String?, type: UTType?, imports: URL) -> Result<Received, Failure> {
        let fm = FileManager.default
        guard (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            return .failure(Failure(message: "The dropped file was empty. Try dragging it in again."))
        }
        let folder = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(fileName(for: url, linkedName: linkedName, suggestedName: suggestedName, type: type))
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: target)
            return .success(Received(url: target, imported: true))
        } catch {
            try? fm.removeItem(at: folder)
            return .failure(Failure(message: "Couldn't keep a copy of the dropped file: \(error.localizedDescription)"))
        }
    }

    /// The name a dropped file is shown and saved under.
    ///
    /// Photos names the files it hands out after an internal reference
    /// ("uuid=9C49…&code=001&library=1…"), which then ends up in the list and
    /// in the destination folder. Prefer a human name when one is available.
    static func fileName(for url: URL, linkedName: String? = nil, suggestedName: String?, type: UTType?) -> String {
        let ext = url.pathExtension.isEmpty ? (type?.preferredFilenameExtension ?? "") : url.pathExtension
        func withExtension(_ base: String) -> String {
            ext.isEmpty || (base as NSString).pathExtension.lowercased() == ext.lowercased() ? base : "\(base).\(ext)"
        }
        func isMachineName(_ name: String) -> Bool { name.hasPrefix("uuid=") || name.contains("&code=") }
        func isTypeDescription(_ name: String) -> Bool {
            [type?.localizedDescription, UTType(filenameExtension: ext)?.localizedDescription]
                .compactMap { $0 }.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        // The name of the file the drop linked to wins, then the file's own name,
        // then the sender's suggestion. macOS's own suggestion for a link is just
        // a description ("JPEG image"), so it comes last.
        for name in [linkedName, url.lastPathComponent].compactMap({ $0 }) {
            let base = (name as NSString).deletingPathExtension
            if !base.isEmpty, !isMachineName(base), !isTypeDescription(base) { return withExtension(name) }
        }
        if let suggested = suggestedName?.trimmingCharacters(in: .whitespaces), !suggested.isEmpty, !isMachineName(suggested) {
            return withExtension(suggested)
        }

        // No human name anywhere: name it after when it was taken, as the
        // photo's own metadata records it, so a batch sorts in shooting order.
        // Files without a capture date (screenshots, exports) use the drop time.
        // Same-second names never clash: the destination adds " (1)".
        let kind = (type ?? UTType(filenameExtension: ext))?.conforms(to: .audiovisualContent) == true ? "Video" : "Photo"
        let when = captureDate(of: url, type: type) ?? Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return withExtension("\(kind) \(stamp.string(from: when))")
    }

    /// When a photo or video was taken, read from the file's own metadata.
    static func captureDate(of url: URL, type: UTType?) -> Date? {
        let type = type ?? UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .audiovisualContent) == true { return videoCreationDate(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized]
                          ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String else { return nil }
        // EXIF stores the camera's wall-clock time with no zone, which is what the name should show.
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return parser.date(from: text)
    }

    /// The general creation date, else any dated metadata item, such as the
    /// iPhone's com.apple.quicktime.creationdate, which keeps its time zone.
    private static func videoCreationDate(_ url: URL) -> Date? {
        final class Box: @unchecked Sendable { var date: Date? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        // Called from drop callbacks on background threads; detached so it never needs the main thread.
        Task.detached {
            let asset = AVURLAsset(url: url)
            if let item = try? await asset.load(.creationDate), let date = try? await item.load(.dateValue) {
                box.date = date
            } else {
                for item in (try? await asset.load(.metadata)) ?? [] {
                    if let date = try? await item.load(.dateValue) { box.date = date; break }
                }
            }
            done.signal()
        }
        return done.wait(timeout: .now() + 5) == .success ? box.date : nil
    }
}
