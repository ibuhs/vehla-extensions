# Vehla Extension SDKs

This directory contains the public SDKs for building Vehla Store extensions.

## Runtime matrix

| Store API | Runtime | SDK product | Process model |
| --- | --- | --- | --- |
| 1 | `node` | `@vehla/store-sdk` | Out of process, one invocation |
| 1 | `executable` | `VehlaStoreSDK` | Out of process, one invocation |
| 2 | `nativeUI` | `VehlaNativeUISDK` | Signed bundle loaded in Vehla |
| 3 | `dockWidget` | `VehlaDockWidgetSDK` | Signed bundle loaded in Vehla |
| 4 | `notch` | `VehlaNotchSDK` | Signed bundle loaded in Vehla, only while turned on |

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
- `VehlaNotchSDK` for `runtime: "notch"`

`VehlaNativeUISDK` and `VehlaDockWidgetSDK` are dynamic products. Bundle build
scripts rewrite their dylib references to the matching frameworks embedded by
Vehla. They are plugin contracts, not standalone application frameworks.

`VehlaNotchSDK` is a static library: it is compiled into the extension's bundle
and Vehla embeds no framework for it. The two sides meet through the
Objective-C protocols `VehlaNotchHost` and `VehlaNotchPlugin`.

## Live activities from any extension (Store API 4)

A live activity is plain data that Vehla draws, so an extension doesn't have to
be a Notch extension to show one. Palette, QuickGlass and native workspace
extensions can post activities too, with none of their code loaded into or
kept running in Vehla.

Declare the ids in `extension.json` and set `"apiVersion": 4`:

```json
"notch": { "activities": [ { "id": "focus", "title": "Focus timer" } ] }
```

Only Notch packages may declare tabs or `background`.

**Node / executable commands** answer with the activity and exit:

```js
return Store.notchActivity("focus", {
  title: "Focus", systemImage: "timer", tint: "#FF9F0A",
  countdown: 25 * 60,            // a clock instead of `detail`
  command: "start",              // run when the activity is clicked
  buttons: [{ title: "Stop", systemImage: "stop.fill", command: "stop" }],
});
// later: return Store.endNotchActivity("focus");
```

Fields: `title`, `detail`, `systemImage`, `tint` ("#RRGGBB"), `progress` (0–1),
`seconds` (how long it stays, 2 s to 8 h), `countdown`, `end`, `command` /
`query`, and up to two `buttons`, each running one of the package's own
commands. Swift commands use `Store.notchActivity(_:_:)` with
`StoreNotchActivity`. See `extensions/focus-timer`.

**Native workspaces** call the context:

```swift
context.showNotchActivity(.init(id: "export", title: "Exporting", progress: 0.4,
                                workspaceID: "main"))   // a click opens the workspace
context.endNotchActivity(id: "export")
```

Packages using this are API 4, so they are listed in `catalog-api4.json` and
only install on Vehla versions that know API 4.

## Notch / Island extensions

A Notch extension adds either or both of:

- **Live activities** in the closed Notch (and the floating Island's title):
  a symbol, a title, a short detail or a running clock, an optional progress
  ring and up to two buttons. They are data (`VehlaNotchActivity`); Vehla draws
  them, so every activity looks at home and costs the extension no views.
- **Tabs** in the open Notch / Island, drawn by the extension's own
  `NSViewController` (SwiftUI through `NSHostingController` is fine). Each tab
  gets its own icon in the Notch's tab bar, the manifest's `systemImage` (a
  puzzle piece when omitted), with `title` as its tooltip, and the whole
  content area below the bar. That area is small (about 160 points high in the
  Notch, a little taller in the floating Island), so lay out for it, fill the
  size you are given and scroll anything longer.
  A tab that needs more room can ask for it with `"height"` (points of content,
  160 to 320) in its manifest entry; the Notch grows while that tab shows.

```json
{
  "apiVersion": 4,
  "runtime": "notch",
  "entrypoint": "bin/MyExtension.bundle",
  "capabilities": ["persistentStorage"],
  "notch": {
    "background": false,
    "tabs": [{ "id": "main", "title": "My Tab", "systemImage": "star.fill" }],
    "activities": [{ "id": "status", "title": "Status" }]
  }
}
```

```swift
@objc(MyPlugin)
public final class MyPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    private var notch: VehlaNotch?

    public func notchDidStart(_ host: any VehlaNotchHost) {
        notch = VehlaNotch(host)
        notch?.show(.init(id: "status", systemImage: "star.fill", title: "Ready", duration: 5))
    }

    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        NSHostingController(rootView: Text("Hello"))
    }
}
```

Rules that keep an extension cheap:

- Nothing is loaded until the user turns the extension on in Settings › Notch /
  Island › Extensions, and every install or update turns it off again.
- With `"background": false` the bundle is loaded when one of its tabs is first
  opened. Set `"background": true` only when the extension must start
  activities by itself while the Notch is closed; it is then loaded when the
  Notch starts.
- A tab's view controller is created when the tab comes on screen and released
  when it leaves. Keep state in your own model, not in the view controller.
- Stop timers and tasks in `notchWillStop()`. After it, the host ignores
  everything the extension asks for.
- Limits: 3 tabs and 8 activities per package; titles 60 characters, details
  80, two buttons, an activity lives at most eight hours. Only ids declared in
  the manifest are shown.
- `open(_:)` needs `openURL` (http and https only) and `copy(_:)` needs
  `clipboardWrite`.

See `extensions/notch-lab` for a complete sample.

## Compatibility

| SDK constant / protocol | Manifest requirement |
| --- | --- |
| Store command wire protocol | `apiVersion: 1` |
| `VehlaNativeUIAPIVersion` | `apiVersion: 2`, `runtime: "nativeUI"` |
| `VehlaDockWidgetAPIVersion` | `apiVersion: 3`, `runtime: "dockWidget"` |
| `VehlaNotchAPIVersion` | `apiVersion: 4`, `runtime: "notch"` |

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
