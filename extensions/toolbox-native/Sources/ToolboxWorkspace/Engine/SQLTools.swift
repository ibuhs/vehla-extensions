import Foundation
import SQLite3

actor SQLTools {
    private let cli = CLIProcessRunner()

    func run(_ request: ToolRequest) async throws -> ToolOutput {
        switch request.toolID {
        case "sql.formatter", "sql.beautifier":
            let sql = try resolveSQLScript(request)
            return ToolOutput(CodeFormatters.sql(sql), meta: sourceMeta(request, sql: sql))
        case "sql.runner":
            return try query(request, mode: .run)
        case "sql.sqliteBrowser":
            return try browse(request)
        case "sql.sqliteEditor":
            return try query(request, mode: .edit)
        case "sql.sqliteDiff":
            return try diffDatabases(request)
        case "sql.csvImport":
            return try csvImport(request)
        case "sql.csvExport":
            return try csvExport(request)
        case "sql.er":
            return try erDiagram(request)
        case "sql.mongo":
            return try await mongoHelper(request)
        case "sql.postgres":
            return try await remoteHelper(request, cliNames: ["psql"], dialect: "postgresql")
        case "sql.mysql":
            return try await remoteHelper(request, cliNames: ["mysql"], dialect: "mysql")
        case "sql.redis", "sql.redisKeys", "sql.redisTTL":
            return try await redis(request)
        case "sql.explain":
            return try explain(request)
        case "sql.migrations":
            return try migrations(request)
        case "sql.schemaCompare":
            return try schemaCompare(request)
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private enum QueryMode { case run, edit }

    /// Loads SQL from the editor, an explicit `sqlPath`, or a `.sql` path pasted as input.
    /// Editor text wins when it contains SQL (so edits after Load .sql are honored).
    private func resolveSQLScript(_ request: ToolRequest) throws -> String {
        let primary = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let sqlPath = (request.options["sqlPath"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !primary.isEmpty, !looksLikeExistingSQLFilePath(primary) {
            return primary
        }
        if !sqlPath.isEmpty {
            return try readTextFile(sqlPath, label: "SQL file")
        }
        if looksLikeExistingSQLFilePath(primary) {
            return try readTextFile(primary, label: "SQL file")
        }
        throw ToolError.invalidInput("Enter SQL, paste a .sql file path, or set sqlPath.")
    }

    private func sourceMeta(_ request: ToolRequest, sql: String) -> String {
        let sqlPath = (request.options["sqlPath"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sqlPath.isEmpty { return "from \(URL(fileURLWithPath: sqlPath).lastPathComponent)" }
        if looksLikeExistingSQLFilePath(primary) {
            return "from \(URL(fileURLWithPath: primary).lastPathComponent)"
        }
        return "\(sql.utf8.count) bytes"
    }

    private func looksLikeExistingSQLFilePath(_ value: String) -> Bool {
        guard value.lowercased().hasSuffix(".sql"),
              !value.contains("\n"),
              value.count < 1_024
        else { return false }
        return FileManager.default.isReadableFile(atPath: value)
    }

    private func isSQLFile(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".sql")
    }

    private func readTextFile(_ path: String, label: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw ToolError.invalidInput("\(label) not found: \(path)")
        }
        let data = try Data(contentsOf: url)
        try ToolLimits.guardSize(String(decoding: data, as: UTF8.self), label: label)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.invalidInput("\(label) is not valid UTF-8.")
        }
        return text
    }

    private func dbPath(_ request: ToolRequest) throws -> String {
        let path = (request.options["dbPath"] ?? request.secondary).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ToolError.invalidInput("Set dbPath to a SQLite database (.db/.sqlite) or .sql dump where supported.")
        }
        return path
    }

    private func open(_ path: String, readonly: Bool = false) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = readonly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            throw ToolError.failed("Could not open SQLite database at \(path)")
        }
        return db
    }

    private func openMemory() throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            ":memory:",
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK, let db else {
            throw ToolError.failed("Could not open in-memory SQLite database.")
        }
        return db
    }

    /// Opens a `.db`/`.sqlite` file, or loads a `.sql` dump into a fresh in-memory database.
    private func openDatabase(at path: String, readonly: Bool) throws -> (db: OpaquePointer, meta: String) {
        if isSQLFile(path) {
            let db = try openMemory()
            let dump = try readTextFile(path, label: "SQL dump")
            do {
                try exec(db, sql: dump)
            } catch {
                sqlite3_close(db)
                throw ToolError.failed(
                    "Failed to load SQL dump into memory: \(error.localizedDescription)"
                )
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            return (db, "loaded \(name) → memory")
        }
        return (try open(path, readonly: readonly), URL(fileURLWithPath: path).lastPathComponent)
    }

    private func browse(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        if isSQLFile(path) {
            let sql = try readTextFile(path, label: "SQL dump")
            let statements = sql
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var lines = [
                "SQL file: \(path)",
                "statements: \(statements.count)",
                "bytes: \(sql.utf8.count)",
                "",
                "Preview (formatted):",
                CodeFormatters.sql(String(statements.prefix(20).joined(separator: ";\n") + (statements.count > 20 ? ";" : ""))),
            ]
            if statements.count > 20 {
                lines.append("")
                lines.append("… \(statements.count - 20) more statements omitted from preview")
            }
            return ToolOutput(lines.joined(separator: "\n"), meta: "sql dump")
        }
        let db = try open(path, readonly: true)
        defer { sqlite3_close(db) }
        let tables = try columnQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        var lines = ["Database: \(path)", "Tables (\(tables.count)):"]
        for table in tables {
            let name = table["name"] ?? ""
            let countRows = try columnQuery(db, sql: "SELECT COUNT(*) AS c FROM \"\(name)\"")
            let count = countRows.first?["c"] ?? "0"
            let cols = try columnQuery(db, sql: "PRAGMA table_info(\"\(name)\")")
            let colList = cols.map { $0["name"] ?? "?" }.joined(separator: ", ")
            lines.append("• \(name)  (\(count) rows)  [\(colList)]")
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }

    private func query(_ request: ToolRequest, mode: QueryMode) throws -> ToolOutput {
        let path = try dbPath(request)
        let sql = try resolveSQLScript(request)
        // `.sql` in dbPath = load dump into memory, then run the editor/sqlPath query.
        let opened = try openDatabase(
            at: path,
            readonly: !isSQLFile(path) && mode == .run && isReadOnlySQL(sql)
        )
        let db = opened.db
        defer { sqlite3_close(db) }
        if isReadOnlySQL(sql) {
            let rows = try columnQuery(db, sql: sql)
            return ToolOutput(
                formatRows(rows),
                meta: "\(rows.count) rows · \(opened.meta)"
            )
        }
        try exec(db, sql: sql)
        let label = mode == .edit ? "editor" : "runner"
        return ToolOutput("OK — statement executed.", meta: "\(label) · \(opened.meta)")
    }

    private func isReadOnlySQL(_ sql: String) -> Bool {
        let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return head.hasPrefix("select") || head.hasPrefix("with") || head.hasPrefix("pragma") || head.hasPrefix("explain")
    }

    private func csvImport(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        let table = request.options["table"] ?? "imported"
        let csv = request.primary
        let rows = parseCSV(csv)
        guard let header = rows.first, header.count > 0 else {
            throw ToolError.invalidInput("CSV is empty.")
        }
        let db = try open(path)
        defer { sqlite3_close(db) }
        let cols = header.map { sanitizeIdent($0) }
        let create = "CREATE TABLE IF NOT EXISTS \"\(sanitizeIdent(table))\" (\(cols.map { "\"\($0)\" TEXT" }.joined(separator: ", ")))"
        try exec(db, sql: create)
        try exec(db, sql: "BEGIN")
        for row in rows.dropFirst() {
            let values = cols.indices.map { index -> String in
                let value = index < row.count ? row[index] : ""
                return sqlLiteral(value)
            }.joined(separator: ", ")
            try exec(
                db,
                sql: "INSERT INTO \"\(sanitizeIdent(table))\" (\(cols.map { "\"\($0)\"" }.joined(separator: ", "))) VALUES (\(values))"
            )
        }
        try exec(db, sql: "COMMIT")
        return ToolOutput("Imported \(rows.count - 1) rows into \(table).", meta: path)
    }

    private func csvExport(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        if isSQLFile(path) {
            throw ToolError.invalidInput("CSV export needs a SQLite database in dbPath.")
        }
        let table = request.options["table"] ?? ""
        let sql: String
        if !table.isEmpty {
            sql = "SELECT * FROM \"\(sanitizeIdent(table))\""
        } else {
            sql = try resolveSQLScript(request)
        }
        let db = try open(path, readonly: true)
        defer { sqlite3_close(db) }
        let rows = try columnQuery(db, sql: sql)
        guard let first = rows.first else { return ToolOutput("", meta: "0 rows") }
        let keys = Array(first.keys).sorted()
        var lines = [keys.joined(separator: ",")]
        for row in rows {
            lines.append(keys.map { csvEscape(row[$0] ?? "") }.joined(separator: ","))
        }
        return ToolOutput(lines.joined(separator: "\n"), meta: "\(rows.count) rows")
    }

    private func erDiagram(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        let db = try open(path, readonly: true)
        defer { sqlite3_close(db) }
        let tables = try columnQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        var lines = ["erDiagram"]
        for table in tables {
            let name = table["name"] ?? "table"
            lines.append("  \(sanitizeIdent(name)) {")
            let cols = try columnQuery(db, sql: "PRAGMA table_info(\"\(name)\")")
            for col in cols {
                let colName = col["name"] ?? "col"
                let type = (col["type"] ?? "TEXT").replacingOccurrences(of: " ", with: "_")
                let pk = col["pk"] == "1" ? " PK" : ""
                lines.append("    \(type) \(sanitizeIdent(colName))\(pk)")
            }
            lines.append("  }")
            let fks = try columnQuery(db, sql: "PRAGMA foreign_key_list(\"\(name)\")")
            for fk in fks {
                let target = fk["table"] ?? "other"
                lines.append("  \(sanitizeIdent(name)) }o--|| \(sanitizeIdent(target)) : \"\(fk["from"] ?? "")\"")
            }
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }

    private func explain(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        let sql = try resolveSQLScript(request)
        let opened = try openDatabase(at: path, readonly: !isSQLFile(path))
        let db = opened.db
        defer { sqlite3_close(db) }
        let rows = try columnQuery(db, sql: "EXPLAIN QUERY PLAN \(sql)")
        let viz = renderExplainPlan(rows)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"/>
        <style>
          body { font: 13px/1.45 ui-monospace, Menlo, monospace; margin: 1rem; background: #0b1220; color: #e2e8f0; }
          .node { margin: 0.35rem 0; padding: 0.45rem 0.6rem; border-left: 3px solid #38bdf8; background: #111827; border-radius: 6px; }
          .meta { color: #94a3b8; font-size: 11px; }
          h1 { font: 600 15px ui-sans-serif, system-ui; }
        </style></head><body>
        <h1>QUERY PLAN</h1>
        \(rows.map { row in
            let id = row["id"] ?? "?"
            let parent = row["parent"] ?? "?"
            let detail = row["detail"] ?? ""
            return "<div class=\"node\"><div class=\"meta\">id \(id) · parent \(parent)</div>\(htmlEscape(detail))</div>"
        }.joined())
        </body></html>
        """
        return ToolOutput(viz, meta: "explain · \(opened.meta)", previewHTML: html)
    }

    private func renderExplainPlan(_ rows: [[String: String]]) -> String {
        guard !rows.isEmpty else { return "Empty query plan." }
        var children: [String: [[String: String]]] = [:]
        var roots: [[String: String]] = []
        for row in rows {
            let parent = row["parent"] ?? "0"
            if parent == "0" || parent.isEmpty {
                roots.append(row)
            } else {
                children[parent, default: []].append(row)
            }
        }
        if roots.isEmpty { roots = rows }

        var lines = ["QUERY PLAN", ""]
        var mermaid = ["flowchart TD"]
        func walk(_ row: [String: String], depth: Int) {
            let id = row["id"] ?? "?"
            let detail = row["detail"] ?? "(no detail)"
            let pad = String(repeating: "  ", count: depth)
            let branch = depth == 0 ? "•" : "└─"
            lines.append("\(pad)\(branch) [\(id)] \(detail)")
            let safeDetail = detail
                .replacingOccurrences(of: "\"", with: "'")
                .prefix(48)
            mermaid.append("  n\(id)[\"\(id): \(safeDetail)\"]")
            if let parent = row["parent"], parent != "0", !parent.isEmpty {
                mermaid.append("  n\(parent) --> n\(id)")
            }
            for child in children[id] ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        for root in roots { walk(root, depth: 0) }
        lines.append("")
        lines.append("Mermaid:")
        lines.append(contentsOf: mermaid)
        lines.append("")
        lines.append("Raw rows:")
        lines.append(formatRows(rows))
        return lines.joined(separator: "\n")
    }

    private func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func migrations(_ request: ToolRequest) throws -> ToolOutput {
        let path = try dbPath(request)
        if isSQLFile(path) {
            let sql = try readTextFile(path, label: "SQL migration/dump")
            return ToolOutput(CodeFormatters.sql(sql), meta: "sql file")
        }
        let db = try open(path, readonly: true)
        defer { sqlite3_close(db) }
        let rows = try columnQuery(
            db,
            sql: """
            SELECT type, name, tbl_name, sql
            FROM sqlite_master
            WHERE sql IS NOT NULL
            ORDER BY type, name
            """
        )
        if rows.isEmpty { return ToolOutput("No schema objects found.") }
        var lines: [String] = []
        for row in rows {
            lines.append("-- \(row["type"] ?? "?") \(row["name"] ?? "?")")
            lines.append(row["sql"] ?? "")
            lines.append("")
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }

    private func schemaCompare(_ request: ToolRequest) throws -> ToolOutput {
        let leftPath = try dbPath(request)
        let rightPath = (request.options["otherDbPath"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rightPath.isEmpty else {
            throw ToolError.invalidInput("Set otherDbPath to the second SQLite database or .sql dump.")
        }
        let left = try schemaDump(leftPath)
        let right = try schemaDump(rightPath)
        return ToolOutput(TextDiff.lineDiff(left, right), meta: "schema diff")
    }

    private func diffDatabases(_ request: ToolRequest) throws -> ToolOutput {
        try schemaCompare(request)
    }

    private func schemaDump(_ path: String) throws -> String {
        if isSQLFile(path) {
            return try CodeFormatters.sql(readTextFile(path, label: "SQL dump"))
        }
        let db = try open(path, readonly: true)
        defer { sqlite3_close(db) }
        let rows = try columnQuery(
            db,
            sql: "SELECT type || ' ' || name || char(10) || COALESCE(sql, '') AS chunk FROM sqlite_master ORDER BY type, name"
        )
        return rows.map { $0["chunk"] ?? "" }.joined(separator: "\n\n")
    }

    private func mongoHelper(_ request: ToolRequest) async throws -> ToolOutput {
        let collection = request.options["collection"] ?? "items"
        let filter = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let filterJSON = filter.isEmpty ? "{}" : filter
        let snippets = [
            "// MongoDB query builder output",
            "db.getCollection(\"\(collection)\").find(\(filterJSON))",
            "db.getCollection(\"\(collection)\").find(\(filterJSON)).limit(50)",
            "db.getCollection(\"\(collection)\").aggregate([{ $match: \(filterJSON) }])",
        ].joined(separator: "\n")
        let url = (request.options["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            return ToolOutput(snippets + "\n\n// Set url (mongodb://…) and re-run to execute via mongosh.", meta: "snippets")
        }
        let shell: String?
        if let mongosh = await cli.which("mongosh") {
            shell = mongosh
        } else {
            shell = await cli.which("mongo")
        }
        guard let shell else {
            return ToolOutput(
                snippets + "\n\n// mongosh/mongo not found on PATH. Snippets only.",
                meta: "snippets"
            )
        }
        let evalJS = "db.getCollection(\"\(collection)\").find(\(filterJSON)).limit(50).toArray()"
        let result = try await cli.run(
            executable: shell,
            arguments: [url, "--quiet", "--eval", evalJS],
            timeoutSeconds: 30
        )
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if result.exitCode != 0 {
            throw ToolError.failed(body.isEmpty ? "mongosh failed." : body)
        }
        return ToolOutput(
            [snippets, "", "--- mongosh result ---", body].joined(separator: "\n"),
            meta: URL(fileURLWithPath: shell).lastPathComponent
        )
    }

    private func remoteHelper(
        _ request: ToolRequest,
        cliNames: [String],
        dialect: String
    ) async throws -> ToolOutput {
        let hasSQLInput = !request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(request.options["sqlPath"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sql = hasSQLInput
            ? try resolveSQLScript(request)
            : (dialect == "postgresql" ? "SELECT version();" : "SELECT VERSION();")
        let url = (request.options["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let examples = dialect == "postgresql"
            ? [
                "Connection examples (url option):",
                "  postgres://user:pass@localhost:5432/dbname",
                "  postgresql://user@localhost/dbname",
                "  host=localhost port=5432 dbname=app user=app",
                "",
                "Useful starter queries:",
                "  SELECT current_database(), current_user;",
                "  \\dt",
                "  EXPLAIN ANALYZE SELECT 1;",
            ]
            : [
                "Connection examples (url option = database name, or host args via mysql defaults):",
                "  mydb",
                "  -h 127.0.0.1 -P 3306 -u root mydb  (put host flags in primary if needed)",
                "",
                "Set password option for MYSQL_PWD when needed.",
                "",
                "Useful starter queries:",
                "  SELECT VERSION(), DATABASE(), USER();",
                "  SHOW TABLES;",
                "  EXPLAIN SELECT 1;",
            ]

        for name in cliNames {
            guard let path = await cli.which(name) else { continue }
            if url.isEmpty {
                return ToolOutput(
                    ([
                        "Found \(name) at \(path).",
                        "Set the url option, then Run to execute against a live database.",
                        "",
                    ] + examples + [
                        "",
                        "Formatted \(dialect) SQL ready to run:",
                        CodeFormatters.sql(sql),
                    ]).joined(separator: "\n"),
                    meta: "\(name) helper"
                )
            }
            if name == "psql" {
                let result = try await cli.run(
                    executable: path,
                    arguments: [url, "-v", "ON_ERROR_STOP=1", "-c", sql]
                )
                let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                if result.exitCode != 0 { throw ToolError.failed(body) }
                return ToolOutput(body, meta: "psql")
            }
            if name == "mysql" {
                let result = try await cli.run(
                    executable: path,
                    arguments: ["--execute", sql] + (url.isEmpty ? [] : [url]),
                    environment: ["MYSQL_PWD": request.options["password"] ?? ""]
                )
                let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                if result.exitCode != 0 { throw ToolError.failed(body) }
                return ToolOutput(body, meta: "mysql")
            }
        }
        return ToolOutput(
            ([
                "No \(cliNames.joined(separator: "/")) client on PATH.",
                "Install the client, or use this as an offline SQL formatter/helper.",
                "",
            ] + examples + [
                "",
                "Formatted \(dialect) SQL:",
                CodeFormatters.sql(sql),
            ]).joined(separator: "\n"),
            meta: "offline helper"
        )
    }

    private func redis(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.options["host"] ?? "127.0.0.1"
        let port = request.options["port"] ?? "6379"
        let key = (request.options["key"] ?? request.primary).trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = request.options["pattern"] ?? "*"
        let command = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let redis = await cli.which("redis-cli") else {
            return ToolOutput(
                [
                    "redis-cli not found on PATH.",
                    "Offline helper for \(host):\(port)",
                    "",
                    "Common commands:",
                    "  PING",
                    "  INFO keyspace",
                    "  SCAN 0 MATCH \(pattern) COUNT 100",
                    "  KEYS \(pattern)",
                    "  TYPE \(key.isEmpty ? "mykey" : key)",
                    "  TTL \(key.isEmpty ? "mykey" : key)",
                    "  GET \(key.isEmpty ? "mykey" : key)",
                    "",
                    "Suggested next command:",
                    command.isEmpty ? "PING" : command,
                    "",
                    "Tip: prefer SCAN over KEYS on production instances.",
                ].joined(separator: "\n"),
                meta: "offline helper"
            )
        }
        var args = ["-h", host, "-p", port]
        if let password = request.options["password"], !password.isEmpty {
            args += ["-a", password]
        }
        switch request.toolID {
        case "sql.redisKeys":
            // Prefer SCAN when available; fall back to KEYS for tiny local DBs.
            args.append(contentsOf: ["--scan", "--pattern", pattern])
        case "sql.redisTTL":
            args.append(contentsOf: ["TTL", key.isEmpty ? "mykey" : key])
        default:
            let parts = command.split(separator: " ").map(String.init)
            args.append(contentsOf: parts.isEmpty ? ["PING"] : parts)
        }
        let result = try await cli.run(executable: redis, arguments: args)
        var body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if result.exitCode != 0 {
            // Older redis-cli without --scan
            if request.toolID == "sql.redisKeys" {
                var fallback = ["-h", host, "-p", port]
                if let password = request.options["password"], !password.isEmpty {
                    fallback += ["-a", password]
                }
                fallback += ["KEYS", pattern]
                let retry = try await cli.run(executable: redis, arguments: fallback)
                body = [retry.stdout, retry.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
                if retry.exitCode != 0 { throw ToolError.failed(body) }
                return ToolOutput(
                    ["# KEYS fallback (SCAN unavailable)", body].joined(separator: "\n"),
                    meta: "redis-cli KEYS"
                )
            }
            throw ToolError.failed(body)
        }
        if request.toolID == "sql.redisKeys" {
            let count = body.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }.count
            return ToolOutput(body.isEmpty ? "(no keys)" : body, meta: "SCAN \(count) keys")
        }
        return ToolOutput(body, meta: "redis-cli")
    }

    private func columnQuery(_ db: OpaquePointer, sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ToolError.failed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let count = Int(sqlite3_column_count(statement))
        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, Int32(i)))
                if let cString = sqlite3_column_text(statement, Int32(i)) {
                    row[name] = String(cString: cString)
                } else {
                    row[name] = ""
                }
            }
            rows.append(row)
            if rows.count >= 5_000 { break }
        }
        return rows
    }

    private func exec(_ db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw ToolError.failed(message)
        }
    }

    private func formatRows(_ rows: [[String: String]]) -> String {
        guard let first = rows.first else { return "(no rows)" }
        let keys = Array(first.keys).sorted()
        var lines = [keys.joined(separator: " | ")]
        lines.append(keys.map { _ in "---" }.joined(separator: " | "))
        for row in rows {
            lines.append(keys.map { row[$0] ?? "" }.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    private func sanitizeIdent(_ value: String) -> String {
        let cleaned = value.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" }
        let text = String(cleaned)
        return text.isEmpty ? "col" : text
    }

    private func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        for character in text {
            if inQuotes {
                if character == "\"" {
                    inQuotes.toggle()
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": inQuotes = true
            case ",":
                row.append(field); field = ""
            case "\n":
                row.append(field); rows.append(row); row = []; field = ""
            case "\r":
                break
            default:
                field.append(character)
            }
        }
        row.append(field)
        if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        return rows
    }
}
