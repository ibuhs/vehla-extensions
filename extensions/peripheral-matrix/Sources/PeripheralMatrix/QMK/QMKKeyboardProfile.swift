import Foundation

struct QMKPhysicalKey: Identifiable, Equatable, Sendable {
    let row: Int
    let column: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var id: Int { row * 21 + column }
}
struct QMKKeyboardProfile: Equatable, Sendable {
    let id: String
    let name: String
    let rows: Int
    let columns: Int
    let layers: Int
    let keys: [QMKPhysicalKey]
    var keysPerLayer: Int { rows * columns }
    var totalKeys: Int { layers * keysPerLayer }
    var layoutWidth: Double { keys.map { $0.x + $0.width }.max() ?? 1 }
    var layoutHeight: Double { keys.map { $0.y + $0.height }.max() ?? 1 }
    // Matrix coordinates and geometry from Keychron's official VIA definition,
    // pinned to the firmware revision used for this keyboard.
    // https://github.com/Keychron/qmk_firmware/blob/618127a725a1773e85f13455602cf6f72ab4de17/keyboards/keychron/k10_pro/via_json/k10_pro_ansi_white.json
    static let k10ProANSIWhite = QMKKeyboardProfile(id: "keychron/k10_pro/ansi/white", name: "Keychron K10 Pro ANSI White", rows: 6, columns: 21, layers: 4, keys: [
        .init(row: 0, column: 0, x: 0, y: 0, width: 1, height: 1),
        .init(row: 0, column: 1, x: 2, y: 0, width: 1, height: 1),
        .init(row: 0, column: 2, x: 3, y: 0, width: 1, height: 1),
        .init(row: 0, column: 3, x: 4, y: 0, width: 1, height: 1),
        .init(row: 0, column: 4, x: 5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 5, x: 6.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 6, x: 7.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 7, x: 8.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 8, x: 9.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 9, x: 11.0, y: 0, width: 1, height: 1),
        .init(row: 0, column: 10, x: 12.0, y: 0, width: 1, height: 1),
        .init(row: 0, column: 11, x: 13.0, y: 0, width: 1, height: 1),
        .init(row: 0, column: 12, x: 14.0, y: 0, width: 1, height: 1),
        .init(row: 0, column: 14, x: 15.25, y: 0, width: 1, height: 1),
        .init(row: 0, column: 15, x: 16.25, y: 0, width: 1, height: 1),
        .init(row: 0, column: 16, x: 17.25, y: 0, width: 1, height: 1),
        .init(row: 0, column: 17, x: 18.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 18, x: 19.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 19, x: 20.5, y: 0, width: 1, height: 1),
        .init(row: 0, column: 20, x: 21.5, y: 0, width: 1, height: 1),
        .init(row: 1, column: 0, x: 0, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 1, x: 1, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 2, x: 2, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 3, x: 3, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 4, x: 4, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 5, x: 5, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 6, x: 6, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 7, x: 7, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 8, x: 8, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 9, x: 9, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 10, x: 10, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 11, x: 11, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 12, x: 12, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 13, x: 13, y: 1.25, width: 2, height: 1),
        .init(row: 1, column: 14, x: 15.25, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 15, x: 16.25, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 16, x: 17.25, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 17, x: 18.5, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 18, x: 19.5, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 19, x: 20.5, y: 1.25, width: 1, height: 1),
        .init(row: 1, column: 20, x: 21.5, y: 1.25, width: 1, height: 1),
        .init(row: 2, column: 0, x: 0, y: 2.25, width: 1.5, height: 1),
        .init(row: 2, column: 1, x: 1.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 2, x: 2.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 3, x: 3.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 4, x: 4.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 5, x: 5.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 6, x: 6.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 7, x: 7.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 8, x: 8.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 9, x: 9.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 10, x: 10.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 11, x: 11.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 12, x: 12.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 13, x: 13.5, y: 2.25, width: 1.5, height: 1),
        .init(row: 2, column: 14, x: 15.25, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 15, x: 16.25, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 16, x: 17.25, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 17, x: 18.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 18, x: 19.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 19, x: 20.5, y: 2.25, width: 1, height: 1),
        .init(row: 2, column: 20, x: 21.5, y: 2.25, width: 1, height: 2),
        .init(row: 3, column: 0, x: 0, y: 3.25, width: 1.75, height: 1),
        .init(row: 3, column: 1, x: 1.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 2, x: 2.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 3, x: 3.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 4, x: 4.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 5, x: 5.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 6, x: 6.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 7, x: 7.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 8, x: 8.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 9, x: 9.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 10, x: 10.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 11, x: 11.75, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 13, x: 12.75, y: 3.25, width: 2.25, height: 1),
        .init(row: 3, column: 17, x: 18.5, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 18, x: 19.5, y: 3.25, width: 1, height: 1),
        .init(row: 3, column: 19, x: 20.5, y: 3.25, width: 1, height: 1),
        .init(row: 4, column: 0, x: 0, y: 4.25, width: 2.25, height: 1),
        .init(row: 4, column: 2, x: 2.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 3, x: 3.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 4, x: 4.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 5, x: 5.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 6, x: 6.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 7, x: 7.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 8, x: 8.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 9, x: 9.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 10, x: 10.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 11, x: 11.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 13, x: 12.25, y: 4.25, width: 2.75, height: 1),
        .init(row: 4, column: 15, x: 16.25, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 17, x: 18.5, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 18, x: 19.5, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 19, x: 20.5, y: 4.25, width: 1, height: 1),
        .init(row: 4, column: 20, x: 21.5, y: 4.25, width: 1, height: 2),
        .init(row: 5, column: 0, x: 0, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 1, x: 1.25, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 2, x: 2.5, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 6, x: 3.75, y: 5.25, width: 6.25, height: 1),
        .init(row: 5, column: 10, x: 10.0, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 11, x: 11.25, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 12, x: 12.5, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 13, x: 13.75, y: 5.25, width: 1.25, height: 1),
        .init(row: 5, column: 14, x: 15.25, y: 5.25, width: 1, height: 1),
        .init(row: 5, column: 15, x: 16.25, y: 5.25, width: 1, height: 1),
        .init(row: 5, column: 16, x: 17.25, y: 5.25, width: 1, height: 1),
        .init(row: 5, column: 17, x: 18.5, y: 5.25, width: 2, height: 1),
        .init(row: 5, column: 19, x: 20.5, y: 5.25, width: 1, height: 1),
    ])
}
