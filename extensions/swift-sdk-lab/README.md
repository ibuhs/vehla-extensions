# Swift SDK Lab

Swift SDK Lab is the complete reference extension for Vehla’s native service APIs. One command exercises private file storage, typed preferences, structured redacted logging, and permission-aware HTTP networking in a signed arm64 background process.

## What it demonstrates

- `StoreStorage` with atomic Codable writes inside the package’s private directory.
- `StorePreferences` with a typed persistent run counter.
- `StoreLogger` with structured metadata and automatic secret redaction.
- `StoreHTTPClient` with capability checks, HTTP/HTTPS validation, timeouts, response limits, and status handling.
- Invocation-level `grantedCapabilities`.
- Declarative forms and rich native result views.

## Build and validate

From the Vehla repository:

```sh
swift run --package-path sdk/swift \
  vehla-swift build examples/swift-sdk-lab

swift run --package-path sdk/swift \
  vehla-swift validate examples/swift-sdk-lab
```

The output must report:

- `Architectures: arm64`
- `Code signature: valid`
- `Execution: background-only`

## Test from the CLI

```sh
swift run --package-path sdk/swift \
  vehla-swift test examples/swift-sdk-lab run-demo
```

The CLI grants the capabilities declared by the manifest. The command uses its default note and GitHub Zen endpoint when form values are absent.

## Install in Vehla

1. Open **Vehla Settings → Store**.
2. Choose **Install Local Package**.
3. Select `examples/swift-sdk-lab`.
4. Review the native executable warning.
5. Set **Access the Network** and **Store Extension Data** to Ask or Allow.
6. Optionally configure the `apiToken` secret.
7. Run `swiftsdklab` or `sdklab`.
8. Enter a note and an HTTP or HTTPS endpoint.

The first run requests both declared permissions. The result displays the persistent run count, storage round trip, final HTTP URL, response status, response size, body preview, and invocation grants.

## Persistence behavior

The example writes:

```text
<Vehla Store data>/com.vehla.examples.swift-sdk-lab/
├── .vehla/
│   └── preferences.json
└── runs/
    └── latest.json
```

`StoreStorage` rejects absolute paths, empty path components, `.` and `..`, backslashes, and symlink escapes. Writes are atomic.

`StorePreferences` serializes each value independently with `Codable`, allowing different keys to contain different strongly typed values.

## Logging and secrets

The logger emits one JSON record per line to standard error. Vehla captures bounded diagnostics, and the SDK replaces every configured secret value with `[REDACTED]` before writing.

Do not intentionally log credentials. Redaction is defense-in-depth for accidental disclosure.

## Networking security

`StoreHTTPClient` refuses to initialize unless Vehla granted `networkAccess` for the invocation. It accepts only HTTP and HTTPS URLs, limits request bodies to 1 MB, defaults response bodies to 5 MB, and limits timeouts to 15 seconds.

Native extensions are not sandboxed and can bypass SDK helpers. Publisher trust, native-install consent, code-signature validation, and source review remain important.
