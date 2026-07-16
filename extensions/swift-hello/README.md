# Swift Hello

A native executable extension built with the Vehla Store Swift SDK.

It demonstrates:

- The `executable` Store runtime.
- Async Swift command handlers.
- Declarative form values.
- Native rich result views and actions.
- Optional brokered notifications.
- Out-of-process crash isolation.
- Background-only execution without a Dock icon or app activation.

## Build

From the `vehla-extensions` repository:

```sh
zsh extensions/swift-hello/build.sh
```

The script creates an optimized Apple Silicon executable, writes `extensions/swift-hello/bin/swift-hello` with executable permissions, and applies an ad hoc code signature.

Validate or test it with the included CLI:

```sh
swift run --package-path sdk/swift vehla-swift validate extensions/swift-hello
swift run --package-path sdk/swift vehla-swift test extensions/swift-hello runtime
```

## Install

Open **Vehla Settings → Store → Install Local Package** and choose `extensions/swift-hello`.

Run:

- `swifthello` — submit a form and render a greeting.
- `swiftruntime` — inspect the native extension process.

## Distribution

The build script produces an arm64-only executable suitable for catalog distribution. Intel and universal native packages are intentionally unsupported.

Native extensions run with the user’s macOS privileges. Vehla requires a valid arm64 Mach-O binary and code signature and runs commands as background-only processes. Process isolation protects Vehla from extension crashes but does not sandbox extension code.
