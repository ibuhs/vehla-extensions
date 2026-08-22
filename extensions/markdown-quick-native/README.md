# Markdown Quick

> **Attribution:** This extension was created with the help of AI and was
> reviewed by a human.

Markdown Quick is a QuickGlass-only Native UI extension. Select Markdown, then
run an action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.markdown-quick` |
| Workspace ID | `markdown-quick` |
| Version | **1.0.0** |
| Runtime | Vehla Native UI (`nativeUI`) |
| Author | ibuhs |
| License | MIT (`LICENSE`) |
| Minimum OS | macOS 14 |

The required workspace is a reference card, not a toolbench. All work happens
from selected text in QuickGlass and stays on this Mac.

## QuickGlass actions

| Action | Delivery | What it does |
| --- | --- | --- |
| Normalize Markdown | Replace selection | Normalizes line endings, heading markers, and extra blank lines |
| Strip Markdown | Replace selection | Returns readable plain text |
| Format Tables | Replace selection | Aligns GFM pipe tables |
| Links to URLs | Replace selection | Turns `[label](url)` into `url` |
| Extract Links | Compact result | Lists Markdown, autolink, and reference URLs |
| Extract Headings | Compact result | Lists ATX headings as an outline |

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the
`MarkdownWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/markdown-quick-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/MarkdownQuickWorkspace.bundle`, then
assembles the installable package at `dist/MarkdownQuick`. Refresh the Store
catalog in Vehla and install **Markdown Quick**, or choose that folder with
**Install Local Package**.
