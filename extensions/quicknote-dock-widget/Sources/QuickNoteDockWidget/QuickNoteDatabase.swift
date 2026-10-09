import Foundation
import SQLite3

enum QuickNoteDatabaseError: LocalizedError, Equatable, Sendable {
    case missing
    case permission(String)
    case unsupported(String)
    case busy
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .missing:
            return "Antinote’s notes database was not found. Open Antinote once so it can create its notes file."
        case .permission(let detail):
            return "Vehla needs Full Disk Access to read Antinote notes. In System Settings, open Privacy & Security → Full Disk Access and enable Vehla. \(detail)"
        case .unsupported(let reason):
            return reason
        case .busy:
            return "Antinote is using its database. Try saving again in a moment."
        case .sqlite(let detail):
            return detail
        }
    }
}

enum QuickNoteSaveResult: Equatable, Sendable {
    case saved(modified: Date?)
    case conflict(current: String)
    case missingNote
}

struct QuickNoteCandidate: Equatable {
    enum Kind: Equatable {
        case stable
        case legacy
    }

    var url: URL
    var kind: Kind
}

struct QuickNoteNote: Identifiable, Equatable, Sendable {
    var id: String
    var content: String
    var created: Date?
    var modified: Date?
    var slot: Int?

    var title: String {
        let line = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stripped = line.drop { $0 == "#" || $0 == " " }
        let text = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Empty note" }
        if text.count > 80 { return String(text.prefix(80)) }
        return text
    }

    var preview: String {
        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let remainder = lines.dropFirst().joined(separator: " ")
        if remainder.isEmpty { return "No extra text" }
        if remainder.count > 90 { return String(remainder.prefix(90)) }
        return remainder
    }
}

struct QuickNoteLibrary: Equatable, Sendable {
    var notes: [QuickNoteNote]
    var canEdit: Bool
    var editBlock: String?
    var sourceName: String
}

enum QuickNoteLinks {
    static func createNote(content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return URL(string: "antinote://x-callback-url/createNote")
        }
        return url(action: "createNote", query: ["content": trimmed])
    }

    static func open(noteID: String) -> URL? {
        url(action: "promoteAndOpen", query: ["noteId": noteID])
    }

    static func overwriteCurrent(content: String) -> URL? {
        url(action: "overwriteCurrent", query: ["content": content])
    }

    static func reloadDatabase() -> URL? {
        URL(string: "antinote://x-callback-url/reloadDB")
    }

    private static func url(action: String, query: [String: String]) -> URL? {
        var components = URLComponents()
        components.scheme = "antinote"
        components.host = "x-callback-url"
        components.path = "/\(action)"
        var unreserved = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        unreserved.insert(charactersIn: "-._~")
        components.percentEncodedQuery = query
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
            }
            .joined(separator: "&")
        return components.url
    }
}

enum QuickNoteDatabase {
    static let contentLimit = 2_000_000

    static func candidates(home: URL) -> [QuickNoteCandidate] {
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        func file(_ bundle: String, _ relative: String, kind: QuickNoteCandidate.Kind) -> QuickNoteCandidate {
            QuickNoteCandidate(
                url: containers.appendingPathComponent("\(bundle)/Data/\(relative)"),
                kind: kind
            )
        }
        return [
            file("com.chabomakers.Antinote", "Documents/notes.sqlite3", kind: .stable),
            file("com.chabomakers.Antinote-setapp", "Documents/notes.sqlite3", kind: .stable),
            file("com.chabomakers.Antinote", "Library/Application Support/cd-v1-notes.sqlite", kind: .legacy),
            file("com.chabomakers.Antinote-setapp", "Library/Application Support/cd-v1-notes.sqlite", kind: .legacy),
        ]
    }

