# Type Polish

Type Polish is a QuickGlass-only Native UI extension. Select prose, then run
an action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.type-polish` |
| Workspace ID | `type-polish` |
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
| Straighten Quotes | Replace selection | Turns curly quotes into `" "` and `' '` |
| Clean Dashes | Replace selection | Turns em/en dashes and ellipses into ASCII |
| Unwrap Lines | Replace selection | Joins hard-wrapped lines; keeps blank-line paragraphs |
| Collapse Spaces | Replace selection | Collapses extra spaces, tabs, and non-breaking spaces |
| Strip Invisible | Replace selection | Removes zero-width marks, soft hyphens, and BOM |
| Polish Text | Replace selection | Runs every cleanup in one pass |

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the
`TypePolishWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/type-polish-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/TypePolishWorkspace.bundle`, then
assembles the installable package at `dist/TypePolish`. Refresh the Store
catalog in Vehla and install **Type Polish**, or choose that folder with
**Install Local Package**.
