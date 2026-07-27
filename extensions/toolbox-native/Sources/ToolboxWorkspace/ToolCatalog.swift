import Foundation

enum ToolCatalog {
    static let all: [ToolDefinition] = json + encoding + crypto + date + text + code + sql + generators + web + networking

    static func tool(id: String) -> ToolDefinition? {
        all.first { $0.id == id }
    }

    static func tools(in category: ToolCategory) -> [ToolDefinition] {
        all.filter { $0.category == category }
    }

    // MARK: - JSON / Data

    private static let json: [ToolDefinition] = [
        .init(id: "json.formatter", category: .json, title: "JSON Formatter", subtitle: "Pretty-print JSON", systemImage: "text.alignleft"),
        .init(id: "json.minifier", category: .json, title: "JSON Minifier", subtitle: "Compact JSON", systemImage: "arrow.down.right.and.arrow.up.left"),
        .init(id: "json.validator", category: .json, title: "JSON Validator", subtitle: "Validate JSON syntax", systemImage: "checkmark.seal"),
        .init(id: "json.diff", category: .json, title: "JSON Diff", subtitle: "Compare two JSON documents", systemImage: "arrow.left.arrow.right", inputKind: .dualText, primaryLabel: "Left JSON", secondaryLabel: "Right JSON"),
        .init(id: "json.merge", category: .json, title: "JSON Merge", subtitle: "Deep-merge objects", systemImage: "arrow.triangle.merge", inputKind: .dualText, primaryLabel: "Base JSON", secondaryLabel: "Overlay JSON"),
        .init(id: "json.toCsv", category: .json, title: "JSON to CSV", subtitle: "Flatten an array of objects", systemImage: "tablecells"),
        .init(id: "json.fromCsv", category: .json, title: "CSV to JSON", subtitle: "Parse CSV into JSON array", systemImage: "tablecells.badge.ellipsis"),
        .init(id: "json.xml", category: .json, title: "XML ↔ JSON", subtitle: "Convert XML and JSON", systemImage: "doc.badge.gearshape", inputKind: .textAndOptions, optionKeys: ["direction"]),
        .init(id: "json.yaml", category: .json, title: "YAML ↔ JSON", subtitle: "Convert with libYAML (Yams)", systemImage: "doc.plaintext", inputKind: .textAndOptions, optionKeys: ["direction"]),
        .init(id: "json.toml", category: .json, title: "TOML Converter", subtitle: "Convert with TOMLKit", systemImage: "doc.text", inputKind: .textAndOptions, optionKeys: ["direction"]),
        .init(id: "json.ini", category: .json, title: "INI Parser", subtitle: "Parse INI into JSON", systemImage: "list.bullet.rectangle"),
        .init(id: "json.bson", category: .json, title: "BSON Viewer", subtitle: "Decode BSON hex/base64 to JSON", systemImage: "eye"),
        .init(id: "json.msgpack", category: .json, title: "MessagePack Viewer", subtitle: "Decode MessagePack hex/base64 to JSON", systemImage: "shippingbox"),
        .init(id: "json.ndjson", category: .json, title: "NDJSON Viewer", subtitle: "Validate and pretty-print NDJSON", systemImage: "list.number"),
        .init(id: "json.prettyNested", category: .json, title: "Pretty Nested Data", subtitle: "Indent nested structures", systemImage: "list.bullet.indent"),
        .init(id: "json.duplicateKeys", category: .json, title: "Duplicate Key Detector", subtitle: "Find duplicate object keys", systemImage: "exclamationmark.triangle"),
        .init(id: "json.explorer", category: .json, title: "Large JSON Explorer", subtitle: "Summarize structure and sizes", systemImage: "magnifyingglass"),
        .init(id: "json.jsonpath", category: .json, title: "JSONPath Tester", subtitle: "Embedded subset: filters, slices, recursive descent", systemImage: "point.topleft.down.to.point.bottomright.curvepath", inputKind: .dualText, primaryLabel: "JSON", secondaryLabel: "JSONPath"),
        .init(id: "json.jmespath", category: .json, title: "JMESPath Tester", subtitle: "Embedded subset: projections, filters, pipes, slices", systemImage: "point.3.filled.connected.trianglepath.dotted", inputKind: .dualText, primaryLabel: "JSON", secondaryLabel: "JMESPath"),
        .init(id: "json.jq", category: .json, title: "jq Query Builder", subtitle: "Embedded jq subset: pipes, map/select, keys, paths", systemImage: "terminal", inputKind: .dualText, primaryLabel: "JSON", secondaryLabel: "Filter"),
        .init(id: "json.schema", category: .json, title: "JSON Schema Generator", subtitle: "Infer a shallow schema from sample JSON", systemImage: "square.stack.3d.up"),
        .init(id: "json.fake", category: .json, title: "Fake JSON Generator", subtitle: "Sample instances from a simple schema/template", systemImage: "wand.and.stars", inputKind: .textAndOptions, optionKeys: ["count"]),
    ]

    // MARK: - Encoding

