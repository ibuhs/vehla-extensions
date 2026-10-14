import Foundation
import IOKit

// Read published service properties only; do not seize input devices or collect keystrokes.
enum RegistryDiscovery {
    static func discover() -> [PeripheralSnapshot] {
        var found: [String: PeripheralSnapshot] = [:]
        for serviceClass in ["IOHIDDevice", "IOHIDEventService", "AppleDeviceManagementHIDEventService"] {
            var iterator: io_iterator_t = 0
            guard let matching = IOServiceMatching(serviceClass), IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let props = properties?.takeRetainedValue() as? [String: Any] else { continue }
                let transport = props["Transport"] as? String ?? "Unknown"
                let usage = (props["PrimaryUsage"] as? NSNumber)?.intValue
                let page = (props["PrimaryUsagePage"] as? NSNumber)?.intValue
                let battery = PeripheralSnapshot.batteryPercent((props["BatteryPercent"] as? NSNumber)?.intValue)
                let wireless = transport.localizedCaseInsensitiveContains("bluetooth") || props["BatteryPercent"] != nil
                guard wireless, (page == 1 && (usage == 2 || usage == 6)) || battery != nil else { continue }
                let name = props["Product"] as? String ?? props["DeviceName"] as? String ?? "Wireless peripheral"
                var registryID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
                // Services with a serial number are deduplicated across registry representations.
                let serial = props["SerialNumber"] as? String
                let id = serial.flatMap { $0.isEmpty ? nil : "hid.serial.\($0).\(name)" } ?? "hid.registry.\(registryID)"
                let item = PeripheralSnapshot(id: id, name: name, transport: transport,
                    kind: usage == 6 ? "Keyboard" : usage == 2 ? "Mouse" : "Peripheral", battery: battery)
                if found[id]?.battery == nil { found[id] = item }
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// Actor isolation keeps blocking IOKit registry reads off the UI executor.
actor RegistryReader {
    private var lastHeadphoneRead = Date.distantPast
    private var headphones: [PeripheralSnapshot] = []
    func read() -> [PeripheralSnapshot] {
        if Date().timeIntervalSince(lastHeadphoneRead) >= 60 {
            lastHeadphoneRead = Date()
            headphones = ConnectedHeadphones.discover()
        }
        return PeripheralInventory.merge(RegistryDiscovery.discover(), batteries: headphones)
    }
}
