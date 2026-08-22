# List Lab

List Lab is a QuickGlass-only Native UI extension. Select a list, then run an
action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.list-lab` |
| Workspace ID | `list-lab` |
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
| Comma to Lines | Replace selection | Splits comma-separated values onto their own lines |
| Lines to Comma | Replace selection | Joins non-empty lines with `, ` |
| Pipe to Lines | Replace selection | Splits pipe-separated values onto their own lines |
| Lines to Pipe | Replace selection | Joins non-empty lines with ` \| ` |
| Shuffle Lines | Replace selection | Randomizes the order of non-empty lines |
| Number Lines | Replace selection | Numbers each item as `1. item` |
| Quote Lines | Replace selection | Wraps each item in `"quotes"` |
| Wrap () | Replace selection | Wraps each item in parentheses |
| Unwrap | Replace selection | Removes one layer of `()`, `[]`, `{}`, or quotes |
| Prefix with Clipboard | Replace selection | Puts the current clipboard text in front of each item |

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the
`ListWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/list-lab-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/ListLabWorkspace.bundle`, then
assembles the installable package at `dist/ListLab`. Refresh the Store
catalog in Vehla and install **List Lab**, or choose that folder with
**Install Local Package**.
