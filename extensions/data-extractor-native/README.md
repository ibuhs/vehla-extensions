# Data Extractor

Data Extractor is a QuickGlass-only Native UI extension. Select text, then run
an action from the QuickGlass overflow menu.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.data-extractor` |
| Workspace ID | `data-extractor` |
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
| Extract Emails | Compact result | Lists unique email addresses |
| Extract Phones | Compact result | Lists unique phone numbers |
| Extract IPs | Compact result | Lists unique IPv4 and IPv6 addresses |
| Extract Mentions | Compact result | Lists unique `@names` |
| Extract Hashtags | Compact result | Lists unique `#tags` |
| Extract All | Compact result | Groups every match by type |
| Extract CSV | Compact result | Exports matches as `type,value` CSV |

## Main-thread safety

`performQuickGlassAction` returns immediately. Work runs on the
`DataExtractorWorker` actor. Completion is reported on the main actor.

## Build, test, and install

```sh
# From this directory (vehla-extensions/extensions/data-extractor-native)
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/DataExtractorWorkspace.bundle`, then
assembles the installable package at `dist/DataExtractor`. Refresh the Store
catalog in Vehla and install **Data Extractor**, or choose that folder with
**Install Local Package**.
