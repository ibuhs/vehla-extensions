import Foundation

public enum Parsers {
    /// `shortcuts list` prints one name per line.
    public static func shortcuts(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// `defaults read -g AppleInterfaceStyle` prints "Dark" in dark mode and fails otherwise.
    public static func isDarkMode(_ result: ShellResult) -> Bool {
        result.ok && result.output.lowercased().contains("dark")
    }

    public static func isTrue(_ output: String) -> Bool {
        ["true", "1", "yes"].contains(output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// `defaults read com.apple.finder CreateDesktop`: absent or 1 means icons are shown.
    public static func desktopIconsShown(_ result: ShellResult) -> Bool {
        guard result.ok else { return true }
        return isTrue(result.output)
    }

    public static func appleScriptString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
