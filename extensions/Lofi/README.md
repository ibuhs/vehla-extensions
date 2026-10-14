# Lofi

A cozy native Vehla dock widget that plays audio directly from a folder chosen by the user. No playlist or third-party music is bundled, downloaded, or fetched from the network.

On first opening the popup, choose **Choose Music Folder** or **Not now**. Users who skip can open the top-right **••• → Choose Source Folder…** menu at any time. The same menu offers Refresh Library and Show Source Folder. Canceling the picker leaves the existing source unchanged.

The selected folder and its subfolders are scanned for MP3, M4A, AAC, WAV, AIFF, CAF, and FLAC files. Hidden files, packages, and symbolic links are skipped. Actual playback depends on macOS audio format support. Titles/artists are read from local metadata when available, with filename fallback. Missing drives, empty folders, or unsupported files show a message; source files are never modified, moved, copied, or deleted.

A read-only security-scoped bookmark remembers the chosen source. Player settings and the bookmark live in the SDK-provided package data directory. Music stays in the selected folder. Previous online-playlist preferences migrate without automatically selecting the old cache; existing users receive the folder prompt too. Old downloaded music can be removed from the previous package data `tracks/` folder; the new extension never uses or recreates it.

## Build and install

```sh
zsh extensions/Lofi/build.sh
swift test --package-path extensions/Lofi
swift run --package-path sdk/swift vehla-swift validate extensions/Lofi/dist/LofiDockWidget
```

Install the folder produced by build.sh through Vehla's Store. In-process plugin updates require restarting Vehla and enabling the widget again. Tests cover first-use/skip behavior, legacy preferences, read-only folder scanning, symbolic-link exclusion, bookmark restoration, playback cancellation, source-file preservation, shuffle, manifest metadata, and rendering.
