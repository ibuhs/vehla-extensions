import Foundation

struct QMKKeyboardCatalog {
    struct Entry: Decodable {
        let id: String
        let name: String
        let vendor: UInt32
        let product: UInt32
        let rows: Int
        let columns: Int
        let layers: Int
        let keys: [Key]
        let customNames: [String]
        let source: String
        let sha256: String
        struct Key: Decodable {
            let row: Int; let column: Int
            let x: Double; let y: Double; let width: Double; let height: Double
        }
        var profile: QMKKeyboardProfile {
            QMKKeyboardProfile(id: id, name: name, rows: rows, columns: columns, layers: layers,
                keys: keys.map { .init(row: $0.row, column: $0.column, x: $0.x, y: $0.y,
                    width: $0.width, height: $0.height, matrixColumns: columns) }, customNames: customNames)
        }
    }
    static let entries: [Entry] = {
        let hostBundle = Bundle(for: PeripheralMatrixPlugin.self)
        let packaged = hostBundle.url(forResource: "PeripheralMatrix_PeripheralMatrix", withExtension: "bundle")
            .flatMap { Bundle(url: $0) }
        #if DEBUG
        let resources = packaged ?? Bundle.module
        #else
        // A packaging error must disable unknown layouts rather than crash Alpha.
        guard let resources = packaged else { return [] }
        #endif
        guard let url = resources.url(forResource: "keyboard-profiles", withExtension: "json"),
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return result
    }()
    static func profile(vendor: UInt32, product: UInt32) -> QMKKeyboardProfile? {
        if vendor == 0x3434 && product == 0x02a3 { return .k10ProANSIWhite }
        return entries.first { $0.vendor == vendor && $0.product == product }?.profile
    }
}
