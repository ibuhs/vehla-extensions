# Vehla Store Swift SDK

Build native command extensions as standalone Swift executables. Vehla launches each invocation out of process, sends one request through standard input, and reads one structured response from standard output.

Native extensions are not loaded into Vehla’s process. A crash terminates only the extension invocation.

## What this SDK provides

The SDK gives Swift extension authors:

- Typed command invocations.
- Selected-text and clipboard context.
- Keychain-backed secret values.
- Declarative form values.
- Native file-picker metadata.
- Private persistent-data directory metadata.
- Confined atomic file storage and typed preferences.
- Structured logging with automatic secret redaction.
- Permission-aware bounded HTTP networking.
- Brokered clipboard, URL, message, and notification actions.
- Structured native result views.
- Async and throwing command handlers.
- Protocol framing and error responses hidden behind `runStoreExtension`.

Vehla still owns command discovery, permission prompts, forms, result rendering, process limits, and catalog verification.

## Runtime architecture

Each command invocation follows this lifecycle:

1. Vehla finds the command in `extension.json`.
2. Vehla asks for required package permissions.
3. Vehla presents the command’s declarative form, if any.
4. Vehla starts the package’s executable in a separate process.
5. The Swift SDK decodes the invocation and calls your handler.
6. Your handler returns a `StoreResult` or throws an error.
7. The SDK encodes the result for Vehla.
8. Vehla validates and renders the result or performs its brokered action.
9. Vehla terminates the extension process.

Standard output belongs exclusively to the SDK protocol. Write diagnostics to standard error.

## Background-only execution guarantee

All Store command extensions execute outside Vehla’s process. Swift SDK extensions additionally enforce background-only application behavior:

- Vehla launches the executable as a child process without activating it.
- Vehla performs process waiting and pipe reads outside the app’s main actor.
- The runtime sets `VEHLA_EXTENSION_BACKGROUND=1`.
- The Swift SDK sets the process activation policy to `prohibited`.
- Extensions cannot create a Dock icon, menu bar, or independently activated app UI through the supported SDK lifecycle.
- Forms, permission prompts, and results are presented by Vehla.

Background-only does not mean persistent. The process starts for one user-requested command and must finish within 15 seconds. Long-running daemons, scheduled jobs, and always-on background services are not currently supported.

## Native UI workspaces

`VehlaNativeUISDK` is a separate, opt-in runtime for complete SwiftUI or
AppKit workspaces hosted inside Vehla's palette panel. Native workspaces use
Store API 2, `runtime: "nativeUI"`, and a signed `.bundle` entrypoint.

Unlike command extensions, native UI bundles load into Vehla's process.
They are **not sandboxed** and must be treated like downloaded desktop
software: they can read or alter Vehla memory, access anything available to
Vehla, make network requests, and crash or compromise the app. Vehla shows a
critical risk warning before installation and requires fresh consent before
the first launch of every package version.

The principal class conforms to `VehlaNativeWorkspacePlugin` and returns an
`NSViewController`. SwiftUI workspaces use `NSHostingController`:

```swift
import SwiftUI
import VehlaNativeUISDK

@objc(MyWorkspacePlugin)
final class MyWorkspacePlugin: NSObject, VehlaNativeWorkspacePlugin {
    let apiVersion = VehlaNativeUIAPIVersion
    let workspaces = [
        VehlaWorkspaceDescriptor(id: "main", title: "My Workspace")
    ]

    @MainActor
    func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController {
        NSHostingController(rootView: MyWorkspaceView(context: context))
    }

    @MainActor
    func workspace(
        _ workspaceID: String,
        themeDidChange theme: VehlaWorkspaceTheme
    ) {
        // Update any custom colors cached by the workspace.
    }
}
```

`context.theme` contains Vehla's current appearance when the workspace opens.
Vehla calls `workspace(_:themeDidChange:)` when that appearance changes.
AppKit semantic colors and SwiftUI's color scheme also inherit the host panel's
appearance. Use `backgroundColor` for the workspace backdrop and
`surfaceColor` for themed panels or overlays.

