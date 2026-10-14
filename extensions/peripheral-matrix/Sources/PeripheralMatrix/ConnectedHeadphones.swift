import Foundation

enum ConnectedHeadphones {
    // macOS's own Bluetooth report includes AirPods earbud/case readings that
    // are not exposed through the standard BLE Battery Service. Run only on the
    // registry worker, cache for a minute, and bound the subprocess lifetime.
    static func discover() -> [PeripheralSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [PeripheralSnapshot] {
        guard let document = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var readings: [String: [String: Any]] = [:]
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, value) in dictionary {
                    if key == "device_connected", let rows = value as? [[String: Any]] {
                        for row in rows {
                            for (name, properties) in row {
                                guard let properties = properties as? [String: Any],
                                      name.localizedCaseInsensitiveContains("airpods") ||
                                      ["Headphones", "Headset"].contains(properties["device_minorType"] as? String ?? "") else { continue }
                                readings[name, default: [:]].merge(properties) { old, new in new }
                            }
                        }
                    } else { walk(value) }
                }
            } else if let values = value as? [Any] { values.forEach(walk) }
        }
        walk(document)
        return readings.map { name, properties in
            let left = percent(properties["device_batteryLevelLeft"])
            let right = percent(properties["device_batteryLevelRight"])
            let device = percent(properties["device_batteryLevelMain"] ?? properties["device_batteryLevel"])
            let caseBattery = percent(properties["device_batteryLevelCase"])
            let details = [("L", left), ("R", right), ("Case", caseBattery)].compactMap { label, value in
                value.map { "\(label) \($0)%" }
            }.joined(separator: " · ")
            return PeripheralSnapshot(id: "headphones.\(name)", name: name, transport: "Bluetooth · Connected",
                kind: "Headphones", battery: [left, right, device].compactMap { $0 }.min(),
                batteryDetails: details.isEmpty ? nil : details)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func percent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return PeripheralSnapshot.batteryPercent(number.intValue) }
        guard let text = value as? String else { return nil }
        return PeripheralSnapshot.batteryPercent(Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)))
    }
}
