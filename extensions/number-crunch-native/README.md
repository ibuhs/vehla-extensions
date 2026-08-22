# Number Crunch

Number Crunch is a QuickGlass-only Native UI extension. Select numbers or
units, then run an action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.number-crunch` |
| Workspace ID | `number-crunch` |
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
| Sum Numbers | Compact result | Adds every number in the selection |
| Average | Compact result | Averages every number in the selection |
| Evaluate | Compact result | Evaluates a math expression (`+ - * / ^ ()`) |
| To Metric | Replace selection | Converts lb, oz, mi, ft, yd, in, and °F |
| To Imperial | Replace selection | Converts kg, g, km, m, cm, mm, and °C |
| Humanize Size | Replace selection | Turns bytes into KiB, MiB, GiB, TiB, or PiB |
| To Bytes | Replace selection | Turns KB, MB, GiB, and bits into bytes |

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the
`NumberCrunchWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/number-crunch-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/NumberCrunchWorkspace.bundle`, then
assembles the installable package at `dist/NumberCrunch`. Refresh the Store
catalog in Vehla and install **Number Crunch**, or choose that folder with
**Install Local Package**.
