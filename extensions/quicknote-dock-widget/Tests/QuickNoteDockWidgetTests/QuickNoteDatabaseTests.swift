import Foundation
import SQLite3
import Testing
@testable import QuickNoteDockWidget

@Suite struct QuickNoteDatabaseTests {
    @Test func locatePrefersNewestStableDatabaseOverLegacy() throws {
        let home = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let older = try touch(home, "com.chabomakers.Antinote/Data/Documents/notes.sqlite3", age: 20)
        _ = try touch(home, "com.chabomakers.Antinote-setapp/Data/Documents/notes.sqlite3", age: 5)
        _ = try touch(home, "com.chabomakers.Antinote/Data/Library/Application Support/cd-v1-notes.sqlite", age: 1)

        let located = try #require(QuickNoteDatabase.locate(home: home))
        #expect(located.kind == .stable)
        #expect(located.url.lastPathComponent == "notes.sqlite3")
        #expect(located.url.path.contains("Antinote-setapp"))
        #expect(located.url != older)
    }

    @Test func locateFallsBackToLegacyDatabase() throws {
        let home = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = try touch(
            home,
            "com.chabomakers.Antinote/Data/Library/Application Support/cd-v1-notes.sqlite",
            age: 0
        )
        let located = try #require(QuickNoteDatabase.locate(home: home))
        #expect(located == QuickNoteCandidate(url: legacy, kind: .legacy))
    }