`context.localAI` provides optional, text-only access to the on-device model
selected and downloaded in Vehla. Check `isAvailable`, display `statusLabel`
when useful, and send a conversation with `complete(messages:)`:

```swift
guard let localAI = context.localAI, localAI.isAvailable else { return }
let response = try await localAI.complete(messages: [
    VehlaWorkspaceAIMessage(role: .system, content: "Be concise."),
    VehlaWorkspaceAIMessage(role: .user, content: prompt),
])
```

A native UI manifest declares each hosted surface and maps commands to it:

```json
{
  "apiVersion": 2,
  "id": "com.example.native-workspace",
  "name": "Native Workspace",
  "version": "1.0.0",
  "runtime": "nativeUI",
  "entrypoint": "bin/NativeWorkspace.bundle",
  "capabilities": ["persistentStorage"],
  "workspaces": [{
    "id": "main",
    "title": "Native Workspace",
    "preferredWidth": 1180,
    "preferredHeight": 760
  }],
  "commands": [{
    "id": "open",
    "title": "Open Native Workspace",
    "workspaceID": "main"
  }]
}
```

Vehla owns the panel, activation, sizing, live theme context, local AI bridge,
package data directory, Keychain-backed secrets, first-launch consent, and
crash recovery. The bundle remains loaded until Vehla exits; disabling or
uninstalling it prevents future launches but does not safely unload executable
code mid-run.

Native UI packages must declare `persistentStorage`. Vehla authorizes that
capability before creating the workspace and provides the resulting private
directory through `context.dataDirectory`.

## Dock widgets

`VehlaDockWidgetSDK` defines Store API 3's trusted in-process Dock widget
contract. A bundle principal class conforms to `VehlaDockWidgetPlugin`,
publishes `VehlaDockWidgetDescriptor` values, and creates one
`NSViewController` for each requested compact, inline, or popup surface.
`VehlaDockWidgetContext` provides package-confined data storage, the current
theme, invalidation, and brokered copy, open, message, and notification
actions.

Use `context.theme.tileTextColor` for text and icons on compact and inline
surfaces. Vehla resolves that color from the user's Dock widget contrast
setting and sends updated values through `widget(_:themeDidChange:)`. Popup
surfaces should continue to use `primaryTextColor` and `secondaryTextColor`,
which follow the current Command Palette theme. Widgets built against an older
SDK automatically fall back to `primaryTextColor`.

The optional `context.localAI` bridge gives trusted widgets text-only
completion access to the on-device MLX model selected and downloaded in Vehla.
Vehla owns model loading and inference; widgets pass `VehlaDockWidgetAIMessage`
values and do not link MLX or access model files. Check `isAvailable`, show
`statusLabel` when unavailable, and call `complete(messages:)` from a
cancellable task.

`context.open(_:)` accepts `http`, `https`, and
`x-apple.systempreferences` URLs. The System Settings scheme lets widgets open
an appropriate macOS settings pane without launching processes directly.

All view creation and lifecycle callbacks run on `MainActor`. Lifecycle
callbacks are synchronous notifications and must return immediately; they
cannot be async because the plugin protocol is Objective-C compatible.
Plugins should launch asynchronous work in cancellable `Task`s stored by a
plugin-owned actor, cancel visibility-specific work when the phase becomes
hidden, and cancel all remaining work from `widgetWillClose(_:)`. Never block
the main actor while waiting for a task.

Packages declaring both `clipboardRead` and `clipboardWrite` may receive
`context.clipboard`, an optional bridge to Vehla's canonical clipboard history.
The bridge exposes text, links, image file URLs, source applications, and pin
state, plus restore, delete, clear, pin, and active-viewer operations. Its
history includes native captures and imported AwesomeCopy clips. Keep a
fallback for older hosts where `context.clipboard` is `nil`.

Dock widgets can read and update manifest-declared Keychain values with
`context.secret(named:)`, `setSecret(_:named:)`, and `removeSecret(named:)`.
Only secret IDs listed in `extension.json` are accepted.

A Dock widget package uses a signed `.bundle` and may omit `commands`:

