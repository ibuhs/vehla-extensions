# Swift Hello

A native executable extension built with the Vehla Store Swift SDK.

It demonstrates:

- The `executable` Store runtime.
- Async Swift command handlers.
- Declarative form values.
- Native rich result views and actions.
- Optional brokered notifications.
- Out-of-process crash isolation.

## Build

From the Vehla repository:

```sh
zsh examples/swift-hello/build.sh
```

The script uses scratch directories under `DerivedData`, creates optimized Apple Silicon and Intel executables, combines them into a universal binary, and writes `examples/swift-hello/bin/swift-hello` with executable permissions.

## Install

Open **Vehla Settings → Store → Install Local Package** and choose `examples/swift-hello`.

Run:

- `swifthello` — submit a form and render a greeting.
- `swiftruntime` — inspect the native extension process.

## Distribution

The build script produces a universal `arm64` and `x86_64` executable suitable for catalog distribution.

Native extensions run with the user’s macOS privileges. Process isolation protects Vehla from extension crashes but does not sandbox extension code.
