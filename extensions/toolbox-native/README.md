# Toolbox Native

> **Attribution:** This extension was created with the help of AI and was
> reviewed by a human.

Toolbox is a standalone macOS 14 SwiftUI Native UI extension for Vehla. It is a
local-first workbench of developer data tools spanning JSON, encoding,
cryptography, dates, text, code, SQL/databases, generators, web development, and
networking — **196 ready tools** across ten categories, with no “Coming soon”
stubs.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.toolbox` |
| Workspace ID | `toolbox` |
| Version | **1.0.0** (`extension.json` / `Info.plist`) |
| Runtime | Vehla Native UI (`nativeUI`) |
| Author | ibuhs |
| License | MIT (`LICENSE`) |
| Minimum OS | macOS 14 |

All tool computation runs **off the main thread** via `ToolWorker` and
per-category actors, so the SwiftUI chrome stays responsive while hashing,
querying SQLite, formatting code, or talking to optional local CLIs.

## Why Toolbox

Use Toolbox when you want quick, local answers without jumping between browser
tabs, random websites, or one-off scripts:

- Paste JSON and format, diff, query (JSONPath / JMESPath / jq), or convert to
  CSV, YAML, TOML, XML, BSON, or MessagePack.
- Encode and decode Base64, URLs, HTML, hex, Morse, emoji shortcodes, and more.
- Hash passwords with real bcrypt / Argon2id, derive keys, encrypt with AES-GCM,
  or mint UUIDs / NanoIDs / ULIDs.
- Work with cron, epochs, timezones, and business-day math.
- Test regexes, preview Markdown, sort/dedupe text, and format code (builtin or
  via Prettier / ESLint / language CLIs).
- Browse SQLite (`.db` or `.sql` dumps), explain query plans, export CSV, or use
  Postgres / MySQL / Redis / Mongo helpers when CLIs are installed.
- Generate fake data, CSS/Tailwind snippets, sitemaps, and robots.txt.
- Preview HTML/CSS/JS in WebKit, serve local HTTP/HTTPS, check CORS, contrast,
  and flex/grid layouts.
- Look up DNS, CIDR, TLS certificates, headers, and User-Agent strings.

## Design principles

1. **Local-first** — Most tools never leave the machine. Network is opt-in
   (public IP, CORS, WHOIS, Lighthouse, GitHub Gists, etc.).
2. **Honest catalog** — Every sidebar entry is implemented. Thin tools are
   documented as subsets or CLI wrappers, not marketed as full replacements for
   `jq`, `psql`, or Chrome DevTools.
3. **Main-thread safe** — Heavy work is actor-isolated; the UI only collects
   input and renders results / previews.
4. **Graceful CLI fallbacks** — Prefer a local binary when present; otherwise
   return a clear offline helper or builtin formatter.
5. **Clear options UX** — Generators and path-based tools hide unused text
   editors; Browse buttons cover `dbPath` / `sqlPath` / `otherDbPath`.

## Build, test, and install

The Swift 6 package links the local Vehla Native UI SDK at `../../../sdk/swift`.

```sh
# From this directory (vehla-extensions/extensions/toolbox-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/ToolboxWorkspace.bundle`, then
assembles the installable package at `dist/Toolbox`. Select that folder in
Vehla’s **Install Local Package** workflow.

Open the workspace from Command Palette with **Open Toolbox**.

### Package layout

```
toolbox-native/
├── Package.swift                 # SPM: ToolboxWorkspace + CArgon2 + deps
├── extension.json                # Vehla package manifest (v1.0.0)
├── Info.plist                    # Bundle version
├── LICENSE / CHANGELOG.md / THIRD_PARTY_NOTICES.md
├── build.sh                      # Release build → bin/ + dist/Toolbox
├── README.md                     # This file
├── Sources/
│   ├── ToolboxWorkspace/         # SwiftUI UI + ToolWorker + engines
│   │   ├── ToolboxWorkspacePlugin.swift
│   │   ├── ToolCatalog.swift     # Source of truth for all 196 tools
│   │   ├── WorkspaceView.swift
│   │   ├── WorkspaceStore.swift
│   │   ├── PreferencesStore.swift
│   │   └── Engine/               # Per-category actors + helpers
│   └── CArgon2/                  # Vendored PHC Argon2 C sources
├── Tests/ToolboxWorkspaceTests/
├── bin/ToolboxWorkspace.bundle   # Built plugin (after ./build.sh)
└── dist/Toolbox/                 # Installable package folder
```

### Dependencies (SPM)

| Package | Role |
| --- | --- |
| VehlaNativeUISDK | Host SDK (workspace plugin, theme, secrets) |
| BCryptSwift | OpenBSD-compatible bcrypt |
| BSON | BSON → JSON decode |
| Yams | YAML ↔ JSON |
| TOMLKit | TOML ↔ JSON |
| Splash | Swift syntax highlighting |
| CArgon2 (local) | RFC 9106 Argon2id |
| system `sqlite3` | SQLite browser / runner / explain |