```json
{
  "apiVersion": 3,
  "id": "com.example.build-widgets",
  "name": "Build Widgets",
  "version": "1.0.0",
  "runtime": "dockWidget",
  "entrypoint": "bin/BuildWidgets.bundle",
  "capabilities": ["persistentStorage"],
  "dockWidgets": [{
    "id": "build-status",
    "title": "Build Status",
    "subtitle": "Latest pipeline result",
    "systemImage": "hammer",
    "preferredPopupWidth": 480,
    "preferredPopupHeight": 560,
    "supportedSurfaces": ["compact", "inline", "popup"]
  }]
}
```

Every widget must support `compact`. Popup widths must be 280–1200 points and
heights 220–900 points. Dock widget packages cannot declare workspaces.
They must declare `persistentStorage`; the authorized private directory is
available through `context.dataDirectory`.
Like native UI workspaces, these bundles execute inside Vehla and are not a
security sandbox.

The complete
[`swift-dock-widget`](https://github.com/ibuhs/Vehla/tree/main/examples/swift-dock-widget)
reference package demonstrates all three surfaces, host actions, and a
cancellable actor-backed background lifecycle. Its `build.sh` rewrites the
SwiftPM SDK dylib reference to the framework embedded by Vehla; custom widget
build scripts must preserve that step.

## Requirements

- macOS 14 or newer.
- An Apple Silicon Mac. Intel executables are not supported.
- Swift 6 or newer.
- A manifest runtime matching the package: `executable`, `nativeUI`, or
  `dockWidget`.
- A compiled executable or signed native bundle included inside the package.
- A valid Mach-O code signature. Ad hoc signing is supported for local development.
- A Vehla build that supports the executable Store runtime.

## Quick start

Use `extensions/swift-hello` as the complete reference package.

Build it:

```sh
zsh extensions/swift-hello/build.sh
```

Install it locally:

1. Open **Vehla Settings**.
2. Select **Store**.
3. Choose **Install Local Package**.
4. Select the `extensions/swift-hello` directory.
5. Confirm that the package appears as a native executable.
6. Run `swifthello` or `swiftruntime` from the palette.

## Developer CLI

The SDK package includes `vehla-swift`, a zero-dependency command-line tool:

```sh
swift run --package-path sdk/swift vehla-swift help
```

Validate a package:

```sh
swift run --package-path sdk/swift \
  vehla-swift validate extensions/swift-hello
```

Validation checks:

- Store API and manifest identity.
- `runtime: executable`.
- Command IDs and titles.
- Entrypoint containment and executable permissions.
- An arm64-only Mach-O architecture.
- Code-signature validity.

Build through the package’s `build.sh`, then validate:

```sh
swift run --package-path sdk/swift \
  vehla-swift build extensions/swift-hello
```

Invoke a command with the same timeout and output constraints as Vehla:

```sh
swift run --package-path sdk/swift \
  vehla-swift test extensions/swift-hello runtime
```

Create a ZIP after validation:

```sh
swift run --package-path sdk/swift \
  vehla-swift package extensions/swift-hello swift-hello-1.2.0.zip
```

Code-sign the entrypoint. Omitting the identity uses an ad hoc signature:

```sh
swift run --package-path sdk/swift \
  vehla-swift sign extensions/swift-hello
```

For Developer ID signing:

```sh
swift run --package-path sdk/swift \
  vehla-swift sign extensions/swift-hello \
  "Developer ID Application: Example Company (TEAMID)"
```

## Recommended package layout

```text
my-swift-extension/
├── extension.json
├── Package.swift
├── build.sh
├── Sources/
│   └── MyExtension/
│       └── main.swift
└── bin/
    └── my-extension
```

The installed package must contain `bin/my-extension`. Source files alone are not enough because Vehla does not compile extensions during installation.

## Add the SDK dependency

```swift
dependencies: [
    .package(path: "../../sdk/swift"),
]
```

Add `VehlaStoreSDK` to the executable target:

```swift
.executableTarget(
    name: "MyExtension",
    dependencies: [
        .product(name: "VehlaStoreSDK", package: "swift"),
    ]
)
```

The package identity for a local dependency is normally its directory name, `swift`. A complete `Package.swift` looks like this:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyExtension",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MyExtension", targets: ["MyExtension"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .executableTarget(
            name: "MyExtension",
            dependencies: [
                .product(
                    name: "VehlaStoreSDK",
                    package: "swift"
                ),
            ]
        ),
    ]
)
```

## Create the executable entrypoint

```swift
import VehlaStoreSDK

