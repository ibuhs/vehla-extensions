# Capture Hub

Capture Hub is a QuickGlass-only Native UI extension. Select text, then run a
capture action from the QuickGlass overflow menu. Its required workspace is a
reference card only.

| | |
| --- | --- |
| Extension ID | `com.ibuhs.vehla.capture-hub` |
| Workspace ID | `capture-hub` |
| Version | **1.0.3** |
| Runtime | Vehla Native UI (`nativeUI`, API 2) |
| Author | ibuhs |
| License | MIT (`LICENSE`) |
| Minimum OS | macOS 14 |

## QuickGlass actions

| Action | What it does |
| --- | --- |
| Add Reminder | Creates one reminder. The first recognized date is removed from the title and used as its due date. |
| Add Lines as Reminders | Creates one reminder per non-empty trimmed line, in order, up to 100 reminders. |
| Create Calendar Event | Uses recognized dates and durations, or starts at the next whole hour for one hour. The original selection is retained in event notes. |
| Create Apple Note | Uses the first non-empty line (up to 80 characters) as the note name and any remaining lines as its body. Long single-line selections use `Vehla Capture` as the name so no selected text is lost. |
| Append to Capture Note | Finds or creates `Vehla Captures` and appends a timestamp plus the complete selected text. |

Every action returns a compact QuickGlass result. Empty selections and unknown
actions return clear errors.

## Permissions and destinations

Reminder actions request full Reminders access and write to the default
reminders list. Event actions request full Calendar access and use the default
writable calendar (or another writable event calendar when the default cannot
be modified). If access is denied, Capture Hub points to the relevant pane in
**System Settings → Privacy & Security**.

Apple does not provide a public Notes write API. The note actions therefore use
AppleScript with Notes' default account and default folder. macOS asks for
Automation permission the first time; if it was denied, enable Vehla under
**System Settings → Privacy & Security → Automation**.

Web selections keep safe paragraph, line, list, heading, emphasis, and link
formatting in Notes. Capture Hub removes scripts, styles, remote resources,
attachments, colors, and unsafe links before sending content to Notes.

Selected text is processed locally and sent only to Reminders, Calendar, or
Apple Notes for the action you choose. Capture Hub makes no network requests
and does not maintain its own capture database.

## Date and duration behavior

Dates are recognized with macOS `NSDataDetector`. For calendar events, a
detector-provided duration wins; otherwise an explicit phrase such as
`for 30 minutes` or `for 2 hours` is used. A later second recognized date can
be the end. Without a date, the event begins at the next whole hour. Without a
duration or later end, it lasts one hour.

## Build, test, and install

```sh
# From vehla-extensions/extensions/capture-hub-native
swift test
./build.sh
```

`build.sh` creates and ad-hoc signs `bin/CaptureHubWorkspace.bundle`, then
assembles `dist/CaptureHub`. In Vehla, refresh the Store catalog or choose that
folder with **Install Local Package**. On first use, approve only the macOS
permissions needed by the chosen action.
