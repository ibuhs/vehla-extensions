# Vehla Extension SDKs

This directory contains the public SDKs for building Vehla Store extensions.

## Runtime matrix

| Store API | Runtime | SDK product | Process model |
| --- | --- | --- | --- |
| 1 | `node` | `@vehla/store-sdk` | Out of process, one invocation |
| 1 | `executable` | `VehlaStoreSDK` | Out of process, one invocation |
| 2 | `nativeUI` | `VehlaNativeUISDK` | Signed bundle loaded in Vehla |
| 3 | `dockWidget` | `VehlaDockWidgetSDK` | Signed bundle loaded in Vehla |

Command runtimes are isolated from Vehla crashes but are not an operating-system
sandbox. Native UI and Dock Widget bundles run inside Vehla and must be treated
like installed desktop software.

## TypeScript / JavaScript

See [`typescript/README.md`](typescript/README.md). Packages in this repository
use a local dependency:

```json
"@vehla/store-sdk": "file:../../sdk/typescript"
```

Run `npm install --install-links` so the installed extension is self-contained.

## Swift

See [`swift/README.md`](swift/README.md). Packages in this repository use:

```swift
.package(path: "../../sdk/swift")
```

Choose the product matching the manifest runtime:

- `VehlaStoreSDK` for `runtime: "executable"`
- `VehlaNativeUISDK` for `runtime: "nativeUI"`
- `VehlaDockWidgetSDK` for `runtime: "dockWidget"`

`VehlaNativeUISDK` and `VehlaDockWidgetSDK` are dynamic products. Bundle build
scripts rewrite their dylib references to the matching frameworks embedded by
Vehla. They are plugin contracts, not standalone application frameworks.

## Compatibility

| SDK constant / protocol | Manifest requirement |
| --- | --- |
| Store command wire protocol | `apiVersion: 1` |
| `VehlaNativeUIAPIVersion` | `apiVersion: 2`, `runtime: "nativeUI"` |
| `VehlaDockWidgetAPIVersion` | `apiVersion: 3`, `runtime: "dockWidget"` |

Vehla validates the manifest API and plugin API before loading native code.
Rebuild and republish extension bundles whenever their SDK-linked bytes change.

## Validate and test

```sh
swift test --package-path sdk/swift
swift run --package-path sdk/swift vehla-swift help
swift run --package-path sdk/swift vehla-swift validate path/to/extension
```

For signed catalog releases, archive checksums and Ed25519 publisher signatures
are separate from the Mach-O code signature on an executable or bundle.

See [`CHANGELOG.md`](CHANGELOG.md) for SDK surface changes.
