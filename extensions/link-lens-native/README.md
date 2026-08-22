# Link Lens

> **Attribution:** This extension was created with the help of AI and was
> reviewed by a human.

Link Lens is a QuickGlass-only Native UI extension. Select a URL or text that
contains URLs, then run a Link Lens action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.link-lens` |
| Workspace ID | `link-lens` |
| Version | **1.0.0** |
| Runtime | Vehla Native UI (`nativeUI`) |
| Author | ibuhs |
| License | MIT (`LICENSE`) |
| Minimum OS | macOS 14 |

The required workspace is a reference card, not a toolbench. All work happens
from selected text in QuickGlass.

## QuickGlass actions

| Action | Delivery | What it does |
| --- | --- | --- |
| Remove Tracking | Replace selection | Drops `utm_*`, click IDs, and similar campaign parameters |
| Unwrap Redirect | Replace selection | Decodes Google / Facebook / Outlook / Proofpoint wrappers, then follows a short redirect chain |
| Inspect Link | Compact result | Shows scheme, host, punycode, path, query, and fragment |
| Extract Links | Compact result | Lists unique URLs found in the selection |
| Check Link Safety | Compact result | Flags credentials, IP hosts, punycode, dangerous schemes, and host-changing redirects |

Parsing and wrapper decoding stay on-device. Unwrap and safety may make a
short HTTPS/HTTP request to follow redirects. No request bodies are uploaded.

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the `LinkWorker`
actor so parsing and network I/O do not block the main thread. Completion is
reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/link-lens-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/LinkLensWorkspace.bundle`, then
assembles the installable package at `dist/LinkLens`. Refresh the Store catalog
in Vehla and install **Link Lens**, or choose that folder with **Install Local
Package**.