    static func locate(
        home: URL,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        modified: (URL) -> Date? = {
            (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date
        }
    ) -> QuickNoteCandidate? {
        let found = candidates(home: home).filter { exists($0.url) }
        let stable = found.filter { $0.kind == .stable }
        let pool = stable.isEmpty ? found : stable
        return pool.max { lhs, rhs in
            (modified(lhs.url) ?? .distantPast) < (modified(rhs.url) ?? .distantPast)
        }
    }

    struct Discovery: Sendable {
        var url: URL
        var tables: [String]
        var noteCount: Int?
        var modified: Date?
        var error: String?

        var hasNotesTable: Bool { tables.contains("notes") }
        var hasLegacyTable: Bool { tables.contains("ZNOTE") }
    }

    /// Scans Antinote's containers for every SQLite file and reports what each holds.
    static func discover(home: URL) -> [Discovery] {
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        let roots = ["com.chabomakers.Antinote", "com.chabomakers.Antinote-setapp"].map {
            containers.appendingPathComponent("\($0)/Data", isDirectory: true)
        }
        let extensions: Set<String> = ["sqlite", "sqlite3", "db", "store"]
        let skipped: Set<String> = ["Caches", "WebKit", "HTTPStorages", "Logs", "Saved Application State"]
        var results: [Discovery] = []
        // Known paths still work when macOS denies enumerating the container.
        for candidate in candidates(home: home) {
            if FileManager.default.fileExists(atPath: candidate.url.path) {
                results.append(inspect(candidate.url))
            }
        }
        for root in roots {
            guard let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in walker {
                if Task.isCancelled { return results }
                if skipped.contains(url.lastPathComponent) {
                    walker.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    walker.skipDescendants()
                    continue
                }
                guard values?.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) else { continue }
                if !results.contains(where: { $0.url == url }) { results.append(inspect(url)) }
            }
        }
        return results
    }

    /// Picks the database Antinote actively uses: a `notes` table wins over the
    /// Core Data store, and the most recently written file wins within a kind.
    static func best(_ found: [Discovery]) -> Discovery? {
        let usable = found.filter { $0.error == nil && ($0.hasNotesTable || $0.hasLegacyTable) }
        let modern = usable.filter(\.hasNotesTable)
        let pool = modern.isEmpty ? usable : modern
        return pool.max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
    }

    private static func inspect(_ url: URL) -> Discovery {
        let manager = FileManager.default
        let stamps = [url.path, url.path + "-wal"].compactMap {
            (try? manager.attributesOfItem(atPath: $0)[.modificationDate]) as? Date
        }
        var discovery = Discovery(url: url, tables: [], noteCount: nil, modified: stamps.max(), error: nil)
        do {
            let database = try SQLiteDB(url: url, writing: false)
            defer { database.close() }
            discovery.tables = try database.tableNames().sorted()
            if discovery.hasNotesTable {
                discovery.noteCount = try database.count("notes")
            } else if discovery.hasLegacyTable {
                discovery.noteCount = try database.count("ZNOTE")
            }
        } catch {
            discovery.error = error.localizedDescription
        }
        return discovery
    }