    @Test func loadAndSavePreservesTimestampStyleAndUntouchedColumns() throws {
        let url = try database("""
        CREATE TABLE notes (
            id TEXT PRIMARY KEY,
            content TEXT,
            created TEXT,
            lastModified TEXT,
            pinned INTEGER
        );
        INSERT INTO notes VALUES (
            'note-1',
            'Hello\nWorld',
            '2026-01-01T00:00:00.000Z',
            '2026-02-01T00:00:00.000Z',
            1
        );
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loaded = try QuickNoteDatabase.load(url)
        #expect(loaded.canEdit)
        #expect(loaded.notes.map(\.title) == ["Hello"])
        #expect(loaded.notes.first?.preview == "World")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try QuickNoteDatabase.save(url, noteID: "note-1", content: "Hello\nUpdated", baseline: "Hello\nWorld", now: now)
        guard case .saved(let modified) = result else {
            Issue.record("Expected a saved note")
            return
        }
        #expect(abs((modified?.timeIntervalSince1970 ?? 0) - now.timeIntervalSince1970) < 1)

        let again = try QuickNoteDatabase.load(url)
        #expect(again.notes.first?.content == "Hello\nUpdated")
        let raw = try scalar(url, "SELECT lastModified || '|' || pinned FROM notes")
        #expect(raw.hasPrefix("2027-"))
        #expect(raw.hasSuffix("|1"))
    }

    @Test func saveUsesUnixAndCoreDataTimestampsFromTheExistingCell() throws {
        let unix = try database("""
        CREATE TABLE notes (id TEXT PRIMARY KEY, content TEXT, lastModified INTEGER);
        INSERT INTO notes VALUES ('a', 'one', 1700000000);
        """)
        defer { try? FileManager.default.removeItem(at: unix.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try QuickNoteDatabase.save(unix, noteID: "a", content: "two", baseline: "one", now: now)
        #expect(try scalar(unix, "SELECT lastModified FROM notes") == "1800000000")

        let coreData = try database("""
        CREATE TABLE notes (id TEXT PRIMARY KEY, content TEXT, lastModified REAL);
        INSERT INTO notes VALUES ('a', 'one', 700000000);
        """)
        defer { try? FileManager.default.removeItem(at: coreData.deletingLastPathComponent()) }
        _ = try QuickNoteDatabase.save(coreData, noteID: "a", content: "two", baseline: "one", now: now)
        let stored = try scalar(coreData, "SELECT lastModified FROM notes")
        #expect(abs((Double(stored) ?? 0) - now.timeIntervalSinceReferenceDate) < 1)
    }

    @Test func saveConflictsWhenTheNoteChanged() throws {
        let url = try database("""
        CREATE TABLE notes (id TEXT PRIMARY KEY, content TEXT, lastModified TEXT);
        INSERT INTO notes VALUES ('a', 'current', '2026-02-01T00:00:00Z');
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let result = try QuickNoteDatabase.save(url, noteID: "a", content: "mine", baseline: "stale")
        #expect(result == .conflict(current: "current"))
        #expect(try scalar(url, "SELECT content FROM notes") == "current")
    }

    @Test func softDeletedNotesStayHidden() throws {
        let url = try database("""
        CREATE TABLE notes (id TEXT PRIMARY KEY, content TEXT, lastModified TEXT, softDeleted INTEGER);
        INSERT INTO notes VALUES ('keep', 'Visible', '2026-02-01T00:00:00Z', 0);
        INSERT INTO notes VALUES ('gone', 'Hidden', '2026-03-01T00:00:00Z', 1);
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loaded = try QuickNoteDatabase.load(url)
        #expect(loaded.notes.map(\.id) == ["keep"])
    }

    @Test func legacyDatabaseReadsAndUpdatesTheNoteBody() throws {
        let url = try database("""
        CREATE TABLE ZNOTE (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZID BLOB,
            ZCONTENT TEXT,
            ZLASTMODIFIED REAL,
            ZISSLOTTED INTEGER,
            ZSOFTDELETED INTEGER,
            ZSLOTINDEX INTEGER
        );
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let uuid = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        try insertLegacy(url: url, uuid: uuid, content: "Slotted\nBody", modified: 800_000_000, slotted: 1, deleted: 0, slot: 3, optimisticLock: 4)
        try insertLegacy(url: url, uuid: UUID(), content: "Trash", modified: 800_000_100, slotted: 0, deleted: 1, slot: 0, optimisticLock: 1)

        let loaded = try QuickNoteDatabase.load(url)
        #expect(loaded.canEdit)
        #expect(loaded.editBlock == nil)
        #expect(loaded.notes.count == 1)
        #expect(loaded.notes.first?.id == uuid.uuidString)
        #expect(loaded.notes.first?.content == "Slotted\nBody")
        #expect(loaded.notes.first?.slot == 3)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try QuickNoteDatabase.save(
            url,
            noteID: uuid.uuidString.lowercased(),
            content: "Slotted\nEdited",
            baseline: "Slotted\nBody",
            now: now
        )
        guard case .saved = result else {
            Issue.record("Expected the Core Data note to save")
            return
        }
        let again = try QuickNoteDatabase.load(url)
        #expect(again.notes.first?.content == "Slotted\nEdited")
        #expect(again.notes.first?.slot == 3)
        #expect(try scalar(url, "SELECT Z_OPT FROM ZNOTE WHERE ZSLOTINDEX = 3") == "5")
        #expect(try scalar(url, "SELECT Z_ENT FROM ZNOTE WHERE ZSLOTINDEX = 3") == "7")
        let stored = try scalar(url, "SELECT ZLASTMODIFIED FROM ZNOTE WHERE ZSLOTINDEX = 3")
        #expect(abs((Double(stored) ?? 0) - now.timeIntervalSinceReferenceDate) < 1)

        let conflict = try QuickNoteDatabase.save(url, noteID: uuid.uuidString, content: "Nope", baseline: "Slotted\nBody")
        #expect(conflict == .conflict(current: "Slotted\nEdited"))
    }

    @Test func missingAndUnrecognizedDatabasesFailClearly() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString).sqlite3")
        #expect(throws: QuickNoteDatabaseError.missing) {
            try QuickNoteDatabase.load(missing)
        }
        let other = try database("CREATE TABLE folders (id TEXT);")
        defer { try? FileManager.default.removeItem(at: other.deletingLastPathComponent()) }
        #expect(throws: QuickNoteDatabaseError.self) {
            try QuickNoteDatabase.load(other)
        }
    }

    @Test func linksPercentEncodeNoteText() throws {
        let created = try #require(QuickNoteLinks.createNote(content: "Milk & bread"))
        #expect(created.scheme == "antinote")
        #expect(created.host == "x-callback-url")
        #expect(created.path == "/createNote")
        let items = try #require(URLComponents(url: created, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first?.value == "Milk & bread")

        let opened = try #require(QuickNoteLinks.open(noteID: "id with space"))
        #expect(URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "id with space")
        #expect(QuickNoteLinks.reloadDatabase()?.absoluteString == "antinote://x-callback-url/reloadDB")
        #expect(QuickNoteLinks.createNote(content: "  ")?.absoluteString == "antinote://x-callback-url/createNote")
    }

    @Test func overwriteLinkKeepsPlusAndAmpersand() throws {
        let url = try #require(QuickNoteLinks.overwriteCurrent(content: "1+1=2 & done\nnext"))
        #expect(url.path == "/overwriteCurrent")
        #expect(url.absoluteString.contains("1%2B1%3D2%20%26%20done%0Anext"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first?.value == "1+1=2 & done\nnext")
    }

    @Test func checkboxesFollowQuickNoteMarkers() {
        let text = "Groceries\n- [ ] milk\n[] eggs\n  - [x] bread\n[X]\nnot - [ ] here\n[ ]no space"
        let boxes = NoteCheckbox.find(in: text)
        let ns = text as NSString
        #expect(boxes.map { ns.substring(with: $0.marker) } == ["- [ ]", "[]", "- [x]", "[X]"])
        #expect(boxes.map(\.checked) == [false, false, true, true])
        #expect(boxes.map { ns.substring(with: $0.body) } == [" milk", " eggs", " bread", ""])

        func toggled(_ box: NoteCheckbox) -> String {
            ns.replacingCharacters(in: box.toggle.range, with: box.toggle.replacement)
        }
        #expect(toggled(boxes[0]).contains("- [x] milk"))
        #expect(toggled(boxes[1]).contains("[x] eggs"))
        #expect(toggled(boxes[2]).contains("  - [ ] bread"))
        #expect(toggled(boxes[3]).hasSuffix("[]\nnot - [ ] here\n[ ]no space"))
    }

    @Test func noteTextMatchingToleratesDisplayDifferences() {
        #expect(NoteText.same("a  b\n", "a b"))
        #expect(NoteText.matches("# Groceries\nsee example.com/…", "# Groceries\nsee https://example.com/long/path"))
        #expect(!NoteText.matches("Other note\nbody", "# Groceries\nbody"))
        #expect(!NoteText.matches("", "anything"))
    }

    @Test func quoteRejectsUnsafeIdentifiers() {
        #expect(QuickNoteDatabase.quote("lastModified") == "\"lastModified\"")
        #expect(QuickNoteDatabase.quote("content); DROP TABLE notes;--") == nil)
        #expect(QuickNoteDatabase.quote("") == nil)
    }

    @Test func launcherScriptActivatesQuickNoteAndOpensTheURL() throws {
        let url = try #require(QuickNoteLinks.open(noteID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let script = QuickNoteLauncher.script(for: url)
        #expect(script.contains("tell application id \"com.chabomakers.Antinote\" to activate"))
        #expect(script.contains("open location \"\(url.absoluteString)\""))
    }

    @Test func noteTitleStripsAMarkdownHeading() {
        let note = QuickNoteNote(id: "1", content: "## Shopping\nEggs", created: nil, modified: nil, slot: nil)
        #expect(note.title == "Shopping")
        #expect(note.preview == "Eggs")
        #expect(QuickNoteNote(id: "2", content: "   \n", created: nil, modified: nil, slot: nil).title == "Empty note")
    }
}