    private static let encoding: [ToolDefinition] = [
        .init(id: "enc.base64", category: .encoding, title: "Base64", subtitle: "Encode or decode Base64", systemImage: "b.square", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.url", category: .encoding, title: "URL Encode/Decode", subtitle: "Percent-encode URL components", systemImage: "link", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.html", category: .encoding, title: "HTML Encode/Decode", subtitle: "Escape HTML entities", systemImage: "chevron.left.forwardslash.chevron.right", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.unicode", category: .encoding, title: "Unicode Converter", subtitle: "Code points and escapes", systemImage: "globe"),
        .init(id: "enc.ascii", category: .encoding, title: "ASCII Converter", subtitle: "Bytes and characters", systemImage: "textformat.abc"),
        .init(id: "enc.binary", category: .encoding, title: "Binary Converter", subtitle: "Text ↔ binary", systemImage: "01.square", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.hex", category: .encoding, title: "Hex Converter", subtitle: "Text ↔ hex", systemImage: "number", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.octal", category: .encoding, title: "Octal Converter", subtitle: "Text ↔ octal", systemImage: "number.square", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.percent", category: .encoding, title: "Percent Encoding", subtitle: "Full percent encode/decode", systemImage: "percent", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.emoji", category: .encoding, title: "Emoji Encoder", subtitle: "GitHub-style shortcodes ↔ emoji", systemImage: "face.smiling", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.morse", category: .encoding, title: "Morse Code", subtitle: "Text ↔ Morse", systemImage: "waveform", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.rot13", category: .encoding, title: "ROT13", subtitle: "Rotate letters by 13", systemImage: "arrow.2.squarepath"),
        .init(id: "enc.base32", category: .encoding, title: "Base32", subtitle: "Encode or decode Base32", systemImage: "b.circle", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.base58", category: .encoding, title: "Base58", subtitle: "Bitcoin-style Base58", systemImage: "bitcoinsign.circle", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.base62", category: .encoding, title: "Base62", subtitle: "Alphanumeric Base62", systemImage: "number.circle", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.base85", category: .encoding, title: "Base85", subtitle: "Ascii85 encode/decode (same path as ASCII85)", systemImage: "a.square", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.base91", category: .encoding, title: "Base91", subtitle: "Encode or decode Base91", systemImage: "a.circle", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.ascii85", category: .encoding, title: "ASCII85", subtitle: "Adobe Ascii85 (alias of Base85 tool)", systemImage: "doc.richtext", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "enc.urlParser", category: .encoding, title: "URL Parser", subtitle: "Break down a URL", systemImage: "link.badge.plus"),
    ]

    // MARK: - Crypto

    private static let crypto: [ToolDefinition] = [
        .init(id: "crypto.sha1", category: .crypto, title: "SHA-1", subtitle: "Hash with SHA-1", systemImage: "number"),
        .init(id: "crypto.sha256", category: .crypto, title: "SHA-256", subtitle: "Hash with SHA-256", systemImage: "number"),
        .init(id: "crypto.sha512", category: .crypto, title: "SHA-512", subtitle: "Hash with SHA-512", systemImage: "number"),
        .init(id: "crypto.sha3", category: .crypto, title: "SHA3-256", subtitle: "Hash with SHA3-256", systemImage: "number"),
        .init(id: "crypto.md5", category: .crypto, title: "MD5", subtitle: "Hash with MD5 (insecure)", systemImage: "exclamationmark.lock"),
        .init(id: "crypto.bcrypt", category: .crypto, title: "Bcrypt", subtitle: "OpenBSD-compatible $2b$ hash/verify", systemImage: "lock.rotation", inputKind: .dualText, primaryLabel: "Password", secondaryLabel: "Hash (for verify)", optionKeys: ["mode", "cost"]),
        .init(id: "crypto.argon2", category: .crypto, title: "Argon2id", subtitle: "RFC 9106 Argon2id hash/verify", systemImage: "lock.rotation", inputKind: .dualText, primaryLabel: "Password", secondaryLabel: "Hash (for verify)", optionKeys: ["mode", "memoryKiB", "iterations", "parallelism"]),
        .init(id: "crypto.pbkdf2", category: .crypto, title: "PBKDF2", subtitle: "Derive a key with PBKDF2-HMAC-SHA256", systemImage: "key", inputKind: .textAndOptions, optionKeys: ["salt", "iterations", "keyLength"]),
        .init(id: "crypto.aes", category: .crypto, title: "AES Encrypt/Decrypt", subtitle: "AES-GCM via passphrase→SHA-256 key", systemImage: "lock", inputKind: .textAndOptions, optionKeys: ["mode", "passphrase"]),
        .init(id: "crypto.rsa", category: .crypto, title: "RSA Encrypt/Decrypt", subtitle: "RSA-OAEP with PEM keys", systemImage: "key.fill", inputKind: .textAndOptions, optionKeys: ["mode", "key"]),
        .init(id: "crypto.ecc", category: .crypto, title: "ECC Tools", subtitle: "P-256 sign / verify", systemImage: "signature", inputKind: .textAndOptions, optionKeys: ["mode", "key", "signature"]),
        .init(id: "crypto.password", category: .crypto, title: "Password Generator", subtitle: "Secure random passwords", systemImage: "lock.doc", inputKind: .none, optionKeys: ["length", "charset"]),
        .init(id: "crypto.token", category: .crypto, title: "Secure Token", subtitle: "URL-safe random token", systemImage: "ticket", inputKind: .none, optionKeys: ["bytes"]),
        .init(id: "crypto.uuid", category: .crypto, title: "UUID Generator", subtitle: "Generate UUIDs", systemImage: "qrcode", inputKind: .none, optionKeys: ["count", "version"]),
        .init(id: "crypto.uuidValidate", category: .crypto, title: "UUID Validator", subtitle: "Validate UUID strings", systemImage: "checkmark.circle"),
        .init(id: "crypto.uuidConvert", category: .crypto, title: "UUID Converter", subtitle: "Upper/lower/URN forms", systemImage: "arrow.triangle.2.circlepath"),
        .init(id: "crypto.nanoid", category: .crypto, title: "NanoID Generator", subtitle: "Generate NanoIDs", systemImage: "barcode", inputKind: .none, optionKeys: ["size", "count"]),
        .init(id: "crypto.ulid", category: .crypto, title: "ULID Generator", subtitle: "Generate ULIDs", systemImage: "clock.badge.checkmark", inputKind: .none, optionKeys: ["count"]),
        .init(id: "crypto.snowflake", category: .crypto, title: "Snowflake ID", subtitle: "Generate Twitter-style IDs", systemImage: "snowflake", inputKind: .none, optionKeys: ["count", "workerId"]),
        .init(id: "crypto.checksum", category: .crypto, title: "Checksum Calculator", subtitle: "CRC32 and Adler-32", systemImage: "sum"),
        .init(id: "crypto.fileHash", category: .crypto, title: "File Hash Calculator", subtitle: "Hash a file path or editor text bytes", systemImage: "doc.badge.gearshape", inputKind: .textAndOptions, primaryLabel: "Text bytes (optional if filePath set)", optionKeys: ["algorithm", "filePath"]),
        .init(id: "crypto.signature", category: .crypto, title: "Signature Verifier", subtitle: "Verify P-256 / RSA signatures", systemImage: "checkmark.seal.fill", inputKind: .textAndOptions, optionKeys: ["algorithm", "key", "signature"]),
    ]

    // MARK: - Date

    private static let date: [ToolDefinition] = [
        .init(id: "date.unix", category: .date, title: "Unix Timestamp", subtitle: "Seconds ↔ human date", systemImage: "clock", inputKind: .textAndOptions, optionKeys: ["mode", "timezone"]),
        .init(id: "date.epoch", category: .date, title: "Epoch Converter", subtitle: "ms / µs / ns epochs", systemImage: "timer", inputKind: .textAndOptions, optionKeys: ["unit", "timezone"]),
        .init(id: "date.relative", category: .date, title: "Relative Date", subtitle: "Add or subtract duration", systemImage: "calendar.badge.plus", inputKind: .textAndOptions, optionKeys: ["amount", "unit"]),
        .init(id: "date.timezone", category: .date, title: "Timezone Converter", subtitle: "Convert between time zones", systemImage: "globe.americas", inputKind: .textAndOptions, optionKeys: ["from", "to"]),
        .init(id: "date.cronBuilder", category: .date, title: "Cron Builder", subtitle: "Build a 5-field cron expression", systemImage: "gearshape.2", inputKind: .textAndOptions, optionKeys: ["minute", "hour", "dom", "month", "dow"]),
        .init(id: "date.cronTester", category: .date, title: "Cron Tester", subtitle: "Next fire times for a cron", systemImage: "calendar.badge.clock", inputKind: .dualText, primaryLabel: "Cron expression", secondaryLabel: "From date (ISO8601, optional)"),
        .init(id: "date.rrule", category: .date, title: "RRULE Generator", subtitle: "Simple iCalendar RRULE builder (not full iCal)", systemImage: "repeat", inputKind: .textAndOptions, optionKeys: ["freq", "interval", "count"]),
        .init(id: "date.business", category: .date, title: "Business Day Calculator", subtitle: "Add business days", systemImage: "briefcase", inputKind: .textAndOptions, optionKeys: ["days"]),
        .init(id: "date.iso8601", category: .date, title: "ISO8601 Validator", subtitle: "Validate ISO-8601 timestamps", systemImage: "checkmark.circle"),
        .init(id: "date.duration", category: .date, title: "Duration Calculator", subtitle: "Difference between two dates", systemImage: "hourglass", inputKind: .dualText, primaryLabel: "Start", secondaryLabel: "End"),
        .init(id: "date.calendarDiff", category: .date, title: "Calendar Difference", subtitle: "Years, months, days between dates", systemImage: "calendar", inputKind: .dualText, primaryLabel: "Start", secondaryLabel: "End"),
        .init(id: "date.stopwatch", category: .date, title: "Stopwatch", subtitle: "Manual lap helper (not a live timer UI)", systemImage: "stopwatch", inputKind: .textAndOptions, optionKeys: ["action"]),
        .init(id: "date.countdown", category: .date, title: "Countdown", subtitle: "Time remaining until a date", systemImage: "timer", inputKind: .textAndOptions, optionKeys: ["target"]),
        .init(id: "date.leap", category: .date, title: "Leap Year Checker", subtitle: "Check if a year is a leap year", systemImage: "leaf"),
        .init(id: "date.format", category: .date, title: "Time Formatter", subtitle: "Format a date with a pattern", systemImage: "textformat", inputKind: .textAndOptions, optionKeys: ["format", "timezone"]),
    ]

    // MARK: - Text

    private static let text: [ToolDefinition] = [
        .init(id: "text.regex", category: .text, title: "Regex Tester", subtitle: "Match and capture groups", systemImage: "text.magnifyingglass", inputKind: .dualText, primaryLabel: "Text", secondaryLabel: "Pattern"),
        .init(id: "text.regexGen", category: .text, title: "Regex Generator", subtitle: "Escape a literal as a pattern", systemImage: "wand.and.rays"),
        .init(id: "text.regexExplain", category: .text, title: "Regex Explainer", subtitle: "Token walkthrough (not a semantic regex engine)", systemImage: "text.book.closed"),
        .init(id: "text.diff", category: .text, title: "Diff Viewer", subtitle: "Line-level text diff", systemImage: "arrow.left.arrow.right", inputKind: .dualText, primaryLabel: "Left", secondaryLabel: "Right"),
        .init(id: "text.merge", category: .text, title: "Merge Tool", subtitle: "Line-level 3-way merge; base+ours split by ---", systemImage: "arrow.triangle.merge", inputKind: .dualText, primaryLabel: "Base + ours (--- separator)", secondaryLabel: "Theirs"),
        .init(id: "text.mdPreview", category: .text, title: "Markdown Preview", subtitle: "Attributed/text dump (use Markdown Editor for HTML)", systemImage: "text.richtext"),
        .init(id: "text.mdEditor", category: .text, title: "Markdown Editor", subtitle: "Normalize Markdown with live HTML preview", systemImage: "pencil"),
        .init(id: "text.htmlPreview", category: .text, title: "HTML Preview", subtitle: "Strip tags → plain text (not a WebKit render)", systemImage: "safari"),
        .init(id: "text.compare", category: .text, title: "Text Compare", subtitle: "Equality and similarity", systemImage: "equal", inputKind: .dualText),
        .init(id: "text.charCount", category: .text, title: "Character Counter", subtitle: "Count characters and bytes", systemImage: "character"),
        .init(id: "text.wordCount", category: .text, title: "Word Counter", subtitle: "Count words", systemImage: "textformat.size"),
        .init(id: "text.lineCount", category: .text, title: "Line Counter", subtitle: "Count lines", systemImage: "list.number"),
        .init(id: "text.dedupe", category: .text, title: "Duplicate Line Remover", subtitle: "Remove duplicate lines", systemImage: "list.bullet"),
        .init(id: "text.sort", category: .text, title: "Sort Lines", subtitle: "Sort lines alphabetically", systemImage: "arrow.up.arrow.down", inputKind: .textAndOptions, optionKeys: ["order"]),
        .init(id: "text.reverse", category: .text, title: "Reverse Lines", subtitle: "Reverse line order", systemImage: "arrow.uturn.down"),
        .init(id: "text.trim", category: .text, title: "Trim Whitespace", subtitle: "Trim lines and collapse blanks", systemImage: "scissors"),
        .init(id: "text.case", category: .text, title: "Case Converter", subtitle: "Upper, lower, title, camel, snake", systemImage: "textformat.abc", inputKind: .textAndOptions, optionKeys: ["mode"]),
        .init(id: "text.slug", category: .text, title: "Slug Generator", subtitle: "URL-friendly slug", systemImage: "link"),
        .init(id: "text.lorem", category: .text, title: "Lorem Ipsum", subtitle: "Generate placeholder text", systemImage: "text.quote", inputKind: .textAndOptions, optionKeys: ["paragraphs"]),
        .init(id: "text.uuidReplace", category: .text, title: "UUID Replacement", subtitle: "Replace UUIDs with fresh ones", systemImage: "arrow.triangle.2.circlepath"),
        .init(id: "text.findReplace", category: .text, title: "Find & Replace", subtitle: "Literal find and replace", systemImage: "magnifyingglass", inputKind: .textAndOptions, optionKeys: ["find", "replace"]),
        .init(id: "text.wrap", category: .text, title: "Text Wrapping", subtitle: "Soft-wrap by width", systemImage: "text.alignleft", inputKind: .textAndOptions, optionKeys: ["width"]),
        .init(id: "text.random", category: .text, title: "Random Text", subtitle: "Generate random words", systemImage: "dice", inputKind: .textAndOptions, optionKeys: ["words"]),
    ]

    // MARK: - Code

    private static let code: [ToolDefinition] = [
        .init(id: "code.highlight", category: .code, title: "Syntax Highlighter", subtitle: "Splash (Swift) + multi-language token colors", systemImage: "paintbrush", inputKind: .textAndOptions, optionKeys: ["language"]),
        .init(id: "code.formatter", category: .code, title: "Code Formatter", subtitle: "Format with Prettier or builtin rules", systemImage: "text.alignleft", inputKind: .textAndOptions, optionKeys: ["language"]),
        .init(id: "code.prettier", category: .code, title: "Prettier", subtitle: "Format via local prettier CLI", systemImage: "sparkles", inputKind: .textAndOptions, optionKeys: ["filename"]),
        .init(id: "code.eslint", category: .code, title: "ESLint Runner", subtitle: "Lint via local eslint CLI", systemImage: "exclamationmark.triangle"),
        .init(id: "code.swift", category: .code, title: "Swift Formatter", subtitle: "swift-format / swiftformat / builtin", systemImage: "swift"),
        .init(id: "code.python", category: .code, title: "Python Formatter", subtitle: "ruff / black / builtin", systemImage: "chevron.left.forwardslash.chevron.right"),
        .init(id: "code.sqlFormat", category: .code, title: "SQL Formatter", subtitle: "Pretty-print SQL", systemImage: "cylinder"),
        .init(id: "code.html", category: .code, title: "HTML Formatter", subtitle: "Indent HTML markup", systemImage: "chevron.left.slash.chevron.right"),
        .init(id: "code.css", category: .code, title: "CSS Formatter", subtitle: "Indent CSS rules", systemImage: "paintpalette"),
        .init(id: "code.yaml", category: .code, title: "YAML Formatter", subtitle: "Normalize YAML indentation", systemImage: "doc.plaintext"),
        .init(id: "code.xml", category: .code, title: "XML Formatter", subtitle: "Indent XML markup", systemImage: "doc.badge.gearshape"),
        .init(id: "code.java", category: .code, title: "Java Formatter", subtitle: "google-java-format or builtin", systemImage: "cup.and.saucer"),
        .init(id: "code.kotlin", category: .code, title: "Kotlin Formatter", subtitle: "ktlint or builtin", systemImage: "k.circle"),
        .init(id: "code.go", category: .code, title: "Go Formatter", subtitle: "gofmt or builtin", systemImage: "g.circle"),
        .init(id: "code.rust", category: .code, title: "Rust Formatter", subtitle: "rustfmt or builtin", systemImage: "gearshape"),
        .init(id: "code.csharp", category: .code, title: "C# Formatter", subtitle: "Builtin indentation (dotnet format not wired)", systemImage: "c.circle"),
        .init(id: "code.diff", category: .code, title: "Code Diff", subtitle: "Line-level code diff", systemImage: "arrow.left.arrow.right", inputKind: .dualText, primaryLabel: "Left", secondaryLabel: "Right"),
        .init(id: "code.ast", category: .code, title: "AST Viewer", subtitle: "Structure outline (not a full parser AST)", systemImage: "point.3.connected.trianglepath.dotted", inputKind: .textAndOptions, optionKeys: ["language"]),
        .init(id: "code.snippets", category: .code, title: "Snippet Manager", subtitle: "Save, list, load, delete snippets", systemImage: "doc.on.clipboard", inputKind: .textAndOptions, optionKeys: ["action", "name", "language"]),
        .init(id: "code.screenshot", category: .code, title: "Code Screenshot", subtitle: "Render code to a PNG with live preview", systemImage: "camera", inputKind: .textAndOptions, optionKeys: ["language"]),
        .init(id: "code.gist", category: .code, title: "GitHub Gist Uploader", subtitle: "Upload a gist with your githubToken secret", systemImage: "arrow.up.doc", inputKind: .textAndOptions, primaryLabel: "File contents", optionKeys: ["filename", "description", "public"]),
    ]

    // MARK: - SQL

    private static let sql: [ToolDefinition] = [
        .init(id: "sql.formatter", category: .sql, title: "SQL Formatter", subtitle: "Pretty-print SQL or a .sql file", systemImage: "text.alignleft", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path", optionKeys: ["sqlPath"]),
        .init(id: "sql.beautifier", category: .sql, title: "SQL Beautifier", subtitle: "Alias for SQL formatter", systemImage: "sparkles", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path", optionKeys: ["sqlPath"]),
        .init(id: "sql.runner", category: .sql, title: "SQL Query Runner", subtitle: "Run against a .db or load a .sql dump in memory", systemImage: "play.fill", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path", optionKeys: ["dbPath", "sqlPath"]),
        .init(id: "sql.sqliteBrowser", category: .sql, title: "SQLite Browser", subtitle: "Browse a .db or preview a .sql dump", systemImage: "internaldrive", inputKind: .none, optionKeys: ["dbPath"]),
        .init(id: "sql.sqliteEditor", category: .sql, title: "SQLite Editor", subtitle: "Execute against a .db or in-memory .sql dump", systemImage: "pencil", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path", optionKeys: ["dbPath", "sqlPath"]),
        .init(id: "sql.sqliteDiff", category: .sql, title: "SQLite Diff", subtitle: "Diff two DB schemas or .sql dumps", systemImage: "arrow.left.arrow.right", inputKind: .none, optionKeys: ["dbPath", "otherDbPath"]),
        .init(id: "sql.csvImport", category: .sql, title: "CSV Importer", subtitle: "Import CSV into SQLite", systemImage: "square.and.arrow.down", inputKind: .textAndOptions, primaryLabel: "CSV", optionKeys: ["dbPath", "table"]),
        .init(id: "sql.csvExport", category: .sql, title: "CSV Exporter", subtitle: "Export SQL/table to CSV", systemImage: "square.and.arrow.up", inputKind: .textAndOptions, primaryLabel: "SQL (optional)", optionKeys: ["dbPath", "table", "sqlPath"]),
        .init(id: "sql.er", category: .sql, title: "ER Diagram Generator", subtitle: "Mermaid erDiagram from SQLite", systemImage: "point.3.filled.connected.trianglepath.dotted", inputKind: .none, optionKeys: ["dbPath"]),
        .init(id: "sql.mongo", category: .sql, title: "MongoDB Query Builder", subtitle: "Find snippets; CLI wrapper when mongosh + url set", systemImage: "leaf", inputKind: .textAndOptions, primaryLabel: "Filter JSON", optionKeys: ["collection", "url"]),
        .init(id: "sql.postgres", category: .sql, title: "PostgreSQL Helper", subtitle: "Offline helper or psql CLI wrapper", systemImage: "cylinder.split.1x2", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path (optional)", optionKeys: ["url", "sqlPath"]),
        .init(id: "sql.mysql", category: .sql, title: "MySQL Helper", subtitle: "Offline helper or mysql CLI wrapper", systemImage: "cylinder", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path (optional)", optionKeys: ["url", "password", "sqlPath"]),
        .init(id: "sql.redis", category: .sql, title: "Redis Browser", subtitle: "redis-cli wrapper with offline command help", systemImage: "externaldrive.connected.to.line.below", inputKind: .textAndOptions, primaryLabel: "Command (optional)", optionKeys: ["host", "port", "password"]),
        .init(id: "sql.redisKeys", category: .sql, title: "Redis Key Explorer", subtitle: "SCAN (or KEYS fallback) via redis-cli", systemImage: "key", inputKind: .none, optionKeys: ["host", "port", "password", "pattern"]),
        .init(id: "sql.redisTTL", category: .sql, title: "Redis TTL Viewer", subtitle: "TTL for a key via redis-cli", systemImage: "clock", inputKind: .textAndOptions, primaryLabel: "Key", optionKeys: ["host", "port", "password", "key"]),
        .init(id: "sql.explain", category: .sql, title: "SQL Explain Visualizer", subtitle: "Tree + Mermaid from SQLite EXPLAIN QUERY PLAN", systemImage: "chart.bar", inputKind: .textAndOptions, primaryLabel: "SQL or .sql path", optionKeys: ["dbPath", "sqlPath"]),
        .init(id: "sql.migrations", category: .sql, title: "SQL Migration Viewer", subtitle: "View DB DDL or a .sql dump", systemImage: "arrow.triangle.branch", inputKind: .none, optionKeys: ["dbPath"]),
        .init(id: "sql.schemaCompare", category: .sql, title: "Schema Comparer", subtitle: "Diff two DB schemas or .sql dumps", systemImage: "arrow.left.arrow.right.square", inputKind: .none, optionKeys: ["dbPath", "otherDbPath"]),
    ]

    // MARK: - Generators

    private static let generators: [ToolDefinition] = [
        .init(id: "gen.uuid", category: .generators, title: "UUID Generator", subtitle: "Generate UUIDs", systemImage: "qrcode", inputKind: .none, optionKeys: ["count", "version"]),
        .init(id: "gen.fake", category: .generators, title: "Fake Data Generator", subtitle: "Rich sample people, companies, and addresses", systemImage: "person.crop.rectangle.stack", inputKind: .none, optionKeys: ["count"]),
        .init(id: "gen.mockApi", category: .generators, title: "Mock API Generator", subtitle: "Express/JSON mock route stubs", systemImage: "externaldrive.connected.to.line.below", inputKind: .textAndOptions, primaryLabel: "Resource name", optionKeys: ["count"]),
        .init(id: "gen.sqlData", category: .generators, title: "SQL Data Generator", subtitle: "INSERT statements for sample rows", systemImage: "tablecells.badge.ellipsis", inputKind: .textAndOptions, primaryLabel: "Table name", optionKeys: ["count", "columns"]),
        .init(id: "gen.testData", category: .generators, title: "Test Data Generator", subtitle: "JSON fixtures for tests", systemImage: "checklist", inputKind: .textAndOptions, primaryLabel: "Entity name", optionKeys: ["count"]),
        .init(id: "gen.password", category: .generators, title: "Password Generator", subtitle: "Secure random passwords", systemImage: "key.fill", inputKind: .none, optionKeys: ["length", "charset", "count"]),
        .init(id: "gen.palette", category: .generators, title: "Color Palette Generator", subtitle: "Harmonized hex palettes", systemImage: "paintpalette", inputKind: .textAndOptions, primaryLabel: "Seed hex (optional)", optionKeys: ["count"]),
        .init(id: "gen.cssShadow", category: .generators, title: "CSS Shadow Generator", subtitle: "box-shadow snippets", systemImage: "square.on.square", inputKind: .none, optionKeys: ["x", "y", "blur", "spread", "color"]),
        .init(id: "gen.cssGradient", category: .generators, title: "CSS Gradient Generator", subtitle: "linear/radial gradients", systemImage: "circle.lefthalf.filled", inputKind: .none, optionKeys: ["type", "angle", "from", "to"]),
        .init(id: "gen.cssAnimation", category: .generators, title: "CSS Animation Generator", subtitle: "@keyframes + animation", systemImage: "play.circle", inputKind: .textAndOptions, primaryLabel: "Name", optionKeys: ["duration", "easing"]),
        .init(id: "gen.tailwindClass", category: .generators, title: "Tailwind Class Builder", subtitle: "Compose utility class strings", systemImage: "square.grid.3x3", inputKind: .none, optionKeys: ["layout", "spacing", "color", "text"]),
        .init(id: "gen.tailwindColor", category: .generators, title: "Tailwind Color Generator", subtitle: "Shade scale from a base color", systemImage: "swatchpalette", inputKind: .textAndOptions, primaryLabel: "Base hex", optionKeys: ["name"]),
        .init(id: "gen.htmlEmail", category: .generators, title: "HTML Email Generator", subtitle: "Table-based email template", systemImage: "envelope", inputKind: .textAndOptions, primaryLabel: "Subject / title", optionKeys: ["preheader"]),
        .init(id: "gen.sitemap", category: .generators, title: "Sitemap Generator", subtitle: "XML sitemap from URL list", systemImage: "map", primaryLabel: "URLs (one per line)"),
        .init(id: "gen.robots", category: .generators, title: "robots.txt Generator", subtitle: "Build a robots.txt", systemImage: "hand.raised", inputKind: .textAndOptions, primaryLabel: "Sitemap URL (optional)", optionKeys: ["userAgent", "disallow"]),
        .init(id: "gen.robotsTest", category: .generators, title: "robots.txt Tester", subtitle: "Check path allow/disallow rules", systemImage: "checkmark.shield", inputKind: .dualText, primaryLabel: "robots.txt", secondaryLabel: "Path to test"),
    ]

    // MARK: - Web Development

    private static let web: [ToolDefinition] = [
        .init(id: "web.htmlPlayground", category: .web, title: "HTML Playground", subtitle: "Edit HTML with a live WebKit preview", systemImage: "chevron.left.forwardslash.chevron.right", primaryLabel: "HTML body"),
        .init(id: "web.cssPlayground", category: .web, title: "CSS Playground", subtitle: "Edit CSS with a live WebKit preview", systemImage: "paintbrush", inputKind: .dualText, primaryLabel: "CSS", secondaryLabel: "HTML body (optional)"),
        .init(id: "web.jsPlayground", category: .web, title: "JavaScript Playground", subtitle: "Edit JS with a live WebKit preview", systemImage: "curlybraces.square", inputKind: .dualText, primaryLabel: "JavaScript", secondaryLabel: "HTML body (optional)"),
        .init(id: "web.liveServer", category: .web, title: "Live Web Server", subtitle: "Serve HTML via local python http.server", systemImage: "antenna.radiowaves.left.and.right", inputKind: .textAndOptions, primaryLabel: "HTML / directory notes", optionKeys: ["port", "action"]),
        .init(id: "web.httpsServer", category: .web, title: "Local HTTPS Server", subtitle: "Serve HTML over local HTTPS with a self-signed cert", systemImage: "lock.laptopcomputer", inputKind: .textAndOptions, primaryLabel: "HTML content", optionKeys: ["port", "action"]),
        .init(id: "web.cors", category: .web, title: "CORS Tester", subtitle: "Probe CORS headers for a URL", systemImage: "arrow.triangle.2.circlepath", inputKind: .textAndOptions, primaryLabel: "URL", optionKeys: ["origin", "method"]),
        .init(id: "web.cookieEditor", category: .web, title: "Cookie Editor", subtitle: "Parse and rebuild Cookie headers", systemImage: "birthday.cake", primaryLabel: "Cookie header"),
        .init(id: "web.localStorage", category: .web, title: "Local Storage Viewer", subtitle: "WebKit probe or JSON dump (not DevTools)", systemImage: "internaldrive", primaryLabel: "HTML page or JSON dump"),
        .init(id: "web.sessionStorage", category: .web, title: "Session Storage Viewer", subtitle: "WebKit probe or JSON dump (not DevTools)", systemImage: "clock.arrow.circlepath", primaryLabel: "HTML page or JSON dump"),
        .init(id: "web.indexedDB", category: .web, title: "IndexedDB Explorer", subtitle: "WebKit probe or JSON export summary", systemImage: "cylinder.split.1x2", primaryLabel: "HTML page or export JSON"),
        .init(id: "web.serviceWorker", category: .web, title: "Service Worker Viewer", subtitle: "Script heuristics + registration probe page", systemImage: "gearshape.2", primaryLabel: "service-worker.js"),
        .init(id: "web.manifest", category: .web, title: "Manifest Validator", subtitle: "Validate Web App Manifest JSON", systemImage: "app.badge", primaryLabel: "manifest.json"),
        .init(id: "web.robotsValidate", category: .web, title: "Robots.txt Validator", subtitle: "Validate robots.txt syntax", systemImage: "doc.text.magnifyingglass", primaryLabel: "robots.txt"),
        .init(id: "web.sitemapValidate", category: .web, title: "Sitemap Validator", subtitle: "Validate sitemap XML", systemImage: "map.fill", primaryLabel: "sitemap.xml"),
        .init(id: "web.lighthouse", category: .web, title: "Lighthouse Wrapper", subtitle: "Score summary via lighthouse CLI when installed", systemImage: "lightbulb", inputKind: .textAndOptions, primaryLabel: "URL", optionKeys: ["preset"]),
        .init(id: "web.a11y", category: .web, title: "Accessibility Checker", subtitle: "axe CLI when available, else static heuristics", systemImage: "accessibility", primaryLabel: "HTML"),
        .init(id: "web.contrast", category: .web, title: "Color Contrast Checker", subtitle: "WCAG contrast ratio", systemImage: "circle.lefthalf.striped.horizontal", inputKind: .dualText, primaryLabel: "Foreground hex", secondaryLabel: "Background hex"),
        .init(id: "web.specificity", category: .web, title: "CSS Specificity Calculator", subtitle: "Score CSS selectors", systemImage: "number.square", primaryLabel: "Selector(s)"),
        .init(id: "web.flexbox", category: .web, title: "Flexbox Visualizer", subtitle: "Live flex layout preview + CSS", systemImage: "rectangle.split.3x1", inputKind: .none, optionKeys: ["direction", "justify", "align", "items"]),
        .init(id: "web.grid", category: .web, title: "Grid Visualizer", subtitle: "Live CSS grid preview + CSS", systemImage: "square.grid.3x3", inputKind: .none, optionKeys: ["cols", "rows", "gap"]),
    ]

    // MARK: - Networking

    private static let networking: [ToolDefinition] = [
        .init(id: "net.ipLookup", category: .networking, title: "IP Lookup", subtitle: "Resolve host → IP addresses", systemImage: "network", primaryLabel: "Hostname or IP"),
        .init(id: "net.localIP", category: .networking, title: "Local IP Viewer", subtitle: "List local interface addresses", systemImage: "laptopcomputer.and.iphone", inputKind: .none),
        .init(id: "net.publicIP", category: .networking, title: "Public IP Viewer", subtitle: "Fetch public IP over HTTPS", systemImage: "globe", inputKind: .none),
        .init(id: "net.cidr", category: .networking, title: "CIDR Calculator", subtitle: "Expand/summarize CIDR blocks", systemImage: "square.stack.3d.up", primaryLabel: "CIDR (e.g. 10.0.0.0/24)"),
        .init(id: "net.subnet", category: .networking, title: "Subnet Calculator", subtitle: "Network/broadcast/hosts", systemImage: "rectangle.split.2x1", inputKind: .textAndOptions, primaryLabel: "IP address", optionKeys: ["prefix"]),
        .init(id: "net.dns", category: .networking, title: "DNS Lookup", subtitle: "A/AAAA/CNAME/MX/TXT via dig/host", systemImage: "externaldrive.connected.to.line.below", inputKind: .textAndOptions, primaryLabel: "Hostname", optionKeys: ["type"]),
        .init(id: "net.whois", category: .networking, title: "WHOIS Lookup", subtitle: "WHOIS via whois CLI", systemImage: "person.text.rectangle", primaryLabel: "Domain or IP"),
        .init(id: "net.reverseDns", category: .networking, title: "Reverse DNS", subtitle: "PTR lookup for an IP", systemImage: "arrow.uturn.backward", primaryLabel: "IP address"),
        .init(id: "net.portScan", category: .networking, title: "Port Scanner", subtitle: "Bounded TCP connect scan (max ~64 ports)", systemImage: "dot.radiowaves.left.and.right", inputKind: .textAndOptions, primaryLabel: "Host", optionKeys: ["ports", "timeoutMs"]),
        .init(id: "net.tcp", category: .networking, title: "TCP Client", subtitle: "Send bytes over TCP", systemImage: "cable.connector", inputKind: .textAndOptions, primaryLabel: "Payload", optionKeys: ["host", "port"]),
        .init(id: "net.udp", category: .networking, title: "UDP Client", subtitle: "Send a UDP datagram", systemImage: "dot.radiowaves.forward", inputKind: .textAndOptions, primaryLabel: "Payload", optionKeys: ["host", "port"]),
        .init(id: "net.ping", category: .networking, title: "Ping Utility", subtitle: "ICMP ping via ping CLI", systemImage: "waveform.path.ecg", inputKind: .textAndOptions, primaryLabel: "Host", optionKeys: ["count"]),
        .init(id: "net.traceroute", category: .networking, title: "Traceroute", subtitle: "traceroute / traceroute6 CLI", systemImage: "point.topleft.down.to.point.bottomright.curvepath", primaryLabel: "Host"),
        .init(id: "net.sslInspect", category: .networking, title: "SSL Certificate Inspector", subtitle: "Leaf cert details via openssl", systemImage: "lock.rectangle", inputKind: .textAndOptions, primaryLabel: "Host", optionKeys: ["port"]),
        .init(id: "net.sslChain", category: .networking, title: "SSL Chain Viewer", subtitle: "Show certificate chain", systemImage: "link", inputKind: .textAndOptions, primaryLabel: "Host", optionKeys: ["port"]),
        .init(id: "net.tlsHandshake", category: .networking, title: "TLS Handshake Tester", subtitle: "Probe TLS with openssl s_client", systemImage: "lock.rotation", inputKind: .textAndOptions, primaryLabel: "Host", optionKeys: ["port"]),
        .init(id: "net.httpHeaders", category: .networking, title: "HTTP Header Viewer", subtitle: "Fetch response headers", systemImage: "list.bullet.rectangle", primaryLabel: "URL"),
        .init(id: "net.cookieInspect", category: .networking, title: "Cookie Inspector", subtitle: "Parse Set-Cookie / Cookie pairs", systemImage: "eye", primaryLabel: "Cookie / Set-Cookie text"),
        .init(id: "net.userAgent", category: .networking, title: "User-Agent Parser", subtitle: "Browser, engine, OS, device, and bot signals", systemImage: "safari", primaryLabel: "User-Agent"),
        .init(id: "net.mime", category: .networking, title: "MIME Type Lookup", subtitle: "Extension ↔ MIME mapping", systemImage: "doc.badge.ellipsis", primaryLabel: "Extension or MIME"),
    ]
}