@main
struct MyExtension {
    static func main() async {
        await runStoreExtension { invocation in
            switch invocation.commandID {
            case "hello":
                return Store.showMessage(
                    "Hello, \(invocation.query)"
                )
            default:
                throw ExtensionError.unknownCommand
            }
        }
    }
}
```

Use `LocalizedError` for clear messages:

```swift
enum ExtensionError: LocalizedError {
    case missingInput
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Enter a value before running this command."
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        }
    }
}
```

Thrown error descriptions are returned to Vehla. Vehla redacts configured secrets and secure form values before displaying runtime diagnostics.

## Manifest

```json
{
  "apiVersion": 1,
  "id": "com.example.swift-extension",
  "name": "Swift Extension",
  "version": "1.0.0",
  "runtime": "executable",
  "entrypoint": "bin/my-extension",
  "commands": [
    {
      "id": "hello",
      "title": "Hello from Swift",
      "keywords": ["swifthello"]
    }
  ]
}
```

Important manifest rules:

- `runtime` must be `executable`.
- `entrypoint` must be a relative path inside the package.
- The entrypoint file must exist and have executable permissions.
- Command and package IDs must be stable valid identifiers.
- Every sensitive Vehla broker API must be declared in `capabilities`.
- Native code is not technically prevented from calling system APIs directly; declarations remain a user-facing contract.

Omitting `runtime` preserves the legacy `node` default.

## Handle invocation input

Every handler receives `StoreInvocation`:

```swift
public struct StoreInvocation {
    public let packageID: String
    public let commandID: String
    public let query: String
    public let context: StoreInvocationContext
}
```

Read the command using `commandID`, not the display title:

```swift
switch invocation.commandID {
case "format":
    // Handle command.
case "inspect":
    // Handle command.
default:
    throw ExtensionError.unknownCommand(invocation.commandID)
}
```

`query` contains the palette argument matched after a command keyword. It can be empty.

## Read context safely

Context values are present only when applicable and authorized:

```swift
let selectedText = invocation.context.selectedText
let clipboardText = invocation.context.clipboardText
let dataDirectory = invocation.context.dataDirectory
let token = invocation.context.secrets["apiToken"]
```

Do not assume optional context is available. Ask for the narrowest capability and provide a useful missing-input error.

## Read declarative form values

Form values use `StoreFormValue`:

```swift
let name = invocation.context.formValues["name"]?.stringValue
let enabled = invocation.context.formValues["enabled"]?.boolValue
let file = invocation.context.formValues["file"]?.fileValue
let files = invocation.context.formValues["files"]?.filesValue
```

Supported values:

- `.string(String)` for text, secure text, multiline text, and select fields.
- `.bool(Bool)` for toggle fields.
- `.file(StoreSelectedFile)` for one selected file.
- `.files([StoreSelectedFile])` for multiple selected files.

Validate values again in the extension. The manifest controls presentation, but extension code remains responsible for command-specific requirements.

## Work with selected files

`StoreSelectedFile` contains:

```swift
public struct StoreSelectedFile {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let contentType: String?
}
```

File fields require the `userSelectedFiles` capability. Selection records user intent but does not create a filesystem sandbox. Reject unexpected directories, types, or oversized files before reading.

## Use secrets

Declare secrets in `extension.json`, then read them by ID:

```swift
guard let token = invocation.context.secrets["apiToken"],
      !token.isEmpty else {
    throw ExtensionError.missingInput
}
```

Required secrets prevent invocation until configured. Never print, persist, embed, or return secret values.

## Service APIs

Vehla includes the capabilities granted for the current invocation in `context.grantedCapabilities`. Service constructors reject access when their required capability was not granted.

### Private storage

Declare `persistentStorage`, then use package-confined atomic storage:

```swift
let storage = try invocation.storage()
try storage.write("hello", to: "notes/latest.txt")
let text = try storage.readString("notes/latest.txt")

