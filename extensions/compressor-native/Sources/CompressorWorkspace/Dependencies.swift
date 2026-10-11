import Foundation

/// A Homebrew package that Compressor shells out to.
struct Dependency: Identifiable, Sendable, Equatable {
    /// Homebrew formula name.
    let formula: String
    /// Executables the formula must provide.
    let tools: [String]
    /// What stops working without it, in plain words.
    let purpose: String
    /// Optional ones only improve results; nothing breaks without them.
    let optional: Bool

    var id: String { formula }
}

enum Dependencies {
    static let all: [Dependency] = [
        Dependency(formula: "ffmpeg", tools: ["ffmpeg", "ffprobe"], purpose: "videos and PNG files", optional: false),
        Dependency(formula: "ghostscript", tools: ["gs"], purpose: "PDFs", optional: false),
        Dependency(formula: "webp", tools: ["cwebp"], purpose: "WebP images", optional: false),
        Dependency(formula: "oxipng", tools: ["oxipng"], purpose: "smaller PNG files", optional: true),
    ]

    /// Dependencies of the given kind (required or optional) that aren't installed.
    static func missing(
        optional: Bool = false,
        finder: (String) -> String? = Tools.find
    ) -> [Dependency] {
        all.filter { $0.optional == optional && $0.tools.contains { finder($0) == nil } }
    }

    static func installCommand(_ dependencies: [Dependency]) -> String {
        "brew install " + dependencies.map(\.formula).joined(separator: " ")
    }

    /// "ffmpeg (videos and PNG files), ghostscript (PDFs)"
    static func summary(_ dependencies: [Dependency]) -> String {
        dependencies.map { "\($0.formula) (\($0.purpose))" }.joined(separator: ", ")
    }

    static func homebrewInstalled(finder: (String) -> String? = Tools.find) -> Bool {
        finder("brew") != nil
    }

    static let homebrewURL = URL(string: "https://brew.sh")!
}
