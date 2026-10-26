# Lofi

A cozy native Vehla dock widget that plays audio directly from a folder chosen by the user. No playlist or third-party music is bundled, downloaded, or fetched from the network.

On first opening the popup, choose **Choose Music Folder** or **Not now**. Users who skip can open the top-right **••• → Choose Source Folder…** menu at any time. The same menu offers Refresh Library and Show Source Folder. Canceling the picker leaves the existing source unchanged.

The selected folder and its subfolders are scanned for MP3, M4A, AAC, WAV, AIFF, CAF, and FLAC files. Hidden files, packages, and symbolic links are skipped. Actual playback depends on macOS audio format support. Titles/artists are read from local metadata when available, with filename fallback. Missing drives, empty folders, or unsupported files show a message; source files are never modified, moved, copied, or deleted.

A read-only security-scoped bookmark remembers the chosen source. Player settings and the bookmark live in the SDK-provided package data directory. Music stays in the selected folder. Previous online-playlist preferences migrate without automatically selecting the old cache; existing users receive the folder prompt too. Old downloaded music can be removed from the previous package data `tracks/` folder; the new extension never uses or recreates it.

After playback starts, Lofi registers with macOS Now Playing for AirPods/headphone gestures, keyboard media keys, and Control Center. Play/pause, next/previous track, playback-position seeking, and 15-second skip commands use the same player as the widget. AirPods gestures follow your device's configured actions. Pausing retains the current track and media controls so the next play gesture resumes Lofi; closing the popup keeps the controls available. Closing the widget, replacing or refreshing the source folder, or a playback failure releases them. macOS chooses the active media app if another app starts playback.

## Build and install

```sh
zsh extensions/Lofi/build.sh
swift test --package-path extensions/Lofi
swift run --package-path sdk/swift vehla-swift validate extensions/Lofi/dist/LofiDockWidget
```

Install the folder produced by build.sh through Vehla's Store. In-process plugin updates require restarting Vehla and enabling the widget again. Tests cover first-use/skip behavior, legacy preferences, read-only folder scanning, symbolic-link exclusion, bookmark restoration, playback cancellation, source-file preservation, shuffle, remote controls and Now Playing lifecycle, manifest metadata, and rendering.

To verify headphone routing after installing: start a track, close the popup, pause with AirPods, then click again to resume the same track. Apple Music should stay paused. Check next/previous gestures, then close the widget and confirm it disappears from Now Playing. Hardware routing requires this check in the running Vehla app; automated tests exercise the command actions and metadata lifecycle.