struct Record: Codable {
    let title: String
    let count: Int
}

try storage.write(
    Record(title: "Vehla", count: 1),
    to: "records/latest.json"
)
let record = try storage.read(
    Record.self,
    from: "records/latest.json"
)
```

Absolute paths, traversal components, empty components, backslashes, and symlink escapes are rejected. Other operations include `exists`, `list`, `createDirectory`, and `remove`.

### Typed preferences

Preferences store independently encoded `Codable` values:

```swift
let preferences = try invocation.preferences()
let count = try await preferences.value(
    forKey: "runCount",
    as: Int.self
) ?? 0
try await preferences.set(count + 1, forKey: "runCount")
```

`StorePreferences` is an actor and also provides `contains`, `allKeys`, `removeValue`, and `removeAll`.

### Structured logging

```swift
let logger = invocation.logger(category: "sync")
logger.info("Sync started", metadata: ["records": "12"])
logger.error("Sync failed")
```

Logs are JSON records written to standard error. The invocation logger automatically redacts every configured secret value. Do not intentionally log credentials; redaction is defense in depth.

### Permission-aware HTTP

Declare `networkAccess`, then create a client:

```swift
let client = try invocation.httpClient()
let response = try await client.get(
    URL(string: "https://api.example.com/status")!,
    headers: ["Accept": "application/json"],
    timeout: 10
).requireSuccess()

let payload = try response.decode(StatusPayload.self)
```

For a JSON request body:

```swift
let request = try StoreHTTPRequest.json(
    method: .post,
    url: URL(string: "https://api.example.com/items")!,
    body: NewItem(name: "Vehla")
)
let response = try await client.send(request).requireSuccess()
```

The client permits only HTTP and HTTPS, limits timeouts to 15 seconds, limits request bodies to 1 MB, and limits response bodies to 5 MB by default. Native code is not sandboxed and can bypass SDK helpers; these checks provide a safe default API, not an operating-system security boundary.

## Return brokered actions

Show a message:

```swift
return Store.showMessage("Finished")
```

Copy text:

```swift
return Store.copyText("Copied value")
```

Open an HTTP or HTTPS URL:

```swift
return Store.openURL("https://example.com")
```

Deliver a notification:

```swift
return Store.notify(
    title: "Export complete",
    body: "The Swift extension finished."
)
```

The package must declare the corresponding capability. Vehla performs these actions after validating the response.

## Return a rich native result

```swift
return Store.view(
    StoreRichView(
        title: "Repository",
        subtitle: "Native Swift result",
        sections: [
            StoreRichSection(
                title: "Summary",
                items: [
                    .text("Inspection completed."),
                    .detail("Status", value: "Healthy"),
                    .code(
                        #"{"ok":true}"#,
                        language: "json"
                    ),
                ]
            ),
        ],
        actions: [
            StoreAction(
                type: .copyText,
                value: "Healthy",
                label: "Copy Status",
                systemImage: "doc.on.doc"
            ),
        ]
    )
)
```

Vehla renders the result with native UI. Extensions do not inject SwiftUI views into the app.

## Return a view and completion action

Use `StoreResult` directly when one invocation needs both:

```swift
return StoreResult(
    action: StoreAction(
        type: .notify,
        value: "The report is ready.",
        title: "Swift extension completed"
    ),
    view: reportView
)
```

## Diagnostics

Never call `print`, because standard output is reserved for protocol responses. Write diagnostics to standard error:

```swift
func log(_ message: String) {
    FileHandle.standardError.write(
        Data("[MyExtension] \(message)\n".utf8)
    )
}
```

Vehla captures bounded diagnostic output and includes it in actionable process errors.

## Build an arm64 executable

Vehla’s native extension runtime supports Apple Silicon only:

```sh
swift build \
  --configuration release \
  --triple arm64-apple-macosx14.0 \
  --scratch-path .build/arm64

