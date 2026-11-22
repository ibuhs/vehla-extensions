# Actions Hub (Notch)

One dense Notch tab for the things you reach for all day: compact single-row tiles in one grid (about
three rows and 18+ items visible without scrolling), with filter chips (All / Scenes / Toggles / Shortcuts /
Apps) in the header. Battery, CPU and memory are left to dedicated plugins.

- **Scenes:** ordered steps (Shortcuts, apps, toggles, URLs, waits). A scene shows progress in the closed Notch.
- **Toggles:** Dark Mode, Keep Awake (with a live activity and Stop button), Mute, Desktop Icons.
- **Shortcuts:** every Shortcut from the Shortcuts app, one tap to run.
- **Apps:** pinned launchers.

Scenes, apps and which toggles appear live in `actions.json` in the extension's data folder
(the slider button reveals it). Steps: `shortcut`, `app`, `toggle`, `url`, `wait`.

```json
{"type":"toggle","id":"darkMode","on":true}
{"type":"shortcut","name":"Start Work"}
```

macOS asks once for permission when a toggle first controls System Events or Finder.
