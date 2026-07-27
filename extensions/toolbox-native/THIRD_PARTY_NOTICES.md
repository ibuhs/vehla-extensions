# Third-party notices

Toolbox Native incorporates the following open-source components.

## VehlaNativeUISDK

Local path dependency (`../../sdk/swift`). Copyright Kaila Labs / Vehla.
Licensed under the terms of the Vehla SDK / host project.

## BCryptSwift

- https://github.com/wisetail/BCryptSwift
- Used for OpenBSD-compatible bcrypt hashing.

## BSON (Orlandos)

- https://github.com/orlandos-nl/BSON
- Used for BSON → JSON decoding.

## Yams

- https://github.com/jpsim/Yams
- Used for YAML ↔ JSON conversion (libYAML).

## TOMLKit

- https://github.com/LebJe/TOMLKit
- Used for TOML ↔ JSON conversion.

## Splash

- https://github.com/JohnSundell/Splash
- Used for Swift syntax highlighting.

## Argon2 (PHC winner)

- https://github.com/P-H-C/phc-winner-argon2
- Vendored under `Sources/CArgon2` (see `Sources/CArgon2/NOTICE`).
- Dual-licensed CC0 1.0 / Apache 2.0 by the Argon2 authors.

## Apple system libraries

- `sqlite3` — linked for SQLite browser, runner, explain, and related tools.
- Security / CryptoKit / Network / WebKit frameworks — system APIs.

Optional command-line tools invoked at runtime (`prettier`, `eslint`, `psql`,
`openssl`, `lighthouse`, etc.) remain the user’s responsibility; Toolbox does
not redistribute them.