## How to use the workspace

1. Pick a **category** in the sidebar (category tool counts appear in the header).
2. Pick a **tool**, or use the sidebar **Search tools** field.
3. Fill editors and/or options, then **Run**. Common enums (`mode`, `direction`,
   `language`, etc.) use pickers; paths support **Browse**.
4. Copy or inspect the output. Tools that produce HTML (playgrounds, flex/grid,
   Markdown, storage probes, SQL explain, code screenshots, etc.) also show a
   live WebKit preview when available.
5. Switch tools freely — options reset to sensible defaults for the selected
   tool; snippets and preferences persist via `persistentStorage`.

### Input kinds

| Kind | What you see |
| --- | --- |
| Single text | One primary editor |
| Dual text | Primary + secondary editors |
| Text + options | Primary editor plus option fields |
| Options only | Option fields only (no unused editor) |
| None | Run with no input (e.g. Local IP) |

Options appear as compact fields above the editors. Paths like `dbPath`,
`otherDbPath`, and `sqlPath` include a **Browse** button.

### Capabilities and secrets

| Capability | Used for |
| --- | --- |
| `persistentStorage` | Snippet manager and workspace preferences |
| `networkAccess` | Public IP, CORS, HTTP headers, DNS/WHOIS CLIs, Lighthouse, gist API, etc. |

| Secret | Purpose |
| --- | --- |
| `githubToken` | GitHub personal access token for **GitHub Gist Uploader** (`code.gist`; set in Vehla Store settings for Toolbox). Needs `gist` scope (or classic PAT with gist access). |

### CLI dependencies (optional)

Several tools work offline with built-in helpers, and use local CLIs when present:

| CLI | Tools |
| --- | --- |
| `python3` | Live HTTP / HTTPS servers |
| `openssl` | Local HTTPS certs, SSL/TLS inspectors |
| `prettier` / `eslint` | Prettier, ESLint |
| `swift-format` / `swiftformat` | Swift formatter |
| `ruff` / `black` | Python formatter |
| `gofmt` / `rustfmt` / `ktlint` / `google-java-format` | Language formatters |
| `psql` / `mysql` / `mongosh` / `mongo` | Remote DB helpers |
| `redis-cli` | Redis tools |
| `dig` / `host` / `whois` / `ping` / `traceroute` | Networking |
| `lighthouse` / `@axe-core/cli` | Lighthouse / accessibility |

When a CLI is missing, the tool either fails with a clear message or returns an
offline helper (formatted SQL, connection examples, heuristics, etc.).

### Common workflows

| Goal | Start with |
| --- | --- |
| Pretty-print / minify API JSON | JSON Formatter / Minifier |
| Query nested JSON without leaving Vehla | JSONPath, JMESPath, or jq |
| Check a password hash | Bcrypt or Argon2id (`mode=verify`) |
| Browse a SQLite dump from a teammate | SQLite Browser → set `dbPath` to the `.sql` or `.db` |
| Preview a flex layout | Flexbox Visualizer → tweak options → Run |
| Serve a quick HTML mock on HTTPS | Local HTTPS Server (`action=start`) |
| Upload a snippet | GitHub Gist Uploader + `githubToken` secret |
| Decode a weird User-Agent | User-Agent Parser |

### Troubleshooting

| Symptom | What to try |
| --- | --- |
| Tool says CLI not found | Install the binary and ensure it is on PATH for GUI apps (launchd PATH can differ from your shell). |
| Gist upload fails auth | Set Toolbox’s `githubToken` secret; confirm gist scope; re-run. |
| SQLite tools empty / error | Confirm `dbPath` points at a readable `.db` or `.sql`; use Browse. |
| HTTPS server won’t start | Need `python3` and `openssl`; try another `port`; stop a previous server (`action=stop`). |
| Lighthouse / axe thin results | Install the CLI globally, or rely on the builtin score/heuristic summary. |
| jq / JMESPath “unsupported” | Use the documented subset (pipes, map/select, filters, paths); full CLI jq is not embedded. |
| UI looks stale after update | Reinstall `dist/Toolbox` and restart Vehla if the host requires it for in-process plugins. |

---

## Catalog overview