private func scratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("antinote-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func touch(_ home: URL, _ relative: String, age: TimeInterval) throws -> URL {
    let url = home.appendingPathComponent("Library/Containers", isDirectory: true).appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data())
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-age)],
        ofItemAtPath: url.path
    )
    return url
}

private func database(_ sql: String) throws -> URL {
    let directory = try scratchDirectory()
    let url = directory.appendingPathComponent("notes.sqlite3")
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
        throw QuickNoteDatabaseError.sqlite("Could not create the test database.")
    }
    defer { sqlite3_close(handle) }
    var error: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(handle, sql, nil, nil, &error)
    let detail = error.map { String(cString: $0) }
    sqlite3_free(error)
    if code != SQLITE_OK {
        throw QuickNoteDatabaseError.sqlite(detail ?? "Could not seed the test database.")
    }
    return url
}

private func insertLegacy(
    url: URL,
    uuid: UUID,
    content: String,
    modified: Double,
    slotted: Int,
    deleted: Int,
    slot: Int,
    optimisticLock: Int = 1
) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { return }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(
        handle,
        "INSERT INTO ZNOTE (Z_ENT, Z_OPT, ZID, ZCONTENT, ZLASTMODIFIED, ZISSLOTTED, ZSOFTDELETED, ZSLOTINDEX) VALUES (7, ?, ?, ?, ?, ?, ?, ?)",
        -1,
        &statement,
        nil
    )
    guard let statement else { return }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int(statement, 1, Int32(optimisticLock))
    let bytes = withUnsafeBytes(of: uuid.uuid) { Data($0) }
    _ = bytes.withUnsafeBytes { buffer in
        sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    _ = content.withCString { pointer in
        sqlite3_bind_text(statement, 3, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    sqlite3_bind_double(statement, 4, modified)
    sqlite3_bind_int(statement, 5, Int32(slotted))
    sqlite3_bind_int(statement, 6, Int32(deleted))
    sqlite3_bind_int(statement, 7, Int32(slot))
    sqlite3_step(statement)
}

private func scalar(_ url: URL, _ sql: String) throws -> String {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
        throw QuickNoteDatabaseError.sqlite("Could not read the test database.")
    }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
    guard let statement else { return "" }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) else { return "" }
    return String(cString: pointer)
}
