import Foundation

struct PeripheralSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let transport: String
    let kind: String
    let battery: Int?
    var batteryDetails: String? = nil
    var icon: String { kind == "Mouse" ? "computermouse.fill" : kind == "Keyboard" ? "keyboard" : kind == "Headphones" ? "headphones" : "battery.100percent" }
    var batteryText: String { batteryDetails ?? battery.map { "\($0)%" } ?? "Unknown" }
    static func batteryPercent(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }
}

// Opt-in QMK Raw HID protocol. Unknown firmware is never sent a layer command.
// Packet: "VHLA", version 1, opcode, layer, layer-count, status, reserved padding.
enum LayerProtocol {
    static func defaultName(layer: UInt8, vendor: UInt32, product: UInt32) -> String {
        if vendor == 0x3434, product == 0x02a3, layer < 4 {
            return ["Mac", "Mac Fn", "Windows", "Windows Fn"][Int(layer)]
        }
        return "Layer \(layer)"
    }
    static let size = 32
    static let magic: [UInt8] = [0x56, 0x48, 0x4c, 0x41, 1]
    static func query() -> [UInt8] { packet(opcode: 1, layer: 0) }
    static func set(layer: UInt8, count: UInt8) -> [UInt8]? {
        guard count > 0, layer < count else { return nil }
        return packet(opcode: 2, layer: layer)
    }
    private static func packet(opcode: UInt8, layer: UInt8) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        bytes.replaceSubrange(0..<magic.count, with: magic); bytes[5] = opcode; bytes[6] = layer
        return bytes
    }
    struct State: Equatable { let active: UInt8; let count: UInt8 }
    static func decode(_ bytes: [UInt8]) -> State? {
        guard bytes.count == size, Array(bytes.prefix(5)) == magic,
              bytes[5] == 0x81 || bytes[5] == 0x82, bytes[8] == 0,
              bytes[7] > 0, bytes[7] <= 32, bytes[6] < bytes[7] else { return nil }
        return State(active: bytes[6], count: bytes[7])
    }
}

// A BLE battery service does not identify the device type. Match it only to a
// unique named device in the registry, preserving the HID row and its mouse/keyboard kind.
enum PeripheralInventory {
    static func merge(_ registry: [PeripheralSnapshot], batteries: [PeripheralSnapshot]) -> [PeripheralSnapshot] {
        var result = registry
        let registryNames = Dictionary(grouping: registry, by: { key($0.name) })
        let batteryNames = Dictionary(grouping: batteries, by: { key($0.name) })
        for battery in batteries {
            let name = key(battery.name)
            if !name.isEmpty, registryNames[name]?.count == 1, batteryNames[name]?.count == 1,
               let index = result.firstIndex(where: { key($0.name) == name }) {
                let original = result[index]
                result[index] = PeripheralSnapshot(id: original.id, name: original.name, transport: original.transport,
                    kind: original.kind, battery: battery.battery ?? original.battery,
                    batteryDetails: battery.batteryDetails ?? original.batteryDetails)
            } else { result.append(battery) }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