| Category | Tools |
| --- | ---: |
| [JSON / Data](#1-json--data) | 22 |
| [Encoding](#2-encoding) | 19 |
| [Cryptography](#3-cryptography) | 22 |
| [Date & Time](#4-date--time) | 15 |
| [Text](#5-text) | 23 |
| [Code](#6-code) | 21 |
| [SQL & Database](#7-sql--database) | 18 |
| [Generators](#8-generators) | 16 |
| [Web Dev](#9-web-dev) | 20 |
| [Networking](#10-networking) | 20 |
| **Total** | **196** |

The tables below are the complete public surface of Toolbox **1.0.0**. If a tool
is missing here, it is not in the shipping catalog.

---

## 1. JSON / Data

Transform, validate, query, and convert structured data.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| JSON Formatter | `json.formatter` | JSON | Pretty-prints JSON with stable indentation. |
| JSON Minifier | `json.minifier` | JSON | Compacts JSON to a single line. |
| JSON Validator | `json.validator` | JSON | Validates JSON syntax and reports errors. |
| JSON Diff | `json.diff` | Left JSON, Right JSON | Structural comparison of two JSON documents. |
| JSON Merge | `json.merge` | Base JSON, Overlay JSON | Deep-merges objects (overlay wins on conflicts). |
| JSON to CSV | `json.toCsv` | JSON array of objects | Flattens rows into CSV. |
| CSV to JSON | `json.fromCsv` | CSV text | Parses CSV into a JSON array of objects. |
| XML ↔ JSON | `json.xml` | Text; `direction` | Converts XML→JSON or JSON→XML (`xml-to-json` / `json-to-xml`). |
| YAML ↔ JSON | `json.yaml` | Text; `direction` | Converts via Yams (`yaml-to-json` / `json-to-yaml`). |
| TOML Converter | `json.toml` | Text; `direction` | Converts via TOMLKit (`toml-to-json` / `json-to-toml`). |
| INI Parser | `json.ini` | INI text | Parses INI sections/keys into JSON. |
| BSON Viewer | `json.bson` | BSON hex or base64 | Decodes BSON to pretty JSON. |
| MessagePack Viewer | `json.msgpack` | MessagePack hex or base64 | Decodes MessagePack to pretty JSON. |
| NDJSON Viewer | `json.ndjson` | NDJSON | Validates line-delimited JSON and pretty-prints each line. |
| Pretty Nested Data | `json.prettyNested` | Nested text/JSON | Indents nested structures for readability. |
| Duplicate Key Detector | `json.duplicateKeys` | JSON text | Finds duplicate object keys that normal parsers would collapse. |
| Large JSON Explorer | `json.explorer` | JSON | Summarizes structure, paths, and approximate sizes. |
| JSONPath Tester | `json.jsonpath` | JSON + JSONPath | Embedded subset: filters, slices, recursive descent (`$..`). |
| JMESPath Tester | `json.jmespath` | JSON + JMESPath | Embedded subset: projections, `[?filters]`, pipes, slices, `keys` / `length`. |
| jq Query Builder | `json.jq` | JSON + filter | Embedded subset: paths, pipes, `map` / `select`, `keys`, `length`, `type`, slices. |
| JSON Schema Generator | `json.schema` | Sample JSON | Infers a shallow JSON Schema-like structure. |
| Fake JSON Generator | `json.fake` | Schema/template; `count` | Sample instances from a simple schema/template. |

---

## 2. Encoding

Encode and decode text across common transfer and novelty formats.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| Base64 | `enc.base64` | Text; `mode` | Encode or decode Base64 (`encode` / `decode`). |
| URL Encode/Decode | `enc.url` | Text; `mode` | Percent-encodes or decodes URL components. |
| HTML Encode/Decode | `enc.html` | Text; `mode` | Escapes or unescapes HTML entities. |
| Unicode Converter | `enc.unicode` | Text | Shows code points and Unicode escapes. |
| ASCII Converter | `enc.ascii` | Text | Maps characters ↔ ASCII byte values. |
| Binary Converter | `enc.binary` | Text; `mode` | Text ↔ binary bit strings. |
| Hex Converter | `enc.hex` | Text; `mode` | Text ↔ hexadecimal. |
| Octal Converter | `enc.octal` | Text; `mode` | Text ↔ octal. |
| Percent Encoding | `enc.percent` | Text; `mode` | Full percent encode/decode (broader than URL component mode). |
| Emoji Encoder | `enc.emoji` | Text; `mode` | GitHub-style shortcodes ↔ emoji (and reverse). |
| Morse Code | `enc.morse` | Text; `mode` | Text ↔ Morse code. |
| ROT13 | `enc.rot13` | Text | Rotates A–Z / a–z by 13 places. |
| Base32 | `enc.base32` | Text; `mode` | Encode or decode Base32. |
| Base58 | `enc.base58` | Text; `mode` | Bitcoin-style Base58 encode/decode. |
| Base62 | `enc.base62` | Text; `mode` | Alphanumeric Base62 encode/decode. |
| Base85 | `enc.base85` | Text; `mode` | Ascii85 / Base85 encode/decode. |
| Base91 | `enc.base91` | Text; `mode` | Encode or decode Base91. |
| ASCII85 | `enc.ascii85` | Text; `mode` | Adobe ASCII85 encode/decode. |
| URL Parser | `enc.urlParser` | URL | Breaks a URL into scheme, host, path, query, fragment, etc. |

---

## 3. Cryptography

Hashes, password hashing, encryption, IDs, and checksums. Prefer Argon2id or
bcrypt for passwords; MD5/SHA-1 are provided for compatibility checks only.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| SHA-1 | `crypto.sha1` | Text | SHA-1 digest (hex). |
| SHA-256 | `crypto.sha256` | Text | SHA-256 digest (hex). |
| SHA-512 | `crypto.sha512` | Text | SHA-512 digest (hex). |
| SHA3-256 | `crypto.sha3` | Text | SHA3-256 digest (hex). |
| MD5 | `crypto.md5` | Text | MD5 digest (insecure; hex). |
| Bcrypt | `crypto.bcrypt` | Password + Hash (verify); `mode`, `cost` | OpenBSD-compatible `$2b$` hash or verify. |
| Argon2id | `crypto.argon2` | Password + Hash (verify); `mode`, `memoryKiB`, `iterations`, `parallelism` | RFC 9106 Argon2id hash or verify. |
| PBKDF2 | `crypto.pbkdf2` | Password; `salt`, `iterations`, `keyLength` | PBKDF2-HMAC-SHA256 key derivation. |
| AES Encrypt/Decrypt | `crypto.aes` | Text; `mode`, `passphrase` | AES-GCM with passphrase→SHA-256 key (not general AES modes). |
| RSA Encrypt/Decrypt | `crypto.rsa` | Text; `mode`, `key` | RSA-OAEP with PEM public/private keys. |
| ECC Tools | `crypto.ecc` | Text; `mode`, `key`, `signature` | P-256 sign / verify. |
| Password Generator | `crypto.password` | Options only: `length`, `charset` | Cryptographically random passwords. |
| Secure Token | `crypto.token` | Options only: `bytes` | URL-safe random token. |
| UUID Generator | `crypto.uuid` | Options only: `count`, `version` | Generates UUIDs (e.g. v4 / v7). |
| UUID Validator | `crypto.uuidValidate` | UUID text | Validates UUID strings. |
| UUID Converter | `crypto.uuidConvert` | UUID text | Upper/lower/URN forms. |
| NanoID Generator | `crypto.nanoid` | Options only: `size`, `count` | Generates NanoIDs. |
| ULID Generator | `crypto.ulid` | Options only: `count` | Generates ULIDs. |
| Snowflake ID | `crypto.snowflake` | Options only: `count`, `workerId` | Twitter-style snowflake IDs. |
| Checksum Calculator | `crypto.checksum` | Text | CRC32 and Adler-32. |
| File Hash Calculator | `crypto.fileHash` | Text and/or `filePath`; `algorithm` | Hashes a browsed file or editor text (md5/sha1/sha256/sha512). |
| Signature Verifier | `crypto.signature` | Message; `algorithm`, `key`, `signature` | Verifies P-256 / RSA signatures. |

---

## 4. Date & Time

Timestamps, cron, calendars, and duration helpers. Timezone-aware where noted.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| Unix Timestamp | `date.unix` | Value; `mode`, `timezone` | Seconds ↔ human-readable date. |
| Epoch Converter | `date.epoch` | Epoch; `unit`, `timezone` | Converts ms / µs / ns epochs (timezone honored). |
| Relative Date | `date.relative` | Date; `amount`, `unit` | Adds or subtracts a duration. |
| Timezone Converter | `date.timezone` | Date; `from`, `to` | Converts between time zones. |
| Cron Builder | `date.cronBuilder` | Options: `minute`, `hour`, `dom`, `month`, `dow` | Builds a 5-field cron expression. |
| Cron Tester | `date.cronTester` | Cron + optional from-date | Lists next fire times. |
| RRULE Generator | `date.rrule` | Options: `freq`, `interval`, `count` | Builds an iCalendar `RRULE`. |
| Business Day Calculator | `date.business` | Date; `days` | Adds business days (skips weekends). |
| ISO8601 Validator | `date.iso8601` | Timestamp | Validates ISO-8601 timestamps. |
| Duration Calculator | `date.duration` | Start, End | Absolute difference between two dates. |
| Calendar Difference | `date.calendarDiff` | Start, End | Years, months, and days between dates. |
| Stopwatch | `date.stopwatch` | Marks / notes; `action` | Manual elapsed-time helper (`lap`, etc.). |
| Countdown | `date.countdown` | Options: `target` | Time remaining until a target date. |
| Leap Year Checker | `date.leap` | Year | Reports whether a year is a leap year. |
| Time Formatter | `date.format` | Date; `format`, `timezone` | Formats a date with a pattern. |

---

## 5. Text

Regex, Markdown, diffs, counters, and everyday text transforms.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| Regex Tester | `text.regex` | Text + Pattern | Matches and shows capture groups. |
| Regex Generator | `text.regexGen` | Literal text | Escapes a literal string as a regex pattern. |
| Regex Explainer | `text.regexExplain` | Pattern | Token-by-token walkthrough of the pattern. |
| Diff Viewer | `text.diff` | Left, Right | Line-level text diff. |
| Merge Tool | `text.merge` | Base+ours (`---` separator), Theirs | Three-way line merge. |
| Markdown Preview | `text.mdPreview` | Markdown | Renders Markdown to an attributed/text dump. |
| Markdown Editor | `text.mdEditor` | Markdown | Normalizes Markdown and shows live HTML preview. |
| HTML Preview | `text.htmlPreview` | HTML | Strips tags and shows text content. |
| Text Compare | `text.compare` | Two texts | Equality and similarity metrics. |
| Character Counter | `text.charCount` | Text | Counts characters and UTF-8 bytes. |
| Word Counter | `text.wordCount` | Text | Counts words. |
| Line Counter | `text.lineCount` | Text | Counts lines. |
| Duplicate Line Remover | `text.dedupe` | Text | Removes duplicate lines (keeps first). |
| Sort Lines | `text.sort` | Text; `order` | Sorts lines (`asc` / `desc`). |
| Reverse Lines | `text.reverse` | Text | Reverses line order. |
| Trim Whitespace | `text.trim` | Text | Trims lines and collapses excess blanks. |
| Case Converter | `text.case` | Text; `mode` | Upper, lower, title, camel, snake, etc. |
| Slug Generator | `text.slug` | Text | URL-friendly slug. |
| Lorem Ipsum | `text.lorem` | Options: `paragraphs` | Placeholder paragraphs. |
| UUID Replacement | `text.uuidReplace` | Text with UUIDs | Replaces each UUID with a fresh one. |
| Find & Replace | `text.findReplace` | Text; `find`, `replace` | Literal find and replace. |
| Text Wrapping | `text.wrap` | Text; `width` | Soft-wraps by character width. |
| Random Text | `text.random` | Options: `words` | Generates random words. |

---

## 6. Code

Format, lint (via CLI when available), highlight, diff, outline, and manage
snippets. Language formatters prefer local CLIs, then fall back to builtins.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| Syntax Highlighter | `code.highlight` | Code; `language` | Splash for Swift + multi-language token colors. |
| Code Formatter | `code.formatter` | Code; `language` | Formats with Prettier or builtin rules by language. |
| Prettier | `code.prettier` | Code; `filename` | Formats via local `prettier` CLI. |
| ESLint Runner | `code.eslint` | Code | Lints via local `eslint` CLI. |
| Swift Formatter | `code.swift` | Swift | `swift-format` / `swiftformat` / builtin. |
| Python Formatter | `code.python` | Python | `ruff` / `black` / builtin. |
| SQL Formatter | `code.sqlFormat` | SQL | Pretty-prints SQL. |
| HTML Formatter | `code.html` | HTML | Indents HTML markup. |
| CSS Formatter | `code.css` | CSS | Indents CSS rules. |
| YAML Formatter | `code.yaml` | YAML | Normalizes YAML indentation. |
| XML Formatter | `code.xml` | XML | Indents XML markup. |
| Java Formatter | `code.java` | Java | `google-java-format` or builtin. |
| Kotlin Formatter | `code.kotlin` | Kotlin | `ktlint` or builtin. |
| Go Formatter | `code.go` | Go | `gofmt` or builtin. |
| Rust Formatter | `code.rust` | Rust | `rustfmt` or builtin. |
| C# Formatter | `code.csharp` | C# | Builtin indentation helper. |
| Code Diff | `code.diff` | Left, Right | Line-level code diff. |
| AST Viewer | `code.ast` | Code; `language` | Language-aware structure outline. |
| Snippet Manager | `code.snippets` | Snippet body; `action`, `name`, `language` | Save / list / load / delete persistent snippets. |
| Code Screenshot | `code.screenshot` | Code; `language` | Renders code to a PNG. |
| GitHub Gist Uploader | `code.gist` | File contents; `filename`, `description`, `public` | Creates a GitHub gist via the API. Requires the `githubToken` secret in Vehla Store settings for Toolbox. Returns the gist URL. |

---

## 7. SQL & Database

SQLite is fully local. Postgres, MySQL, MongoDB, and Redis helpers use CLIs when
installed, otherwise return offline guidance and formatted statements.

For SQLite tools, `dbPath` may point at a `.db` file **or** a `.sql` dump (loaded
in memory). `sqlPath` / the primary editor can also supply a `.sql` file path.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| SQL Formatter | `sql.formatter` | SQL or `.sql` path; `sqlPath` | Pretty-prints SQL. |
| SQL Beautifier | `sql.beautifier` | SQL or `.sql` path; `sqlPath` | Alias for the SQL formatter. |
| SQL Query Runner | `sql.runner` | SQL or `.sql` path; `dbPath`, `sqlPath` | Runs SQL against a `.db` or in-memory dump. |
| SQLite Browser | `sql.sqliteBrowser` | Options: `dbPath` | Lists tables / preview for a `.db` or `.sql` dump. |
| SQLite Editor | `sql.sqliteEditor` | SQL or `.sql` path; `dbPath`, `sqlPath` | Executes statements against DB or in-memory dump. |
| SQLite Diff | `sql.sqliteDiff` | Options: `dbPath`, `otherDbPath` | Diffs two DB schemas or `.sql` dumps. |
| CSV Importer | `sql.csvImport` | CSV; `dbPath`, `table` | Imports CSV rows into SQLite. |
| CSV Exporter | `sql.csvExport` | Optional SQL; `dbPath`, `table`, `sqlPath` | Exports a table or query result to CSV. |
| ER Diagram Generator | `sql.er` | Options: `dbPath` | Emits Mermaid `erDiagram` from SQLite schema. |
| MongoDB Query Builder | `sql.mongo` | Filter JSON; `collection`, `url` | Builds `find` snippets; runs via `mongosh`/`mongo` when `url` is set. |
| PostgreSQL Helper | `sql.postgres` | Optional SQL / `.sql`; `url`, `sqlPath` | Offline connection examples + format, or execute via `psql`. |
| MySQL Helper | `sql.mysql` | Optional SQL / `.sql`; `url`, `password`, `sqlPath` | Offline help + format, or execute via `mysql`. |
| Redis Browser | `sql.redis` | Optional command; `host`, `port`, `password` | Runs `redis-cli` (defaults to `PING`) or offline command help. |
| Redis Key Explorer | `sql.redisKeys` | Options: `host`, `port`, `password`, `pattern` | `SCAN` by pattern (falls back to `KEYS`). |
| Redis TTL Viewer | `sql.redisTTL` | Key; `host`, `port`, `password`, `key` | Shows TTL for a key. |
| SQL Explain Visualizer | `sql.explain` | SQL or `.sql`; `dbPath`, `sqlPath` | Tree + Mermaid from SQLite `EXPLAIN QUERY PLAN` (HTML preview). |
| SQL Migration Viewer | `sql.migrations` | Options: `dbPath` | Views DB DDL or a `.sql` dump. |
| Schema Comparer | `sql.schemaCompare` | Options: `dbPath`, `otherDbPath` | Diffs two schemas or dumps. |

---

## 8. Generators

Produce sample data, credentials, CSS/Tailwind snippets, and SEO files.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| UUID Generator | `gen.uuid` | Options: `count`, `version` | Generates UUIDs. |
| Fake Data Generator | `gen.fake` | Options: `count` | Rich sample people, companies, phones, and addresses as JSON. |
| Mock API Generator | `gen.mockApi` | Resource name; `count` | Express-style JSON mock route stubs. |
| SQL Data Generator | `gen.sqlData` | Table name; `count`, `columns` | `INSERT` statements for sample rows. |
| Test Data Generator | `gen.testData` | Entity name; `count` | JSON fixtures for tests. |
| Password Generator | `gen.password` | Options: `length`, `charset`, `count` | Secure random passwords. |
| Color Palette Generator | `gen.palette` | Optional seed hex; `count` | Harmonized hex palettes. |
| CSS Shadow Generator | `gen.cssShadow` | Options: `x`, `y`, `blur`, `spread`, `color` | `box-shadow` snippets. |
| CSS Gradient Generator | `gen.cssGradient` | Options: `type`, `angle`, `from`, `to` | Linear/radial gradient CSS. |
| CSS Animation Generator | `gen.cssAnimation` | Name; `duration`, `easing` | `@keyframes` + `animation` snippet. |
| Tailwind Class Builder | `gen.tailwindClass` | Options: `layout`, `spacing`, `color`, `text` | Composes utility class strings. |
| Tailwind Color Generator | `gen.tailwindColor` | Base hex; `name` | Shade scale from a base color. |
| HTML Email Generator | `gen.htmlEmail` | Subject/title; `preheader` | Table-based transactional email template. |
| Sitemap Generator | `gen.sitemap` | URLs (one per line) | Builds XML sitemap. |
| robots.txt Generator | `gen.robots` | Optional sitemap URL; `userAgent`, `disallow` | Builds a `robots.txt`. |
| robots.txt Tester | `gen.robotsTest` | robots.txt + Path | Checks allow/disallow for a path. |

---

## 9. Web Dev

Playgrounds, local servers, browser-storage probes, PWA checks, and CSS layout
visualizers. Playgrounds and layout tools use live WebKit previews.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| HTML Playground | `web.htmlPlayground` | HTML body | Live WebKit preview of HTML. |
| CSS Playground | `web.cssPlayground` | CSS + optional HTML body | Live preview of CSS against sample/custom markup. |
| JavaScript Playground | `web.jsPlayground` | JS + optional HTML body | Live preview of JavaScript in WebKit. |
| Live Web Server | `web.liveServer` | HTML / notes; `port`, `action` | Serves HTML via local `python3 -m http.server` (`start` / `stop`). |
| Local HTTPS Server | `web.httpsServer` | HTML; `port`, `action` | Local HTTPS with openssl self-signed cert + Python SSL server. |
| CORS Tester | `web.cors` | URL; `origin`, `method` | Probes CORS response headers. |
| Cookie Editor | `web.cookieEditor` | Cookie header | Parses and rebuilds `Cookie` headers. |
| Local Storage Viewer | `web.localStorage` | HTML page or JSON dump | Live WebKit `localStorage` probe or JSON dump mode. |
| Session Storage Viewer | `web.sessionStorage` | HTML page or JSON dump | Live WebKit `sessionStorage` probe or JSON dump mode. |
| IndexedDB Explorer | `web.indexedDB` | HTML page or export JSON | Live WebKit IndexedDB probe or export summary. |
| Service Worker Viewer | `web.serviceWorker` | `service-worker.js` | Analyzes SW scripts and probes registration APIs. |
| Manifest Validator | `web.manifest` | `manifest.json` | Validates Web App Manifest JSON. |
| Robots.txt Validator | `web.robotsValidate` | `robots.txt` | Validates robots.txt syntax/structure. |
| Sitemap Validator | `web.sitemapValidate` | `sitemap.xml` | Validates sitemap XML. |
| Lighthouse Wrapper | `web.lighthouse` | URL; `preset` | Score summary via `lighthouse` CLI when installed. |
| Accessibility Checker | `web.a11y` | HTML | `@axe-core/cli` when available, else heuristic checks. |
| Color Contrast Checker | `web.contrast` | Foreground hex, Background hex | WCAG contrast ratio (AA / AAA). |
| CSS Specificity Calculator | `web.specificity` | Selector(s) | Scores CSS selectors as `(a,b,c)`. |
| Flexbox Visualizer | `web.flexbox` | Options: `direction`, `justify`, `align`, `items` | Live flex layout preview + CSS. |
| Grid Visualizer | `web.grid` | Options: `cols`, `rows`, `gap` | Live CSS grid preview + CSS. |

---

## 10. Networking

DNS, addressing, scanning, sockets, TLS, and HTTP helpers. Port scans are
intentionally bounded. Prefer these for diagnostics, not aggressive scanning.

| Tool | ID | Inputs / options | What it does |
| --- | --- | --- | --- |
| IP Lookup | `net.ipLookup` | Hostname or IP | Resolves host → IP addresses. |
| Local IP Viewer | `net.localIP` | None | Lists local interface addresses. |
| Public IP Viewer | `net.publicIP` | None | Fetches public IP over HTTPS. |
| CIDR Calculator | `net.cidr` | CIDR (e.g. `10.0.0.0/24`) | Expands/summarizes CIDR blocks. |
| Subnet Calculator | `net.subnet` | IP; `prefix` | Network, broadcast, and host range. |
| DNS Lookup | `net.dns` | Hostname; `type` | A / AAAA / CNAME / MX / TXT via `dig`/`host`. |
| WHOIS Lookup | `net.whois` | Domain or IP | WHOIS via `whois` CLI. |
| Reverse DNS | `net.reverseDns` | IP | PTR lookup. |
| Port Scanner | `net.portScan` | Host; `ports`, `timeoutMs` | Bounded TCP connect scan (ranges capped). |
| TCP Client | `net.tcp` | Payload; `host`, `port` | Sends bytes over TCP and reads a response when available. |
| UDP Client | `net.udp` | Payload; `host`, `port` | Sends a UDP datagram. |
| Ping Utility | `net.ping` | Host; `count` | ICMP ping via `ping` CLI. |
| Traceroute | `net.traceroute` | Host | `traceroute` / `traceroute6` CLI. |
| SSL Certificate Inspector | `net.sslInspect` | Host; `port` | Leaf certificate details via `openssl`. |
| SSL Chain Viewer | `net.sslChain` | Host; `port` | Shows the certificate chain. |
| TLS Handshake Tester | `net.tlsHandshake` | Host; `port` | Probes TLS with `openssl s_client`. |
| HTTP Header Viewer | `net.httpHeaders` | URL | Fetches response headers. |
| Cookie Inspector | `net.cookieInspect` | Cookie / Set-Cookie text | Parses cookie attribute pairs. |
| User-Agent Parser | `net.userAgent` | User-Agent string | Browser, engine, OS, device, architecture, bot signals. |
| MIME Type Lookup | `net.mime` | Extension or MIME | Extension ↔ MIME mapping. |

---

## Architecture notes

- **UI:** SwiftUI workspace (`WorkspaceView` + `WorkspaceStore`) hosted by
  Vehla Native UI. The store owns selection, editors, options, run state,
  preview HTML, and preference restore.
- **Execution:** `ToolWorker` dispatches to category actors (`JSONTools`,
  `EncodingTools`, `CryptoTools`, `DateTools`, `TextTools`, `CodeTools`,
  `SQLTools`, `GeneratorTools`, `WebTools`, `NetworkTools`).
- **Catalog source of truth:** `Sources/ToolboxWorkspace/ToolCatalog.swift`
  (keep the README tables in sync when adding tools).
- **Previews:** `ToolOutput.previewHTML` drives an embedded `WKWebView` for
  playgrounds, Markdown, flex/grid, storage probes, service workers, and SQL
  explain diagrams.
- **Themes:** Follows live Vehla theme updates via `VehlaWorkspaceTheme`.
- **Limits:** Large inputs are guarded (see `ToolLimits`); outputs may be
  truncated for safety.
- **Tests:** `swift test` covers hashing, JSON/YAML/JSONPath, SQL dump paths,
  generators, layout previews, jq/JMESPath, and catalog readiness.

### Limits

| Limit | Value |
| --- | --- |
| Max input size | 8 MiB (`ToolLimits.maxInputBytes`) |
| Max output characters | 2,000,000 (then truncated with a marker) |

### Honest scope (thin / helper tools)

These tools are useful locally but are **not** full replacements for dedicated
CLIs or browser DevTools. Catalog subtitles also call this out.

| Area | What you actually get |
| --- | --- |
| JSONPath / JMESPath / jq | Embedded subsets (filters, pipes, map/select, slices). Not CLI `jq`. |
| AST Viewer | Language-aware structure outline — not SwiftSyntax / tree-sitter AST. |
| HTML Preview (Text) | Tag strip → plain text. Use Web HTML Playground for rendering. |
| Markdown Preview vs Editor | Preview = attributed/text dump; Editor = live HTML. |
| File Hash | Hashes `filePath` (Browse) **or** editor text bytes. |
| Stopwatch | Manual lap/`action` helper — not a live ticking UI. |
| RRULE / Cron | Simple builders + next-fire estimates — not full iCal/cron dialects. |
| Schema / Fake JSON | Shallow inference / template samples. |
| Mongo / Postgres / MySQL / Redis | Offline helpers + local CLI wrappers when installed. |
| Lighthouse / a11y | CLI score summary or static heuristics. |
| Storage / IndexedDB / SW | WebKit probe pages + heuristics — not Chrome DevTools. |
| Port Scanner | TCP connect only; ranges capped (~64 ports), short timeouts. |
| AES | Passphrase → SHA-256 → AES-GCM only (not arbitrary AES modes/KDFs). |
| PBKDF2 | Default salt is `"toolbox"` if you leave `salt` empty — set your own. |
| Base85 / ASCII85 | Same Ascii85 implementation (aliases). |
| C# Formatter | Builtin indentation helper (`dotnet format` is not wired). |
| Local HTTP(S) servers | Bind **127.0.0.1** only; HTTPS uses a self-signed cert. |

### Query engine caveats

| Engine | Supported highlights | Not included |
| --- | --- | --- |
| JSONPath | `$..`, filters, slices | Full Jayway/Goessner supersets |
| JMESPath | Projections, `[?…]`, pipes, slices, `keys` / `length` | Every builtin / multi-select edge case |
| jq | Paths, pipes, `map`/`select`, `keys`, `length`, `type`, `to_entries`, `sort`, `unique`, `flatten` | Full jq language / modules |

For production pipelines, keep using real `jq` / `psql` / browser DevTools.

## Security notes

- Password hashing and AES/RSA run locally; nothing is uploaded unless you use
  a network tool or gist upload.
- The `githubToken` secret is read from Vehla’s Keychain-backed secret storage
  at run time for `code.gist` only — it is not written into snippet files.
  Missing/invalid tokens surface as clear run errors (empty secret → prompt to
  configure; HTTP 401 from GitHub → failed with message).
- Redis may pass `-a password` on the `redis-cli` process command line (visible
  to local process listings). MySQL uses `MYSQL_PWD` in the process environment.
- Port scanning and remote probes are for hosts you are authorized to test.
  Scans are bounded (port ranges capped, short timeouts).
- WebKit previews enable `allowFileAccessFromFileURLs` for local HTML probes —
  only load content you trust.
- Local servers write under `NSTemporaryDirectory` and listen on loopback;
  stop with `action=stop`.
- Review any exported SQL dumps, cookie headers, or tokens before sharing.
- Local HTTPS uses a **self-signed** certificate suitable for development only.

## Contributing / extending

1. Add a `ToolDefinition` in `ToolCatalog.swift`.
2. Implement the `case` in the matching category actor under `Engine/`.
3. Keep work off the main actor; use `CLIProcessRunner` for subprocesses.
4. Add or extend tests in `Tests/ToolboxWorkspaceTests`.
5. Document the tool in this README’s catalog tables.
6. Bump version + What’s New when the change is user-visible.
7. Run `swift test && ./build.sh` and reinstall `dist/Toolbox`.

## Versioning

Current release: **1.0.0** (bundle version `2`). See `CHANGELOG.md`.

Bump `extension.json` `version` and `Info.plist`
(`CFBundleShortVersionString` / `CFBundleVersion`) together when shipping.
User-visible changes should also update Vehla’s What’s New entry for the
current app release.

CI: `.github/workflows/toolbox-native.yml` runs `swift test` and `./build.sh`
when this package (or the Swift SDK) changes.

## License and authorship

Copyright © 2026 ibuhs. Licensed under the MIT License — see `LICENSE`.

Third-party components are listed in `THIRD_PARTY_NOTICES.md`.

This extension was created with the help of AI and was reviewed by a human
before release. Treat the catalog documentation and offline/CLI fallbacks as
the contract for what each tool guarantees.
