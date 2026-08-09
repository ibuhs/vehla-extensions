# Changelog

All notable changes to Toolbox Native are documented here.

## 1.0.1 — 2026-08-08

### Added
- QuickGlass actions for common JSON, encoding, hashing, date, text, and code
  transformations.
- Prefilled Toolbox handoff for actions that require the full workspace.

### Fixed
- QuickGlass transformations now preserve output whitespace and use the correct
  result presentation.

## 1.0.0 — 2026-07-24

Initial public package identity: `com.ibuhs.vehla.toolbox`.

### Added
- Full ready catalog of **196** tools across JSON, Encoding, Cryptography,
  Date & Time, Text, Code, SQL & Database, Generators, Web Dev, and Networking.
- Off-main-thread execution via `ToolWorker` and category actors.
- Real bcrypt (OpenBSD `$2b$`) and Argon2id (RFC 9106 / PHC C).
- YAML (Yams), TOML (TOMLKit), BSON, MessagePack decode, Splash highlighting.
- Live WebKit playgrounds, flex/grid previews, Markdown HTML preview.
- SQLite `.db` / `.sql` dump workflows, SQL explain trees, Redis SCAN helpers.
- GitHub Gist Uploader (`code.gist`) using the `githubToken` secret.
- Option pickers for common enums, empty-search UI, file browse for hashing,
  and PNG preview for code screenshots.

### Notes
- jq / JMESPath / JSONPath are embedded subsets, not full CLI engines.
- Postgres / MySQL / Mongo / Redis / Lighthouse / axe use local CLIs when present.
- Created with AI assistance; reviewed by a human before release.
