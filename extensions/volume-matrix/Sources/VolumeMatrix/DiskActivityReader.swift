import Foundation
import IOKit

/// Driver counters are physical-device totals, never per-APFS-volume estimates.
enum DiskActivityReader {
    static func read() -> [String: DiskCounters] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: DiskCounters] = [:]
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }
            guard let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: NSNumber],
                  let read = stats["Bytes (Read)"]?.uint64Value, let written = stats["Bytes (Write)"]?.uint64Value else { continue }
            var children: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(driver, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let media = IOIteratorNext(children), media != 0 {
                defer { IOObjectRelease(media) }
                let whole = IORegistryEntryCreateCFProperty(media, "Whole" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
                guard whole, let name = IORegistryEntryCreateCFProperty(media, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
                result[name] = DiskCounters(read: read, written: written)
            }
        }
        return result
    }
}