    static func load(_ url: URL) throws -> QuickNoteLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw QuickNoteDatabaseError.missing
        }
        let database = try SQLiteDB(url: url, writing: false)
        defer { database.close() }
        let tables = try database.tableNames()
        if tables.contains("notes") {
            return try loadNotes(database, sourceName: url.lastPathComponent)
        }
        if tables.contains("ZNOTE") {
            return try loadLegacy(database, sourceName: url.lastPathComponent)
        }
        throw QuickNoteDatabaseError.unsupported(
            "\(url.lastPathComponent) does not contain an Antinote notes table this widget recognizes."
        )
    }

    static func save(
        _ url: URL,
        noteID: String,
        content: String,
        baseline: String,
        now: Date = Date()
    ) throws -> QuickNoteSaveResult {
        if content.utf8.count > contentLimit {
            throw QuickNoteDatabaseError.unsupported("This note is too large to save from the Dock.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw QuickNoteDatabaseError.missing
        }
        let database = try SQLiteDB(url: url, writing: true)
        defer { database.close() }
        let tables = try database.tableNames()
        if tables.contains("ZNOTE"), !tables.contains("notes") {
            return try database.updateLegacyNote(id: noteID, content: content, baseline: baseline, now: now)
        }
        let columns = try noteColumns(database)
        guard columns.canEdit else {
            throw QuickNoteDatabaseError.unsupported(
                columns.editBlock ?? "This Antinote database can be read here, but not edited."
            )
        }
        try database.execute("BEGIN IMMEDIATE")
        do {
            let row = try database.noteRow(columns: columns, id: noteID)
            guard let row else {
                try database.execute("ROLLBACK")
                return .missingNote
            }
            guard row.content == baseline else {
                try database.execute("ROLLBACK")
                return .conflict(current: row.content)
            }
            let modified = QuickNoteTimestamp.stored(now, like: row.modifiedRaw)
            try database.updateNote(
                columns: columns,
                id: noteID,
                content: content,
                modified: modified
            )
            guard database.changedRows == 1 else {
                try database.execute("ROLLBACK")
                throw QuickNoteDatabaseError.sqlite("The note was not updated.")
            }
            try database.execute("COMMIT")
            return .saved(modified: modified.flatMap(QuickNoteTimestamp.date(from:)))
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private static func loadNotes(_ database: SQLiteDB, sourceName: String) throws -> QuickNoteLibrary {
        let columns = try noteColumns(database)
        let notes = try database.notes(columns: columns)
        return QuickNoteLibrary(
            notes: notes,
            canEdit: columns.canEdit,
            editBlock: columns.editBlock,
            sourceName: sourceName
        )
    }

    private static func loadLegacy(_ database: SQLiteDB, sourceName: String) throws -> QuickNoteLibrary {
        let info = try database.columnInfo("ZNOTE")
        let names = Set(info.map(\.name))
        guard names.contains("ZCONTENT"), names.contains("ZID") else {
            throw QuickNoteDatabaseError.unsupported("The Antinote database has no note text column.")
        }
        let contentType = try database.storageType(table: "ZNOTE", column: "ZCONTENT")
        let editable = contentType == nil || contentType == "text" || contentType == "null"
        let notes = try database.legacyNotes(available: names)
        return QuickNoteLibrary(
            notes: notes,
            canEdit: editable,
            editBlock: editable ? nil : "Note text is not stored as text, so this widget will not change it.",
            sourceName: sourceName
        )
    }

    private static func noteColumns(_ database: SQLiteDB) throws -> NoteColumns {
        let info = try database.columnInfo("notes")
        let byName = Dictionary(uniqueKeysWithValues: info.map { ($0.name.lowercased(), $0) })
        guard let id = byName["id"], let content = byName["content"] else {
            throw QuickNoteDatabaseError.unsupported("The notes table is missing id or content.")
        }
        guard quote(id.name) != nil, quote(content.name) != nil else {
            throw QuickNoteDatabaseError.unsupported("The notes table uses column names this widget will not write.")
        }
        let modified = ["lastmodified", "modified", "updatedat", "updated"].compactMap { byName[$0] }.first
        let created = ["created", "createdat", "creationdate"].compactMap { byName[$0] }.first
        let deleted = ["softdeleted", "isdeleted", "deleted", "invoid", "isvoid", "voided"].compactMap { byName[$0] }.first
        let slotted = ["isslotted", "slotted"].compactMap { byName[$0] }.first
        let slot = ["slotindex", "slot"].compactMap { byName[$0] }.first
        let sample = try database.sampleTypes(id: id.name, content: content.name)
        var editBlock: String?
        var canEdit = true
        if let contentType = sample.contentType, contentType != "text" && contentType != "null" {
            canEdit = false
            editBlock = "Note text is not stored as text, so this widget will not change it."
        }
        if let idType = sample.idType, idType != "text" && idType != "integer" && idType != "null" {
            canEdit = false
            editBlock = "Note identifiers are in a format this widget will not write."
        }
        if let deleted, !deleted.type.isEmpty, !deleted.isIntegerLike {
            canEdit = false
            editBlock = "This notes table has a deletion column this widget does not understand."
        }
        for column in [modified, created, deleted, slotted, slot].compactMap({ $0 }) {
            if quote(column.name) == nil {
                canEdit = false
                editBlock = "The notes table uses column names this widget will not write."
            }
        }
        return NoteColumns(
            id: id.name,
            content: content.name,
            created: created?.name,
            modified: modified?.name,
            deleted: deleted.flatMap { $0.isIntegerLike ? $0.name : nil },
            slotted: slotted?.name,
            slotIndex: slot?.name,
            canEdit: canEdit,
            editBlock: editBlock
        )
    }

    static func quote(_ identifier: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard !identifier.isEmpty, identifier.count < 64,
              identifier.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else { return nil }
        return "\"\(identifier)\""
    }
}

enum QuickNoteTimestamp {
    static func date(from value: SQLValue) -> Date? {
        switch value {
        case .text(let text):
            return date(fromText: text)
        case .integer(let number):
            return date(fromNumber: Double(number))
        case .real(let number):
            return date(fromNumber: number)
        case .null:
            return nil
        }
    }

    /// Rebuilds a timestamp using the same storage as an existing cell.
    static func stored(_ date: Date, like sample: SQLValue) -> SQLValue? {
        switch sample {
        case .text(let text):
            guard let formatted = textStored(date, like: text) else { return nil }
            return .text(formatted)
        case .integer(let number):
            guard let stored = numberStored(date, like: Double(number)) else { return nil }
            return .integer(Int64(stored.rounded()))
        case .real(let number):
            guard let stored = numberStored(date, like: number) else { return nil }
            return .real(stored)
        case .null:
            return nil
        }
    }

    private static func date(fromText text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func date(fromNumber number: Double) -> Date? {
        if number >= 1_000_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if number >= 1_100_000_000 {
            return Date(timeIntervalSince1970: number)
        }
        if number > 0 {
            return Date(timeIntervalSinceReferenceDate: number)
        }
        return nil
    }

    private static func numberStored(_ date: Date, like sample: Double) -> Double? {
        if sample >= 1_000_000_000_000 {
            return date.timeIntervalSince1970 * 1000
        }
        if sample >= 1_100_000_000 {
            return date.timeIntervalSince1970
        }
        if sample > 0 {
            return date.timeIntervalSinceReferenceDate
        }
        return nil
    }

    private static func textStored(_ date: Date, like sample: String) -> String? {
        guard Self.date(fromText: sample) != nil else { return nil }
        if sample.contains(" ") && !sample.contains("T") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
        let formatter = ISO8601DateFormatter()
        var options: ISO8601DateFormatter.Options = [.withInternetDateTime]
        if sample.contains(".") {
            options.insert(.withFractionalSeconds)
        }
        formatter.formatOptions = options
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

struct NoteColumns {
    var id: String
    var content: String
    var created: String?
    var modified: String?
    var deleted: String?
    var slotted: String?
    var slotIndex: String?
    var canEdit: Bool
    var editBlock: String?
}

enum SQLValue: Equatable, Sendable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

private struct ColumnInfo {
    var name: String
    var type: String

    var isIntegerLike: Bool {
        let upper = type.uppercased()
        return upper.contains("INT") || upper.contains("BOOL")
    }
}

private struct SampleTypes {
    var idType: String?
    var contentType: String?
}

private struct StoredRow {
    var content: String
    var modifiedRaw: SQLValue
}

private final class SQLiteDB {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, writing: Bool) throws {
        var database: OpaquePointer?
        let flags = writing ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        let code = url.path.withCString { sqlite3_open_v2($0, &database, flags | SQLITE_OPEN_FULLMUTEX, nil) }
        guard code == SQLITE_OK, let database else {
            let detail = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database { sqlite3_close(database) }
            throw Self.openError(code: code, detail: detail, writing: writing)
        }
        handle = database
        sqlite3_busy_timeout(database, 1_500)
        if !writing {
            try? execute("PRAGMA query_only = ON")
        }
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
        }
        handle = nil
    }

    deinit { close() }

    var changedRows: Int { Int(sqlite3_changes(handle)) }

    func tableNames() throws -> Set<String> {
        let rows = try queryRows("SELECT name FROM sqlite_master WHERE type = 'table'")
        return Set(rows.compactMap { $0.first })
    }

    func count(_ table: String) throws -> Int {
        guard let quoted = QuickNoteDatabase.quote(table) else { return 0 }
        let rows = try queryRows("SELECT COUNT(*) FROM \(quoted)")
        return rows.first?.first.flatMap { Int($0) } ?? 0
    }

    func columnInfo(_ table: String) throws -> [ColumnInfo] {
        guard let quoted = QuickNoteDatabase.quote(table) else {
            throw QuickNoteDatabaseError.unsupported("Refusing to inspect table \(table).")
        }
        var statement: OpaquePointer?
        try prepare("PRAGMA table_info(\(quoted))", statement: &statement)
        guard let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var columns: [ColumnInfo] = []
        while try step(statement) {
            columns.append(ColumnInfo(name: text(statement, 1), type: text(statement, 2)))
        }
        return columns
    }

    func sampleTypes(id: String, content: String) throws -> SampleTypes {
        guard let idName = QuickNoteDatabase.quote(id), let contentName = QuickNoteDatabase.quote(content) else {
            throw QuickNoteDatabaseError.unsupported("Refusing to read note columns.")
        }
        let sql = "SELECT typeof(\(idName)), typeof(\(contentName)) FROM notes LIMIT 1"
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        guard let statement else { return SampleTypes(idType: nil, contentType: nil) }
        defer { sqlite3_finalize(statement) }
        guard try step(statement) else { return SampleTypes(idType: nil, contentType: nil) }
        return SampleTypes(idType: text(statement, 0), contentType: text(statement, 1))
    }

    func notes(columns: NoteColumns) throws -> [QuickNoteNote] {
        guard let id = QuickNoteDatabase.quote(columns.id),
              let content = QuickNoteDatabase.quote(columns.content)
        else { throw QuickNoteDatabaseError.unsupported("Refusing to read note columns.") }
        var fields = ["\(id)", "\(content)"]
        func append(_ name: String?) -> Bool {
            guard let name, let quoted = QuickNoteDatabase.quote(name) else { return false }
            fields.append(quoted)
            return true
        }
        let hasCreated = append(columns.created)
        let hasModified = append(columns.modified)
        let hasSlot = append(columns.slotIndex)
        let hasSlotted = append(columns.slotted)
        var sql = "SELECT \(fields.joined(separator: ", ")) FROM notes"
        var filters: [String] = []
        if let deleted = columns.deleted, let quoted = QuickNoteDatabase.quote(deleted) {
            filters.append("(\(quoted) IS NULL OR \(quoted) = 0)")
        }
        if !filters.isEmpty {
            sql += " WHERE " + filters.joined(separator: " AND ")
        }
        if hasModified, let modified = columns.modified, let quoted = QuickNoteDatabase.quote(modified) {
            sql += " ORDER BY \(quoted) DESC"
        }
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        guard let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var notes: [QuickNoteNote] = []
        var totalBytes = 0
        while try step(statement) {
            try Task.checkCancellation()
            var index: Int32 = 2
            let created = hasCreated ? QuickNoteTimestamp.date(from: value(statement, index)) : nil
            if hasCreated { index += 1 }
            let modified = hasModified ? QuickNoteTimestamp.date(from: value(statement, index)) : nil
            if hasModified { index += 1 }
            let slotIndex = hasSlot ? int(statement, index) : nil
            if hasSlot { index += 1 }
            let slotted = hasSlotted ? int(statement, index) : 1
            let slot = slotted == 0 ? nil : slotIndex
            totalBytes += Int(sqlite3_column_bytes(statement, 1))
            guard totalBytes <= 100 * 1_024 * 1_024 else { throw QuickNoteDatabaseError.unsupported("Import exceeds 100 MiB of note text.") }
            guard sqlite3_column_bytes(statement, 1) <= QuickNoteDatabase.contentLimit else {
                throw QuickNoteDatabaseError.unsupported("An imported note exceeds the 2 MB note limit.")
            }
            guard notes.count < 50_000 else { throw QuickNoteDatabaseError.unsupported("Import supports 50,000 notes at once.") }
            guard [SQLITE_TEXT, SQLITE_NULL].contains(sqlite3_column_type(statement, 1)) else {
                throw QuickNoteDatabaseError.unsupported("An Antinote note is not stored as plain text.")
            }
            let noteID = sqlite3_column_type(statement, 0) == SQLITE_INTEGER ? text(statement, 0) : identifier(statement, 0)
            guard let noteID, !noteID.isEmpty else { throw QuickNoteDatabaseError.unsupported("An Antinote note has an unsupported identifier.") }
            notes.append(QuickNoteNote(
                id: noteID,
                content: text(statement, 1),
                created: created,
                modified: modified,
                slot: slot
            ))
        }
        return notes
    }

    func legacyNotes(available: Set<String>) throws -> [QuickNoteNote] {
        var sql = "SELECT ZID, ZCONTENT"
        let hasCreated = available.contains("ZCREATED")
        let hasModified = available.contains("ZLASTMODIFIED")
        let hasSlot = available.contains("ZSLOTINDEX")
        let hasSlotted = available.contains("ZISSLOTTED")
        if hasCreated { sql += ", ZCREATED" }
        if hasModified { sql += ", ZLASTMODIFIED" }
        if hasSlot { sql += ", ZSLOTINDEX" }
        if hasSlotted { sql += ", ZISSLOTTED" }
        sql += " FROM ZNOTE"
        if available.contains("ZSOFTDELETED") {
            sql += " WHERE ZSOFTDELETED IS NULL OR ZSOFTDELETED = 0"
        }
        if hasModified { sql += " ORDER BY ZLASTMODIFIED DESC" }
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        guard let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var notes: [QuickNoteNote] = []
        var totalBytes = 0
        while try step(statement) {
            try Task.checkCancellation()
            guard let id = identifier(statement, 0) else { continue }
            var index: Int32 = 2
            let created = hasCreated ? QuickNoteTimestamp.date(from: value(statement, index)) : nil
            if hasCreated { index += 1 }
            let modified = hasModified ? QuickNoteTimestamp.date(from: value(statement, index)) : nil
            if hasModified { index += 1 }
            let slotIndex = hasSlot ? int(statement, index) : nil
            if hasSlot { index += 1 }
            let slotted = hasSlotted ? int(statement, index) : 1
            totalBytes += Int(sqlite3_column_bytes(statement, 1))
            guard totalBytes <= 100 * 1_024 * 1_024 else { throw QuickNoteDatabaseError.unsupported("Import exceeds 100 MiB of note text.") }
            guard sqlite3_column_bytes(statement, 1) <= QuickNoteDatabase.contentLimit else {
                throw QuickNoteDatabaseError.unsupported("An imported note exceeds the 2 MB note limit.")
            }
            guard notes.count < 50_000 else { throw QuickNoteDatabaseError.unsupported("Import supports 50,000 notes at once.") }
            guard [SQLITE_TEXT, SQLITE_NULL].contains(sqlite3_column_type(statement, 1)) else {
                throw QuickNoteDatabaseError.unsupported("An Antinote note is not stored as plain text.")
            }
            notes.append(QuickNoteNote(
                id: id,
                content: text(statement, 1),
                created: created,
                modified: modified,
                slot: slotted == 0 ? nil : slotIndex
            ))
        }
        return notes
    }

    func noteRow(columns: NoteColumns, id: String) throws -> StoredRow? {
        guard let idName = QuickNoteDatabase.quote(columns.id),
              let contentName = QuickNoteDatabase.quote(columns.content)
        else { throw QuickNoteDatabaseError.unsupported("Refusing to read this note.") }
        let modifiedSQL: String
        if let modified = columns.modified, let quoted = QuickNoteDatabase.quote(modified) {
            modifiedSQL = quoted
        } else {
            modifiedSQL = "NULL"
        }
        var statement: OpaquePointer?
        try prepare(
            "SELECT \(contentName), \(modifiedSQL) FROM notes WHERE \(idName) = ? LIMIT 1",
            statement: &statement
        )
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, id: id)
        guard try step(statement) else { return nil }
        return StoredRow(content: text(statement, 0), modifiedRaw: value(statement, 1))
    }

    func updateNote(columns: NoteColumns, id: String, content: String, modified: SQLValue?) throws {
        guard let idName = QuickNoteDatabase.quote(columns.id),
              let contentName = QuickNoteDatabase.quote(columns.content)
        else { throw QuickNoteDatabaseError.unsupported("Refusing to write this note.") }
        var assignments = ["\(contentName) = ?"]
        let writeModified = modified != nil && modified != .null
        if writeModified, let modifiedName = columns.modified, let quoted = QuickNoteDatabase.quote(modifiedName) {
            assignments.append("\(quoted) = ?")
        }
        var statement: OpaquePointer?
        try prepare(
            "UPDATE notes SET \(assignments.joined(separator: ", ")) WHERE \(idName) = ?",
            statement: &statement
        )
        guard let statement else { return }
        defer { sqlite3_finalize(statement) }
        try bind(statement, index: 1, value: .text(content))
        var next: Int32 = 2
        if writeModified, let modified, assignments.count == 2 {
            try bind(statement, index: next, value: modified)
            next += 1
        }
        try bind(statement, index: next, id: id)
        _ = try step(statement)
    }

    func storageType(table: String, column: String) throws -> String? {
        guard let tableName = QuickNoteDatabase.quote(table),
              let columnName = QuickNoteDatabase.quote(column)
        else { return nil }
        var statement: OpaquePointer?
        try prepare(
            "SELECT typeof(\(columnName)) FROM \(tableName) WHERE \(columnName) IS NOT NULL LIMIT 1",
            statement: &statement
        )
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard try step(statement) else { return nil }
        let kind = text(statement, 0)
        return kind.isEmpty ? nil : kind
    }

    func updateLegacyNote(id: String, content: String, baseline: String, now: Date) throws -> QuickNoteSaveResult {
        let names = Set(try columnInfo("ZNOTE").map(\.name))
        guard names.contains("ZID"), names.contains("ZCONTENT") else {
            throw QuickNoteDatabaseError.unsupported("This Antinote database has no editable note text.")
        }
        let idType = try storageType(table: "ZNOTE", column: "ZID")
        try execute("BEGIN IMMEDIATE")
        do {
            guard let row = try legacyStoredRow(id: id, idType: idType, names: names) else {
                try execute("ROLLBACK")
                return .missingNote
            }
            guard row.content == baseline else {
                try execute("ROLLBACK")
                return .conflict(current: row.content)
            }
            let modified = legacyModifiedValue(now, like: row.modifiedRaw, available: names.contains("ZLASTMODIFIED"))
            try writeLegacyNote(
                id: id,
                idType: idType,
                content: content,
                baseline: baseline,
                modified: modified,
                names: names
            )
            guard changedRows == 1 else {
                let current = try legacyStoredRow(id: id, idType: idType, names: names)
                try execute("ROLLBACK")
                if let current, current.content != baseline {
                    return .conflict(current: current.content)
                }
                return .missingNote
            }
            try execute("COMMIT")
            return .saved(modified: modified.flatMap(QuickNoteTimestamp.date(from:)))
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func legacyStoredRow(id: String, idType: String?, names: Set<String>) throws -> StoredRow? {
        let modifiedSQL = names.contains("ZLASTMODIFIED") ? "ZLASTMODIFIED" : "NULL"
        var statement: OpaquePointer?
        try prepare(
            "SELECT ZCONTENT, \(modifiedSQL) FROM ZNOTE WHERE ZID = ? LIMIT 1",
            statement: &statement
        )
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        try bindIdentity(statement, index: 1, id: id, idType: idType)
        guard try step(statement) else { return nil }
        return StoredRow(content: text(statement, 0), modifiedRaw: value(statement, 1))
    }

    private func writeLegacyNote(
        id: String,
        idType: String?,
        content: String,
        baseline: String,
        modified: SQLValue?,
        names: Set<String>
    ) throws {
        var assignments = ["ZCONTENT = ?"]
        let writeModified = modified != nil && modified != .null && names.contains("ZLASTMODIFIED")
        if writeModified {
            assignments.append("ZLASTMODIFIED = ?")
        }
        if names.contains("Z_OPT") {
            assignments.append("Z_OPT = IFNULL(Z_OPT, 0) + 1")
        }
        var statement: OpaquePointer?
        try prepare(
            "UPDATE ZNOTE SET \(assignments.joined(separator: ", ")) WHERE ZID = ? AND ZCONTENT = ?",
            statement: &statement
        )
        guard let statement else { return }
        defer { sqlite3_finalize(statement) }
        var index: Int32 = 1
        try bind(statement, index: index, value: .text(content))
        index += 1
        if writeModified, let modified {
            try bind(statement, index: index, value: modified)
            index += 1
        }
        try bindIdentity(statement, index: index, id: id, idType: idType)
        index += 1
        try bind(statement, index: index, value: .text(baseline))
        _ = try step(statement)
    }

    private func legacyModifiedValue(_ date: Date, like sample: SQLValue, available: Bool) -> SQLValue? {
        guard available else { return nil }
        if let stored = QuickNoteTimestamp.stored(date, like: sample) {
            return stored
        }
        if sample == .null {
            return .real(date.timeIntervalSinceReferenceDate)
        }
        return nil
    }

    private func bindIdentity(_ statement: OpaquePointer, index: Int32, id: String, idType: String?) throws {
        if idType == "blob" {
            guard let bytes = uuidBytes(id) else {
                throw QuickNoteDatabaseError.unsupported("This note’s identifier could not be matched.")
            }
            let code = bytes.withUnsafeBytes { raw in
                sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(raw.count), transient)
            }
            try check(code, detail: "Could not bind note id.")
            return
        }
        try bind(statement, index: index, id: id)
    }

    private func uuidBytes(_ id: String) -> [UInt8]? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &error)
        let detail = error.map { String(cString: $0) }
        sqlite3_free(error)
        try check(code, detail: detail)
    }

    private func queryRows(_ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        guard let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while try step(statement) {
            let count = sqlite3_column_count(statement)
            rows.append((0..<count).map { text(statement, $0) })
        }
        return rows
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        try check(code, detail: String(cString: sqlite3_errmsg(handle)))
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        let code = sqlite3_step(statement)
        if code == SQLITE_ROW { return true }
        if code == SQLITE_DONE { return false }
        try check(code, detail: String(cString: sqlite3_errmsg(handle)))
        return false
    }

    private func bind(_ statement: OpaquePointer, index: Int32, id: String) throws {
        if let number = Int64(id), id.allSatisfy(\.isNumber) {
            try check(sqlite3_bind_int64(statement, index, number), detail: "Could not bind note id.")
        } else {
            try bind(statement, index: index, value: .text(id))
        }
    }

    private func bind(_ statement: OpaquePointer, index: Int32, value: SQLValue) throws {
        let code: Int32
        switch value {
        case .text(let text):
            code = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
        case .integer(let number):
            code = sqlite3_bind_int64(statement, index, number)
        case .real(let number):
            code = sqlite3_bind_double(statement, index, number)
        case .null:
            code = sqlite3_bind_null(statement, index)
        }
        try check(code, detail: "Could not bind a note value.")
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func int(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func value(_ statement: OpaquePointer, _ index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(text(statement, index))
        default:
            return .null
        }
    }

    private func identifier(_ statement: OpaquePointer, _ index: Int32) -> String? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_TEXT:
            let value = text(statement, index)
            return value.isEmpty ? nil : value
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count == 16, let pointer = sqlite3_column_blob(statement, index) else { return nil }
            let bytes = UnsafeRawBufferPointer(start: pointer, count: count)
            let uuid = UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
            return uuid.uuidString
        default:
            return nil
        }
    }

    private func check(_ code: Int32, detail: String?) throws {
        if code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW { return }
        if code == SQLITE_BUSY || code == SQLITE_LOCKED {
            throw QuickNoteDatabaseError.busy
        }
        throw QuickNoteDatabaseError.sqlite(detail ?? "SQLite error \(code).")
    }

    private static func openError(code: Int32, detail: String, writing: Bool) -> QuickNoteDatabaseError {
        let lowered = detail.lowercased()
        if code == SQLITE_AUTH || code == SQLITE_PERM
            || lowered.contains("not permitted")
            || lowered.contains("authorization")
            || lowered.contains("operation not permitted") {
            return .permission(detail)
        }
        if code == SQLITE_CANTOPEN {
            return .permission(detail)
        }
        return .sqlite(writing ? "Could not open Antinote’s database for editing. \(detail)" : detail)
    }
}
