import Foundation

/// A project folder kept for one-click `cd`.
public struct FavoriteFolder: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var path: String
    public var id: String { path }
    public init(name: String, path: String) { self.name = name; self.path = path }
}

public enum FavoriteFolders {
    public static let limit = 12

    /// One spelling per folder: no trailing slash, `.` and `..` resolved (symlinks are left as typed).
    public static func normalize(_ path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        return standardized.isEmpty ? "/" : standardized
    }

    public static func defaultName(for path: String, home: String) -> String {
        let normalized = normalize(path)
        if normalized == normalize(home) { return "Home" }
        if normalized == "/" { return "/" }
        return (normalized as NSString).lastPathComponent
    }

    public static func contains(_ path: String, in folders: [FavoriteFolder]) -> Bool {
        let target = normalize(path)
        return folders.contains { normalize($0.path) == target }
    }

    /// Adds the folder at the end. Nil when it is already there or the list is full.
    public static func adding(_ path: String, to folders: [FavoriteFolder], home: String) -> [FavoriteFolder]? {
        guard folders.count < limit, !contains(path, in: folders) else { return nil }
        let normalized = normalize(path)
        return folders + [FavoriteFolder(name: defaultName(for: normalized, home: home), path: normalized)]
    }

    public static func removing(_ path: String, from folders: [FavoriteFolder]) -> [FavoriteFolder] {
        let target = normalize(path)
        return folders.filter { normalize($0.path) != target }
    }

    /// The line typed for the shell. The leading space keeps it out of history (the usual convention),
    /// and `--` plus quoting make any folder name safe, including ones that start with a dash.
    public static func cdCommand(for path: String) -> String {
        " cd -- " + ShellQuote.quote(normalize(path))
    }
}
