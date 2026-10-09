import AppKit

/// Optional in the library so existing backups decode without migration.
enum MathResultColor: String, Codable, CaseIterable, Sendable {
    case automatic, primary, white, black, yellow, orange, green, cyan, pink
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .primary: "Match Note Text"
        default: rawValue.capitalized
        }
    }
    @MainActor func resolve(textColor: NSColor) -> NSColor {
        switch self {
        case .automatic: textColor.withAlphaComponent(0.75)
        case .primary: textColor
        case .white: .white
        case .black: .black
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .green: .systemGreen
        case .cyan: .systemCyan
        case .pink: .systemPink
        }
    }
}