arm64_bin="$(swift build \
  --configuration release \
  --triple arm64-apple-macosx14.0 \
  --scratch-path .build/arm64 \
  --show-bin-path)"

mkdir -p bin
install -m 755 "$arm64_bin/MyExtension" bin/my-extension
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier com.example.swift-extension \
  bin/my-extension
```

Confirm the architecture:

```sh
lipo -archs bin/my-extension
```

Expected output:

```text
arm64
```

## Test without Vehla

The SDK transport can be smoke-tested from a terminal:

```sh
printf '%s\n' \
  '{"jsonrpc":"2.0","id":"test","method":"store.invoke","params":{"packageID":"com.example.swift-extension","commandID":"hello","query":"Vehla","context":{"secrets":{},"formValues":{}}}}' \
  | bin/my-extension
```

Expected response shape:

```json
{
  "jsonrpc": "2.0",
  "id": "test",
  "result": {
    "action": {
      "type": "showMessage",
      "value": "Hello, Vehla"
    }
  }
}
```

This wire format is an internal runtime detail. Extension code should use the typed SDK APIs.

## Install locally

1. Build `bin/my-extension`.
2. Confirm it is executable with `test -x bin/my-extension`.
3. Open **Settings → Store**.
4. Choose **Install Local Package**.
5. Select the extension directory, not `bin` or `extension.json`.
6. Confirm the installed package shows **Native executable**.
7. Review permissions and run a command keyword.

Local packages intentionally show as local or unsigned because they were not installed from a signed catalog archive.

## Publish to the catalog

Before publishing:

1. Increment the manifest version when source or binary bytes change.
2. Produce the arm64 release binary.
3. Test both the executable directly and the installed package.
4. Include source, `Package.swift`, `build.sh`, and the release binary.
5. Run the signed catalog builder.
6. Verify the resulting archive checksum and Ed25519 signature.
7. Commit the source, immutable archive, and catalog entry together.

Vehla records publisher provenance only when installation uses a verified signed catalog archive. Installing the source directory locally cannot establish that provenance.

## Command runtime limits

Executable Swift commands currently use the same invocation limits as Node
extensions:

- One process per invocation.
- 15-second execution timeout.
- 1 MB standard-output protocol limit.
- Bounded diagnostic output.
- No long-running background process.
- No scheduled execution.
- No extension-defined global hotkey.

Move slow work behind a remote API or split it into bounded commands.

These one-shot limits do not apply to hosted Dock widgets. Dock widget
background tasks may remain active while their widget is visible or enabled,
but must use cancellable async work and stop promptly when Vehla sends
`.hidden` or `widgetWillClose(_:)`.

## Troubleshooting

### Entrypoint not found

Build the executable before installation and ensure `entrypoint` exactly matches its relative path.

### Entrypoint is not executable

Run:

```sh
chmod 755 bin/my-extension
```

Reinstall the package because Vehla copies local packages during installation.

### Code signature is invalid

Sign the final arm64 binary after copying it into the package:

```sh
swift run --package-path sdk/swift \
  vehla-swift sign path/to/extension
```

Signing must be the final binary build step.

### Bad CPU type in executable

The package is not arm64-only. Rebuild it for `arm64-apple-macosx14.0`.

### Command timed out

The handler exceeded 15 seconds. Reduce work, add explicit network timeouts, or split the operation.

### Invalid response

Do not write logs with `print`. Any non-protocol standard output corrupts the response. Use standard error.

### Changes do not appear

Rebuild the binary, then reinstall the local package. Vehla runs its installed copy, not the source directory.

## Security

An executable extension runs under the user’s macOS account. Out-of-process execution provides crash isolation, not a security sandbox. Native code can call system APIs without going through Vehla’s capability broker. Install only trusted, source-reviewed packages and cryptographically sign catalog archives.

Treat manifest capabilities as a transparent user contract, not an operating-system enforcement boundary. Keep dependencies small, review transitive code, avoid shell execution, scope credentials narrowly, and publish reproducible source alongside every binary.
