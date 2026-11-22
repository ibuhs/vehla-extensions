import Foundation

public enum GitBranch {
    /// The checked-out branch (or short commit) for a working directory, read straight from
    /// `.git/HEAD` so no process is spawned. Handles worktrees, where `.git` is a file.
    public static func read(from directory: String?) -> String? {
        guard var dir = directory.map({ URL(fileURLWithPath: $0) }) else { return nil }
        for _ in 0..<12 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                return head(in: isDirectory.boolValue ? dotGit : gitDir(fromFile: dotGit, base: dir))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    private static func gitDir(fromFile file: URL, base: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first,
              line.hasPrefix("gitdir:") else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
    }

    private static func head(in gitDir: URL?) -> String? {
        guard let gitDir,
              let text = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref:") {
            let ref = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        }
        return line.isEmpty ? nil : String(line.prefix(7))
    }
}
